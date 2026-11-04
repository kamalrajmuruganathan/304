// ============================================================================
// Tournoi contre les bots : règles du match (6 donnes, égalité, 0 jeton),
// enchaînement des tours, mémorisation, et donnes jouées à l'écran.
// ============================================================================
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:game304/l10n/app_localizations.dart';
import 'package:game304/main.dart';
import 'package:game304/settings.dart';
import 'package:game304/tournament.dart';

/// Joue jusqu'à la fenêtre de résultat d'une donne de tournoi.
Future<void> playToTourResult(WidgetTester t, Random rnd) async {
  final l = lookupAppLocalizations(const Locale('fr'));
  for (var i = 0; i < 1500; i++) {
    await t.pump(const Duration(milliseconds: 350));
    expect(t.takeException(), isNull);
    if (find.byKey(const ValueKey('tour-continue')).evaluate().isNotEmpty) {
      return;
    }
    final playable = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('play-'));
    if (playable.evaluate().isNotEmpty) {
      await t.tap(playable.at(rnd.nextInt(playable.evaluate().length)),
          warnIfMissed: false);
      continue;
    }
    final passe = find.text(l.pass);
    if (passe.evaluate().isNotEmpty) {
      await t.tap(passe.first);
      continue;
    }
    final buttons = find.descendant(
        of: find.byType(Wrap),
        matching: find.byWidgetPredicate(
            (w) => w is FilledButton || w is OutlinedButton));
    if (buttons.evaluate().isNotEmpty) await t.tap(buttons.first);
  }
  fail('la donne de tournoi ne se termine pas');
}

void main() {
  test('match : 6 donnes, égalité prolongée, 0 jeton = fin immédiate', () {
    var s = const TourState();
    expect(s.level, 'easy');
    expect(s.fresh, isTrue);
    for (var d = 1; d <= 5; d++) {
      s = s.afterDeal(12, 10, d & 3);
      expect(s.matchOver, isFalse, reason: 'donne $d');
    }
    s = s.afterDeal(11, 11, 2); // 6 donnes, égalité
    expect(s.matchOver, isFalse);
    expect(s.extra, isTrue);
    s = s.afterDeal(9, 13, 3); // donne décisive perdue
    expect(s.matchOver, isTrue);
    expect(s.matchWon, isFalse);
    expect(s.restart().round, 0);

    // 0 jeton avant la 6e donne
    expect(const TourState(deal: 2).afterDeal(22, 0, 0).matchWon, isTrue);
    expect(const TourState(deal: 2).afterDeal(0, 22, 0).matchOver, isTrue);
  });

  test('tours : Facile → Normal → Difficile, titre après la finale', () {
    var s = const TourState(titles: 2);
    s = s.afterDeal(14, 8, 0);
    for (var i = 0; i < 5; i++) {
      s = s.afterDeal(14, 8, i & 3);
    }
    expect(s.matchWon, isTrue);
    s = s.next();
    expect((s.round, s.level, s.deal, s.ns, s.ew), (1, 'normal', 0, 11, 11));
    s = s.next();
    expect(s.level, 'hard');
    s = s.next();
    expect((s.round, s.titles, s.fresh), (0, 3, true));
    // relu depuis JSON, valeurs hors bornes ramenées
    final r = TourState.fromJson({'round': 9, 'ns': 40, 'ew': -1, 'dealer': 6});
    expect((r.round, r.ns, r.ew, r.dealer), (2, 22, 0, 2));
  });

  testWidgets(
      'tournoi à l\'écran : donnes jouées, match mémorisé, '
      'partie solo intacte', (t) async {
    SharedPreferences.setMockInitialValues({});
    await loadSettings();
    tour.value = const TourState();
    soloSave.value = null;
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final l = lookupAppLocalizations(const Locale('fr'));
    await t.pumpWidget(const Game304App(locale: Locale('fr')));
    final btn = find.byKey(const ValueKey('home-tournament'));
    await t.ensureVisible(btn);
    await t.pumpAndSettle();
    expect(find.textContaining(l.tourRules), findsOneWidget);
    await t.tap(btn);
    await t.pumpAndSettle();

    final rnd = Random(3);
    for (var d = 1; d <= 3; d++) {
      await playToTourResult(t, rnd);
      final st = tour.value;
      expect(st.deal, d);
      expect(st.ns + st.ew, 22);
      expect(find.byKey(const ValueKey('tour-status')), findsOneWidget);
      if (!st.matchOver) {
        expect(find.textContaining(l.tourDeal(d, kTourDeals)), findsOneWidget);
      }
      await t.tap(find.byKey(const ValueKey('tour-continue')));
      await t.pumpAndSettle();
      if (st.matchOver) break;
    }
    // mémorisé
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tour304'), isNotNull);
    // la partie solo n'est pas touchée
    expect(soloSave.value, isNull);
    tour.value = const TourState();
  });

  testWidgets('finale contre le niveau Difficile : une donne sans erreur',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    await loadSettings();
    tour.value = const TourState(round: 2, deal: 5, ns: 12, ew: 10);
    t.view.physicalSize = const Size(360, 640) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final l = lookupAppLocalizations(const Locale('fr'));
    await t.pumpWidget(const Game304App(locale: Locale('fr')));
    final btn = find.byKey(const ValueKey('home-tournament'));
    await t.ensureVisible(btn);
    await t.pumpAndSettle();
    expect(find.textContaining(l.tourRound2), findsOneWidget);
    expect(find.textContaining(l.tourOpponents(l.levelHard)), findsOneWidget);
    await t.tap(btn);
    await t.pumpAndSettle();
    await playToTourResult(t, Random(1));
    final st = tour.value;
    expect(st.deal, 6);
    if (st.matchOver) {
      expect(
          find.textContaining(st.matchWon ? l.tourChampion : l.tourEliminated),
          findsOneWidget);
      await t.tap(find.byKey(const ValueKey('tour-continue')));
      await t.pumpAndSettle();
      expect(tour.value.round, 0);
      expect(tour.value.titles, st.matchWon ? 1 : 0);
    } else {
      expect(find.textContaining(l.tourExtra), findsOneWidget);
    }
    tour.value = const TourState();
  });
}
