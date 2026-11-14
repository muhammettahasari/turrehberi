import 'dart:io';

import 'package:flutter/services.dart';

/// Telefonun bir ağ arayüzündeki IPv4 adresi.
class LocalAddr {
  LocalAddr(this.name, this.ip);

  final String name;
  final String ip;

  /// Küçük sayı = karekoda önce yazılır.
  /// 0: erişim noktası arayüzü, 1: Wi-Fi, 9: mobil veri / VPN (karekoda girmez).
  int get rank {
    final n = name.toLowerCase();
    if (n.startsWith('ap') || n.contains('swlan') || n.contains('softap') || n == 'wlan1') {
      return 0;
    }
    if (n.startsWith('wlan')) return 1;
    if (n.startsWith('rmnet') || n.startsWith('ccmni') || n.startsWith('tun') ||
        n.startsWith('dummy') || n.startsWith('v4-') || n.startsWith('rev_rmnet')) {
      return 9;
    }
    if (ip.startsWith('192.168.')) return 2;
    return 5;
  }
}

/// Android tarafındaki küçük yardımcılar (MainActivity.kt).
class Net {
  static const _ch = MethodChannel('turses/net');

  static Future<List<LocalAddr>> localAddrs() async {
    final found = <String, LocalAddr>{};
    try {
      final list = await _ch.invokeListMethod<String>('localIps') ?? const <String>[];
      for (final s in list) {
        final i = s.lastIndexOf('/');
        if (i <= 0) continue;
        final a = LocalAddr(s.substring(0, i), s.substring(i + 1));
        found[a.ip] = a;
      }
    } catch (_) {}
    try {
      for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final ad in ni.addresses) {
          found.putIfAbsent(ad.address, () => LocalAddr(ni.name, ad.address));
        }
      }
    } catch (_) {}
    final out = found.values.where((a) => !a.ip.startsWith('127.')).toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    return out;
  }

  /// Uygulamanın trafiğini Wi-Fi'a sabitler. İnterneti olmayan erişim
  /// noktasında telefon mobil veriye kaçmasın diye gerekli.
  static Future<bool> bindWifi() async {
    try {
      return await _ch.invokeMethod<bool>('bindWifi') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> unbind() async {
    try {
      await _ch.invokeMethod('unbind');
    } catch (_) {}
  }

  static Future<void> openHotspotSettings() async {
    try {
      await _ch.invokeMethod('openHotspotSettings');
    } catch (_) {}
  }

  static Future<void> openWifiSettings() async {
    try {
      await _ch.invokeMethod('openWifiSettings');
    } catch (_) {}
  }
}
