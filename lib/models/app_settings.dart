import 'dart:convert';

/// حالت پروکسی بر اساس برنامه
/// off    = همه‌ی برنامه‌ها از VPN رد شوند
/// only   = فقط برنامه‌های انتخاب‌شده از VPN رد شوند
/// bypass = برنامه‌های انتخاب‌شده از VPN رد نشوند (مستقیم بروند)
enum PerAppMode { off, only, bypass }

class DnsPreset {
  final String label;
  final String ip;
  const DnsPreset(this.label, this.ip);
}

const dnsPresets = <DnsPreset>[
  DnsPreset('Cloudflare', '1.1.1.1'),
  DnsPreset('Google', '8.8.8.8'),
  DnsPreset('Quad9', '9.9.9.9'),
  DnsPreset('AdGuard', '94.140.14.14'),
];

class AppSettings {
  final String remoteDns;
  final PerAppMode perAppMode;
  final Set<String> perAppPackages;

  const AppSettings({
    this.remoteDns = '1.1.1.1',
    this.perAppMode = PerAppMode.off,
    this.perAppPackages = const {},
  });

  AppSettings copyWith({
    String? remoteDns,
    PerAppMode? perAppMode,
    Set<String>? perAppPackages,
  }) =>
      AppSettings(
        remoteDns: remoteDns ?? this.remoteDns,
        perAppMode: perAppMode ?? this.perAppMode,
        perAppPackages: perAppPackages ?? this.perAppPackages,
      );

  static final _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

  static bool isValidIpv4(String s) {
    final m = _ipv4.firstMatch(s.trim());
    if (m == null) return false;
    for (var i = 1; i <= 4; i++) {
      if (int.parse(m.group(i)!) > 255) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'remoteDns': remoteDns,
        'perAppMode': perAppMode.name,
        'perAppPackages': perAppPackages.toList(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    PerAppMode mode = PerAppMode.off;
    final m = j['perAppMode'];
    for (final v in PerAppMode.values) {
      if (v.name == m) mode = v;
    }
    final dns = (j['remoteDns'] as String?) ?? '1.1.1.1';
    return AppSettings(
      remoteDns: isValidIpv4(dns) ? dns : '1.1.1.1',
      perAppMode: mode,
      perAppPackages:
          ((j['perAppPackages'] as List?) ?? const []).cast<String>().toSet(),
    );
  }

  String encode() => jsonEncode(toJson());

  static AppSettings decode(String s) {
    try {
      return AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }
}
