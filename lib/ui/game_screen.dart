import 'package:flutter/material.dart' hide Card;
import '../engine/engine.dart';
import '../ai/bots.dart';
import '../l10n/app_localizations.dart';
import '../settings.dart';

// Palette « table royale » (miroir du prototype web validé).
const _feltA = Color(0xFF0F5A3C);
const _feltB = Color(0xFF063421);
const _gold = Color(0xFFE3C565);
const _goldD = Color(0xFFA5822F);
const _woodB = Color(0xFF160A06);
const _cream = Color(0xFFF6F1E2);
const _ink = Color(0xFF1A160F);
const _red = Color(0xFFB12B2B);
const _txt = Color(0xFFF3EAD6);
const _dim = Color(0xFFC9B48A);

/// Écran de jeu : table royale câblée au moteur (solo vs 3 bots).
/// La logique de flux reflète le contrôleur du prototype validé ; toute la
/// logique de règles reste dans Engine. Prévu pour basculer plus tard sur
/// lib/net/client.dart (multijoueur).
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final Engine e = Engine();
  String _msg = '';
  String get msg => _msg;

  /// Changer le message efface la ligne d'aide et le conseil affichés.
  set msg(String v) {
    _msg = v;
    tip = '';
    _hinted = null;
  }

  /// Ligne d'aide sous le message (comme le prototype).
  String tip = '';

  /// Carte mise en valeur par « 💡 Conseil ».
  String? _hinted;

  /// Dernier pli terminé de la donne (bouton « Dernier pli »).
  Map<String, dynamic>? _lastTrick;
  List<Widget> actions = [];

  /// Pli terminé, affiché pendant la pause de fin de pli. Tant qu'il est non
  /// nul, aucune carte n'est jouable (sinon un 2e déroulé démarre en parallèle).
  List<TrickPlay>? _doneTrick;
  static const int human = 0;

  AppLocalizations get l => AppLocalizations.of(context)!;
  String _seat(int s) => [l.mSud, l.seatEast, l.seatNorth, l.seatWest][s];

  @override
  void initState() {
    super.initState();
    e.onLog = (_) {};
    WidgetsBinding.instance.addPostFrameCallback((_) => _startHand());
  }

  void _bots(void Function() f) => Future.delayed(botDelay(600), () {
        if (mounted) setState(f);
      });

  // ======================= déroulé d'une donne =======================
  void _startHand() {
    _lastTrick = null;
    e.newHand();
    _handleRedeal(0);
  }

  void _handleRedeal(int safety) {
    if (safety > 6 || !e.canRedeal()) {
      e.startBidding1();
      _stepBid();
      return;
    }
    if (e.eldest == human) {
      setState(() {
        msg = l.weakHand(e.handPoints(human));
        actions = [
          _btn(
              l.redeal,
              () => setState(() {
                    e.redeal();
                    _handleRedeal(safety + 1);
                  }),
              primary: true),
          _btn(
              l.keep,
              () => setState(() {
                    e.startBidding1();
                    _stepBid();
                  })),
        ];
      });
    } else {
      setState(() {
        msg = l.botRedeals(_seat(e.eldest));
        actions = [];
      });
      _bots(() {
        e.redeal();
        _handleRedeal(safety + 1);
      });
    }
  }

  void _stepBid() {
    if (e.phase == 'allpass') {
      setState(() {
        msg = l.allPass;
        actions = [];
      });
      _bots(_startHand);
      return;
    }
    if (e.phase != 'bid1') {
      _afterRound1();
      return;
    }
    if (e.bidTurn == human) {
      final legal = e.legalBids();
      setState(() {
        msg =
            '${l.bid1You(e.handPoints(human))} ${e.highBid != null ? l.bestBid('${e.highBid}', _seat(e.highBidder!)) : l.noBidYet}';
        tip = l.bid1Hint;
        actions = [
          for (final v in legal)
            _btn('$v', () {
              e.placeBid(v);
              setState(_nextBid);
            }),
          _btn(l.pass, () {
            e.placeBid(null);
            setState(_nextBid);
          }),
          _btn(l.hint, () {
            final v = botBid(e, human);
            setState(() => tip = v != null ? l.hintBid('$v') : l.hintPass);
          }),
        ];
      });
    } else {
      setState(() {
        msg = l.thinking(_seat(e.bidTurn));
        actions = [];
      });
      _bots(() {
        e.placeBid(botBid(e, e.bidTurn));
        _nextBid();
      });
    }
  }

  void _nextBid() {
    if (e.phase == 'allpass') {
      msg = l.allPass;
      actions = [];
      _bots(_startHand);
      return;
    }
    if (e.phase == 'chooseTrump1') {
      _afterRound1();
      return;
    }
    _stepBid();
  }

  void _afterRound1() {
    final tm = e.trumpMaker1!;
    if (tm == human) {
      setState(() {
        msg = l.youWinR1;
        tip = l.trumpTip;
        actions = [];
      });
    } else {
      setState(() {
        msg = l.botSetsTrump(_seat(tm));
        actions = [];
      });
      _bots(() {
        e.chooseTrump1(botChooseTrump(e, tm));
        _stepBid2();
      });
    }
  }

  void _stepBid2() {
    if (e.phase != 'bid2') {
      _afterRound2();
      return;
    }
    if (e.bid2Turn == human) {
      final legal = e.legalBids2();
      if (legal.isEmpty && !e.canPCC()) {
        setState(() {
          msg = l.mustPass2;
          actions = [];
        });
        _bots(() {
          e.placeBid2(null);
          _stepBid2();
        });
        return;
      }
      setState(() {
        msg = l.bid2You(e.handPoints(human));
        tip = l.bid2Hint;
        actions = [
          for (final v in legal.take(5))
            _btn('$v', () {
              e.placeBid2(v);
              setState(_stepBid2);
            }),
          if (e.canPCC())
            _btn('Partner Close Caps', () {
              e.placeBid2('PCC');
              setState(_stepBid2);
            }, gold: true),
          _btn(l.pass, () {
            e.placeBid2(null);
            setState(_stepBid2);
          }),
          _btn(l.hint, () {
            final v = botBid2(e, human);
            setState(() => tip = v == null
                ? l.hintPass
                : l.hintBid(v == 'PCC' ? 'Partner Close Caps' : '$v'));
          }),
        ];
      });
    } else {
      setState(() {
        msg = l.botRound2(_seat(e.bid2Turn));
        actions = [];
      });
      _bots(() {
        e.placeBid2(botBid2(e, e.bid2Turn));
        _stepBid2();
      });
    }
  }

  void _afterRound2() {
    if (e.phase == 'chooseTrumpPCC') {
      final tm = e.trumpMaker!;
      if (tm == human) {
        setState(() {
          msg = l.pccYou;
          tip = l.pccHint;
          actions = [];
        });
      } else {
        setState(() {
          msg = l.botPcc(_seat(tm));
          actions = [];
        });
        _bots(() {
          e.chooseTrumpPCC(botChooseTrump(e, tm));
          _stepPlay();
        });
      }
      return;
    }
    if (e.phase == 'chooseTrump2') {
      final tm = e.trumpMaker!;
      if (tm == human) {
        setState(() {
          msg = l.youTakeR2;
          tip = l.trumpTip;
          actions = [];
        });
      } else {
        setState(() {
          msg = l.botNewTrump(_seat(tm));
          actions = [];
        });
        _bots(() {
          e.chooseTrump2(botChooseTrump(e, tm));
          _preplay();
        });
      }
      return;
    }
    _preplay();
  }

  void _preplay() {
    final tm = e.trumpMaker!;
    if (tm == human) {
      setState(() {
        msg = l.openOrClosed;
        tip = l.openHint;
        actions = [
          _btn(l.closedGame, () {
            e.startPlayClosed();
            setState(_stepPlay);
          }, primary: true),
          _btn(l.openGame, () {
            e.startPlayOpen();
            if (e.phase == 'spoilt') {
              setState(() {
                msg = l.spoilt;
                actions = [];
              });
              _bots(_startHand);
            } else {
              setState(_stepPlay);
            }
          }),
        ];
      });
    } else {
      e.startPlayClosed();
      _stepPlay();
    }
  }

  void _stepPlay() {
    if (e.tricks.length == 8) return;
    final seat = e.turn;
    if (e.hands[seat].isEmpty && seat == e.trumpMaker && e.indicatorOnTable) {
      setState(() {
        msg = l.lastTrickTM;
        actions = [];
      });
      _bots(() => _afterPlay(e.playLastIndicator(seat)));
      return;
    }
    if (seat == human) {
      setState(() {
        final facedown = e.currentTrick.isNotEmpty &&
            !e.trumpOpen &&
            !e.hands[human].any((c) => c.suit == e.ledSuit);
        msg = e.currentTrick.isEmpty
            ? l.youLead
            : facedown
                ? l.youFacedown
                : l.youFollow;
        final t = e.trumpSuit;
        tip = e.trumpOpen && t != null
            ? l.trumpOpenHint('${kSuitSym[t]} ${_suitName(t)}')
            : l.trumpHiddenHint;
        actions = [
          _btn(l.hint, _showPlayHint),
          if (_lastTrick != null) _btn(l.lastTrickBtn, _openLastTrick),
        ];
      });
    } else {
      setState(() {
        msg = l.botPlays(_seat(seat));
        if (e.soloMode && e.mutedSeat == human) tip = l.pccOut;
        actions = [];
      });
      _bots(() {
        final c = botPlay(e, seat);
        final r = c is PlayIndicator
            ? e.playIndicatorToCut(seat)
            : e.playCard(seat, c as Card);
        _afterPlay(r);
      });
    }
  }

  String _suitName(String s) =>
      {'S': l.suitS, 'C': l.suitC, 'D': l.suitD, 'H': l.suitH}[s]!;

  /// 💡 Conseil pendant le jeu : la carte que jouerait l'IA (comme le prototype).
  void _showPlayHint() {
    if (e.phase != 'play' || e.turn != human || e.hands[human].isEmpty) return;
    final ch = botPlay(e, human);
    setState(() {
      if (ch is PlayIndicator) {
        tip = l.hintDiscard;
      } else {
        _hinted = (ch as Card).key;
        tip = l.hintPlay;
      }
    });
  }

  /// Dernier pli : les 4 cartes, le gagnant entouré d'or.
  void _openLastTrick() {
    final t = _lastTrick;
    if (t == null) return;
    final names = [l.seatYou, l.seatEast, l.seatNorth, l.seatWest];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF211208),
        title: Text(
            l.lastTrickTitle(t['points'] as int, names[t['winner'] as int]),
            style: const TextStyle(color: _gold, fontSize: 16)),
        content: Wrap(spacing: 10, runSpacing: 10, children: [
          for (final p in t['cards'] as List<TrickPlay>)
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(names[p.seat],
                  style: const TextStyle(color: _dim, fontSize: 11)),
              const SizedBox(height: 4),
              Container(
                decoration: p.seat == t['winner']
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: _gold, width: 3))
                    : null,
                child: p.faceDown && !e.trumpOpen && p.seat != human
                    ? _facedown()
                    : _cardWidget(p.card, big: true),
              ),
            ]),
        ]),
        actions: [
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(), child: Text(l.close)),
        ],
      ),
    );
  }

  void _afterPlay(Map<String, dynamic> r) {
    if (r['trickDone'] == true) {
      _lastTrick = r;
      setState(() => _doneTrick = r['cards'] as List<TrickPlay>);
      Future.delayed(botDelay(950), () {
        if (!mounted) return;
        setState(() => _doneTrick = null);
        if (r['handDone'] == true) {
          _showResult(r);
        } else {
          setState(_stepPlay);
        }
      });
    } else {
      setState(_stepPlay);
    }
  }

  void _onHumanCard(Card c) {
    if (!_canPlay(c)) return;
    if (e.phase == 'chooseTrumpPCC') {
      e.chooseTrumpPCC(c);
      _stepPlay();
      return;
    }
    if (e.phase == 'chooseTrump2') {
      e.chooseTrump2(c);
      _preplay();
      return;
    }
    if (e.phase == 'chooseTrump1') {
      e.chooseTrump1(c);
      _stepBid2();
      return;
    }
    if (e.phase == 'play' && e.turn == human) {
      setState(
          () => actions = []); // plus de Conseil / Dernier pli une fois joué
      _afterPlay(e.playCard(human, c));
    }
  }

  bool _canPlay(Card c) {
    // choix d'atout : seulement quand c'est le joueur qui choisit (pas pendant
    // qu'un bot pose le sien)
    if (e.phase == 'chooseTrump1') return e.trumpMaker1 == human;
    if (e.phase == 'chooseTrump2' || e.phase == 'chooseTrumpPCC') {
      return e.trumpMaker == human;
    }
    if (e.phase != 'play' || e.turn != human || _doneTrick != null) {
      return false;
    }
    final facedown = e.currentTrick.isNotEmpty &&
        !e.trumpOpen &&
        !e.hands[human].any((x) => x.suit == e.ledSuit);
    if (facedown) return true;
    return e.playableCards(human).any((x) => x.key == c.key);
  }

  void _showResult(Map<String, dynamic> r) {
    final s = r['score'] as Map<String, dynamic>;
    final nsWon =
        s['success'] == true ? s['tmTeam'] == 'NS' : s['tmTeam'] == 'EW';
    final over = r['gameOver'] == true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF211208),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _goldD)),
        title: Text(nsWon ? l.dealWon : l.dealLost,
            style: const TextStyle(color: _gold, fontWeight: FontWeight.bold)),
        content: Text(
          '${s['pcc'] == true ? 'Partner Close Caps · ${s['tricks']}/8 — ${s['success'] == true ? l.succeeded : l.failedPcc}' : '${l.bid} ${s['bid']} · ${l.pointsN(s['tmPoints'] as int)} — ${s['success'] == true ? l.succeeded : l.failedBid}${s['caps'] == true ? ' · ${l.caps}' : ''}'}\n${l.tokens} — ${l.us} ${e.tokens['NS']} · ${l.them} ${e.tokens['EW']}${over ? '\n\n${r['gameWinner'] == 'NS' ? l.gameWon : l.gameLost}' : ''}',
          style: const TextStyle(color: _dim),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (over) e.tokens = {'NS': 11, 'EW': 11};
              _startHand();
            },
            child: Text(over ? l.playAgain : l.nextDeal),
          ),
        ],
      ),
    );
  }

  // ============================ widgets ============================
  Widget _btn(String label, VoidCallback onTap,
      {bool primary = false, bool gold = false}) {
    if (gold) {
      return FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
              backgroundColor: _gold, foregroundColor: const Color(0xFF2A1C06)),
          child: Text(label));
    }
    if (primary) return FilledButton(onPressed: onTap, child: Text(label));
    return OutlinedButton(onPressed: onTap, child: Text(label));
  }

  bool _isActive(int s) =>
      (e.phase == 'bid1' && e.bidTurn == s) ||
      (e.phase == 'bid2' && e.bid2Turn == s) ||
      (e.phase == 'play' && e.turn == s);

  Widget _cardWidget(Card c,
      {Key? key,
      bool big = false,
      bool playable = false,
      bool hinted = false,
      VoidCallback? onTap}) {
    final red = c.suit == 'D' || c.suit == 'H';
    final w = big ? 52.0 : 46.0, h = big ? 74.0 : 66.0;
    final card = Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, _cream]),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
            color: hinted
                ? const Color(0xFF7FD7FF)
                : playable
                    ? _gold
                    : Colors.black26,
            width: hinted ? 3 : (playable ? 2 : 1)),
        boxShadow: [
          const BoxShadow(
              color: Colors.black45, blurRadius: 5, offset: Offset(0, 2)),
          if (hinted) const BoxShadow(color: Color(0xAA7FD7FF), blurRadius: 14),
        ],
      ),
      alignment: Alignment.center,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(c.rank,
            style: TextStyle(
                color: red ? _red : _ink,
                fontWeight: FontWeight.bold,
                fontSize: big ? 19 : 17,
                height: 1)),
        Text(kSuitSym[c.suit]!,
            style: TextStyle(
                color: red ? _red : _ink, fontSize: big ? 17 : 15, height: 1)),
      ]),
    );
    return onTap != null
        ? GestureDetector(key: key, onTap: onTap, child: card)
        : KeyedSubtree(key: key, child: card);
  }

  Widget _facedown({bool big = true}) => Container(
        width: big ? 52 : 24,
        height: big ? 74 : 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8A6A2E), Color(0xFF6B5122)]),
          border: Border.all(color: const Color(0xFF4A370F)),
        ),
      );

  /// [compact] : avatar seul (écran étroit, évite le chevauchement avec la main).
  Widget _pod(int seat, {bool compact = false}) {
    final active = _isActive(seat);
    final muted = e.soloMode && e.mutedSeat == seat;
    final base = [l.seatYou, l.seatEast, l.seatNorth, l.seatWest][seat];
    var meta = seat == 0
        ? l.mSud
        : seat == 2
            ? l.mPartner
            : l.mAI;
    if (e.trumpMaker == seat) meta = e.pcc ? l.mSolo : l.mMaker;
    if (muted) meta = l.mOut;
    return Opacity(
      opacity: muted ? 0.55 : 1,
      child: Container(
        padding: EdgeInsets.fromLTRB(3, 3, compact ? 3 : 10, 3),
        decoration: BoxDecoration(
          color: const Color(0x52000000),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: active ? _gold : const Color(0xFF5A3D2E),
              width: active ? 2 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                  colors: [Color(0xFF2A3A52), Color(0xFF141B28)]),
              // avatar seul : bordure dorée épaisse = preneur
              border: Border.all(
                  color: active || (compact && e.trumpMaker == seat)
                      ? _gold
                      : _goldD,
                  width: compact && e.trumpMaker == seat ? 3 : 2),
            ),
            child: Text(base.characters.first,
                style: const TextStyle(
                    color: _gold, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          if (!compact) const SizedBox(width: 6),
          if (!compact)
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(base, style: const TextStyle(color: _txt, fontSize: 12)),
                  Text(meta.toUpperCase(),
                      style: TextStyle(
                          color: e.trumpMaker == seat ? _gold : _dim,
                          fontSize: 9,
                          letterSpacing: 0.4)),
                ]),
        ]),
      ),
    );
  }

  Alignment _seatAlign(int s) {
    switch (s) {
      case 0:
        return Alignment.bottomCenter;
      case 1:
        return Alignment.centerRight;
      case 2:
        return Alignment.topCenter;
      default:
        return Alignment.centerLeft;
    }
  }

  Widget _trickArea() {
    return SizedBox(
      width: 176,
      height: 168,
      child: Stack(
        children: [
          for (final p in _doneTrick ?? e.currentTrick)
            Align(
              alignment: _seatAlign(p.seat),
              child: (p.faceDown && !e.trumpOpen)
                  ? _facedown()
                  : _cardWidget(p.card, big: true),
            ),
        ],
      ),
    );
  }

  Widget _handFan() {
    final h = e.hands[human];
    if (h.isEmpty) return const SizedBox(height: 118);
    return LayoutBuilder(builder: (ctx, cons) {
      final n = h.length;
      final spacing =
          n > 1 ? ((cons.maxWidth - 60) / n).clamp(26.0, 42.0) : 0.0;
      final totalW = spacing * (n - 1) + 56;
      final startX = (cons.maxWidth - totalW) / 2;
      final mid = (n - 1) / 2;
      return SizedBox(
        height: 118,
        width: cons.maxWidth,
        child: Stack(
          children: [
            for (int i = 0; i < n; i++)
              Positioned(
                left: startX + i * spacing,
                bottom: 6.0 + (mid - (i - mid).abs()) * 3.0,
                child: Transform.rotate(
                  angle: (i - mid) * 0.06,
                  child: _cardWidget(
                    h[i],
                    key: ValueKey(
                        '${_canPlay(h[i]) ? 'play' : 'hand'}-${h[i].key}'),
                    big: true,
                    playable: _canPlay(h[i]),
                    hinted: _hinted == h[i].key,
                    onTap: _canPlay(h[i]) ? () => _onHumanCard(h[i]) : null,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _trumpChip() {
    final t = e.trumpSuit;
    final txt = (t != null && e.trumpOpen)
        ? '${l.trump} ${kSuitSym[t]}'
        : l.trumpHidden;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _goldD),
      ),
      child: Text(txt, style: const TextStyle(color: _txt, fontSize: 12)),
    );
  }

  Widget _stat(String k, String v, {Color color = _txt}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(k.toUpperCase(),
              style: const TextStyle(
                  color: _dim, fontSize: 9, letterSpacing: 0.6)),
          Text(v,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
      );

  Widget _teamPanel(String label, int tok, Color c) => Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0x40000000),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF5A3D2E)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(color: _dim, fontSize: 11)),
          Text('$tok',
              style: TextStyle(
                  color: c,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  height: 1)),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: tok / 22,
              minHeight: 5,
              backgroundColor: const Color(0x22FFFFFF),
              valueColor: const AlwaysStoppedAnimation<Color>(_gold),
            ),
          ),
        ]),
      );

  Widget _scoreboard() {
    final t = e.trumpSuit;
    String trumpTxt;
    Color trumpColor = _txt;
    if (t != null && e.trumpOpen) {
      trumpTxt = kSuitSym[t]!;
      trumpColor = (t == 'D' || t == 'H') ? const Color(0xFFE06666) : _txt;
    } else if (t != null) {
      trumpTxt = l.closed;
    } else {
      trumpTxt = '—';
    }
    String tgtUs = '—', tgtThem = '—';
    if (e.bid != null && e.trumpMaker != null) {
      if (e.pcc) {
        tgtUs = teamOf(e.trumpMaker!) == 'NS' ? l.eightTricks : l.def;
        tgtThem = teamOf(e.trumpMaker!) == 'EW' ? l.eightTricks : l.def;
      } else {
        final us = teamOf(e.trumpMaker!) == 'NS' ? e.bid! : 305 - e.bid!;
        tgtUs = '$us';
        tgtThem = '${305 - us}';
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF241009), Color(0xFF160A06)]),
      ),
      child: Column(children: [
        Row(children: [
          _teamPanel(l.us, e.tokens['NS']!, _gold),
          Expanded(
            // réduit l'ensemble sur les écrans étroits au lieu de déborder
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _stat(l.bid, e.pcc ? 'PCC' : (e.bid?.toString() ?? '—')),
                _stat(l.trump, trumpTxt, color: trumpColor),
                _stat(l.tricks, '${e.trickWinsNS}–${e.trickWinsEW}'),
              ]),
            ),
          ),
          _teamPanel(l.them, e.tokens['EW']!, const Color(0xFFE0C07A)),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(
            child: Text('${l.tgtUs} $tgtUs',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _dim, fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text('${l.tgtThem} $tgtThem',
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(color: _dim, fontSize: 11)),
          ),
        ]),
      ]),
    );
  }

  Widget _table() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          gradient: const RadialGradient(
              center: Alignment(0, -0.1),
              radius: 0.95,
              colors: [_feltA, _feltB]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _goldD, width: 2),
          boxShadow: const [
            BoxShadow(
                color: Colors.black54, blurRadius: 16, offset: Offset(0, 8))
          ],
        ),
        child: LayoutBuilder(builder: (context, cons) {
          // écran étroit : la pastille d'atout passe sous la rangée de Nord et
          // le pion du joueur se réduit à son avatar (textes longs en ta/si)
          final narrow = cons.maxWidth < 520;
          return Stack(
            children: [
              Positioned(top: narrow ? 58 : 10, left: 12, child: _trumpChip()),
              Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                      padding: const EdgeInsets.only(top: 6), child: _pod(2))),
              Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _pod(1, compact: narrow))),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _pod(3, compact: narrow))),
              Align(alignment: Alignment.center, child: _trickArea()),
              Positioned(
                  left: 10,
                  bottom: narrow ? 126 : 8, // au-dessus de la main
                  child: _pod(0, compact: narrow)),
              Align(alignment: Alignment.bottomCenter, child: _handFan()),
            ],
          );
        }),
      ),
    );
  }

  Widget _panel() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1C0F09), Color(0xFF140A06)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(msg, style: const TextStyle(color: _txt, fontSize: 13)),
          if (tip.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(tip, style: const TextStyle(color: _dim, fontSize: 11.5)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _woodB,
      body: SafeArea(
        child: Column(
          children: [
            _scoreboard(),
            Expanded(child: _table()),
            _panel(),
          ],
        ),
      ),
    );
  }
}
