import 'dart:convert';

enum Protocol { vmess, vless, trojan, shadowsocks }

class ServerConfig {
  final String id;
  final String name;
  final Protocol protocol;
  final String address;
  final int port;

  /// لینک اصلی (vmess://... و غیره) که به هسته داده می‌شود
  final String raw;

  /// پینگ بر حسب میلی‌ثانیه؛ null = تست نشده، -1 = ناموفق
  final int? pingMs;

  const ServerConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.address,
    required this.port,
    required this.raw,
    this.pingMs,
  });

  ServerConfig copyWith({int? pingMs, String? name}) => ServerConfig(
        id: id,
        name: name ?? this.name,
        protocol: protocol,
        address: address,
        port: port,
        raw: raw,
        pingMs: pingMs ?? this.pingMs,
      );

  String get protocolLabel => switch (protocol) {
        Protocol.vmess => 'VMess',
        Protocol.vless => 'VLESS',
        Protocol.trojan => 'Trojan',
        Protocol.shadowsocks => 'Shadowsocks',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'address': address,
        'port': port,
        'raw': raw,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> j) => ServerConfig(
        id: j['id'] as String,
        name: j['name'] as String,
        protocol: Protocol.values.byName(j['protocol'] as String),
        address: j['address'] as String,
        port: j['port'] as int,
        raw: j['raw'] as String,
      );

  static String encodeList(List<ServerConfig> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<ServerConfig> decodeList(String s) => (jsonDecode(s) as List)
      .map((e) => ServerConfig.fromJson(e as Map<String, dynamic>))
      .toList();
}
