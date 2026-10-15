// ============================================================================
// Chat vocal de table — WebRTC pair-à-pair (maillage : jusqu'à 3 liaisons par
// joueur). L'AUDIO va directement d'un appareil à l'autre ; le serveur de jeu
// ne relaie que la signalisation (messages `voice` et `rtc`, docs/PROTOCOL.md).
// Gratuit : STUN public par défaut ; un relais TURN optionnel est fourni par le
// serveur (variables TURN_*), utile derrière certains réseaux mobiles.
// ============================================================================
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'client.dart';

/// Sièges avec lesquels [me] doit être relié : les autres joueurs connectés
/// qui ont rejoint le vocal.
Set<int> voicePeers(int me, List<Map> players) => {
      for (var s = 0; s < players.length; s++)
        if (s != me &&
            players[s]['voice'] == true &&
            players[s]['online'] != false)
          s
    };

/// Dans chaque paire, seul le plus petit siège envoie l'offre (pas de
/// collision quand deux joueurs rejoignent le vocal en même temps).
bool callsFirst(int me, int other) => me < other;

/// État d'une liaison avec un autre joueur (icône à côté de son nom).
enum PeerLink { connecting, connected, failed }

class VoiceChat {
  VoiceChat(this.client);
  final GameClient client;

  /// true après [join] (micro autorisé, les autres peuvent nous entendre).
  final ValueNotifier<bool> joined = ValueNotifier(false);
  final ValueNotifier<bool> muted = ValueNotifier(false);

  /// Siège -> état de la liaison audio.
  final ValueNotifier<Map<int, PeerLink>> links = ValueNotifier(const {});

  MediaStream? _local;
  final Map<int, RTCPeerConnection> _pcs = {};
  final Map<int, RTCVideoRenderer> _out = {}; // lecture du son reçu
  final Map<int, List<RTCIceCandidate>> _pending = {};
  StreamSubscription<Map>? _events;
  StreamSubscription<GameView>? _states;
  bool _disposed = false;

  /// Ouvre le micro et rejoint le vocal. Lève une exception si le micro est
  /// refusé ou absent (l'UI affiche un message).
  Future<void> join() async {
    if (joined.value) return;
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    if (_disposed) {
      await _stopLocal();
      return;
    }
    if (!kIsWeb) {
      // jeu posé sur la table : haut-parleur plutôt qu'écouteur d'appel
      try {
        await Helper.setSpeakerphoneOn(true);
      } catch (_) {}
    }
    muted.value = false;
    joined.value = true;
    _events = client.events.listen(_onEvent);
    _states = client.states.listen((v) => _sync(v));
    client.voice(true);
    final v = client.last;
    if (v != null) await _sync(v);
  }

  /// Coupe / rétablit le micro sans quitter le vocal.
  void toggleMute() {
    muted.value = !muted.value;
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted.value;
    }
    client.voice(true, muted: muted.value); // les autres voient le micro coupé
  }

  /// Quitte le vocal (micro fermé, liaisons coupées).
  Future<void> leave() async {
    if (!joined.value) return;
    joined.value = false;
    client.voice(false);
    await _events?.cancel();
    await _states?.cancel();
    for (final s in _pcs.keys.toList()) {
      await _close(s);
    }
    await _stopLocal();
  }

  Future<void> dispose() async {
    _disposed = true;
    await leave();
  }

  // ---------------------------------------------------------------------------

  Future<void> _stopLocal() async {
    for (final t in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    _local = null;
  }

  void _setLink(int seat, PeerLink? l) {
    final m = Map<int, PeerLink>.of(links.value);
    if (l == null) {
      m.remove(seat);
    } else {
      m[seat] = l;
    }
    links.value = m;
  }

  /// Ouvre / ferme les liaisons selon qui est dans le vocal.
  Future<void> _sync(GameView v) async {
    if (!joined.value) return;
    final peers = voicePeers(v.you, v.players);
    for (final s in _pcs.keys.toList()) {
      if (!peers.contains(s)) await _close(s);
    }
    for (final s in peers) {
      if (!_pcs.containsKey(s) && callsFirst(v.you, s)) await _call(s);
    }
  }

  void _onEvent(Map m) {
    switch (m['t']) {
      case 'rtc':
        _onSignal(m['from'] as int, m['data'] as Map);
      case 'reconnected':
        // le serveur a oublié notre présence : on la redonne et on refait
        // les liaisons (les anciennes sont coupées de l'autre côté)
        for (final s in _pcs.keys.toList()) {
          _close(s);
        }
        client.voice(true, muted: muted.value);
    }
  }

  Future<RTCPeerConnection> _open(int seat) async {
    final pc = await createPeerConnection({
      'iceServers': client.iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _pcs[seat] = pc;
    _setLink(seat, PeerLink.connecting);
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      await pc.addTrack(t, _local!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      client.rtc(seat, {
        'ice': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        }
      });
    };
    pc.onTrack = (e) async {
      if (e.streams.isEmpty || !identical(_pcs[seat], pc)) return;
      final r = _out[seat] ?? RTCVideoRenderer();
      if (!_out.containsKey(seat)) {
        await r.initialize();
        _out[seat] = r;
      }
      r.srcObject = e.streams.first; // sur le web : un <audio> joue le son
    };
    pc.onConnectionState = (st) {
      if (!identical(_pcs[seat], pc)) return;
      if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setLink(seat, PeerLink.connected);
      } else if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _setLink(seat, PeerLink.failed);
      }
    };
    return pc;
  }

  Future<void> _call(int seat) async {
    final pc = await _open(seat);
    final offer = await pc.createOffer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(offer);
    client.rtc(seat, {'sdp': offer.sdp, 'type': offer.type});
  }

  Future<void> _onSignal(int from, Map data) async {
    if (!joined.value) return;
    try {
      if (data['type'] == 'offer') {
        if (_pcs.containsKey(from)) {
          // nouvelle tentative : on garde les candidats déjà reçus pour elle
          // (ils peuvent arriver juste avant l'offre)
          final early = _pending.remove(from);
          await _close(from);
          if (early != null) _pending[from] = early;
        }
        final pc = await _open(from);
        await pc.setRemoteDescription(
            RTCSessionDescription(data['sdp'] as String, 'offer'));
        await _flush(from);
        final answer = await pc.createAnswer({});
        await pc.setLocalDescription(answer);
        client.rtc(from, {'sdp': answer.sdp, 'type': answer.type});
      } else if (data['type'] == 'answer') {
        final pc = _pcs[from];
        if (pc == null) return;
        await pc.setRemoteDescription(
            RTCSessionDescription(data['sdp'] as String, 'answer'));
        await _flush(from);
      } else if (data['ice'] is Map) {
        final j = data['ice'] as Map;
        final c = RTCIceCandidate(j['candidate'] as String?,
            j['sdpMid'] as String?, j['sdpMLineIndex'] as int?);
        final pc = _pcs[from];
        if (pc != null && await pc.getRemoteDescription() != null) {
          await pc.addCandidate(c);
        } else {
          (_pending[from] ??= []).add(c); // arrivé avant l'offre/la réponse
        }
      }
    } catch (e) {
      debugPrint('voix : signal de $from ignoré ($e)');
      _setLink(from, PeerLink.failed);
    }
  }

  Future<void> _flush(int seat) async {
    final pc = _pcs[seat];
    final list = _pending.remove(seat) ?? const [];
    for (final c in list) {
      await pc?.addCandidate(c);
    }
  }

  Future<void> _close(int seat) async {
    _pending.remove(seat);
    final pc = _pcs.remove(seat);
    _setLink(seat, null);
    final r = _out.remove(seat);
    if (r != null) {
      r.srcObject = null;
      await r.dispose();
    }
    await pc?.close();
  }
}
