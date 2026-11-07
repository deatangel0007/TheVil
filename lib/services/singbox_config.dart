import 'dart:convert';

/// تبدیل لینک اشتراک‌گذاری (vmess/vless/trojan/ss) به کانفیگ JSON برای sing-box.
/// فرمت هدف: sing-box نسخه‌ی 1.12.x
class SingboxConfig {
  static String fromLink(String link) {
    final config = {
      'log': {'level': 'info', 'timestamp': true},
      'dns': {
        'servers': [
          {
            'type': 'udp',
            'tag': 'dns-remote',
            'server': '1.1.1.1',
            'detour': 'proxy',
          },
          {'type': 'udp', 'tag': 'dns-direct', 'server': '8.8.8.8'},
        ],
        'final': 'dns-remote',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': ['172.19.0.1/30'],
          'mtu': 1500,
          'auto_route': true,
          'stack': 'mixed',
        },
      ],
      'outbounds': [
        _outbound(link),
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'rules': [
          {'action': 'sniff'},
          {'protocol': 'dns', 'action': 'hijack-dns'},
          {'ip_is_private': true, 'outbound': 'direct'},
        ],
        'final': 'proxy',
        'auto_detect_interface': true,
        'default_domain_resolver': 'dns-direct',
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  // ---------------------------------------------------------------- outbounds

  static Map<String, dynamic> _outbound(String link) {
    if (link.startsWith('vmess://')) return _vmess(link);
    if (link.startsWith('ss://')) return _shadowsocks(link);
    final u = Uri.parse(link);
    final q = Map<String, String>.from(u.queryParameters);

    if (link.startsWith('vless://')) {
      final flow = q['flow'] ?? '';
      return {
        'type': 'vless',
        'tag': 'proxy',
        'server': u.host,
        'server_port': u.port,
        'uuid': Uri.decodeComponent(u.userInfo),
        if (flow.isNotEmpty) 'flow': flow,
        'packet_encoding': 'xudp',
        if (_tls(q, u.host) != null) 'tls': _tls(q, u.host),
        if (_transport(q) != null) 'transport': _transport(q),
      };
    }

    if (link.startsWith('trojan://')) {
      q.putIfAbsent('security', () => 'tls'); // تروجان پیش‌فرض TLS است
      return {
        'type': 'trojan',
        'tag': 'proxy',
        'server': u.host,
        'server_port': u.port,
        'password': Uri.decodeComponent(u.userInfo),
        if (_tls(q, u.host) != null) 'tls': _tls(q, u.host),
        if (_transport(q) != null) 'transport': _transport(q),
      };
    }

    throw FormatException('پروتکل پشتیبانی نمی‌شود: $link');
  }

  static Map<String, dynamic> _vmess(String link) {
    final j = jsonDecode(_b64(link.substring('vmess://'.length)))
        as Map<String, dynamic>;
    String s(String k) => j[k]?.toString() ?? '';

    final net = s('net').isEmpty ? 'tcp' : s('net');
    final q = <String, String>{
      'type': net,
      'security': s('tls') == 'tls' ? 'tls' : 'none',
      'sni': s('sni'),
      'host': s('host'),
      'path': s('path'),
      'alpn': s('alpn'),
      'fp': s('fp'),
      // در vmess مسیر gRPC همان نام سرویس است
      'serviceName': s('path'),
    }..removeWhere((_, v) => v.isEmpty);

    final addr = s('add');
    final scy = s('scy');
    return {
      'type': 'vmess',
      'tag': 'proxy',
      'server': addr,
      'server_port': int.parse(s('port')),
      'uuid': s('id'),
      'security': scy.isEmpty ? 'auto' : scy,
      'alter_id': int.tryParse(s('aid')) ?? 0,
      if (_tls(q, addr) != null) 'tls': _tls(q, addr),
      if (_transport(q) != null) 'transport': _transport(q),
    };
  }

  static Map<String, dynamic> _shadowsocks(String link) {
    var rest = link.substring('ss://'.length);
    final hash = rest.indexOf('#');
    if (hash != -1) rest = rest.substring(0, hash);
    final qi = rest.indexOf('?');
    if (qi != -1) rest = rest.substring(0, qi);

    String userInfo, hostPort;
    if (rest.contains('@')) {
      final at = rest.lastIndexOf('@');
      userInfo = rest.substring(0, at);
      hostPort = rest.substring(at + 1);
      if (!userInfo.contains(':')) {
        userInfo = _b64(userInfo);
      } else {
        userInfo = Uri.decodeComponent(userInfo);
      }
    } else {
      final decoded = _b64(rest); // method:password@host:port
      final at = decoded.lastIndexOf('@');
      userInfo = decoded.substring(0, at);
      hostPort = decoded.substring(at + 1);
    }
    final colon = userInfo.indexOf(':');
    final pi = hostPort.lastIndexOf(':');
    return {
      'type': 'shadowsocks',
      'tag': 'proxy',
      'server': hostPort.substring(0, pi),
      'server_port': int.parse(hostPort.substring(pi + 1)),
      'method': userInfo.substring(0, colon),
      'password': userInfo.substring(colon + 1),
    };
  }

  // ------------------------------------------------------------ tls / transport

  static Map<String, dynamic>? _tls(Map<String, String> q, String address) {
    final sec = q['security'] ?? '';
    if (sec != 'tls' && sec != 'reality') return null;

    final sni = (q['sni'] ?? '').isNotEmpty ? q['sni']! : address;
    final tls = <String, dynamic>{'enabled': true, 'server_name': sni};

    if (q['allowInsecure'] == '1' || q['insecure'] == '1') {
      tls['insecure'] = true;
    }
    if ((q['alpn'] ?? '').isNotEmpty) tls['alpn'] = q['alpn']!.split(',');
    if ((q['fp'] ?? '').isNotEmpty) {
      tls['utls'] = {'enabled': true, 'fingerprint': q['fp']};
    }
    if (sec == 'reality') {
      tls['reality'] = {
        'enabled': true,
        'public_key': q['pbk'] ?? '',
        'short_id': q['sid'] ?? '',
      };
      tls.putIfAbsent('utls', () => {'enabled': true, 'fingerprint': 'chrome'});
    }
    return tls;
  }

  static Map<String, dynamic>? _transport(Map<String, String> q) {
    final host = q['host'] ?? '';
    final path = (q['path'] ?? '').isEmpty ? '/' : q['path']!;
    switch (q['type'] ?? 'tcp') {
      case 'ws':
        return {
          'type': 'ws',
          'path': path,
          if (host.isNotEmpty) 'headers': {'Host': host},
        };
      case 'grpc':
        return {'type': 'grpc', 'service_name': q['serviceName'] ?? ''};
      case 'http':
      case 'h2':
        return {
          'type': 'http',
          'path': path,
          if (host.isNotEmpty) 'host': host.split(','),
        };
      case 'httpupgrade':
        return {
          'type': 'httpupgrade',
          'path': path,
          if (host.isNotEmpty) 'host': host,
        };
      default:
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
