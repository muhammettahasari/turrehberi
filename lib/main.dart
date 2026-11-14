import 'package:flutter/material.dart';

import 'guide_page.dart';
import 'listener_page.dart';
import 'net.dart';
import 'profile.dart';
import 'setup_page.dart';
import 'updater.dart';

void main() => runApp(const TurSesApp());

const kBrand = Color(0xFF0F3D3E);
const kAccent = Color(0xFFF2A541);
const kBg = Color(0xFFF4F1EA);

class TurSesApp extends StatelessWidget {
  const TurSesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TurSes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBrand,
          primary: kBrand,
          secondary: kAccent,
        ),
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(backgroundColor: kBg, foregroundColor: kBrand),
      ),
      home: const _StartGate(),
    );
  }
}

/// Açılışta: ad ve izinler tamamsa ana ekran, değilse kurulum.
class _StartGate extends StatefulWidget {
  const _StartGate();

  @override
  State<_StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<_StartGate> {
  bool? _ready;

  @override
  void initState() {
    super.initState();
    () async {
      await Profile.load();
      final ok = await Profile.isReady();
      if (mounted) setState(() => _ready = ok);
    }();
  }

  @override
  Widget build(BuildContext context) {
    final r = _ready;
    if (r == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return r ? const HomePage() : const SetupPage();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  UpdateInfo? _update;
  double? _progress; // null: indirme yok
  String? _updateMsg;

  @override
  void initState() {
    super.initState();
    _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    final u = await Updater.check();
    if (mounted && u != null) setState(() => _update = u);
  }

  Future<void> _installUpdate() async {
    final u = _update;
    if (u == null || _progress != null) return;
    setState(() {
      _progress = 0;
      _updateMsg = null;
    });
    try {
      final f = await Updater.download(u, (p) {
        if (mounted) setState(() => _progress = p);
      });
      final r = await Net.installApk(f.path);
      if (!mounted) return;
      setState(() {
        _progress = null;
        _updateMsg = switch (r) {
          'permission' =>
            'Açılan ekranda "Bu kaynaktan izin ver"i açın, geri dönüp tekrar "Güncelle"ye dokunun.',
          'started' => 'Açılan pencerede "Güncelle"ye dokunun.',
          _ => 'Güncelleme başlatılamadı.',
        };
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _updateMsg = 'İndirilemedi: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          children: [
            if (_update != null) _updateBanner(),
            const Icon(Icons.headphones_rounded, size: 56, color: kBrand),
            const SizedBox(height: 8),
            Text('TurSes',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: kBrand, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Rehber konuşur, grup kendi kulaklığından dinler.',
                textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Adınız: ${Profile.name}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                TextButton(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SetupPage(fromHome: true)));
                    if (mounted) setState(() {});
                  },
                  child: const Text('Değiştir'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _RoleCard(
              icon: Icons.mic_rounded,
              title: 'Rehber',
              subtitle: 'Ağı aç, karekodu göster, konuş.',
              color: kBrand,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const GuidePage())),
            ),
            const SizedBox(height: 14),
            _RoleCard(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Turist',
              subtitle: 'Karekodu okut, rehberin ağına bağlan, dinle.',
              color: kAccent,
              dark: true,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const ListenerPage())),
            ),
            const SizedBox(height: 24),
            Text(
              'Deneme sürümü ${kBuild == 0 ? '' : kBuild} · '
              'Ücretsiz: rehber başına en fazla 10 dinleyici',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _updateBanner() {
    final u = _update!;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0D28F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Yeni sürüm hazır: deneme ${u.build}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_progress != null) ...[
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 6),
            Text('İndiriliyor… %${((_progress ?? 0) * 100).round()}'),
          ] else
            FilledButton.icon(
              onPressed: _installUpdate,
              icon: const Icon(Icons.system_update_rounded),
              label: const Text('Güncelle'),
            ),
          if (_updateMsg != null) ...[
            const SizedBox(height: 6),
            Text(_updateMsg!, style: const TextStyle(fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.dark = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? const Color(0xFF17282A) : Colors.white;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Icon(icon, size: 44, color: fg),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: fg, fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: fg.withOpacity(0.85))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
