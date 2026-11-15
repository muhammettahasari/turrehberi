import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'main.dart';
import 'net.dart';
import 'profile.dart';
import 'protocol.dart';

enum _Phase { idle, connecting, listening, full }

class ListenerPage extends StatefulWidget {
  const ListenerPage({super.key});

  @override
  State<ListenerPage> createState() => _ListenerPageState();
}

class _ListenerPageState extends State<ListenerPage> {
  JoinInfo? _info;
  _Phase _phase = _Phase.idle;
  String _status = '';

  WebSocket? _ws;
  RTCPeerConnection? _pc;
  bool _remoteSet = false;
  bool _answerSent = false;
  final List<RTCIceCandidate> _inbox = [];
  final List<Map<String, dynamic>> _outbox = [];
  String? _guideName;
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
    super.dispose();
  }

  /// Sesi "medya" olarak çal: kulaklıkta (kablolu ya da Bluetooth) yüksek
  /// kaliteyle çıkar, ses tuşları medya sesini ayarlar.
  Future<void> _setupAudio() async {
    try {
      await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.media);
    } catch (_) {}
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

  /// Wi-Fi kapalıysa açar (Android 10+ tek dokunuşluk sistem paneli ile).
  Future<bool> _ensureWifiOn() async {
    if (await Net.wifiEnabled()) return true;
    final r = await Net.enableWifi();
    if (r == 'enabled') return true;
    if (r == 'failed') {
      _setStatus('Wi-Fi kapalı. Lütfen Wi-Fi\'ı açın; uygulama bağlanmayı deneyecek.',
          _Phase.connecting);
      return false;
    }
    _setStatus('Wi-Fi kapalı. Açılan pencereden Wi-Fi\'ı açın.', _Phase.connecting);
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_closing || !mounted) return false;
      if (await Net.wifiEnabled()) {
        await Future<void>.delayed(const Duration(seconds: 1)); // Wi-Fi'ın hazır olması için
        return true;
      }
    }
    _setStatus('Wi-Fi açılmadı. Açtıktan sonra "Ağa yeniden bağlan"a dokunun.', _Phase.connecting);
    return false;
  }

  /// Karekoddaki Wi-Fi ağına bağlanır. Android "Bağlan" onayı ister.
  Future<void> _joinWifi() async {
    final w = _info?.wifi;
    if (w == null) return;
    if (!await _ensureWifiOn()) return;
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
    _send({'type': 'join', 'name': Profile.name});
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
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(data as String) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    try {
      switch (m['type']) {
        case 'offer':
          {
            final g = (m['guide'] ?? '').toString();
            if (g.isNotEmpty && g != _guideName && mounted) setState(() => _guideName = g);
            await _answer(m['sdp'] as String);
          }
        case 'ice':
          {
            final c = RTCIceCandidate(m['candidate'] as String?, m['sdpMid'] as String?,
                (m['sdpMLineIndex'] as num?)?.toInt());
            if (_remoteSet && _pc != null) {
              await _pc!.addCandidate(c);
            } else {
              _inbox.add(c);
            }
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
    } catch (_) {
      _onLost();
    }
  }

  Future<void> _answer(String sdp) async {
    await _closePc();
    final pc = await createPeerConnection(kRtcConfig);
    _pc = pc;
    _remoteSet = false;
    _answerSent = false;
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      final msg = <String, dynamic>{
        'type': 'ice',
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      };
      if (_answerSent) {
        _send(msg);
      } else {
        _outbox.add(msg);
      }
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setStatus('Rehberi dinliyorsunuz', _Phase.listening);
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _setStatus('Bağlantı zayıfladı, bekleniyor…', _Phase.connecting);
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _onLost();
      }
    };
    // Gelen ses parçası Android'de kendiliğinden çalınır.
    pc.onTrack = (_) {};
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    _remoteSet = true;
    for (final c in List<RTCIceCandidate>.from(_inbox)) {
      await pc.addCandidate(c);
    }
    _inbox.clear();
    final answer = await pc.createAnswer({});
    await pc.setLocalDescription(answer);
    _send({'type': 'answer', 'sdp': answer.sdp});
    _answerSent = true;
    for (final msg in _outbox) {
      _send(msg);
    }
    _outbox.clear();
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

  Future<void> _closePc() async {
    final pc = _pc;
    _pc = null;
    _remoteSet = false;
    _answerSent = false;
    _outbox.clear();
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
    }
  }

  void _cleanup() {
    _closePc();
    _inbox.clear();
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
      appBar: AppBar(title: Text(_guideName == null ? 'Turist' : 'Rehber: $_guideName')),
      body: SafeArea(
        child: _phase == _Phase.idle ? _idleView() : _activeView(),
      ),
    );
  }

  Widget _idleView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('Adınız: ${Profile.name}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        _step('1', 'Kulaklığınızı takın', 'Kablolu ya da Bluetooth fark etmez.'),
        _step('2', 'Rehberin karekodunu okutun',
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
