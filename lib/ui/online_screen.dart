// ============================================================================
// Multijoueur en ligne : salon (créer / rejoindre une table avec un code) et
// table en ligne. L'écran n'applique AUCUNE règle : il affiche la vue rédigée
// envoyée par le serveur autoritatif et lui transmet les coups du joueur.
// Adresse du serveur : --dart-define=SERVER_URL=wss://<service>.run.app/ws
// ============================================================================
import 'dart:async';
import 'package:flutter/material.dart' hide Card;
import '../engine/engine.dart';
import '../l10n/app_localizations.dart';
import '../net/client.dart';

const String kServerUrl = String.fromEnvironment('SERVER_URL',
    defaultValue: 'ws://localhost:8080/ws');

const _gold = Color(0xFFE3C565);
const _goldD = Color(0xFFA5822F);
const _feltA = Color(0xFF0F5A3C);
const _feltB = Color(0xFF063421);
const _cream = Color(0xFFF6F1E2);
const _ink = Color(0xFF1A160F);
const _red = Color(0xFFB12B2B);
const _txt = Color(0xFFF3EAD6);
const _dim = Color(0xFFC9B48A);

// ------------------------------- SALON --------------------------------------
class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({super.key});
  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  StreamSubscription<Map>? _sub;
  String? _error;
  bool _busy = false;

  void _connect(void Function(GameClient c) then) {
    setState(() {
      _busy = true;
      _error = null;
    });
    final c = GameClient(kServerUrl)..connect();
    _sub = c.events.listen((m) {
      if (!mounted) return;
      if (m['t'] == 'joined') {
        _sub?.cancel();
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => OnlineGameScreen(client: c)));
      } else if (m['t'] == 'error' || m['t'] == 'disconnected') {
        setState(() {
          _busy = false;
          _error = m['t'] == 'error'
              ? '${m['msg']}'
              : AppLocalizations.of(context)!.serverUnreachable(kServerUrl);
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
    final name =
        _name.text.trim().isEmpty ? l.defaultPlayer : _name.text.trim();
    return Scaffold(
      appBar: AppBar(title: Text(l.privateTable)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                  labelText: l.yourName, hintText: l.defaultPlayer),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : () => _connect((c) => c.create(name)),
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
            OutlinedButton(
              onPressed: _busy || _code.text.trim().length != 4
                  ? null
                  : () => _connect(
                      (c) => c.join(_code.text.trim().toUpperCase(), name)),
              child: Text(l.join),
            ),
            if (_busy) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Color(0xFFE0866A))),
            ],
            const SizedBox(height: 24),
            Text(
              l.lobbyInfo,
              style: const TextStyle(color: _dim, fontSize: 12),
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
  GameView? v;
  bool _waiting = false; // action envoyée, réponse du serveur attendue
  Timer? _unlock;
  late final StreamSubscription<GameView> _s1;
  late final StreamSubscription<Map> _s2;

  GameClient get c => widget.client;
  AppLocalizations get l => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    v = c.last;
    _s1 = c.states.listen((view) {
      if (mounted) {
        setState(() {
          v = view;
          _waiting = false;
        });
      }
    });
    _s2 = c.events.listen((m) {
      if (!mounted) return;
      if (m['t'] == 'error') {
        setState(() => _waiting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${m['msg']}')));
      } else if (m['t'] == 'disconnected') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.connectionLost)));
      }
    });
  }

  @override
  void dispose() {
    _s1.cancel();
    _s2.cancel();
    _unlock?.cancel();
    c.dispose();
    super.dispose();
  }

  // siège réel -> position à l'écran (0 bas, 1 droite, 2 haut, 3 gauche)
  int _rel(int seat) => (seat - v!.you + 4) % 4;

  String _playerName(int seat) {
    final p = v!.players.length > seat ? v!.players[seat] : null;
    if (p == null) return [l.mSud, l.seatEast, l.seatNorth, l.seatWest][seat];
    return p['bot'] == true ? l.mAI : '${p['name']}';
  }

  List<Card> get _myCards => v!.hands[v!.you].cards ?? const [];

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

  void _tapCard(Card card) => _send(() => _sendCard(card));

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
    if (_waiting) return const [];
    if (!g.started) {
      return [
        if (g.you == 0)
          FilledButton(onPressed: () => _send(c.start), child: Text(l.start)),
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
                    backgroundColor: _gold,
                    foregroundColor: const Color(0xFF2A1C06)),
                onPressed: () => _send(c.partnerCloseCaps),
                child: const Text('Partner Close Caps')),
          OutlinedButton(
              onPressed: () => _send(() => c.bid2(null)), child: Text(l.pass)),
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

  Widget _card(Card card, {bool playable = false, double width = 50}) {
    final red = card.suit == 'D' || card.suit == 'H';
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
              color: red ? _red : _ink,
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
        width: 50,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          gradient: const LinearGradient(
              colors: [Color(0xFF8A6A2E), Color(0xFF6B5122)]),
        ),
      );

  Widget _seatLabel(int seat) {
    final g = v!;
    final active = g.started &&
        g.phase != 'scored' &&
        ((g.phase == 'play' && g.turn == seat) ||
            (g.yourTurn && seat == g.you));
    final cnt = g.hands[seat].count;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x55000000),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: active ? _gold : const Color(0xFF5A3D2E)),
      ),
      child: Text(
          '${_playerName(seat)}${g.trumpMaker == seat ? ' · ${l.mMaker}' : ''}  ($cnt)',
          style: const TextStyle(color: _txt, fontSize: 12)),
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
    final us = g.you % 2 == 0 ? 'NS' : 'EW';
    final them = us == 'NS' ? 'EW' : 'NS';
    return Scaffold(
      backgroundColor: const Color(0xFF160A06),
      appBar: AppBar(
        // le code de table reste toujours lisible (il se partage)
        title: Text(l.tableTitle(g.code ?? '')),
      ),
      body: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            color: const Color(0xFF123524),
            child: Text(
              // tout est vu de MON équipe (je peux être Est/Ouest)
              '${l.us} ${g.tokens[us]} · ${l.them} ${g.tokens[them]}\n'
              '${g.pcc ? 'Partner Close Caps' : '${l.bid} ${g.bid ?? '—'}'} · '
              '${trump == null ? l.trumpHidden : '${l.trump} ${g.trumpOpen ? kSuitSym[trump] : '${kSuitSym[trump]} ${l.onlyYou}'}'} · '
              '${l.tricks} ${us == 'NS' ? g.trickWinsNS : g.trickWinsEW}–'
              '${us == 'NS' ? g.trickWinsEW : g.trickWinsNS}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _txt),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const RadialGradient(colors: [_feltA, _feltB]),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _goldD, width: 2),
              ),
              child: Stack(children: [
                for (final s in [1, 2, 3])
                  Align(
                    // côtés : au-dessus de la ligne du pli (sinon recouverts
                    // par les cartes d'Est/Ouest sur écran étroit)
                    alignment: _rel((g.you + s) % 4) == 2
                        ? Alignment.topCenter
                        : Alignment(_rel((g.you + s) % 4) == 1 ? 1 : -1, -0.55),
                    child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _seatLabel((g.you + s) % 4)),
                  ),
                Center(
                  child: SizedBox(
                    width: 180,
                    height: 170,
                    // pli en cours ; s'il est vide, le dernier pli terminé
                    // reste visible jusqu'à l'entame suivante
                    child: Stack(children: [
                      for (final p in g.currentTrick.isEmpty
                          ? (g.lastTrick ?? const <TrickCardView>[])
                          : g.currentTrick)
                        Align(
                          alignment: _align(_rel(p.seat)),
                          child: p.card == null ? _back() : _card(p.card!),
                        ),
                    ]),
                  ),
                ),
                Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _seatLabel(g.you))),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_prompt(), style: const TextStyle(color: _txt)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: _actions()),
              ],
            ),
          ),
          Container(
            height: 96,
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF1C0F09),
            // les 8 cartes tiennent sur la largeur (pas de défilement)
            child: LayoutBuilder(builder: (context, cons) {
              final w = ((cons.maxWidth - 8 * 4) / 8).clamp(30.0, 50.0);
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final card in _myCards)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _card(card, playable: _playable(card), width: w),
                    ),
                ],
              );
            }),
          ),
        ]),
      ),
    );
  }
}
