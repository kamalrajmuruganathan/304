// ============================================================================
// IA « difficile » (lib/ai/hard.dart) : coups légaux, pas de triche (la
// décision ne dépend pas des cartes cachées), et plus forte que l'IA normale.
// ============================================================================
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:game304/ai/bots.dart';
import 'package:game304/ai/hard.dart';
import 'package:game304/engine/engine.dart';

/// Joue les enchères avec l'IA normale (jeu fermé) ; false si tous passent.
bool bidAll(Engine e) {
  e.newHand();
  var rc = 0;
  while (e.canRedeal() && rc < 8) {
    e.redeal();
    rc++;
  }
  e.startBidding1();
  while (e.phase == 'bid1') {
    e.placeBid(botBid(e, e.bidTurn));
    if (e.phase == 'allpass') return false;
  }
  e.chooseTrump1(botChooseTrump(e, e.trumpMaker1!));
  while (e.phase == 'bid2') {
    e.placeBid2(botBid2(e, e.bid2Turn));
  }
  if (e.phase == 'chooseTrumpPCC') {
    e.chooseTrumpPCC(botChooseTrump(e, e.trumpMaker!));
  } else if (e.phase == 'chooseTrump2') {
    e.chooseTrump2(botChooseTrump(e, e.trumpMaker!));
  }
  if (e.phase == 'preplay') e.startPlayClosed();
  return true;
}

/// Un coup ; [hard] : Est/Ouest jouent avec l'IA difficile.
void step(Engine e, bool hard, Random r) {
  final s = e.turn;
  if (e.hands[s].isEmpty && s == e.trumpMaker && e.indicatorOnTable) {
    e.playLastIndicator(s);
    return;
  }
  if (botCallCaps(e, s)) e.callCaps(s);
  final c =
      hard && s.isOdd ? botPlayHard(e, s, rng: r, samples: 6) : botPlay(e, s);
  if (c is PlayIndicator) {
    expect(e.canCutWithIndicator(s), isTrue);
    e.playIndicatorToCut(s);
  } else {
    final card = c as Card;
    expect(e.playableCards(s).any((x) => x.key == card.key), isTrue,
        reason: 'carte illégale $card');
    e.playCard(s, card);
  }
}

void main() {
  test('IA difficile : 150 donnes, coups légaux, 304 points, 8 plis', () {
    final r = Random(1);
    var played = 0;
    for (var d = 0; d < 400 && played < 150; d++) {
      final e = Engine(seed: 1000 + d);
      if (!bidAll(e)) continue;
      played++;
      while (e.phase == 'play') {
        step(e, true, r);
      }
      expect(e.tricks.length, 8);
      expect(e.pointsNS + e.pointsEW, 304);
      expect(e.tokens['NS']! + e.tokens['EW']!, 22);
    }
    expect(played, 150);
  });

  test('IA difficile : ne lit pas les cartes cachées (mains, atout posé)', () {
    var checked = 0, closedTrump = 0;
    for (var d = 0; d < 200 && checked < 60; d++) {
      final e = Engine(seed: 5000 + d);
      if (!bidAll(e)) continue;
      final r = Random(d);
      // avance jusqu'à un tour d'Est ou d'Ouest en milieu de donne
      final stopAt = 2 + r.nextInt(18);
      var n = 0;
      while (e.phase == 'play' && (n < stopAt || e.turn.isEven)) {
        step(e, false, r);
        n++;
      }
      if (e.phase != 'play') continue;
      final seat = e.turn;
      if (e.hands[seat].isEmpty) continue;
      // autre répartition des cartes que [seat] ne voit pas : mains des 3
      // autres (mêmes tailles) et, s'il ne connaît pas l'atout, atout posé
      final twin = e.copy();
      final others = [
        for (var p = 0; p < 4; p++)
          if (p != seat) p
      ];
      final hidden = <Card>[for (final p in others) ...twin.hands[p]];
      final trumpKnown = e.trumpOpen || seat == e.trumpMaker;
      final swapIndicator = e.indicatorOnTable && !trumpKnown;
      if (swapIndicator) hidden.add(twin.indicator!);
      hidden.shuffle(Random(d + 7));
      if (swapIndicator) {
        twin.indicator = hidden.removeLast();
        twin.trumpSuit = twin.indicator!.suit;
        closedTrump++;
      }
      for (final p in others) {
        final k = twin.hands[p].length;
        twin.hands[p] = hidden.sublist(0, k);
        hidden.removeRange(0, k);
      }
      for (final p in others) {
        sortHand(twin.hands[p]);
      }
      final a = botPlayHard(e, seat, rng: Random(42), samples: 8);
      final b = botPlayHard(twin, seat, rng: Random(42), samples: 8);
      String k(Object x) => x is Card ? x.key : 'indicator';
      expect(k(a), k(b), reason: 'donne $d, siège $seat');
      checked++;
    }
    expect(checked, 60);
    expect(closedTrump, greaterThan(5)); // le cas « atout caché » est couvert
  });

  test('IA difficile plus forte que l\'IA normale (mêmes donnes)', () {
    // mesuré (tool/hard_sim.dart, 3000 donnes, 24 tirages) : +0,22 jeton par
    // donne pour Est-Ouest (± 0,05). Ici : 200 donnes, contrôle grossier.
    var diff = 0;
    for (var d = 0; d < 200; d++) {
      int run(bool hard) {
        final e = Engine(seed: 90000 + d);
        if (!bidAll(e)) return 0;
        final r = Random(d);
        while (e.phase == 'play') {
          final s = e.turn;
          if (e.hands[s].isEmpty && s == e.trumpMaker && e.indicatorOnTable) {
            e.playLastIndicator(s);
            continue;
          }
          if (botCallCaps(e, s)) e.callCaps(s);
          final c = hard && s.isOdd ? botPlayHard(e, s, rng: r) : botPlay(e, s);
          c is PlayIndicator
              ? e.playIndicatorToCut(s)
              : e.playCard(s, c as Card);
        }
        return e.tokens['EW']!;
      }

      diff += run(true) - run(false);
    }
    expect(diff, greaterThan(0), reason: 'gain total d\'Est-Ouest : $diff');
  });
}
