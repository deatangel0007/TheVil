import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_config.dart';
import '../services/config_parser.dart';
import '../services/singbox_config.dart';
import '../services/vpn_service.dart';

enum ConnStatus { disconnected, connecting, connected }

class AppState extends ChangeNotifier {
  static const _kServers = 'servers';
  static const _kSelected = 'selected';

  final VpnService _vpn = VpnService();

  List<ServerConfig> servers = [];
  String? selectedId;
  ConnStatus status = ConnStatus.disconnected;

  /// آخرین خطا (برای نمایش به کاربر)
  String? error;

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
    selectedId = p.getString(_kSelected);
    final crash = await _vpn.takeCrash();
    if (crash != null && crash.isNotEmpty) error = 'کرش قبلی:\n$crash';
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServers, ServerConfig.encodeList(servers));
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

  Future<void> toggle() async {
    final s = selected;
    if (s == null || status == ConnStatus.connecting) return;

    if (status == ConnStatus.connected) {
      await _vpn.stop();
      status = ConnStatus.disconnected;
      notifyListeners();
      return;
    }

    status = ConnStatus.connecting;
    error = null;
    notifyListeners();
    try {
      await _vpn.start(SingboxConfig.fromLink(s.raw));
      if (!_vpn.mockMode) await _waitForService();
      status = ConnStatus.connected;
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
