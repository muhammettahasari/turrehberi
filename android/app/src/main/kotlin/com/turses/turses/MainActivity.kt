package com.turses.turses

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "turses/net")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "localIps" -> result.success(localIps())
                    "bindWifi" -> result.success(bindWifi())
                    "unbind" -> {
                        connectivity().bindProcessToNetwork(null)
                        result.success(true)
                    }
                    "openHotspotSettings" -> {
                        openHotspotSettings()
                        result.success(true)
                    }
                    "openWifiSettings" -> {
                        openSettings(Intent(Settings.ACTION_WIFI_SETTINGS))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun connectivity(): ConnectivityManager =
        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    /** "arayüz/ip" biçiminde tüm IPv4 adresleri (ör. "swlan0/192.168.43.1"). */
    private fun localIps(): List<String> {
        val out = ArrayList<String>()
        try {
            for (ni in Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!ni.isUp || ni.isLoopback) continue
                for (addr in Collections.list(ni.inetAddresses)) {
                    if (addr is Inet4Address) {
                        out.add(ni.name + "/" + (addr.hostAddress ?: continue))
                    }
                }
            }
        } catch (e: Exception) {
            // Liste boş döner; Dart tarafı yedek yöntemi dener.
        }
        return out
    }

    /**
     * Uygulamanın tüm bağlantılarını Wi-Fi ağına sabitler. Rehberin erişim
     * noktasında internet yoksa Android trafiği mobil veriye yönlendirebilir;
     * bu çağrı bunu engeller.
     */
    @Suppress("DEPRECATION")
    private fun bindWifi(): Boolean {
        val cm = connectivity()
        for (n in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(n) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                return cm.bindProcessToNetwork(n)
            }
        }
        cm.bindProcessToNetwork(null)
        return false
    }

    private fun openHotspotSettings() {
        val tether = Intent().setClassName("com.android.settings", "com.android.settings.TetherSettings")
        if (!openSettings(tether)) {
            openSettings(Intent(Settings.ACTION_WIRELESS_SETTINGS))
        }
    }

    private fun openSettings(intent: Intent): Boolean {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
