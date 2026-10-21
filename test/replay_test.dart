// ============================================================================
// « Revoir la donne » : données (Engine.replayJson, vue réseau) et écran, dans
// les 4 langues sur petit écran.
// ============================================================================
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:game304/ai/bots.dart';
import 'package:game304/engine/engine.dart';
import 'package:game304/l10n/app_localizations.dart';
import 'package:game304/ui/replay.dart';

import 'hard_test.dart' show bidAll;

/// Une donne jouée par les bots jusqu'au bout (graine [seed]).
Engine playedDeal(int seed) {
  for (var s = seed;; s++) {
    final e = Engine(seed: s);
    if (!bidAll(e)) continue;
    while (e.phase == 'play') {
      final t = e.turn;
      if (e.hands[t].isEmpty && t == e.trumpMaker && e.indicatorOnTable) {
        e.playLastIndicator(t);
        continue;
      }
      final c = botPlay(e, t);
      c is PlayIndicator ? e.playIndicatorToCut(t) : e.playCard(t, c as Card);
    }
    return e;
  }
}

void main() {
  test('replayJson : 8 plis, mains vidées pli après pli, rien avant le jeu',
      () {
    expect(Engine(seed: 1).replayJson(), isNull);
    final e0 = Engine(seed: 1)..newHand();
    expect(e0.snapshot(forSeat: 0)['replay'], isNull);
    var withIndicator = 0;
    for (var seed = 0; seed < 60; seed++) {
      final e = playedDeal(seed * 7);
      final r = DealReplay.fromJson(e.replayJson())!;
      expect(r.tricks.length, 8);
      expect(r.trumpMaker, e.trumpMaker);
      if (r.indicator != null) withIndicator++;
      var cards = 0;
      for (var s = 0; s < 4; s++) {
        cards += r.hands[s].length;
      }
      expect(cards + (r.indicator != null ? 1 : 0), 32);
      for (var k = 0; k <= 8; k++) {
        var left = 0;
        for (var s = 0; s < 4; s++) {
          left += r.handAfter(s, k).length;
        }
        final played = r.tricks.take(k).fold(0, (a, t) => a + t.cards.length);
        final indPlayed = r.indicator != null && !r.indicatorAfter(k) ? 1 : 0;
        expect(left, cards - played + indPlayed, reason: 'graine $seed, pli $k');
      }
      // à la fin, seul le partenaire écarté (PCC) garde des cartes
      for (var s = 0; s < 4; s++) {
        if (s != r.mutedSeat) expect(r.handAfter(s, 8), isEmpty);
      }
      // la vue réseau ne contient la donne qu'une fois terminée
      expect(e.phase, 'scored');
      expect(e.snapshot(forSeat: 1)['replay'], isNotNull);
    }
    expect(withIndicator, greaterThan(10)); // jeu fermé : atout posé affiché
  });

  for (final lang in ['fr', 'en', 'ta', 'si']) {
    testWidgets('écran Revoir la donne en $lang (360×640)', (t) async {
      t.view.physicalSize = const Size(360, 640) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final l = lookupAppLocalizations(Locale(lang));
      final e = playedDeal(3);
      final r = DealReplay.fromJson(e.replayJson())!;
      final names = [l.seatYou, l.seatEast, l.seatNorth, l.seatWest];
      await t.pumpWidget(MaterialApp(
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ReplayScreen(replay: r, names: names),
      ));
      expect(find.text(l.replayStart), findsWidgets);
      for (var k = 1; k <= 8; k++) {
        await t.tap(find.byKey(const ValueKey('replay-next')));
        await t.pump();
        expect(t.takeException(), isNull);
        final tr = r.tricks[k - 1];
        expect(find.text(l.replayTrick(k, names[tr.winner], tr.points)),
            findsOneWidget);
      }
      await t.tap(find.byKey(const ValueKey('replay-first')));
      await t.pump();
      expect(find.text(l.replayStart), findsWidgets);
      await t.tap(find.byKey(const ValueKey('replay-last')));
      await t.pump();
      expect(find.text('8 / 8'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
