import 'package:flutter/material.dart' hide Card;
import '../engine/engine.dart';
import '../ai/bots.dart';

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
  String msg = '';
  List<Widget> actions = [];
  static const int human = 0;

  @override
  void initState() {
    super.initState();
    e.onLog = (_) {};
    WidgetsBinding.instance.addPostFrameCallback((_) => _startHand());
  }

  void _refresh() => setState(() {});
  void _bots(void Function() f) =>
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(f);
      });

  // ======================= déroulé d'une donne =======================
  void _startHand() {
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
        msg = 'Main faible (${e.handPoints(human)} pts, < 15). Redistribuer ?';
        actions = [
          _btn('Redistribuer', () => setState(() {
                e.redeal();
                _handleRedeal(safety + 1);
              }), primary: true),
          _btn('Garder', () => setState(() {
                e.startBidding1();
                _stepBid();
              })),
        ];
      });
    } else {
      setState(() {
        msg = '${kSeatName[e.eldest]} redistribue (main faible)…';
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
        msg = 'Tout le monde a passé. Nouvelle donne.';
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
        msg = '1er tour — à vous (${e.handPoints(human)} pts sur 4 cartes).';
        actions = [
          for (final v in legal)
            _btn('$v', () {
              e.placeBid(v);
              setState(_nextBid);
            }),
          _btn('Passe', () {
            e.placeBid(null);
            setState(_nextBid);
          }),
        ];
      });
    } else {
      setState(() {
        msg = '${kSeatName[e.bidTurn]} réfléchit…';
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
      msg = 'Tout le monde a passé. Nouvelle donne.';
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
        msg = 'Vous gagnez le 1er tour ! Touchez une carte : elle devient l\'atout (caché).';
        actions = [];
      });
    } else {
      setState(() {
        msg = '${kSeatName[tm]} pose l\'atout…';
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
          msg = '2e tour : vous devez passer.';
          actions = [];
        });
        _bots(() {
          e.placeBid2(null);
          _stepBid2();
        });
        return;
      }
      setState(() {
        msg = '2e tour (8 cartes, ${e.handPoints(human)} pts).';
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
          _btn('Passe', () {
            e.placeBid2(null);
            setState(_stepBid2);
          }),
        ];
      });
    } else {
      setState(() {
        msg = '${kSeatName[e.bid2Turn]} (2e tour)…';
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
          msg = 'Partner Close Caps ! Touchez votre carte d\'atout.';
          actions = [];
        });
      } else {
        setState(() {
          msg = '${kSeatName[tm]} annonce Partner Close Caps…';
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
          msg = 'Vous prenez au 2e tour ! Touchez votre nouvel atout.';
          actions = [];
        });
      } else {
        setState(() {
          msg = '${kSeatName[tm]} choisit un nouvel atout…';
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
        msg = 'Jeu fermé (atout caché) ou ouvert ?';
        actions = [
          _btn('Jeu fermé', () {
            e.startPlayClosed();
            setState(_stepPlay);
          }, primary: true),
          _btn('Jeu ouvert', () {
            e.startPlayOpen();
            if (e.phase == 'spoilt') {
              setState(() {
                msg = 'Atout gâché — aucun adversaire n\'a d\'atout. Redistribution.';
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
        msg = 'Dernier pli : le preneur joue son atout.';
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
            ? 'À vous. Vous entamez.'
            : facedown
                ? 'À vous. Vous ne pouvez pas suivre : jouez une carte (face cachée).'
                : 'À vous. Suivez la couleur si possible.';
        actions = [];
      });
    } else {
      setState(() {
        msg = '${kSeatName[seat]} joue…';
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

  void _afterPlay(Map<String, dynamic> r) {
    _refresh();
    if (r['trickDone'] == true) {
      Future.delayed(const Duration(milliseconds: 950), () {
        if (!mounted) return;
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
    if (e.phase == 'chooseTrump1' ||
        (e.phase == 'bid2' && e.trumpMaker1 == human && e.indicator == null)) {
      e.chooseTrump1(c);
      _stepBid2();
      return;
    }
    if (e.phase == 'play' && e.turn == human) {
      _afterPlay(e.playCard(human, c));
    }
  }

  bool _canPlay(Card c) {
    final choosing = e.phase == 'chooseTrump1' ||
        e.phase == 'chooseTrump2' ||
        e.phase == 'chooseTrumpPCC' ||
        (e.phase == 'bid2' && e.trumpMaker1 == human && e.indicator == null);
    if (choosing) return true;
    if (e.phase != 'play' || e.turn != human) return false;
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
        title: Text(nsWon ? 'Donne gagnée' : 'Donne perdue',
            style: const TextStyle(color: _gold, fontWeight: FontWeight.bold)),
        content: Text(
          '${s['pcc'] == true
                  ? 'Partner Close Caps · ${s['tricks']}/8 plis — ${s['success'] == true ? 'réussie' : 'ratée'}'
                  : 'Enchère ${s['bid']} · ${s['tmPoints']} pts — ${s['success'] == true ? 'réussie' : 'chutée'}${s['caps'] == true ? ' · Caps !' : ''}'}\nJetons — Nous ${e.tokens['NS']} · Eux ${e.tokens['EW']}${over
                  ? '\n\n${r['gameWinner'] == 'NS' ? '🏆 Partie gagnée !' : 'Partie perdue.'}'
                  : ''}',
          style: const TextStyle(color: _dim),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (over) e.tokens = {'NS': 11, 'EW': 11};
              _startHand();
            },
            child: Text(over ? 'Rejouer' : 'Donne suivante'),
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
      {bool big = false, bool playable = false, VoidCallback? onTap}) {
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
            color: playable ? _gold : Colors.black26, width: playable ? 2 : 1),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 5, offset: Offset(0, 2))
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
    return onTap != null ? GestureDetector(onTap: onTap, child: card) : card;
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

  Widget _pod(int seat) {
    final active = _isActive(seat);
    final muted = e.soloMode && e.mutedSeat == seat;
    final base = seat == 0
        ? 'Vous'
        : seat == 1
            ? 'Est'
            : seat == 2
                ? 'Nord'
                : 'Ouest';
    var meta = seat == 0
        ? 'Sud'
        : seat == 2
            ? 'partenaire'
            : 'IA';
    if (e.trumpMaker == seat) meta = e.pcc ? 'solo' : 'preneur';
    if (muted) meta = 'écarté';
    return Opacity(
      opacity: muted ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
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
              border: Border.all(color: active ? _gold : _goldD, width: 2),
            ),
            child: Text(base[0],
                style: const TextStyle(
                    color: _gold, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(width: 6),
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
          for (final p in e.currentTrick)
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
                    big: true,
                    playable: _canPlay(h[i]),
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
    final txt = (t != null && e.trumpOpen) ? 'atout ${kSuitSym[t]}' : 'atout caché';
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
      trumpTxt = 'fermé';
    } else {
      trumpTxt = '—';
    }
    String tgtUs = '—', tgtThem = '—';
    if (e.bid != null && e.trumpMaker != null) {
      if (e.pcc) {
        tgtUs = teamOf(e.trumpMaker!) == 'NS' ? '8 plis' : 'déf.';
        tgtThem = teamOf(e.trumpMaker!) == 'EW' ? '8 plis' : 'déf.';
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
          _teamPanel('Nous', e.tokens['NS']!, _gold),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _stat('Enchère', e.pcc ? 'PCC' : (e.bid?.toString() ?? '—')),
              _stat('Atout', trumpTxt, color: trumpColor),
              _stat('Plis', '${e.trickWinsNS}–${e.trickWinsEW}'),
            ]),
          ),
          _teamPanel('Eux', e.tokens['EW']!, const Color(0xFFE0C07A)),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Notre objectif $tgtUs',
              style: const TextStyle(color: _dim, fontSize: 11)),
          Text('Objectif adverse $tgtThem',
              style: const TextStyle(color: _dim, fontSize: 11)),
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
              center: Alignment(0, -0.1), radius: 0.95, colors: [_feltA, _feltB]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _goldD, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 8))
          ],
        ),
        child: Stack(
          children: [
            Positioned(top: 10, left: 12, child: _trumpChip()),
            Align(
                alignment: Alignment.topCenter,
                child: Padding(
                    padding: const EdgeInsets.only(top: 6), child: _pod(2))),
            Align(
                alignment: Alignment.centerRight,
                child: Padding(
                    padding: const EdgeInsets.only(right: 6), child: _pod(1))),
            Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                    padding: const EdgeInsets.only(left: 6), child: _pod(3))),
            Align(alignment: Alignment.center, child: _trickArea()),
            Positioned(left: 10, bottom: 8, child: _pod(0)),
            Align(alignment: Alignment.bottomCenter, child: _handFan()),
          ],
        ),
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
