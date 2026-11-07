import 'package:flutter/services.dart';

/// پل بین Flutter و هسته‌ی نیتیو (Xray / sing-box).
///
/// اندروید: یک MethodChannel با نام `red_vpn/core` در MainActivity پیاده‌سازی کنید
/// که متدهای `start` و `stop` را با VpnService اجرا کند.
/// تا وقتی هسته وصل نشده، حالت شبیه‌سازی (Mock) فعال است تا بتوانید UI را ببینید.
class VpnService {
  static const _channel = MethodChannel('red_vpn/core');

  /// true یعنی هسته‌ی واقعی پیدا نشده و اتصال شبیه‌سازی می‌شود.
  bool mockMode = false;

  /// [configJson] کانفیگ کامل sing-box است (از SingboxConfig.fromLink).
  Future<void> start(
    String configJson, {
    String appMode = 'off',
    List<String> appPackages = const [],
  }) async {
    try {
      await _channel.invokeMethod('start', {
        'config': configJson,
        'appMode': appMode,
        'appPackages': appPackages,
      });
    } on MissingPluginException {
      mockMode = true;
      await Future.delayed(const Duration(milliseconds: 1500));
    }
  }

  /// وضعیت سرویس نیتیو: {running: bool, error: String?}
  Future<Map<String, dynamic>?> status() async {
    try {
      final r = await _channel.invokeMethod('status');
      return (r as Map?)?.cast<String, dynamic>();
    } on MissingPluginException {
      return null;
    }
  }

  /// لاگ‌های هسته‌ی sing-box و سرویس
  Future<String> logs() async {
    try {
      return await _channel.invokeMethod<String>('logs') ?? '';
    } on MissingPluginException {
      return '(هسته‌ی نیتیو وصل نیست)';
    }
  }

  /// متن کرش دفعه‌ی قبل (اگر برنامه کرش کرده باشد)
  Future<String?> takeCrash() async {
    try {
      return await _channel.invokeMethod<String>('takeCrash');
    } on MissingPluginException {
      return null;
    }
  }

  /// ترافیک: {rx, tx, running}؛ rx/tx برابر -1 یعنی دستگاه پشتیبانی نمی‌کند.
  Future<Map<String, dynamic>?> traffic() async {
    try {
      final r = await _channel.invokeMethod('traffic');
      return (r as Map?)?.cast<String, dynamic>();
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// فهرست برنامه‌های نصب‌شده: [{package, label, system}]
  Future<List<Map<String, dynamic>>> listApps() async {
    try {
      final r = await _channel.invokeMethod<List<dynamic>>('listApps');
      return (r ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } on MissingPluginException {
      return [];
    }
  }

  /// اسکن QR با دوربین؛ متن QR یا null (لغو). خطا را پرتاب می‌کند.
  Future<String?> scanQr() async {
    try {
      return await _channel.invokeMethod<String>('scanQr');
    } on MissingPluginException {
      throw 'اسکن QR در حالت شبیه‌سازی ممکن نیست';
    } on PlatformException catch (e) {
      throw e.message ?? e.code;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } on MissingPluginException {
      mockMode = true;
    }
  }
}
