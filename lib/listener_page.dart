import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'audio.dart';
import 'main.dart';
import 'net.dart';
import 'protocol.dart';

enum _Phase { idle, connecting, listening, full }

const _kListening = 'Rehberi dinliyorsunuz';

class ListenerPage extends StatefulWidget {
  const ListenerPage({super.key});

  @override
  State<ListenerPage> createState() => _ListenerPageState();
}

class _ListenerPageState extends State<ListenerPage> {
  final _name = TextEditingController();
  JoinInfo? _info;
  _Phase _phase = _Phase.idle;
  String _status = '';

  WebSocket? _ws;
  bool _playing = false;
  bool _guideMuted = false;
  DateTime? _lastAudio;
  Timer? _watch;
  Timer? _retry;
  bool _closing = false;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _setupAudio();
  }

  @override
  void dispose() {
    _closing = true;
    _retry?.cancel();
    _cleanup();
    Net.unbind();
    WakelockPlus.disable();
    _name.dispose();
    super.dispose();
  }

  /// Ses "medya" olarak çalınır (AudioEngine.kt): kulaklıkta (kablolu ya da
  /// Bluetooth) çıkar, ses tuşları medya sesini ayarlar.
  Future<void> _setupAudio() async {
    try {
      await Permission.bluetoothConnect.request();
    } catch (_) {}
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _scan() async {
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      _snack('Karekod okumak için kamera izni gerekli.');
      return;
    }
    if (!mounted) return;
    final raw = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));
    if (raw == null) return;
    if (raw.startsWith('WIFI:')) {
      _snack('Bu bir Wi-Fi karekodu. Önce telefonunuzun kamerasıyla okutup ağa bağlanın, '
          'sonra rehberin TurSes karekodunu okutun.');
      return;
    }
    final info = JoinInfo.tryParse(raw);
    if (info == null) {
      _snack('Bu bir TurSes karekodu değil.');
      return;
    }
    _info = info;
    _closing = false;
    if (info.wifi != null) {
      await _joinWifi();
      if (_closing || !mounted) return;
    } else {
      setState(() {
        _phase = _Phase.connecting;
        _status = 'Rehbere bağlanılıyor…';
      });
    }
    _connect();
  }

  /// Karekoddaki Wi-Fi ağına bağlanır. Android "Bağlan" onayı ister.
  Future<void> _joinWifi() async {
    final w = _info?.wifi;
    if (w == null) return;
    _setStatus('"${w.ssid}" ağına bağlanılıyor…\nAçılan pencerede ağı seçip "Bağlan"a dokunun.',
        _Phase.connecting);
    final ok = await Net.connectWifi(w);
    if (!ok) {
      _setStatus('Ağa otomatik bağlanılamadı. Wi-Fi ayarlarından "${w.ssid}" ağına elle '
          'bağlanın; uygulama bağlanmayı denemeye devam ediyor…');
    } else {
      _setStatus('Ağa bağlanıldı, rehbere bağlanılıyor…');
    }
  }

  Future<void> _connect() async {
    final info = _info;
    if (info == null || _closing || _connecting) return;
    _connecting = true;
    final onWifi = await Net.bindWifi();
    WebSocket? ws;
    for (final ip in info.ips) {
      try {
        ws = await WebSocket.connect('ws://$ip:${info.port}')
            .timeout(const Duration(seconds: 3));
        break;
      } catch (_) {}
    }
    _connecting = false;
    if (_closing) {
      ws?.close();
      return;
    }
    if (ws == null) {
      _setStatus(onWifi
          ? 'Rehbere ulaşılamadı. Rehberin erişim noktasına bağlı olduğunuzdan emin olun. '
              'Yeniden deneniyor…'
          : 'Wi-Fi bağlantısı yok. Önce rehberin erişim noktasına bağlanın. Yeniden deneniyor…');
      _scheduleRetry();
      return;
    }
    _ws = ws;
    ws.pingInterval = const Duration(seconds: 4);
    ws.listen(
      _onMessage,
      onDone: _onLost,
      onError: (_) => _onLost(),
      cancelOnError: true,
    );
    _setStatus('Rehbere bağlanıldı, ses açılıyor…');
    _send({'type': 'join', 'name': _name.text.trim()});
  }

  void _send(Map<String, dynamic> m) {
    try {
      _ws?.add(jsonEncode(m));
    } catch (_) {}
  }

  void _setStatus(String s, [_Phase? phase]) {
    if (!mounted) return;
    setState(() {
      _status = s;
      if (phase != null) _phase = phase;
    });
  }

  Future<void> _onMessage(dynamic data) async {
    if (data is! String) {
      // 20 ms'lik ses parçası
      if (!_playing) return;
      final frame = data is Uint8List ? data : Uint8List.fromList(data as List<int>);
      NativeAudio.play(frame);
      final first = _lastAudio == null;
      _lastAudio = DateTime.now();
      if (first || _phase != _Phase.listening || _status != _kListening) {
        _setStatus(_kListening, _Phase.listening);
      }
      return;
    }
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(data) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'welcome':
        {
          _guideMuted = m['muted'] == true;
          _playing = await NativeAudio.startPlayback();
          if (!_playing) {
            _setStatus('Ses çalınamadı. Telefonu yeniden başlatıp tekrar deneyin.');
            return;
          }
          _setStatus(_guideMuted ? 'Bağlandınız. Rehber şu an sessizde.' : 'Bağlandınız, ses bekleniyor…',
              _Phase.listening);
          _watch?.cancel();
          _watch = Timer.periodic(const Duration(seconds: 1), (_) => _checkSilence());
        }
      case 'muted':
        {
          _guideMuted = m['value'] == true;
          if (_guideMuted) _setStatus('Rehber şu an sessizde.', _Phase.listening);
        }
      case 'full':
        {
          _closing = true;
          _cleanup();
          final limit = m['limit'] ?? kFreeLimit;
          _setStatus('Bu tur dolu. Ücretsiz sürümde bir rehbere en fazla $limit kişi bağlanabilir.',
              _Phase.full);
        }
    }
  }

  /// Bağlıyken ses kesilirse kullanıcıya söyle.
  void _checkSilence() {
    if (!mounted || _phase != _Phase.listening || _guideMuted) return;
    final last = _lastAudio;
    if (last != null && DateTime.now().difference(last) > const Duration(seconds: 3)) {
      _setStatus('Ses gelmiyor; bağlantı zayıf olabilir. Rehbere yaklaşın.');
    }
  }

  void _onLost() {
    if (_closing) return;
    _cleanup();
    _setStatus('Bağlantı koptu, yeniden bağlanılıyor…', _Phase.connecting);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), () {
      if (!_closing && mounted) _connect();
    });
  }

  void _cleanup() {
    _watch?.cancel();
    _watch = null;
    _playing = false;
    _lastAudio = null;
    NativeAudio.stopPlayback();
    final ws = _ws;
    _ws = null;
    try {
      ws?.close();
    } catch (_) {}
  }

  void _leave() {
    _closing = true;
    _retry?.cancel();
    _send({'type': 'leave'});
    _cleanup();
    Net.unbind();
    setState(() {
      _phase = _Phase.idle;
      _status = '';
    });
  }

  // ---------------- arayüz ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Turist')),
      body: SafeArea(
        child: _phase == _Phase.idle ? _idleView() : _activeView(),
      ),
    );
  }

  Widget _idleView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _step('1', 'Adınızı yazın', 'Rehber listesinde bu isimle görünürsünüz.'),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          maxLength: 30,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Adınız',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 4),
        _step('2', 'Kulaklığınızı takın', 'Kablolu ya da Bluetooth fark etmez.'),
        _step('3', 'Rehberin karekodunu okutun',
            'Telefonunuz rehberin ağına kendiliğinden bağlanır. Android "Bağlan" diye sorarsa onaylayın.'),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          onPressed: _scan,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Karekodu okut'),
        ),
      ],
    );
  }

  Widget _step(String no, String title, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: kBrand,
            child: Text(no, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeView() {
    final listening = _phase == _Phase.listening;
    final full = _phase == _Phase.full;
    final color = full
        ? Colors.grey
        : listening
            ? const Color(0xFF1F8A5B)
            : kAccent;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.25), blurRadius: 24, spreadRadius: 8),
                ],
              ),
              child: Icon(
                full
                    ? Icons.group_off_rounded
                    : listening
                        ? Icons.headphones_rounded
                        : Icons.wifi_find_rounded,
                size: 72,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 22),
            Text(_status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (listening)
              const Text('Sesi telefonunuzun ses tuşlarıyla ayarlayın.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
            if (!listening && !full) const LinearProgressIndicator(),
            const SizedBox(height: 28),
            if (!listening && !full && _info?.wifi != null) ...[
              TextButton.icon(
                onPressed: () async {
                  await _joinWifi();
                  _connect();
                },
                icon: const Icon(Icons.wifi_rounded),
                label: const Text('Ağa yeniden bağlan'),
              ),
              TextButton.icon(
                onPressed: Net.openWifiSettings,
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Wi-Fi ayarlarını aç'),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: full
                  ? () => setState(() {
                        _phase = _Phase.idle;
                        _status = '';
                      })
                  : _leave,
              icon: const Icon(Icons.logout_rounded),
              label: Text(full ? 'Geri' : 'Ayrıl'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Karekodu okutun')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_done) return;
          for (final b in capture.barcodes) {
            final v = b.rawValue;
            if (v != null && v.isNotEmpty) {
              _done = true;
              Navigator.of(context).pop(v);
              return;
            }
          }
        },
      ),
    );
  }
}
