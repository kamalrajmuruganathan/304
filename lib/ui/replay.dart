// ============================================================================
// « Revoir la donne » : les 8 plis un par un, mains de tout le monde dévoilées.
// Données : Engine.replayJson() (solo) ou champ `replay` de la vue réseau
// (envoyé par le serveur seulement une fois la donne terminée).
// ============================================================================
import 'package:flutter/material.dart' hide Card;

import '../engine/engine.dart';
import '../l10n/app_localizations.dart';
import '../settings.dart';
import 'skin.dart';

Color get _gold => sk.accent;
const _cream = Color(0xFFF6F1E2);
const _ink = Color(0xFF1A160F);
const _red = Color(0xFFB12B2B);
Color get _txt => sk.text;
Color get _dim => sk.dim;

class ReplayPlay {
  final int seat;
  final Card card;
  final bool faceDown, indicator;
  const ReplayPlay(this.seat, this.card, this.faceDown, this.indicator);
}

class ReplayTrick {
  final int winner, points;
  final List<ReplayPlay> cards;
  const ReplayTrick(this.winner, this.points, this.cards);
}

/// Une donne complète, prête à être rejouée à l'écran.
class DealReplay {
  final List<List<Card>> hands; // au début du jeu des plis
  final Card? indicator; // atout posé sur la table au début du jeu
  final String? trumpSuit;
  final int? trumpMaker, mutedSeat;
  final Object? bid;
  final bool pcc;
  final List<ReplayTrick> tricks;

  const DealReplay(
      {required this.hands,
      required this.indicator,
      required this.trumpSuit,
      required this.trumpMaker,
      required this.mutedSeat,
      required this.bid,
      required this.pcc,
      required this.tricks});

  static DealReplay? fromJson(Map? j) {
    if (j == null) return null;
    Card c(Object? x) => Engine.cardFromJson(x as Map);
    return DealReplay(
      hands: [
        for (final h in j['hands'] as List) [for (final x in h as List) c(x)]
      ],
      indicator: j['indicator'] == null ? null : c(j['indicator']),
      trumpSuit: j['trumpSuit'] as String?,
      trumpMaker: j['trumpMaker'] as int?,
      mutedSeat: j['mutedSeat'] as int?,
      bid: j['bid'],
      pcc: j['pcc'] == true,
      tricks: [
        for (final t in j['tricks'] as List)
          ReplayTrick(
            (t as Map)['winner'] as int,
            t['points'] as int,
            [
              for (final p in t['cards'] as List)
                ReplayPlay((p as Map)['seat'] as int, c(p['card']),
                    p['faceDown'] == true, p['indicator'] == true)
            ],
          )
      ],
    );
  }

  /// Cartes encore en main de [seat] après [step] plis.
  List<Card> handAfter(int seat, int step) {
    final played = <String>{
      for (final t in tricks.take(step))
        for (final p in t.cards)
          if (p.seat == seat) p.card.key
    };
    return [
      for (final c in hands[seat])
        if (!played.contains(c.key)) c
    ];
  }

  /// L'atout posé est-il encore sur la table après [step] plis ?
  bool indicatorAfter(int step) =>
      indicator != null &&
      !tricks
          .take(step)
          .any((t) => t.cards.any((p) => p.card.key == indicator!.key));
}

class ReplayScreen extends StatefulWidget {
  const ReplayScreen(
      {super.key, required this.replay, required this.names, this.you = 0});
  final DealReplay replay;

  /// Nom affiché de chaque siège (0 Sud, 1 Est, 2 Nord, 3 Ouest).
  final List<String> names;

  /// Siège affiché en bas (le joueur ; 0 pour un spectateur).
  final int you;

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  int step = 0; // 0 = début du jeu ; k = après le pli k

  DealReplay get r => widget.replay;
  int get last => r.tricks.length;

  Widget _card(Card c, {double w = 30, bool dim = false, bool gold = false}) {
    final col = suitColor(c.suit, ink: _ink, red: _red);
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: Container(
        width: w,
        height: w * 1.42,
        margin: const EdgeInsets.all(1.5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Colors.white, _cream]),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
              color: gold ? _gold : Colors.black26, width: gold ? 2.5 : 1),
        ),
        child: Text('${c.rank}\n${kSuitSym[c.suit]}',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: col,
                fontWeight: FontWeight.bold,
                fontSize: w * 0.34,
                height: 1.05)),
      ),
    );
  }

  /// Main d'un siège (et l'atout posé devant le preneur).
  Widget _hand(int seat, AppLocalizations l, {bool vertical = false}) {
    final cards = r.handAfter(seat, step);
    final muted = r.mutedSeat == seat;
    final showInd = seat == r.trumpMaker && r.indicatorAfter(step);
    final name = Text(
        '${widget.names[seat]}${seat == r.trumpMaker ? ' · ${l.mMaker}' : ''}'
        '${muted ? ' · ${l.mOut}' : ''}',
        key: ValueKey('replay-name-$seat'),
        textAlign: TextAlign.center,
        style: TextStyle(color: _txt, fontSize: 11));
    final row = Wrap(
      alignment: WrapAlignment.center,
      direction: Axis.horizontal,
      children: [
        for (final c in cards)
          KeyedSubtree(
              key: ValueKey('replay-hand-$seat-${c.key}'),
              child: _card(c, dim: muted)),
        if (showInd)
          Tooltip(
            message: l.replayIndicator,
            child: KeyedSubtree(
                key: const ValueKey('replay-indicator'),
                child: _card(r.indicator!, gold: true)),
          ),
      ],
    );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      name,
      const SizedBox(height: 2),
      vertical ? SizedBox(width: 70, child: row) : row,
    ]);
  }

  Widget _trick(AppLocalizations l) {
    if (step == 0) {
      return SizedBox(
        width: 150,
        height: 140,
        child: Center(
            child: Text(l.replayStart,
                textAlign: TextAlign.center,
                style: TextStyle(color: _dim, fontSize: 12))),
      );
    }
    final t = r.tricks[step - 1];
    Alignment at(int seat) => const [
          Alignment.bottomCenter,
          Alignment.centerRight,
          Alignment.topCenter,
          Alignment.centerLeft
        ][(seat - widget.you + 4) % 4];
    return SizedBox(
      width: 150,
      height: 140,
      child: Stack(children: [
        for (final p in t.cards)
          Align(
            alignment: at(p.seat),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _card(p.card, w: 34, gold: p.seat == t.winner),
              if (p.faceDown)
                Text(l.replayHidden,
                    style: TextStyle(color: _dim, fontSize: 9)),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    int rel(int k) => (widget.you + k) % 4;
    // plis et points cumulés jusqu'à l'étape affichée
    var tNS = 0, tEW = 0, pNS = 0, pEW = 0;
    for (final t in r.tricks.take(step)) {
      if (t.winner.isEven) {
        tNS++;
        pNS += t.points;
      } else {
        tEW++;
        pEW += t.points;
      }
    }
    final usNS = widget.you.isEven;
    final title = step == 0
        ? l.replayStart
        : l.replayTrick(step, widget.names[r.tricks[step - 1].winner],
            r.tricks[step - 1].points);
    final trump = r.trumpSuit == null ? '—' : kSuitSym[r.trumpSuit]!;
    return Scaffold(
      backgroundColor: sk.bg,
      appBar: AppBar(title: Text(l.replayTitle)),
      body: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            color: sk.bar.$1,
            child: Text(
              '${r.pcc ? 'Partner Close Caps' : '${l.bid} ${r.bid ?? '—'}'} · '
              '${l.trump} $trump · ${l.tricks} '
              '${usNS ? tNS : tEW}–${usNS ? tEW : tNS} · '
              '${l.pointsN(usNS ? pNS : pEW)}–${usNS ? pEW : pNS}',
              key: const ValueKey('replay-score'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _txt),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(title,
                key: const ValueKey('replay-title'),
                textAlign: TextAlign.center,
                style: TextStyle(color: _gold, fontSize: 15)),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                    colors: [sk.tableColors.$1, sk.tableColors.$2]),
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
              child: SingleChildScrollView(
                child: Column(children: [
                  _hand(rel(2), l),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _hand(rel(3), l, vertical: true),
                      Expanded(child: Center(child: _trick(l))),
                      _hand(rel(1), l, vertical: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _hand(rel(0), l),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    key: const ValueKey('replay-first'),
                    tooltip: l.replayStart,
                    onPressed: step > 0 ? () => setState(() => step = 0) : null,
                    icon: const Icon(Icons.first_page)),
                IconButton(
                    key: const ValueKey('replay-prev'),
                    tooltip: l.replayPrev,
                    onPressed: step > 0 ? () => setState(() => step--) : null,
                    icon: const Icon(Icons.chevron_left)),
                Text('$step / $last', style: TextStyle(color: _txt)),
                IconButton(
                    key: const ValueKey('replay-next'),
                    tooltip: l.replayNext,
                    onPressed:
                        step < last ? () => setState(() => step++) : null,
                    icon: const Icon(Icons.chevron_right)),
                IconButton(
                    key: const ValueKey('replay-last'),
                    tooltip: l.replayEnd,
                    onPressed:
                        step < last ? () => setState(() => step = last) : null,
                    icon: const Icon(Icons.last_page)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
