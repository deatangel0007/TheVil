import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/server_config.dart';
import '../models/subscription.dart';
import '../models/traffic_info.dart';
import '../services/config_parser.dart';
import '../services/singbox_config.dart';
import '../services/vpn_service.dart';

enum ConnStatus { disconnected, connecting, connected }

class AppState extends ChangeNotifier {
  static const _kServers = 'servers';
  static const _kSelected = 'selected';
  static const _kSubs = 'subs';
  static const _kSettings = 'settings';

  final VpnService _vpn = VpnService();

  List<ServerConfig> servers = [];
  List<Subscription> subs = [];
  String? selectedId;
  ConnStatus status = ConnStatus.disconnected;

  /// آخرین خطا (برای نمایش به کاربر)
  String? error;

  /// نتیجه‌ی تست اینترنت بعد از اتصال
  String? testResult;

  /// در حال دانلود اشتراک
  bool busy = false;

  AppSettings settings = const AppSettings();

  /// سرعت و حجم مصرفی (هر ثانیه به‌روز می‌شود)
  final ValueNotifier<TrafficInfo> traffic = ValueNotifier(TrafficInfo.zero);

  /// false یعنی دستگاه آمار ترافیک را نمی‌دهد
  bool trafficSupported = true;

  Timer? _trafficTimer;
  int _baseRx = 0, _baseTx = 0, _lastRx = 0, _lastTx = 0;
  bool _hasBase = false;

  ServerConfig? get selected {
    for (final s in servers) {
      if (s.id == selectedId) return s;
    }
    return servers.isEmpty ? null : servers.first;
  }

  bool get mockMode => _vpn.mockMode;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kServers);
    if (s != null) servers = ServerConfig.decodeList(s);
    final sb = p.getString(_kSubs);
    if (sb != null) subs = Subscription.decodeList(sb);
    selectedId = p.getString(_kSelected);
    final st = p.getString(_kSettings);
    if (st != null) settings = AppSettings.decode(st);
    final crash = await _vpn.takeCrash();
    if (crash != null && crash.isNotEmpty) error = 'کرش قبلی:\n$crash';
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServers, ServerConfig.encodeList(servers));
    await p.setString(_kSubs, Subscription.encodeList(subs));
    if (selectedId != null) await p.setString(_kSelected, selectedId!);
  }

  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSettings, s.encode());
    notifyListeners();
  }

  @override
  void dispose() {
    _trafficTimer?.cancel();
    traffic.dispose();
    super.dispose();
  }

  /// تعداد کانفیگ‌های اضافه‌شده را برمی‌گرداند.
  Future<int> addFromText(String text) async {
    final parsed = ConfigParser.parseMany(text);
    var added = 0;
    for (final c in parsed) {
      if (servers.any((e) => e.id == c.id)) continue;
      servers.add(c);
      added++;
    }
    selectedId ??= servers.isEmpty ? null : servers.first.id;
    await _save();
    notifyListeners();
    return added;
  }

  /// هر متنی را می‌پذیرد: لینک مستقیم، چند لینک، base64 یا لینک اشتراک (http/https).
  /// پیام موفقیت را برمی‌گرداند و در صورت شکست، پیام فارسی پرتاب می‌کند.
  Future<String> addFromAny(String text) async {
    text = text.trim();
    if (text.isEmpty) throw 'متنی برای افزودن پیدا نشد (کلیپ‌بورد خالی است)';

    if (ConfigParser.parseMany(text).isNotEmpty) {
      final n = await addFromText(text);
      return n > 0 ? '$n کانفیگ اضافه شد' : 'این کانفیگ‌ها از قبل اضافه شده بودند';
    }

    final m = RegExp(r'''https?://[^\s"'<>]+''').firstMatch(text);
    if (m != null) {
      final n = await addSubscription(m.group(0)!);
      return 'اشتراک اضافه شد: $n سرور';
    }

    final bad = ConfigParser.unsupportedSchemes(text);
    if (bad.isNotEmpty) {
      throw 'پروتکل ${bad.join('، ')} هنوز پشتیبانی نمی‌شود. فقط vmess / vless / trojan / ss';
    }
    throw 'لینک معتبری پیدا نشد (vmess / vless / trojan / ss یا لینک اشتراک http)';
  }

  Future<void> select(String id) async {
    selectedId = id;
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    servers.removeWhere((e) => e.id == id);
    if (selectedId == id) selectedId = servers.isEmpty ? null : servers.first.id;
    await _save();
    notifyListeners();
  }

  // ------------------------------------------------------------- اشتراک‌ها

  Future<String> _download(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..badCertificateCallback = (_, __, ___) => false;
    try {
      return await () async {
        final req = await client.getUrl(Uri.parse(url));
        // بعضی پنل‌ها فقط برای کلاینت‌های شناخته‌شده کانفیگ می‌دهند
        req.headers.set('User-Agent', 'v2rayNG/1.8.5');
        req.headers.set('Accept', '*/*');
        final res = await req.close();
        if (res.statusCode != 200) {
          await res.drain<void>();
          throw 'سرور اشتراک جواب داد: HTTP ${res.statusCode}'
              '${res.statusCode == 403 ? ' (دسترسی رد شد؛ لینک منقضی یا مسدود است)' : ''}'
              '${res.statusCode == 404 ? ' (لینک اشتباه یا حذف شده)' : ''}';
        }
        final bytes = await res.fold<List<int>>(<int>[], (a, b) {
          a.addAll(b);
          if (a.length > 8 * 1024 * 1024) throw 'پاسخ اشتراک بیش از حد بزرگ است';
          return a;
        });
        return utf8.decode(bytes, allowMalformed: true);
      }()
          .timeout(const Duration(seconds: 40));
    } on TimeoutException {
      throw 'زمان دانلود اشتراک تمام شد. اگر VPN خاموش است ممکن است آدرس پنل از ایران بسته باشد؛ '
          'یک بار با VPN دیگر وصل شو و دوباره امتحان کن.';
    } on SocketException catch (e) {
      throw 'اتصال به سرور اشتراک ممکن نشد (${e.message}). '
          'اینترنت را چک کن؛ ممکن است آدرس پنل مسدود باشد.';
    } on HandshakeException {
      throw 'خطای TLS هنگام اتصال به سرور اشتراک (گواهی نامعتبر یا اتصال مسدود)';
    } on FormatException {
      throw 'لینک اشتراک قابل خواندن نیست';
    } finally {
      client.close(force: true);
    }
  }

  /// وقتی هیچ کانفیگی از پاسخ اشتراک درنیامد، دلیل محتمل را توضیح می‌دهد.
  String _explainEmpty(String body) {
    final t = body.trim();
    final low = t.toLowerCase();
    if (t.isEmpty) return 'سرور اشتراک پاسخ خالی داد (اشتراک منقضی یا بدون کانفیگ است)';
    if (low.startsWith('<!doctype') || low.startsWith('<html') || low.contains('<body')) {
      return 'سرور به‌جای کانفیگ یک صفحه‌ی وب برگرداند. لینک اشتباه، منقضی یا مسدود است.';
    }
    if (low.contains('proxies:') || low.contains('proxy-groups:')) {
      return 'این اشتراک فرمت Clash دارد. از پنل، لینک نوع V2Ray / base64 را بگیر.';
    }
    if (t.startsWith('{') || t.startsWith('[')) {
      return 'این اشتراک فرمت JSON دارد (مثلاً sing-box) که هنوز پشتیبانی نمی‌شود. '
          'لینک نوع V2Ray / base64 را بگیر.';
    }
    final bad = ConfigParser.unsupportedSchemes(t);
    if (bad.isNotEmpty) {
      return 'کانفیگ‌های این اشتراک از پروتکل ${bad.join('، ')} هستند که هنوز پشتیبانی نمی‌شود '
          '(فقط vmess / vless / trojan / ss).';
    }
    final preview = t.length > 80 ? '${t.substring(0, 80)}...' : t;
    return 'در پاسخ اشتراک کانفیگ معتبری پیدا نشد. ابتدای پاسخ:\n$preview';
  }

  /// اشتراک جدید اضافه می‌کند و بلافاصله دانلودش می‌کند. تعداد سرور را برمی‌گرداند.
  Future<int> addSubscription(String url) async {
    url = url.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      throw 'لینک اشتراک معتبر نیست (باید با http یا https شروع شود)';
    }
    final id = url.hashCode.toRadixString(16);
    if (!subs.any((s) => s.id == id)) {
      subs.add(Subscription(id: id, url: url, name: uri.host));
    }
    try {
      return await refreshSubscription(id);
    } catch (_) {
      // اگر دانلود اول شکست خورد، اشتراک بی‌سرور در لیست نماند
      if (!servers.any((s) => s.subId == id)) {
        subs.removeWhere((s) => s.id == id);
        await _save();
        notifyListeners();
      }
      rethrow;
    }
  }

  /// سرورهای یک اشتراک را دوباره دانلود و جایگزین می‌کند.
  Future<int> refreshSubscription(String id) async {
    final sub = subs.firstWhere((s) => s.id == id);
    busy = true;
    notifyListeners();
    try {
      final body = await _download(sub.url);
      final parsed =
          ConfigParser.parseMany(body).map((c) => c.withSubId(id)).toList();
      if (parsed.isEmpty) throw _explainEmpty(body);
      servers.removeWhere((s) => s.subId == id);
      for (final c in parsed) {
        if (!servers.any((e) => e.id == c.id)) servers.add(c);
      }
      if (!servers.any((s) => s.id == selectedId)) {
        selectedId = servers.isEmpty ? null : servers.first.id;
      }
      final i = subs.indexWhere((s) => s.id == id);
      subs[i] = sub.copyWith(updatedMs: DateTime.now().millisecondsSinceEpoch);
      await _save();
      return parsed.length;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> removeSubscription(String id) async {
    subs.removeWhere((s) => s.id == id);
    servers.removeWhere((s) => s.subId == id);
    if (!servers.any((s) => s.id == selectedId)) {
      selectedId = servers.isEmpty ? null : servers.first.id;
    }
    await _save();
    notifyListeners();
  }

  // ----------------------------------------------------------------- اتصال

  Future<void> toggle() async {
    final s = selected;
    if (s == null || status == ConnStatus.connecting) return;

    if (status == ConnStatus.connected) {
      _stopTrafficPolling();
      await _vpn.stop();
      status = ConnStatus.disconnected;
      testResult = null;
      notifyListeners();
      return;
    }

    status = ConnStatus.connecting;
    error = null;
    testResult = null;
    notifyListeners();
    try {
      var mode = settings.perAppMode;
      if (settings.perAppPackages.isEmpty) mode = PerAppMode.off;
      await _vpn.start(
        SingboxConfig.fromLink(s.raw, remoteDns: settings.remoteDns),
        appMode: mode.name,
        appPackages: settings.perAppPackages.toList(),
      );
      if (!_vpn.mockMode) await _waitForService();
      status = ConnStatus.connected;
      if (!_vpn.mockMode) {
        _startTrafficPolling();
        _testConnection(); // بدون await: در پس‌زمینه
      }
    } catch (e) {
      error = e.toString();
      status = ConnStatus.disconnected;
    }
    notifyListeners();
  }

  /// قطع و وصل دوباره (برای اعمال تنظیمات جدید)
  Future<void> reconnect() async {
    if (status != ConnStatus.connected) return;
    await toggle(); // قطع
    await Future.delayed(const Duration(milliseconds: 700));
    await toggle(); // وصل
  }

  // ---------------------------------------------------------------- ترافیک

  void _startTrafficPolling() {
    _trafficTimer?.cancel();
    _hasBase = false;
    trafficSupported = true;
    traffic.value = TrafficInfo.zero;
    _trafficTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _pollTraffic());
    _pollTraffic();
  }

  void _stopTrafficPolling() {
    _trafficTimer?.cancel();
    _trafficTimer = null;
    traffic.value = TrafficInfo.zero;
  }

  Future<void> _pollTraffic() async {
    if (status != ConnStatus.connected) return;
    final t = await _vpn.traffic();
    if (t == null || status != ConnStatus.connected) return;

    // اگر سرویس نیتیو خودش از بین رفته باشد، وضعیت را اصلاح می‌کنیم
    if (t['running'] == false) {
      _stopTrafficPolling();
      status = ConnStatus.disconnected;
      testResult = null;
      final st = await _vpn.status();
      final err = st?['error'] as String?;
      if (err != null) error = err;
      notifyListeners();
      return;
    }

    final rx = (t['rx'] as num?)?.toInt() ?? -1;
    final tx = (t['tx'] as num?)?.toInt() ?? -1;
    if (rx < 0 || tx < 0) {
      if (trafficSupported) {
        trafficSupported = false;
        notifyListeners();
      }
      return;
    }
    if (!_hasBase) {
      _baseRx = _lastRx = rx;
      _baseTx = _lastTx = tx;
      _hasBase = true;
    }
    traffic.value = TrafficInfo(
      downBps: (rx - _lastRx).clamp(0, 1 << 40).toInt(),
      upBps: (tx - _lastTx).clamp(0, 1 << 40).toInt(),
      downTotal: (rx - _baseRx).clamp(0, 1 << 50).toInt(),
      upTotal: (tx - _baseTx).clamp(0, 1 << 50).toInt(),
    );
    _lastRx = rx;
    _lastTx = tx;
  }

  /// منتظر می‌ماند تا سرویس نیتیو بالا بیاید؛ اگر خطا داشت آن را پرتاب می‌کند.
  Future<void> _waitForService() async {
    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      final st = await _vpn.status();
      if (st == null) return;
      final err = st['error'] as String?;
      if (err != null) throw err;
      if (st['running'] == true) return;
    }
    throw 'سرویس VPN بعد از ۹ ثانیه بالا نیامد';
  }

  /// بعد از اتصال، یک درخواست کوچک از مسیر VPN می‌فرستد تا معلوم شود اینترنت واقعاً کار می‌کند.
  Future<void> _testConnection() async {
    testResult = 'در حال تست اینترنت...';
    notifyListeners();
    final sw = Stopwatch()..start();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .getUrl(Uri.parse('https://www.gstatic.com/generate_204'));
      final res = await req.close().timeout(const Duration(seconds: 12));
      await res.drain<void>();
      testResult = res.statusCode == 204 || res.statusCode == 200
          ? 'اینترنت از مسیر VPN کار می‌کند ✓ (${sw.elapsedMilliseconds} ms)'
          : 'پاسخ عجیب از شبکه: ${res.statusCode}';
    } catch (e) {
      testResult = 'اینترنت از مسیر VPN کار نمی‌کند ✗\n$e';
    } finally {
      client.close();
    }
    if (status == ConnStatus.connected) notifyListeners();
  }

  Future<String> fetchLogs() async => await _vpn.logs();

  Future<List<Map<String, dynamic>>> listApps() => _vpn.listApps();

  Future<String?> scanQr() => _vpn.scanQr();

  void clearError() {
    error = null;
    notifyListeners();
  }

  /// تست پینگ ساده با اتصال TCP به آدرس سرور.
  Future<void> pingAll() async {
    await Future.wait(servers.map((s) async {
      final sw = Stopwatch()..start();
      int ms;
      try {
        final sock = await Socket.connect(s.address, s.port,
            timeout: const Duration(seconds: 4));
        sock.destroy();
        ms = sw.elapsedMilliseconds;
      } catch (_) {
        ms = -1;
      }
      final i = servers.indexWhere((e) => e.id == s.id);
      if (i != -1) servers[i] = servers[i].copyWith(pingMs: ms);
      notifyListeners();
    }));
  }
}
