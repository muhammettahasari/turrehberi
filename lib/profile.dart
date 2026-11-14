import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'net.dart';

/// Kullanıcının adı ve kurulum durumu (telefonda saklanır).
class Profile {
  static String name = '';
  static int sdk = 0;

  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      name = sp.getString('user_name') ?? '';
    } catch (_) {}
    sdk = await Net.sdkInt();
  }

  static Future<void> saveName(String value) async {
    name = value.trim();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('user_name', name);
    } catch (_) {}
  }

  static bool get needsNearbyPermission => sdk >= 33;

  /// Kurulum ekranı atlanabilir mi: ad var ve zorunlu izinler verilmiş.
  static Future<bool> isReady() async {
    if (name.trim().length < 2) return false;
    if (!await Permission.locationWhenInUse.isGranted) return false;
    if (needsNearbyPermission && !await Permission.nearbyWifiDevices.isGranted) return false;
    return true;
  }
}
