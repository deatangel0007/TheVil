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

  Future<void> start(String rawLink) async {
    try {
      await _channel.invokeMethod('start', {'link': rawLink});
    } on MissingPluginException {
      mockMode = true;
      await Future.delayed(const Duration(milliseconds: 1500));
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
