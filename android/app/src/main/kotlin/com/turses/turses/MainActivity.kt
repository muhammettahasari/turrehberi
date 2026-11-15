package com.turses.turses

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections

class MainActivity : FlutterActivity() {

    private val main = Handler(Looper.getMainLooper())

    /** Mikrofon ve çalma (yerel ağ sesi). */
    private val audio = AudioEngine()

    /** Rehber: uygulamanın açtığı yerel erişim noktası. */
    private var hotspot: WifiManager.LocalOnlyHotspotReservation? = null

    /** Turist: karekoddaki ağa yapılan bağlantı. */
    private var wifiCallback: ConnectivityManager.NetworkCallback? = null
    private var wifiNetwork: Network? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "turses/mic").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                audio.sink = events
            }

            override fun onCancel(arguments: Any?) {
                audio.sink = null
            }
        })
        MethodChannel(messenger, "turses/audio").setMethodCallHandler { call, result ->
            when (call.method) {
                "startCapture" -> result.success(audio.startCapture())
                "stopCapture" -> {
                    audio.stopCapture()
                    result.success(true)
                }
                "startPlayback" -> result.success(audio.startPlayback())
                "stopPlayback" -> {
                    audio.stopPlayback()
                    result.success(true)
                }
                "play" -> {
                    val frame = call.arguments as? ByteArray
                    if (frame != null) audio.play(frame)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "turses/net")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "localIps" -> result.success(localIps())
                    "startLocalHotspot" -> startLocalHotspot(result)
                    "stopLocalHotspot" -> {
                        stopLocalHotspot()
                        result.success(true)
                    }
                    "connectWifi" -> connectWifi(
                        call.argument<String>("ssid") ?: "",
                        call.argument<String>("pass"),
                        call.argument<Int>("sec") ?: 1,
                        result
                    )
                    "bindWifi" -> result.success(bindWifi())
                    "wifiEnabled" -> result.success(wifiManager().isWifiEnabled)
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "locationEnabled" -> result.success(locationEnabled())
                    "openLocationSettings" -> {
                        startSafely(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                        result.success(true)
                    }
                    "enableWifi" -> result.success(enableWifi())
                    "unbind" -> {
                        releaseWifi()
                        result.success(true)
                    }
                    "openHotspotSettings" -> {
                        openHotspotSettings()
                        result.success(true)
                    }
                    "openWifiSettings" -> {
                        startSafely(Intent(Settings.ACTION_WIFI_SETTINGS))
                        result.success(true)
                    }
                    "is64" -> result.success(Build.SUPPORTED_64_BIT_ABIS.isNotEmpty())
                    "updateDir" -> {
                        val d = File(cacheDir, "updates")
                        d.mkdirs()
                        result.success(d.absolutePath)
                    }
                    "installApk" -> result.success(installApk(call.argument<String>("path") ?: ""))
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        audio.stopCapture()
        audio.stopPlayback()
        stopLocalHotspot()
        releaseWifi()
        super.onDestroy()
    }

    private fun connectivity(): ConnectivityManager =
        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private fun wifiManager(): WifiManager =
        applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

    // ---------------------------------------------------------------- adresler

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

    // ------------------------------------------------- rehber: kendi Wi-Fi ağı

    private fun startLocalHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("unsupported", "Android 8 gerekli", null)
            return
        }
        val existing = hotspot
        if (existing != null) {
            result.success(hotspotInfo(existing))
            return
        }
        var replied = false
        try {
            wifiManager().startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                    hotspot = reservation
                    if (!replied) {
                        replied = true
                        result.success(hotspotInfo(reservation))
                    }
                }

                override fun onStopped() {
                    hotspot = null
                }

                override fun onFailed(reason: Int) {
                    if (!replied) {
                        replied = true
                        result.error("failed", reason.toString(), null)
                    }
                }
            }, main)
        } catch (e: Exception) {
            if (!replied) {
                replied = true
                result.error("exception", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun hotspotInfo(r: WifiManager.LocalOnlyHotspotReservation): Map<String, Any?> {
        var ssid: String? = null
        var pass: String? = null
        var sec = 1
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val c = r.softApConfiguration
            ssid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                c.wifiSsid?.toString()
            } else {
                c.ssid
            }
            pass = c.passphrase
            sec = c.securityType
        } else {
            val c = r.wifiConfiguration
            ssid = c?.SSID
            pass = c?.preSharedKey
        }
        return mapOf(
            "ssid" to ssid?.removeSurrounding("\""),
            "pass" to pass?.removeSurrounding("\""),
            "sec" to sec
        )
    }

    private fun stopLocalHotspot() {
        try {
            hotspot?.close()
        } catch (e: Exception) {
        }
        hotspot = null
    }

    // ------------------------------------------- turist: rehberin ağına bağlan

    private fun connectWifi(ssid: String, pass: String?, sec: Int, result: MethodChannel.Result) {
        releaseWifi()
        if (ssid.isEmpty()) {
            result.success(false)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(legacyConnect(ssid, pass))
            return
        }
        val builder = WifiNetworkSpecifier.Builder().setSsid(ssid)
        if (!pass.isNullOrEmpty()) {
            if (sec == 3) builder.setWpa3Passphrase(pass) else builder.setWpa2Passphrase(pass)
        }
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(builder.build())
            .build()
        val cm = connectivity()
        var replied = false
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                wifiNetwork = network
                cm.bindProcessToNetwork(network)
                main.post {
                    if (!replied) {
                        replied = true
                        result.success(true)
                    }
                }
            }

            override fun onUnavailable() {
                main.post {
                    if (!replied) {
                        replied = true
                        result.success(false)
                    }
                }
            }

            override fun onLost(network: Network) {
                if (wifiNetwork == network) {
                    wifiNetwork = null
                    cm.bindProcessToNetwork(null)
                }
            }
        }
        wifiCallback = cb
        try {
            cm.requestNetwork(request, cb, 60000)
        } catch (e: Exception) {
            wifiCallback = null
            if (!replied) {
                replied = true
                result.success(false)
            }
        }
    }

    /** Android 9 ve altı: ağı kaydedip bağlan. */
    @Suppress("DEPRECATION")
    private fun legacyConnect(ssid: String, pass: String?): Boolean {
        return try {
            val wm = wifiManager()
            val conf = WifiConfiguration()
            conf.SSID = "\"" + ssid + "\""
            if (pass.isNullOrEmpty()) {
                conf.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
            } else {
                conf.preSharedKey = "\"" + pass + "\""
            }
            val id = wm.addNetwork(conf)
            if (id == -1) return false
            wm.disconnect()
            wm.enableNetwork(id, true)
            wm.reconnect()
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Uygulamanın tüm bağlantılarını Wi-Fi ağına sabitler. Rehberin ağında
     * internet yoksa Android trafiği mobil veriye yönlendirebilir; bu çağrı
     * bunu engeller.
     */
    @Suppress("DEPRECATION")
    private fun bindWifi(): Boolean {
        val cm = connectivity()
        val own = wifiNetwork
        if (own != null) return cm.bindProcessToNetwork(own)
        for (n in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(n) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                return cm.bindProcessToNetwork(n)
            }
        }
        cm.bindProcessToNetwork(null)
        return false
    }

    /**
     * Wi-Fi'ı açar. Android 10+ uygulamaların Wi-Fi'ı doğrudan açmasına izin
     * vermez; bunun yerine tek dokunuşla açılan sistem paneli gösterilir.
     * Dönüş: "enabled", "panel" ya da "failed".
     */
    @Suppress("DEPRECATION")
    private fun enableWifi(): String {
        val wm = wifiManager()
        if (wm.isWifiEnabled) return "enabled"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return if (startSafely(Intent(Settings.Panel.ACTION_WIFI))) "panel"
            else if (startSafely(Intent(Settings.ACTION_WIFI_SETTINGS))) "panel"
            else "failed"
        }
        return try {
            if (wm.setWifiEnabled(true)) "enabled" else "failed"
        } catch (e: Exception) {
            "failed"
        }
    }

    @Suppress("DEPRECATION")
    private fun locationEnabled(): Boolean {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            lm.isLocationEnabled
        } else {
            lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }
    }

    private fun releaseWifi() {
        val cm = connectivity()
        val cb = wifiCallback
        wifiCallback = null
        wifiNetwork = null
        if (cb != null) {
            try {
                cm.unregisterNetworkCallback(cb)
            } catch (e: Exception) {
            }
        }
        cm.bindProcessToNetwork(null)
    }

    // ---------------------------------------------------------------- ayarlar

    private fun openHotspotSettings() {
        val tether = Intent().setClassName("com.android.settings", "com.android.settings.TetherSettings")
        if (!startSafely(tether)) {
            startSafely(Intent(Settings.ACTION_WIRELESS_SETTINGS))
        }
    }

    private fun startSafely(intent: Intent): Boolean {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    // ------------------------------------------------------------- güncelleme

    private fun installApk(path: String): String {
        val file = File(path)
        if (!file.exists()) return "missing"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startSafely(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
            )
            return "permission"
        }
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (startSafely(intent)) "started" else "failed"
        } catch (e: Exception) {
            "failed"
        }
    }
}
