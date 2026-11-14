import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'main.dart';
import 'net.dart';
import 'profile.dart';

/// İlk açılış: ad, izinler, Wi-Fi ve konumun açılması.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key, this.fromHome = false});

  /// Ana ekrandan "adı değiştir" ile açıldıysa bitince geri döner.
  final bool fromHome;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> with WidgetsBindingObserver {
  final _nameCtl = TextEditingController(text: Profile.name);
  bool _loc = false, _nearby = false, _mic = false, _cam = false;
  bool _wifiOn = false, _locOn = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nameCtl.addListener(() => setState(() {}));
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ayarlardan dönünce durumu yenile.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final loc = await Permission.locationWhenInUse.isGranted;
    final nearby =
        !Profile.needsNearbyPermission || await Permission.nearbyWifiDevices.isGranted;
    final mic = await Permission.microphone.isGranted;
    final cam = await Permission.camera.isGranted;
    final wifiOn = await Net.wifiEnabled();
    final locOn = await Net.locationEnabled();
    if (!mounted) return;
    setState(() {
      _loc = loc;
      _nearby = nearby;
      _mic = mic;
      _cam = cam;
      _wifiOn = wifiOn;
      _locOn = locOn;
    });
  }

  /// Tek düğmeyle hepsini iste; kapalı olanları açtır.
  Future<void> _allowAll() async {
    setState(() => _busy = true);
    await [
      Permission.locationWhenInUse,
      if (Profile.needsNearbyPermission) Permission.nearbyWifiDevices,
      Permission.microphone,
      Permission.camera,
    ].request();
    await _refresh();
    if (!_wifiOn) {
      await Net.enableWifi();
    } else if (!_locOn) {
      await Net.openLocationSettings();
    }
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _ask(Permission p) async {
    final st = await p.request();
    if (st.isPermanentlyDenied) await openAppSettings();
    await _refresh();
  }

  String get _name => _nameCtl.text.trim();

  bool get _ready => _name.length >= 2 && _loc && _nearby && _wifiOn && _locOn;

  Future<void> _continue() async {
    await Profile.saveName(_name);
    if (!mounted) return;
    if (widget.fromHome) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kurulum')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const Text(
              'TurSes\'in çalışması için birkaç izin gerekiyor. Rehber de turist de aynı '
              'adımları bir kez yapar.',
            ),
            const SizedBox(height: 18),
            const Text('Adınız ve soyadınız',
                style: TextStyle(fontWeight: FontWeight.w700, color: kBrand)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtl,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'Örn. Ayşe Yılmaz',
                helperText: 'Zorunlu. Rehberin listesinde ve yoklamada bu ad görünür.',
                filled: true,
                fillColor: Colors.white,
                border: const OutlineInputBorder(),
                errorText: _nameCtl.text.isNotEmpty && _name.length < 2 ? 'En az 2 harf' : null,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _allowAll,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.verified_user_rounded),
              label: const Text('Tüm izinleri ver ve aç'),
            ),
            const SizedBox(height: 10),
            _row(
              ok: _loc,
              icon: Icons.location_on_rounded,
              title: 'Konum izni',
              text: 'Wi-Fi ağı kurmak ve haritada grubu görmek için.',
              onFix: () => _ask(Permission.locationWhenInUse),
            ),
            if (Profile.needsNearbyPermission)
              _row(
                ok: _nearby,
                icon: Icons.wifi_find_rounded,
                title: 'Yakındaki Wi-Fi cihazları izni',
                text: 'Rehberin ağını açmak ve ona bağlanmak için.',
                onFix: () => _ask(Permission.nearbyWifiDevices),
              ),
            _row(
              ok: _wifiOn,
              icon: Icons.wifi_rounded,
              title: 'Wi-Fi açık',
              text: 'Ses Wi-Fi üzerinden gelir. İnternet gerekmez.',
              onFix: () async {
                await Net.enableWifi();
                await _refresh();
              },
              fixLabel: 'Aç',
            ),
            _row(
              ok: _locOn,
              icon: Icons.my_location_rounded,
              title: 'Konum servisi açık',
              text: 'Android, Wi-Fi ağı kurmak için konumun açık olmasını istiyor.',
              onFix: Net.openLocationSettings,
              fixLabel: 'Aç',
            ),
            _row(
              ok: _mic,
              icon: Icons.mic_rounded,
              title: 'Mikrofon (rehber için)',
              text: 'Rehberin sesini gruba iletmek için.',
              onFix: () => _ask(Permission.microphone),
              optional: true,
            ),
            _row(
              ok: _cam,
              icon: Icons.qr_code_scanner_rounded,
              title: 'Kamera (turist için)',
              text: 'Rehberin karekodunu okutmak için.',
              onFix: () => _ask(Permission.camera),
              optional: true,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _ready ? _continue : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              child: Text(widget.fromHome ? 'Kaydet' : 'Devam'),
            ),
            if (!_ready) ...[
              const SizedBox(height: 8),
              const Text(
                'Devam etmek için adınızı yazın; konum, Wi-Fi ve (varsa) yakındaki cihazlar '
                'izinlerini verin, Wi-Fi ile konumu açın.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row({
    required bool ok,
    required IconData icon,
    required String title,
    required String text,
    required VoidCallback onFix,
    String fixLabel = 'İzin ver',
    bool optional = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2DDD2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: kBrand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(text, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          if (ok)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.check_circle_rounded, color: Color(0xFF1F8A5B)),
            )
          else
            TextButton(
              onPressed: onFix,
              child: Text(optional ? '$fixLabel (isteğe bağlı)' : fixLabel,
                  style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
