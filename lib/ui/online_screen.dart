// ============================================================================
// Multijoueur en ligne : salon (créer / rejoindre une table avec un code) et
// table en ligne. L'écran n'applique AUCUNE règle : il affiche la vue rédigée
// envoyée par le serveur autoritatif et lui transmet les coups du joueur.
// Adresse du serveur : --dart-define=SERVER_URL=wss://<service>.run.app/ws
// ============================================================================
import 'dart:async';
import 'package:flutter/material.dart' hide Card;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../engine/engine.dart';
import '../l10n/app_localizations.dart';
import '../net/client.dart';
import '../net/voice.dart';
import '../settings.dart';
import 'skin.dart';
import '../sound.dart';
import 'anim.dart';
import 'recap.dart';
import 'caps.dart';
import 'leave.dart';
import 'invite.dart';
import 'replay.dart';

const String kServerUrl = String.fromEnvironment('SERVER_URL',
    defaultValue: 'ws://localhost:8080/ws');

/// Adresse utilisée par le salon (modifiable par les tests, qui lancent le
/// serveur sur un port libre).
String serverUrl = kServerUrl;

Color get _gold => sk.accent;
Color get _goldD => sk.accentDim;
const _cream = Color(0xFFF6F1E2);
const _ink = Color(0xFF1A160F);
const _red = Color(0xFFB12B2B);
Color get _txt => sk.text;
Color get _dim => sk.dim;

/// Message d'erreur du serveur dans la langue du joueur (`code` stable envoyé
/// par bin/server.dart ; `msg` en repli pour un code inconnu).
String serverErrorText(AppLocalizations l, Map m) {
  switch (m['code']) {
    case 'notYourTurn':
      return l.errNotYourTurn;
    case 'invalidAction':
      return l.errInvalidAction;
    case 'tableNotFound':
      return l.errTableNotFound;
    case 'tableFull':
      return l.errTableFull;
    case 'sessionExpired':
      return l.errSessionExpired;
  }
  return '${m['msg']}';
}

// ------------------------------- SALON --------------------------------------
class OnlineLobbyScreen extends StatefulWidget {
  /// Code reçu par un lien d'invitation (?table=ABCD), pré-rempli.
  final String? initialCode;

  /// Ouvert depuis « Table publique » de l'accueil : on cherche une table
  /// tout de suite (prénom du profil).
  final bool autoQuick;
  const OnlineLobbyScreen(
      {super.key, this.initialCode, this.autoQuick = false});
  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  late final _name = TextEditingController(text: playerName.value);
  final _code = TextEditingController();
  StreamSubscription<Map>? _sub;
  bool _slow =
      false; // connexion lente : serveur gratuit en train de se réveiller

  /// Table en cours mémorisée (rechargement de page, app fermée par le système).
  ({String code, String token})? _saved;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null) _code.text = widget.initialCode!;
    if (widget.autoQuick) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _quick();
      });
    }
    loadSavedTable().then((t) {
      if (mounted) setState(() => _saved = t);
    });
    // Réveille le serveur dès l'ouverture du salon (hébergement gratuit qui
    // s'endort) : il est prêt quand le joueur a fini de taper son nom.
    try {
      final ch = WebSocketChannel.connect(Uri.parse(serverUrl));
      ch.stream.listen((_) {}, onError: (_) {}, cancelOnError: true);
      ch.ready.then((_) => ch.sink.close(), onError: (_) {});
    } catch (_) {}
  }

  String? _error;
  bool _busy = false;

  /// Prénom tapé ici : mémorisé dans le profil (pré-rempli la prochaine fois).
  String get _playerName {
    final n = cleanName(_name.text);
    if (n.isNotEmpty && n != playerName.value) setProfile(n, avatar.value);
    return n.isEmpty ? AppLocalizations.of(context)!.defaultPlayer : n;
  }

  void _quick() => _connect((c) => c
    ..connect()
    ..quick(_playerName, avatar: avatar.value));

  void _connect(void Function(GameClient c) then) {
    setState(() {
      _busy = true;
      _slow = false;
      _error = null;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _busy) setState(() => _slow = true);
    });
    final c = GameClient(serverUrl);
    _sub = c.events.listen((m) {
      if (!mounted) return;
      if (m['t'] == 'joined' ||
          m['t'] == 'reconnected' ||
          m['t'] == 'watching') {
        _sub?.cancel();
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => OnlineGameScreen(client: c)));
      } else if (m['t'] == 'error' || m['t'] == 'disconnected') {
        _sub?.cancel();
        c.dispose();
        if (m['code'] == 'sessionExpired') clearSavedTable(); // table disparue
        setState(() {
          if (m['code'] == 'sessionExpired') _saved = null;
          _busy = false;
          _error = m['t'] == 'error'
              ? serverErrorText(AppLocalizations.of(context)!, m)
              : AppLocalizations.of(context)!.serverUnreachable(serverUrl);
        });
      }
    });
    then(c);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.playOnline)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.initialCode != null) ...[
              Text(l.invitedTo(widget.initialCode!),
                  key: const ValueKey('invited'),
                  style: TextStyle(color: _gold, fontSize: 15)),
              const SizedBox(height: 12),
              // page web ouverte sur Android : rejoindre dans l'appli installée
              if (offerAndroidApp) ...[
                OutlinedButton.icon(
                  key: const ValueKey('open-app'),
                  onPressed: () => openInAndroidApp(widget.initialCode!),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l.openInApp),
                ),
                const SizedBox(height: 12),
              ],
            ],
            TextField(
              controller: _name,
              maxLength: kMaxName,
              decoration: InputDecoration(
                  labelText: l.yourName, hintText: l.defaultPlayer),
            ),
            const SizedBox(height: 8),
            // table publique : d'autres joueurs, sans code
            FilledButton.icon(
              key: const ValueKey('quick'),
              onPressed: _busy ? null : _quick,
              icon: const Icon(Icons.public),
              label: Text(l.publicTable),
            ),
            const SizedBox(height: 6),
            Text(l.publicInfo, style: TextStyle(color: _dim, fontSize: 12)),
            const SizedBox(height: 12),
            Text(l.privateTable, style: TextStyle(color: _gold, fontSize: 15)),
            if (_saved != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                key: const ValueKey('resume'),
                onPressed: _busy
                    ? null
                    : () => _connect((c) => c.resume(_saved!.token)),
                icon: const Icon(Icons.replay),
                label: Text(l.resumeTable(_saved!.code)),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _connect((c) => c
                    ..connect()
                    ..create(_playerName, avatar: avatar.value)),
              child: Text(l.createTable),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              maxLength: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l.tableCodeLabel),
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy || _code.text.trim().length != 4
                      ? null
                      : () => _connect((c) => c
                        ..connect()
                        ..join(_code.text.trim().toUpperCase(), _playerName,
                            avatar: avatar.value)),
                  child: Text(l.join),
                ),
              ),
              const SizedBox(width: 8),
              // regarder la partie sans jouer
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('watch'),
                  onPressed: _busy || _code.text.trim().length != 4
                      ? null
                      : () => _connect((c) => c
                        ..connect()
                        ..watch(_code.text.trim().toUpperCase())),
                  icon: const Icon(Icons.visibility),
                  label: Text(l.watch),
                ),
              ),
            ]),
            if (_busy) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
              if (_slow) ...[
                const SizedBox(height: 12),
                Text(l.serverWaking,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _dim, fontSize: 12)),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Color(0xFFE0866A))),
            ],
            const SizedBox(height: 24),
            Text(
              l.lobbyInfo,
              style: TextStyle(color: _dim, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------- TABLE EN LIGNE ---------------------------------
class OnlineGameScreen extends StatefulWidget {
  final GameClient client;
  const OnlineGameScreen({super.key, required this.client});
  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  /// Taille des cartes : réglage « grandes cartes » × agrandissement automatique
  /// sur grand écran.
  double get _k => cardScale * autoCardScale(MediaQuery.sizeOf(context));

  GameView? v;
  Map<String, int>? _tokensBefore;

  /// Dernière donne terminée (envoyée par le serveur) : « Revoir la donne ».
  DealReplay? _replay;
  bool _waiting = false; // action envoyée, réponse du serveur attendue
  Timer? _unlock;
  bool _offline = false; // connexion perdue, reconnexion automatique en cours

  /// Messages du chat de table (siège, nom, texte) et non lus.
  final ValueNotifier<List<(int, String, String)>> _chat = ValueNotifier([]);

  /// Dernier message de chaque joueur, affiché en bulle quelques secondes.
  final Map<int, String> _bubbles = {};
  final Map<int, Timer> _bubbleTimers = {};
  int _unread = 0;
  bool _chatOpen = false;
  late final StreamSubscription<GameView> _s1;
  late final StreamSubscription<Map> _s2;

  /// Chat vocal (WebRTC pair-à-pair, voir lib/net/voice.dart).
  late final VoiceChat _voice = VoiceChat(c);

  GameClient get c => widget.client;

  /// Spectateur : il voit la table depuis le siège de Sud, sans main.
  bool get _spec => v?.spectating ?? false;

  /// Siège affiché en bas de l'écran (le mien ; Sud pour un spectateur).
  int get _me => _spec || v == null ? 0 : v!.you;
  AppLocalizations get l => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    keepScreenOn(true); // l'écran ne s'éteint pas pendant la partie
    for (final n in [_voice.joined, _voice.muted, _voice.links]) {
      n.addListener(_redraw);
    }
    v = c.last;
    if (v != null && v!.phase != 'scored') _tokensBefore = Map.of(v!.tokens);
    if (c.code != null && c.token != null) saveTable(c.code!, c.token!);
    _s1 = c.states.listen((view) {
      _sounds(v, view);
      // annonce « Caps » d'un joueur : affichée à toute la table
      final by = view.capsBy;
      // (pas au 1er état reçu : reconnexion, annonce déjà faite)
      if (by != null && v != null && v!.capsBy == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.capsCalledBy(_playerName(by)))));
      }
      // jetons avant la donne (les jetons ne changent qu'en phase scored)
      if (view.phase != 'scored') _tokensBefore = Map.of(view.tokens);
      final rp = DealReplay.fromJson(view.replay);
      if (rp != null) _replay = rp;
      if (mounted) {
        setState(() {
          v = view;
          _waiting = false;
          _offline = false;
        });
      }
    });
    _s2 = c.events.listen((m) {
      if (!mounted) return;
      if (m['t'] == 'error') {
        setState(() => _waiting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(serverErrorText(l, m))));
      } else if (m['t'] == 'reconnecting') {
        setState(() => _offline = true);
      } else if (m['t'] == 'reconnected') {
        setState(() {
          _offline = false;
          _waiting = false;
        });
      } else if (m['t'] == 'disconnected') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.connectionLost)));
      } else if (m['t'] == 'chat') {
        final seat = m['seat'] as int;
        _chat.value = [
          ..._chat.value,
          (seat, '${m['name'] ?? ''}', '${m['text']}')
        ];
        // bulle au-dessus du joueur pendant 4 s (sans ouvrir le chat)
        _bubbleTimers[seat]?.cancel();
        _bubbleTimers[seat] = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _bubbles.remove(seat));
        });
        setState(() {
          _bubbles[seat] = chatText(l, '${m['text']}');
          if (!_chatOpen) _unread++;
        });
      }
    });
  }

  @override
  void dispose() {
    _s1.cancel();
    _s2.cancel();
    _unlock?.cancel();
    for (final t in _bubbleTimers.values) {
      t.cancel();
    }
    _chat.dispose();
    keepScreenOn(false);
    for (final n in [_voice.joined, _voice.muted, _voice.links]) {
      n.removeListener(_redraw);
    }
    _voice.dispose(); // micro fermé, liaisons audio coupées
    c.leave(); // siège rendu à un bot pour les autres joueurs
    c.dispose();
    // quitter la table : plus rien à reprendre (pas pour un spectateur, qui
    // n'a pas de place à lui)
    if (!_spec) clearSavedTable();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  /// Bouton micro : 1er toucher = rejoindre le vocal (autorisation du micro),
  /// ensuite = couper / rétablir le micro. Appui long = quitter le vocal.
  Future<void> _tapVoice() async {
    if (_voice.joined.value) {
      _voice.toggleMute();
      return;
    }
    try {
      await _voice.join();
    } catch (e) {
      debugPrint('voix : micro refusé ($e)');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.voiceDenied)));
      }
    }
  }

  Future<void> _leaveVoice() async {
    if (!_voice.joined.value) return;
    await _voice.leave();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.voiceLeft)));
    }
  }

  /// Petit micro à côté du nom d'un joueur qui a rejoint le vocal : vert =
  /// relié (on l'entend), orange = connexion, rouge = échec ou micro coupé.
  Widget? _voiceBadge(int seat) {
    final g = v!;
    final p = seat < g.players.length ? g.players[seat] : const {};
    if (p['voice'] != true) return null;
    Color color;
    String label;
    if (seat == g.you) {
      final mute = _voice.muted.value;
      color = mute ? Colors.redAccent : Colors.greenAccent;
      label = mute ? l.voiceUnmute : l.voiceMute;
    } else {
      final link = _voice.links.value[seat];
      if (p['muted'] == true) {
        // micro coupé chez lui : visible de tous
        return Icon(Icons.mic_off,
            key: ValueKey('voice-$seat'),
            size: 14,
            color: Colors.redAccent,
            semanticLabel: l.voiceMutedOther);
      } else if (!_voice.joined.value) {
        color = Colors.grey;
        label = l.voiceJoin;
      } else if (link == PeerLink.connected) {
        color = Colors.greenAccent;
        label = l.voiceConnected;
      } else if (link == PeerLink.failed) {
        color = Colors.redAccent;
        label = l.voiceFailed;
      } else {
        color = Colors.orangeAccent;
        label = l.voiceConnecting;
      }
    }
    return Icon(seat == g.you && _voice.muted.value ? Icons.mic_off : Icons.mic,
        key: ValueKey('voice-$seat'),
        size: 14,
        color: color,
        semanticLabel: label);
  }

  /// Sons d'après l'évolution de la vue (carte posée, pli ramassé, résultat).
  void _sounds(GameView? old, GameView now) {
    final before = old?.currentTrick.length ?? 0;
    final after = now.currentTrick.length;
    if (now.phase == 'scored' && old?.phase != 'scored') {
      final sc = now.lastScore;
      if (sc != null) {
        final us = (now.spectating ? 0 : now.you) % 2 == 0 ? 'NS' : 'EW';
        final ok = sc['success'] == true;
        playSfx((ok ? sc['tmTeam'] == us : sc['tmTeam'] != us)
            ? Sfx.win
            : Sfx.lose);
      }
    } else if (after > before) {
      playSfx(Sfx.card);
    } else if (after == 0 && before > 0) {
      playSfx(Sfx.trick);
    }
  }

  /// Chat de table : feuille du bas avec l'historique et un champ de saisie.
  Future<void> _openChat() async {
    setState(() {
      _chatOpen = true;
      _unread = 0;
    });
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: sk.dialog,
      builder: (ctx) => _ChatSheet(
        messages: _chat,
        you: v?.you,
        nameOf: _playerName,
        // spectateur, ou table publique (inconnus) : réactions seulement
        onSend: _spec || (v?.public ?? false) ? null : c.chat,
        note: _spec
            ? l.spectatingInfo
            : (v?.public ?? false)
                ? l.publicChatInfo
                : null,
      ),
    );
    if (mounted) setState(() => _chatOpen = false);
  }

  // siège réel -> position à l'écran (0 bas, 1 droite, 2 haut, 3 gauche)
  int _rel(int seat) => (seat - _me + 4) % 4;

  String _playerName(int seat) {
    final p = v!.players.length > seat ? v!.players[seat] : null;
    if (p == null) return [l.mSud, l.seatEast, l.seatNorth, l.seatWest][seat];
    if (p['bot'] == true) return l.mAI;
    // table publique : pas de prénom entre inconnus, « Joueur N »
    final name = '${p['name'] ?? ''}'.isEmpty
        ? '${l.defaultPlayer} ${seat + 1}'
        : '${p['name']}';
    // joueur absent trop longtemps : un bot joue à sa place
    return p['away'] == true ? '$name (${l.mAI})' : name;
  }

  void _openReplay() {
    final rp = _replay;
    if (rp == null) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReplayScreen(
            replay: rp,
            names: [for (var s = 0; s < 4; s++) _playerName(s)],
            you: _me)));
  }

  List<Card> get _myCards =>
      _spec ? const [] : v!.hands[v!.you].cards ?? const [];

  bool get _choosingTrump =>
      v!.yourTurn &&
      (v!.phase == 'chooseTrump1' ||
          v!.phase == 'chooseTrump2' ||
          v!.phase == 'chooseTrumpPCC');

  bool _playable(Card card) {
    final g = v!;
    if (_waiting) return false;
    if (_choosingTrump) return true;
    if (!g.yourTurn || g.phase != 'play') return false;
    // le serveur donne la liste exacte (atouts épuisés : il faut mener atout…)
    final legal = g.playable;
    if (legal != null) return legal.any((x) => x.key == card.key);
    if (g.currentTrick.isEmpty) return true;
    final canFollow = _myCards.any((x) => x.suit == g.ledSuit);
    return !canFollow || card.suit == g.ledSuit; // le serveur revalide tout
  }

  /// Envoie une action et bloque l'interface jusqu'à la réponse du serveur
  /// (nouvel état ou erreur) : un double appui n'envoie pas deux coups.
  void _send(void Function() action) {
    if (_waiting) return;
    setState(() => _waiting = true);
    action();
    _unlock?.cancel();
    _unlock = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _waiting = false); // sécurité réseau
    });
  }

  void _tapCard(Card card) {
    if (v?.phase == 'play') haptic();
    _send(() => _sendCard(card));
  }

  void _sendCard(Card card) {
    final g = v!;
    switch (g.phase) {
      case 'chooseTrump1':
        c.chooseTrump1(card);
        break;
      case 'chooseTrump2':
        c.chooseTrump2(card);
        break;
      case 'chooseTrumpPCC':
        c.chooseTrumpPCC(card);
        break;
      case 'play':
        c.play(card);
        break;
    }
  }

  String _prompt() {
    final g = v!;
    if (g.spectating) return l.spectatingInfo;
    if (!g.started) {
      return g.you == 0 ? l.shareCode(g.code ?? '') : l.waitingHost;
    }
    if (g.gameOver) {
      final weWon = g.tokens[g.you % 2 == 0 ? 'NS' : 'EW']! > 0;
      return '${weWon ? l.gameWon : l.gameLost} '
          '${g.you == 0 ? l.youCanRestart : l.hostCanRestart}';
    }
    if (g.phase == 'scored') return l.dealOverNext;
    if (!g.yourTurn) return l.othersTurn;
    switch (g.phase) {
      case 'redeal':
        return l.weakHandAsk;
      case 'bid1':
        return l.bid1Short;
      case 'chooseTrump1':
      case 'chooseTrump2':
      case 'chooseTrumpPCC':
        return l.tapTrump;
      case 'bid2':
        return l.bid2Short;
      case 'preplay':
        return l.openOrClosed;
      case 'play':
        return l.yourTurnPlay;
    }
    return '';
  }

  List<Widget> _actions() {
    final g = v!;
    if (_waiting || g.spectating) return const [];
    if (!g.started) {
      return [
        if (g.you == 0)
          FilledButton(onPressed: () => _send(c.start), child: Text(l.start)),
        OutlinedButton.icon(
            key: const ValueKey('invite'),
            onPressed: () => shareInvite(context, g.code ?? ''),
            icon: const Icon(Icons.share),
            label: Text(l.invite)),
      ];
    }
    if (g.gameOver) {
      return [
        if (g.you == 0)
          FilledButton(onPressed: () => _send(c.start), child: Text(l.newGame)),
      ];
    }
    if (!g.yourTurn) return const [];
    switch (g.phase) {
      case 'redeal':
        return [
          FilledButton(
              onPressed: () => _send(() => c.redeal(keep: false)),
              child: Text(l.redeal)),
          OutlinedButton(
              onPressed: () => _send(() => c.redeal(keep: true)),
              child: Text(l.keep)),
        ];
      case 'bid1':
        return [
          for (final b in g.legalBids)
            OutlinedButton(
                onPressed: () => _send(() => c.bid(b)), child: Text('$b')),
          OutlinedButton(onPressed: () => _send(c.pass), child: Text(l.pass)),
        ];
      case 'bid2':
        return [
          for (final b in g.legalBids.take(5))
            OutlinedButton(
                onPressed: () => _send(() => c.bid2(b)), child: Text('$b')),
          if (g.canPCC)
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: _gold, foregroundColor: sk.onAccent),
                onPressed: () => _send(c.partnerCloseCaps),
                child: const Text('Partner Close Caps')),
          OutlinedButton(
              onPressed: () => _send(() => c.bid2(null)), child: Text(l.pass)),
        ];
      case 'play':
        return [
          // annonce « Caps » avant d'entamer (le serveur juge : Wrong Caps)
          if (g.canCaps)
            FilledButton(
                key: const ValueKey('call-caps'),
                style: FilledButton.styleFrom(
                    backgroundColor: _gold, foregroundColor: sk.onAccent),
                onPressed: () async {
                  if (await confirmCaps(context)) _send(c.callCaps);
                },
                child: Text(l.callCaps)),
          if (g.canCut)
            FilledButton(
                key: const ValueKey('cut-indicator'),
                onPressed: () => _send(c.playIndicator),
                child: Text(l.cutIndicator)),
        ];
      case 'preplay':
        return [
          FilledButton(
              onPressed: () => _send(() => c.setOpen(false)),
              child: Text(l.closedGame)),
          OutlinedButton(
              onPressed: () => _send(() => c.setOpen(true)),
              child: Text(l.openGame)),
        ];
    }
    return const [];
  }

  Widget _card(Card card, {bool playable = false, double? width}) {
    width ??= 50 * _k;
    final col = suitColor(card.suit, ink: _ink, red: _red);
    final w = Container(
      width: width,
      height: width * 1.44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.white, _cream]),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
            color: playable ? _gold : Colors.black26, width: playable ? 2 : 1),
      ),
      child: Text('${card.rank}\n${kSuitSym[card.suit]}',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: col,
              fontWeight: FontWeight.bold,
              fontSize: width * 0.32,
              height: 1.1)),
    );
    return playable
        ? GestureDetector(
            key: ValueKey('play-${card.key}'),
            onTap: () => _tapCard(card),
            child: w)
        : w;
  }

  Widget _back() => Container(
        width: 50 * _k,
        height: 72 * _k,
        decoration: cardBackDecoration(), // dos choisi dans les réglages
      );

  Widget _seatLabel(int seat) {
    final g = v!;
    final active = g.started &&
        g.phase != 'scored' &&
        ((g.phase == 'play' && g.turn == seat) ||
            (g.yourTurn && seat == g.you));
    final cnt = g.hands[seat].count;
    final bubble = _bubbles[seat];
    final label = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: sk.pod,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: active ? _gold : sk.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // avatar choisi par le joueur (pas pour les bots)
        if (seat < g.players.length &&
            g.players[seat]['bot'] != true &&
            g.players[seat]['avatar'] is int) ...[
          avatarIcon(g.players[seat]['avatar'] as int, size: 18),
          const SizedBox(width: 4),
        ],
        if (_voiceBadge(seat) case final badge?) ...[
          badge,
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(
              '${_playerName(seat)}${g.trumpMaker == seat ? ' · ${l.mMaker}' : ''}  ($cnt)',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _txt, fontSize: 12)),
        ),
      ]),
    );
    if (bubble == null) return label;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        key: ValueKey('bubble-$seat'),
        constraints: const BoxConstraints(maxWidth: 160),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E9D2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(bubble,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF1A160F), fontSize: 12)),
      ),
      label,
    ]);
  }

  /// Résultat de la donne (calculé par le moteur côté serveur), vu de MON
  /// équipe — même présentation que le dialogue de fin de donne en solo.
  Widget _scoreCard(GameView g) {
    final sc = g.lastScore!;
    final us = _me % 2 == 0 ? 'NS' : 'EW';
    final them = us == 'NS' ? 'EW' : 'NS';
    final success = sc['success'] == true;
    final weWon = success ? sc['tmTeam'] == us : sc['tmTeam'] != us;
    final detail = sc['pcc'] == true
        ? 'Partner Close Caps · ${sc['tricks']}/8 — '
            '${success ? l.succeeded : l.failedPcc}'
        : '${l.bid} ${sc['bid']} · ${l.pointsN(sc['tmPoints'] as int)} — '
            '${success ? l.succeeded : l.failedBid}'
            '${sc['caps'] == true ? ' · ${l.caps}' : ''}'
            '${sc['wrongCaps'] == null ? '' : '\n${sc['wrongCaps'] == us ? l.wrongCapsUs(kWrongCapsPenalty) : l.wrongCapsThem(kWrongCapsPenalty)}'}';
    return Container(
      key: const ValueKey('score-card'),
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sk.dialog,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _goldD),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(weWon ? l.dealWon : l.dealLost,
            style: TextStyle(
                color: _gold, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(detail,
            textAlign: TextAlign.center, style: TextStyle(color: _dim)),
        const SizedBox(height: 6),
        const SizedBox(height: 10),
        if (_replay != null)
          TextButton.icon(
            key: const ValueKey('open-replay'),
            onPressed: _openReplay,
            icon: const Icon(Icons.history),
            label: Text(l.replayTitle),
          ),
        DealRecap(
          tricks: us == 'NS'
              ? (g.trickWinsNS, g.trickWinsEW)
              : (g.trickWinsEW, g.trickWinsNS),
          points:
              us == 'NS' ? (g.pointsNS, g.pointsEW) : (g.pointsEW, g.pointsNS),
          tokens: (g.tokens[us]!, g.tokens[them]!),
          delta: g.tokens[us]! - (_tokensBefore?[us] ?? g.tokens[us]!),
        ),
      ]),
    );
  }

  Alignment _align(int rel) => const [
        Alignment.bottomCenter,
        Alignment.centerRight,
        Alignment.topCenter,
        Alignment.centerLeft
      ][rel];

  @override
  Widget build(BuildContext context) {
    final g = v;
    if (g == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final trump = g.trumpSuit;
    final us = _me % 2 == 0 ? 'NS' : 'EW';
    final them = us == 'NS' ? 'EW' : 'NS';
    return LeaveGuard(
        child: Scaffold(
      backgroundColor: sk.bg,
      appBar: AppBar(
        // le code de table reste toujours lisible (il se partage)
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(l.tableTitle(g.code ?? ''))),
          if (g.spectators > 0) ...[
            const SizedBox(width: 8),
            Icon(Icons.visibility,
                size: 16, semanticLabel: l.spectators(g.spectators)),
            Text(' ${g.spectators}',
                key: const ValueKey('spectators'),
                style: const TextStyle(fontSize: 14)),
          ],
        ]),
        actions: [
          IconButton(
            key: const ValueKey('share-table'),
            tooltip: l.invite,
            onPressed: () => shareInvite(context, g.code ?? ''),
            icon: const Icon(Icons.share),
          ),
          // revoir la dernière donne terminée
          if (_replay != null)
            IconButton(
              key: const ValueKey('replay-last-deal'),
              tooltip: l.replayTitle,
              onPressed: _openReplay,
              icon: const Icon(Icons.history),
            ),
          // réactions rapides : 2 touchers, sans clavier
          if (!g.spectating)
            PopupMenuButton<String>(
              key: const ValueKey('react'),
              tooltip: l.reactions,
              icon: const Icon(Icons.add_reaction_outlined),
              onSelected: (k) => c.chat(reactionCode(k)),
              itemBuilder: (_) => [
                for (final k in kReactions)
                  PopupMenuItem(
                      key: ValueKey('react-$k'),
                      value: k,
                      child: Text(chatText(l, reactionCode(k)))),
              ],
            ),
          // chat vocal : toucher = micro (rejoindre, couper, rétablir),
          // appui long = quitter le vocal
          // pas de vocal entre inconnus (table publique)
          if (!g.spectating && !g.public)
            GestureDetector(
              onLongPress: _leaveVoice,
              child: IconButton(
                key: const ValueKey('voice'),
                tooltip: !_voice.joined.value
                    ? l.voiceJoin
                    : (_voice.muted.value ? l.voiceUnmute : l.voiceMute),
                onPressed: _tapVoice,
                icon: Icon(
                    !_voice.joined.value
                        ? Icons.mic_none
                        : (_voice.muted.value ? Icons.mic_off : Icons.mic),
                    color: !_voice.joined.value
                        ? null
                        : (_voice.muted.value
                            ? Colors.redAccent
                            : Colors.greenAccent)),
              ),
            ),
          IconButton(
            key: const ValueKey('chat-open'),
            tooltip: l.chat,
            onPressed: _openChat,
            icon: Badge(
              isLabelVisible: _unread > 0,
              label: Text('$_unread'),
              child: const Icon(Icons.chat_bubble_outline),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (_offline)
            Container(
              key: const ValueKey('offline'),
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              color: const Color(0xFF8A4B12),
              child: Text(l.reconnecting,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            color: sk.bar.$1,
            child: Text(
              // tout est vu de MON équipe (je peux être Est/Ouest)
              '${l.us} ${g.tokens[us]} · ${l.them} ${g.tokens[them]}\n'
              '${g.pcc ? 'Partner Close Caps' : '${l.bid} ${g.bid ?? '—'}'} · '
              '${trump == null ? l.trumpHidden : '${l.trump} ${g.trumpOpen ? kSuitSym[trump] : '${kSuitSym[trump]} ${l.onlyYou}'}'} · '
              '${l.tricks} ${us == 'NS' ? g.trickWinsNS : g.trickWinsEW}–'
              '${us == 'NS' ? g.trickWinsEW : g.trickWinsNS}',
              textAlign: TextAlign.center,
              style: TextStyle(color: _txt),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [
                  sk.tableColors.$1,
                  sk.tableColors.$2
                ]), // thème (Bois : tapis choisi)
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sk.tableBorder, width: 2),
                boxShadow: sk.glow == null
                    ? null
                    : [
                        BoxShadow(
                            color: sk.glow!.withValues(alpha: 0.3),
                            blurRadius: 26)
                      ],
              ),
              child: Stack(children: [
                for (final s in [1, 2, 3])
                  Align(
                    // côtés : au-dessus de la ligne du pli (sinon recouverts
                    // par les cartes d'Est/Ouest sur écran étroit)
                    alignment: _rel((_me + s) % 4) == 2
                        ? Alignment.topCenter
                        : Alignment(_rel((_me + s) % 4) == 1 ? 1 : -1, -0.55),
                    child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _seatLabel((_me + s) % 4)),
                  ),
                Center(
                  child: SizedBox(
                    width: 180 * _k,
                    height: 170 * _k,
                    // pli en cours ; s'il est vide, le dernier pli terminé
                    // reste visible jusqu'à l'entame suivante
                    child: Stack(children: [
                      if (g.currentTrick.isNotEmpty)
                        for (final p in g.currentTrick)
                          Align(
                            alignment: _align(_rel(p.seat)),
                            child: p.card == null ? _back() : _card(p.card!),
                          )
                      else
                        // pli terminé : visible pendant la pause du serveur,
                        // puis ramassé vers le gagnant
                        for (final p in g.lastTrick ?? const <TrickCardView>[])
                          Align(
                            alignment: _align(_rel(p.seat)),
                            child: GatherTo(
                              key: ValueKey(
                                  'gather-${g.trickWinsNS + g.trickWinsEW}-${p.seat}'),
                              toward: _align(_rel(g.lastTrickWinner ?? p.seat)),
                              duration: const Duration(milliseconds: 1100),
                              child: p.card == null ? _back() : _card(p.card!),
                            ),
                          ),
                    ]),
                  ),
                ),
                Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _seatLabel(_me))),
                if (g.phase == 'scored' && g.lastScore != null)
                  Center(child: _scoreCard(g)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_prompt(), style: TextStyle(color: _txt)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: _actions()),
              ],
            ),
          ),
          Container(
            height: 96 * _k,
            padding: const EdgeInsets.all(8),
            color: sk.panel.$2,
            // les 8 cartes tiennent sur la largeur (pas de défilement)
            child: g.spectating
                ? Center(
                    child: Text(l.spectatingInfo,
                        key: const ValueKey('spectating'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _dim)))
                : LayoutBuilder(builder: (context, cons) {
                    final w =
                        ((cons.maxWidth - 8 * 4) / 8).clamp(30.0, 50.0 * _k);
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final (i, card) in _myCards.indexed)
                          Padding(
                            key: ValueKey('deal-${card.key}'),
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: DealIn(
                                index: i,
                                child: _card(card,
                                    playable: _playable(card), width: w)),
                          ),
                      ],
                    );
                  }),
          ),
        ]),
      ),
    ));
  }
}

/// Feuille du chat : possède son champ de saisie (libéré avec elle, après
/// l'animation de fermeture).
class _ChatSheet extends StatefulWidget {
  const _ChatSheet(
      {required this.messages,
      required this.you,
      required this.nameOf,
      required this.onSend,
      this.note});
  final ValueNotifier<List<(int, String, String)>> messages;
  final int? you;
  final String Function(int seat) nameOf;
  final void Function(String text)? onSend; // null : lecture seule
  final String? note; // pourquoi on ne peut pas écrire

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    widget.onSend?.call(t);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 12,
          bottom: 12 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(l.chat,
            style: TextStyle(
                color: _gold, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ValueListenableBuilder<List<(int, String, String)>>(
            valueListenable: widget.messages,
            builder: (_, msgs, __) => ListView(
              shrinkWrap: true,
              reverse: true,
              children: [
                for (final (seat, name, text) in msgs.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                          text:
                              '${name.isEmpty ? widget.nameOf(seat) : name} : ',
                          style: TextStyle(
                              color: seat == widget.you ? _gold : _dim,
                              fontWeight: FontWeight.bold)),
                      TextSpan(
                          text: chatText(AppLocalizations.of(context)!, text),
                          style: TextStyle(color: _txt)),
                    ])),
                  ),
              ],
            ),
          ),
        ),
        if (widget.onSend == null && widget.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(widget.note!,
                key: const ValueKey('chat-note'),
                style: TextStyle(color: _dim, fontSize: 12)),
          ),
        if (widget.onSend != null)
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('chat-input'),
                controller: _input,
                maxLength: 200,
                decoration:
                    InputDecoration(hintText: l.chatHint, counterText: ''),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
                key: const ValueKey('chat-send'),
                tooltip: l.send,
                onPressed: _send,
                icon: const Icon(Icons.send)),
          ]),
      ]),
    );
  }
}
