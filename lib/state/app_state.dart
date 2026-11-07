import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_config.dart';
import '../models/subscription.dart';
import '../services/config_parser.dart';
import '../services/singbox_config.dart';
import '../services/vpn_service.dart';

enum ConnStatus { disconnected, connecting, connected }

class AppState extends ChangeNotifier {
  static const _kServers = 'servers';
  static const _kSelected = 'selected';
  static const _kSubs = 'subs';

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
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      // بعضی پنل‌ها فقط برای کلاینت‌های شناخته‌شده کانفیگ می‌دهند
      req.headers.set('User-Agent', 'v2rayNG/1.8.5');
      final res = await req.close().timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) throw 'سرور اشتراک جواب داد: HTTP ${res.statusCode}';
      return await res.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
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
      if (parsed.isEmpty) {
        throw 'در این اشتراک کانفیگ معتبری پیدا نشد (فقط vmess/vless/trojan/ss پشتیبانی می‌شود)';
      }
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
      await _vpn.start(SingboxConfig.fromLink(s.raw));
      if (!_vpn.mockMode) await _waitForService();
      status = ConnStatus.connected;
      if (!_vpn.mockMode) _testConnection(); // بدون await: در پس‌زمینه
    } catch (e) {
      error = e.toString();
      status = ConnStatus.disconnected;
    }
    notifyListeners();
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
