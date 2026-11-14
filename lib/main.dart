import 'package:flutter/material.dart';

import 'guide_page.dart';
import 'listener_page.dart';

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
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          children: [
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
            const SizedBox(height: 28),
            _RoleCard(
              icon: Icons.mic_rounded,
              title: 'Rehber',
              subtitle: 'Mobil erişim noktasını aç, karekodu göster, konuş.',
              color: kBrand,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const GuidePage())),
            ),
            const SizedBox(height: 14),
            _RoleCard(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Turist',
              subtitle: 'Rehberin ağına bağlan, karekodu okut, dinle.',
              color: kAccent,
              dark: true,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const ListenerPage())),
            ),
            const SizedBox(height: 24),
            const Text(
              'Deneme sürümü · Ücretsiz: rehber başına en fazla 10 dinleyici',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
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
