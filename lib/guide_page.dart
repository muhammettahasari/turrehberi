import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'main.dart';
import 'net.dart';
import 'protocol.dart';

/// Rehbere bağlanan bir dinleyici.
class _Peer {
  _Peer(this.id, this.ws);

  final int id;
  final WebSocket ws;
  String name = 'Turist';
  RTCPeerConnection? pc;
  RTCPeerConnectionState? state;
  bool remoteSet = false;
  bool offerSent = false;
  final List<RTCIceCandidate> inbox = []; // gelen, henüz eklenemeyen adaylar
  final List<Map<String, dynamic>> outbox = []; // teklif gitmeden çıkan adaylar

  void send(Map<String, dynamic> m) {
    try {
      ws.add(jsonEncode(m));
    } catch (_) {}
  }
}

class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> with WidgetsBindingObserver {
  HttpServer? _server;
  MediaStream? _mic;
  final Map<int, _Peer> _peers = {};
  int _nextId = 1;
  List<LocalAddr> _addrs = [];
  bool _muted = false;
  bool _starting = true;
  String? _error;
  Timer? _ipTimer;

  // Ağ: uygulamanın açtığı ağ (önerilen) ya da rehberin kendi erişim noktası.
  WifiCreds? _wifi;
  bool _ownNet = false;
  bool _netBusy = false;
  String? _netMsg;
  final _ssidCtl = TextEditingController();
  final _passCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Rehber ayarlardan erişim noktasını açıp dönünce adresi hemen yenile.
    if (state == AppLifecycleState.resumed) _refreshAddrs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    if (_ownNet) Net.stopLocalHotspot();
    _ssidCtl.dispose();
    _passCtl.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _start() async {
    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      _fail('Mikrofon izni verilmedi. Ayarlardan TurSes için mikrofona izin verin.');
      return;
    }
    try {
      _mic = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    } catch (e) {
      _fail('Mikrofon açılamadı: $e');
      return;
    }
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, kPort, shared: true);
    } catch (e) {
      _fail('Yayın sunucusu başlatılamadı: $e');
      return;
    }
    _server!.listen(_onRequest, onError: (_) {});
    await _loadSavedWifi();
    await _refreshAddrs();
    _ipTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refreshAddrs());
    if (mounted) setState(() => _starting = false);
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _error = msg;
      _starting = false;
    });
  }

  Future<void> _loadSavedWifi() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final ssid = sp.getString('hotspot_ssid') ?? '';
      final pass = sp.getString('hotspot_pass') ?? '';
      _ssidCtl.text = ssid;
      _passCtl.text = pass;
      if (ssid.isNotEmpty && !_ownNet) _wifi = WifiCreds(ssid, pass);
    } catch (_) {}
  }

  Future<void> _saveManualWifi() async {
    final ssid = _ssidCtl.text.trim();
    final pass = _passCtl.text;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('hotspot_ssid', ssid);
      await sp.setString('hotspot_pass', pass);
    } catch (_) {}
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _wifi = ssid.isEmpty ? null : WifiCreds(ssid, pass));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ağ bilgisi kaydedildi; karekoda eklendi.')));
  }

  Future<void> _startOwnNet() async {
    setState(() {
      _netBusy = true;
      _netMsg = null;
    });
    // Android 13+: yakındaki cihazlar, daha eski sürümler: konum izni.
    try {
      await Permission.nearbyWifiDevices.request();
    } catch (_) {}
    try {
      await Permission.locationWhenInUse.request();
    } catch (_) {}
    try {
      final w = await Net.startLocalHotspot();
      if (!mounted) return;
      setState(() {
        _wifi = w;
        _ownNet = true;
      });
      await _refreshAddrs();
    } catch (e) {
      if (mounted) setState(() => _netMsg = e.toString());
    } finally {
      if (mounted) setState(() => _netBusy = false);
    }
  }

  Future<void> _stopOwnNet() async {
    await Net.stopLocalHotspot();
    if (!mounted) return;
    setState(() {
      _ownNet = false;
      _wifi = null;
    });
    await _loadSavedWifi();
    if (mounted) setState(() {});
    await _refreshAddrs();
  }

  Future<void> _refreshAddrs() async {
    final list = await Net.localAddrs();
    if (!mounted) return;
    final changed = list.map((a) => a.ip).join(',') != _addrs.map((a) => a.ip).join(',');
    if (changed) setState(() => _addrs = list);
  }

  Future<void> _onRequest(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = 200;
      req.response.write('TurSes');
      await req.response.close();
      return;
    }
    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(req);
    } catch (_) {
      return;
    }
    ws.pingInterval = const Duration(seconds: 4);
    final peer = _Peer(_nextId++, ws);
    ws.listen(
      (data) => _onMessage(peer, data),
      onDone: () => _drop(peer),
      onError: (_) => _drop(peer),
      cancelOnError: true,
    );
  }

  Future<void> _onMessage(_Peer p, dynamic data) async {
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(data as String) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    try {
      switch (m['type']) {
        case 'join':
          {
            if (_peers.length >= kFreeLimit) {
              p.send({'type': 'full', 'limit': kFreeLimit});
              await p.ws.close();
              return;
            }
            final n = (m['name'] ?? '').toString().trim();
            p.name = n.isEmpty ? 'Turist ${p.id}' : (n.length > 30 ? n.substring(0, 30) : n);
            _peers[p.id] = p;
            if (mounted) setState(() {});
            await _sendOffer(p);
          }
        case 'answer':
          {
            final pc = p.pc;
            if (pc == null) return;
            await pc.setRemoteDescription(RTCSessionDescription(m['sdp'] as String, 'answer'));
            p.remoteSet = true;
            for (final c in List<RTCIceCandidate>.from(p.inbox)) {
              await pc.addCandidate(c);
            }
            p.inbox.clear();
          }
        case 'ice':
          {
            final c = RTCIceCandidate(m['candidate'] as String?, m['sdpMid'] as String?,
                (m['sdpMLineIndex'] as num?)?.toInt());
            if (p.remoteSet && p.pc != null) {
              await p.pc!.addCandidate(c);
            } else {
              p.inbox.add(c);
            }
          }
        case 'leave':
          _drop(p);
      }
    } catch (_) {
      // Bozuk bir mesaj tüm yayını düşürmesin.
    }
  }

  Future<void> _sendOffer(_Peer p) async {
    final mic = _mic;
    if (mic == null) return;
    final pc = await createPeerConnection(kRtcConfig);
    p.pc = pc;
    for (final t in mic.getAudioTracks()) {
      await pc.addTrack(t, mic);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      final msg = <String, dynamic>{
        'type': 'ice',
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      };
      if (p.offerSent) {
        p.send(msg);
      } else {
        p.outbox.add(msg);
      }
    };
    pc.onConnectionState = (s) {
      p.state = s;
      if (mounted) setState(() {});
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) _drop(p);
    };
    final offer = await pc.createOffer({});
    await pc.setLocalDescription(offer);
    p.send({'type': 'offer', 'sdp': offer.sdp});
    p.offerSent = true;
    for (final msg in p.outbox) {
      p.send(msg);
    }
    p.outbox.clear();
  }

  void _drop(_Peer p) {
    final removed = _peers.remove(p.id) != null;
    final pc = p.pc;
    p.pc = null;
    pc?.close();
    try {
      p.ws.close();
    } catch (_) {}
    if (removed && mounted) setState(() {});
  }

  void _toggleMute() {
    final mic = _mic;
    if (mic == null) return;
    setState(() => _muted = !_muted);
    for (final t in mic.getAudioTracks()) {
      t.enabled = !_muted;
    }
  }

  Future<void> _stop() async {
    _ipTimer?.cancel();
    for (final p in List<_Peer>.from(_peers.values)) {
      _drop(p);
    }
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    final mic = _mic;
    _mic = null;
    if (mic != null) {
      for (final t in mic.getTracks()) {
        try {
          await t.stop();
        } catch (_) {}
      }
      try {
        await mic.dispose();
      } catch (_) {}
    }
  }

  // ---------------- arayüz ----------------

  List<String> get _qrIps =>
      _addrs.where((a) => a.rank < 9).map((a) => a.ip).take(4).toList();

  bool get _hotspotLikely => _addrs.any((a) => a.rank == 0);

  String _stateLabel(_Peer p) {
    switch (p.state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return 'Dinliyor';
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return 'Kesildi, bekleniyor';
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return 'Bağlantı sorunu';
      default:
        return 'Bağlanıyor…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final listening = _peers.values
        .where((p) => p.state == RTCPeerConnectionState.RTCPeerConnectionStateConnected)
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('Rehber')),
      body: SafeArea(
        child: _error != null
            ? _ErrorBox(_error!)
            : _starting
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      _micCard(listening),
                      _hotspotCard(),
                      _qrCard(),
                      _listenersCard(),
                    ],
                  ),
      ),
    );
  }

  Widget _micCard(int listening) {
    return _Card(
      child: Column(
        children: [
          GestureDetector(
            onTap: _toggleMute,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _muted ? Colors.grey.shade500 : const Color(0xFFC8402F),
                boxShadow: [
                  BoxShadow(
                    color: (_muted ? Colors.grey : const Color(0xFFC8402F)).withOpacity(0.25),
                    blurRadius: 24,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      size: 54, color: Colors.white),
                  const SizedBox(height: 6),
                  Text(_muted ? 'Sessizde' : 'Yayında',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _muted
                ? 'Grup sizi duymuyor. Açmak için daireye dokunun.'
                : '$listening / ${_peers.length} kişi dinliyor · Sessize almak için dokunun',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _hotspotCard() {
    const ok = Color(0xFF1F8A5B);
    return _Card(
      title: '1 · Ağ',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_ownNet && _wifi != null) ...[
            Row(children: [
              const Icon(Icons.check_circle_rounded, color: ok),
              const SizedBox(width: 8),
              Expanded(child: Text('TurSes ağı açık: ${_wifi!.ssid}')),
            ]),
            const SizedBox(height: 6),
            const Text('Turistler karekodu okutunca bu ağa kendiliğinden bağlanır.',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _stopOwnNet, child: const Text('Ağı kapat')),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _netBusy ? null : _startOwnNet,
              icon: _netBusy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering_rounded),
              label: const Text('TurSes ağını başlat (önerilen)'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Uygulama kendi Wi-Fi ağını açar; turistler karekodla bu ağa bağlanır. '
              'Telefonun normal erişim noktası kapalı olmalı. İnternet paylaşılmaz.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            if (_netMsg != null) ...[
              const SizedBox(height: 8),
              Text(_netMsg!, style: const TextStyle(color: Color(0xFFC8402F))),
            ],
            const SizedBox(height: 4),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Kendi erişim noktamı kullanacağım'),
              subtitle: Text(
                  _wifi != null ? 'Kayıtlı ağ: ${_wifi!.ssid}' : 'Ağ adı ve şifresini bir kez yazın',
                  style: const TextStyle(fontSize: 12)),
              children: [
                TextField(
                  controller: _ssidCtl,
                  decoration: const InputDecoration(
                      labelText: 'Erişim noktası adı', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passCtl,
                  decoration: const InputDecoration(
                      labelText: 'Şifre', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: Net.openHotspotSettings,
                      icon: const Icon(Icons.settings_rounded),
                      label: const Text('Ayarları aç'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                        onPressed: _saveManualWifi, child: const Text('Kaydet')),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(_hotspotLikely ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      size: 18, color: _hotspotLikely ? ok : kAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        _hotspotLikely
                            ? 'Erişim noktası açık görünüyor.'
                            : 'Erişim noktası kapalı görünüyor.',
                        style: const TextStyle(fontSize: 13)),
                  ),
                ]),
                const SizedBox(height: 8),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _qrCard() {
    final ips = _qrIps;
    return _Card(
      title: '2 · TurSes karekodu',
      child: ips.isEmpty
          ? const Text('Ağ adresi bulunamadı. Önce 1. adımdaki ağı açın; karekod kendiliğinden çıkacak.')
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(
                    data: JoinInfo(ips, kPort, _wifi).encode(),
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                    _wifi != null
                        ? 'Turistler TurSes\'te "Turist" bölümünden bu karekodu okutsun; '
                            'ağa kendiliğinden bağlanırlar.'
                        : 'Ağ bilgisi eklenmedi: turistler önce Wi-Fi\'a elle bağlanmalı, '
                            'sonra bu karekodu okutmalı.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text('Adres: ${ips.first}:$kPort',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
    );
  }

  Widget _listenersCard() {
    final list = _peers.values.toList();
    return _Card(
      title: 'Dinleyiciler (${list.length} / $kFreeLimit)',
      child: list.isEmpty
          ? const Text('Henüz bağlanan yok.')
          : Column(
              children: [
                for (final p in list)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.circle,
                      size: 12,
                      color: p.state == RTCPeerConnectionState.RTCPeerConnectionStateConnected
                          ? const Color(0xFF1F8A5B)
                          : Colors.grey,
                    ),
                    title: Text(p.name),
                    trailing: Text(_stateLabel(p),
                        style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  ),
              ],
            ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2DDD2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(title!,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: kBrand, fontSize: 15)),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.msg);

  final String msg;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFC8402F)),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
                onPressed: () => openAppSettings(), child: const Text('Uygulama ayarlarını aç')),
          ],
        ),
      ),
    );
  }
}
