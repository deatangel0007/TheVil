import 'dart:convert';

import '../models/server_config.dart';

/// تبدیل لینک‌های اشتراک‌گذاری (vmess/vless/trojan/ss) به [ServerConfig].
class ConfigParser {
  /// چند لینک (هر خط یکی) یا یک محتوای base64 از اشتراک را می‌پذیرد.
  static List<ServerConfig> parseMany(String text) {
    var content = text.trim();
    if (!content.contains('://')) {
      final decoded = _tryB64(content);
      if (decoded != null) content = decoded;
    }
    final result = <ServerConfig>[];
    for (final line in const LineSplitter().convert(content)) {
      final cfg = parse(line.trim());
      if (cfg != null) result.add(cfg);
    }
    return result;
  }

  static ServerConfig? parse(String link) {
    try {
      if (link.startsWith('vmess://')) return _vmess(link);
      if (link.startsWith('vless://')) return _uri(link, Protocol.vless);
      if (link.startsWith('trojan://')) return _uri(link, Protocol.trojan);
      if (link.startsWith('ss://')) return _ss(link);
    } catch (_) {}
    return null;
  }

  static ServerConfig _vmess(String link) {
    final body = link.substring('vmess://'.length);
    final json = jsonDecode(_b64(body)) as Map<String, dynamic>;
    final addr = json['add'].toString();
    final port = int.parse(json['port'].toString());
    final name = (json['ps']?.toString().isNotEmpty ?? false)
        ? json['ps'].toString()
        : addr;
    return ServerConfig(
      id: _id(link),
      name: name,
      protocol: Protocol.vmess,
      address: addr,
      port: port,
      raw: link,
    );
  }

  static ServerConfig _uri(String link, Protocol p) {
    final u = Uri.parse(link);
    final name = u.fragment.isNotEmpty
        ? Uri.decodeComponent(u.fragment)
        : u.host;
    return ServerConfig(
      id: _id(link),
      name: name,
      protocol: p,
      address: u.host,
      port: u.port,
      raw: link,
    );
  }

  static ServerConfig _ss(String link) {
    var rest = link.substring('ss://'.length);
    var name = '';
    final hash = rest.indexOf('#');
    if (hash != -1) {
      name = Uri.decodeComponent(rest.substring(hash + 1));
      rest = rest.substring(0, hash);
    }
    final q = rest.indexOf('?');
    if (q != -1) rest = rest.substring(0, q);

    String hostPort;
    if (rest.contains('@')) {
      hostPort = rest.substring(rest.lastIndexOf('@') + 1);
    } else {
      final decoded = _b64(rest);
      hostPort = decoded.substring(decoded.lastIndexOf('@') + 1);
    }
    final idx = hostPort.lastIndexOf(':');
    final host = hostPort.substring(0, idx);
    final port = int.parse(hostPort.substring(idx + 1));
    return ServerConfig(
      id: _id(link),
      name: name.isEmpty ? host : name,
      protocol: Protocol.shadowsocks,
      address: host,
      port: port,
      raw: link,
    );
  }

  static String _id(String s) => s.hashCode.toRadixString(16);

  static String? _tryB64(String s) {
    try {
      return _b64(s);
    } catch (_) {
      return null;
    }
  }

  static String _b64(String s) {
    var t = s.replaceAll('-', '+').replaceAll('_', '/').trim();
    while (t.length % 4 != 0) {
      t += '=';
    }
    return utf8.decode(base64.decode(t));
  }
}
