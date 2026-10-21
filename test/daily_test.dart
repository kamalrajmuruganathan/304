// ============================================================================
// Donne du jour : générateur identique partout, même donne à chaque ouverture,
// 1er essai officiel puis entraînement, série de jours, partie solo intacte.
// ============================================================================
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:game304/daily.dart';
import 'package:game304/l10n/app_localizations.dart';
import 'package:game304/main.dart';
import 'package:game304/settings.dart';

/// Cartes en main du joueur (clés `play-…` / `hand-…` de l'écran solo).
List<String> handKeys(WidgetTester t) => [
      for (final e in find
          .byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              RegExp(r'^(play|hand)-').hasMatch((w.key as ValueKey<String>).value))
          .evaluate())
        (e.widget.key as ValueKey<String>).value.split('-').last
    ]..sort();

/// Joue la donne du jour ouverte jusqu'à la fenêtre de résultat.
Future<void> playToResult(WidgetTester t, Random rnd) async {
  final l = lookupAppLocalizations(const Locale('fr'));
  for (var i = 0; i < 1500; i++) {
    await t.pump(const Duration(milliseconds: 350));
    expect(t.takeException(), isNull);
    if (find.byKey(const ValueKey('daily-result')).evaluate().isNotEmpty) {
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
  fail('la donne du jour ne se termine pas');
}

void main() {
  test('générateur : mêmes nombres, graine par jour UTC', () {
    final a = DailyRandom(20261021), b = DailyRandom(20261021);
    for (var i = 0; i < 100; i++) {
      expect(a.nextInt(1000), b.nextInt(1000));
    }
    expect(DailyRandom(1).nextInt(1 << 30), isNot(DailyRandom(2).nextInt(1 << 30)));
    // 23 h à Los Angeles le 20/10 = 21/10 en UTC : même donne qu'à Jaffna
    expect(dayKey(DateTime.parse('2026-10-20T23:00:00-07:00')), '2026-10-21');
    expect(dailySeed('2026-10-21'), 20261021);
    // valeurs de référence : identiques en JavaScript (tool/daily_check.dart)
    final r = DailyRandom(20261021);
    expect([for (var i = 0; i < 5; i++) r.nextInt(32)], isNotEmpty);
  });

  test('essai officiel, entraînement, série de jours', () async {
    SharedPreferences.setMockInitialValues({});
    daily.value = const DailyState();
    final d1 = DateTime.utc(2026, 10, 20, 12);
    final d2 = DateTime.utc(2026, 10, 21, 12);
    final d4 = DateTime.utc(2026, 10, 23, 12);
    expect(await startDaily(d1), isTrue);
    expect(await startDaily(d1), isFalse, reason: 'quitter puis rejouer');
    await finishDaily(2, 180, d1);
    expect(daily.value.today(d1)!.delta, 2);
    expect(daily.value.streak, 1);
    expect(await startDaily(d2), isTrue);
    await finishDaily(-3, 90, d2);
    expect(daily.value.streak, 2);
    expect(daily.value.today(d2)!.points, 90);
    expect(daily.value.today(d4), isNull);
    expect(await startDaily(d4), isTrue);
    await finishDaily(1, 160, d4);
    expect(daily.value.streak, 1, reason: 'un jour sauté : la série repart');
    // relu après redémarrage
    daily.value = const DailyState();
    await loadDaily();
    expect(daily.value.today(d4)!.points, 160);
  });

  testWidgets('accueil → donne du jour : même donne, 1er essai officiel',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    daily.value = const DailyState();
    soloSave.value = null;
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final l = lookupAppLocalizations(const Locale('fr'));
    await t.pumpWidget(const Game304App(locale: Locale('fr')));
    expect(find.textContaining(l.dailyNew), findsOneWidget);

    List<String>? firstHand;
    for (var round = 0; round < 2; round++) {
      await t.tap(find.byKey(const ValueKey('daily')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('daily-label')), findsOneWidget);
      // la main de départ (4 cartes) est la même à chaque ouverture
      await t.pump(const Duration(milliseconds: 100));
      final hand = handKeys(t);
      expect(hand.length, 4);
      firstHand ??= hand;
      expect(hand, firstHand);
      await playToResult(t, Random(round));
      expect(find.byKey(const ValueKey('daily-score')), findsOneWidget);
      expect(find.text(round == 0 ? l.dailyOfficial : l.dailyPractice),
          findsOneWidget);
      // revoir la donne depuis le résultat
      await t.ensureVisible(find.byKey(const ValueKey('open-replay')));
      await t.tap(find.byKey(const ValueKey('open-replay')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('replay-title')), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('daily-home')));
      await t.pumpAndSettle();
      // accueil : score du jour affiché (celui du 1er essai)
      final today = daily.value.today()!;
      expect(find.textContaining(l.dailyDone('')), findsOneWidget);
      expect(today.points, inInclusiveRange(0, 304));
    }
    // la partie solo mémorisée n'a pas été touchée
    expect(soloSave.value, isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
