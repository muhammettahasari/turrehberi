import 'dart:convert';

/// Rehber telefonunda açılan eşleşme sunucusunun portu.
const int kPort = 8765;

/// Ücretsiz sürümde bir rehbere bağlanabilecek en fazla dinleyici.
const int kFreeLimit = 10;

const String kAppTag = 'turses';

/// Yerel ağda internet ya da STUN sunucusu gerekmez.
const Map<String, dynamic> kRtcConfig = {
  'iceServers': <Map<String, dynamic>>[],
  'sdpSemantics': 'unified-plan',
};

/// Karekodun içindeki bilgi: rehber telefonunun ağ adresleri ve port.
class JoinInfo {
  JoinInfo(this.ips, this.port);

  final List<String> ips;
  final int port;

  String encode() =>
      jsonEncode({'app': kAppTag, 'v': 1, 'port': port, 'ips': ips});

  static JoinInfo? tryParse(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is Map && m['app'] == kAppTag && m['ips'] is List) {
        final ips = (m['ips'] as List).map((e) => e.toString()).toList();
        final port = (m['port'] as num?)?.toInt() ?? kPort;
        if (ips.isNotEmpty) return JoinInfo(ips, port);
      }
    } catch (_) {}
    return null;
  }
}
