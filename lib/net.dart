import 'dart:io';

import 'package:flutter/services.dart';

import 'protocol.dart';

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

/// Erişim noktası açılamadığında kullanıcıya gösterilecek açıklama.
class HotspotError implements Exception {
  HotspotError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Android tarafındaki yardımcılar (MainActivity.kt).
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

  /// Uygulamanın kendi Wi-Fi ağını (yerel erişim noktası) açar.
  static Future<WifiCreds> startLocalHotspot() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('startLocalHotspot');
      final ssid = (m?['ssid'] ?? '').toString();
      if (ssid.isEmpty) throw HotspotError('Ağ açıldı ama adı okunamadı.');
      return WifiCreds(ssid, (m?['pass'] ?? '').toString(), (m?['sec'] as num?)?.toInt() ?? 1);
    } on PlatformException catch (e) {
      throw HotspotError(_hotspotMessage(e));
    }
  }

  static String _hotspotMessage(PlatformException e) {
    if (e.code == 'failed') {
      switch (e.message) {
        case '1':
          return 'Uygun kanal bulunamadı. Biraz sonra tekrar deneyin.';
        case '3':
          return 'Telefonun normal erişim noktası ya da başka bir Wi-Fi paylaşımı açık. '
              'Onu kapatıp tekrar deneyin.';
        case '4':
          return 'Bu telefonda erişim noktası açmak kısıtlanmış.';
      }
      return 'Ağ açılamadı (kod ${e.message}).';
    }
    if (e.code == 'unsupported') return 'Bu özellik Android 8 ve üstünde çalışır.';
    return 'Ağ açılamadı. Konum servisini açıp "Yakındaki cihazlar / Konum" iznini verin. '
        '(${e.message})';
  }

  static Future<void> stopLocalHotspot() async {
    try {
      await _ch.invokeMethod('stopLocalHotspot');
    } catch (_) {}
  }

  /// Turist telefonunu rehberin ağına bağlar. Android bir onay penceresi açar.
  static Future<bool> connectWifi(WifiCreds w) async {
    try {
      return await _ch.invokeMethod<bool>(
              'connectWifi', {'ssid': w.ssid, 'pass': w.pass, 'sec': w.sec}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> wifiEnabled() async {
    try {
      return await _ch.invokeMethod<bool>('wifiEnabled') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// "enabled": açıldı, "panel": kullanıcıya Wi-Fi paneli gösterildi, "failed".
  static Future<String> enableWifi() async {
    try {
      return await _ch.invokeMethod<String>('enableWifi') ?? 'failed';
    } catch (_) {
      return 'failed';
    }
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

  /// Ağ bağlantısını ve sabitlemeyi bırakır.
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

  static Future<bool> is64Bit() async {
    try {
      return await _ch.invokeMethod<bool>('is64') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<String> updateDir() async {
    final d = await _ch.invokeMethod<String>('updateDir');
    if (d == null) throw Exception('Güncelleme klasörü yok');
    return d;
  }

  /// "started", "permission" (kullanıcı izin vermeli), "missing" ya da "failed".
  static Future<String> installApk(String path) async {
    try {
      return await _ch.invokeMethod<String>('installApk', {'path': path}) ?? 'failed';
    } catch (_) {
      return 'failed';
    }
  }
}
