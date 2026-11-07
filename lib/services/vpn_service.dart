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
  Future<void> start(String configJson) async {
    try {
      await _channel.invokeMethod('start', {'config': configJson});
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

  /// متن کرش دفعه‌ی قبل (اگر برنامه کرش کرده باشد)
  Future<String?> takeCrash() async {
    try {
      return await _channel.invokeMethod<String>('takeCrash');
    } on MissingPluginException {
      return null;
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
