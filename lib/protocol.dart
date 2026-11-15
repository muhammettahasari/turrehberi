import 'dart:convert';

/// Rehber telefonunda açılan eşleşme sunucusunun portu.
const int kPort = 8765;

/// Ücretsiz sürümde bir rehbere bağlanabilecek en fazla dinleyici.
const int kFreeLimit = 10;

const String kAppTag = 'turses';

/// Wi-Fi ağ bilgisi. sec: 0 açık, 1 WPA2, 2 WPA2/WPA3 geçiş, 3 WPA3.
class WifiCreds {
  WifiCreds(this.ssid, this.pass, [this.sec = 1]);

  final String ssid;
  final String pass;
  final int sec;

  Map<String, dynamic> toJson() => {'s': ssid, 'p': pass, 'sec': sec};

  static WifiCreds? fromJson(dynamic m) {
    if (m is! Map) return null;
    final s = (m['s'] ?? '').toString();
    if (s.isEmpty) return null;
    return WifiCreds(s, (m['p'] ?? '').toString(), (m['sec'] as num?)?.toInt() ?? 1);
  }
}

/// Karekodun içindeki bilgi: Wi-Fi ağı (varsa), rehber telefonunun adresleri, port.
class JoinInfo {
  JoinInfo(this.ips, this.port, [this.wifi]);

  final List<String> ips;
  final int port;
  final WifiCreds? wifi;

  String encode() => jsonEncode({
        'app': kAppTag,
        'v': 1,
        'port': port,
        'ips': ips,
        if (wifi != null) 'w': wifi!.toJson(),
      });

  static JoinInfo? tryParse(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is Map && m['app'] == kAppTag && m['ips'] is List) {
        final ips = (m['ips'] as List).map((e) => e.toString()).toList();
        final port = (m['port'] as num?)?.toInt() ?? kPort;
        if (ips.isNotEmpty) return JoinInfo(ips, port, WifiCreds.fromJson(m['w']));
      }
    } catch (_) {}
    return null;
  }
}
