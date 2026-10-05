// ============================================================================
// Test d'interface Flutter (écran solo) : l'app est lancée sur un écran de
// téléphone et des donnes complètes sont jouées en touchant les vrais boutons
// et les vraies cartes. Échoue sur toute exception (dont les débordements de
// mise en page) et sur tout blocage. Équivalent Flutter de tools/ui-test.
// ============================================================================
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game304/l10n/app_localizations.dart';
import 'package:game304/main.dart';
import 'package:game304/settings.dart';

/// Cas rencontrés pendant les parties (pour vérifier la couverture).
final seen = <String>{};

/// Joue [deals] donnes dans la langue [lang]. [onTexts] reçoit, à chaque pas,
/// tous les textes affichés (contrôle des traductions).
Future<int> playSolo(WidgetTester tester,
    {required Size size,
    required int deals,
    required int seed,
    String lang = 'fr',
    void Function(List<String> texts)? onTexts}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final rnd = Random(seed);
  final l = lookupAppLocalizations(Locale(lang));
  String head(String s) => s.split(RegExp(r'[.!:(]')).first.trim();
  final cases = {
    'preneur 1er tour': head(l.youWinR1),
    'fermé/ouvert': head(l.openOrClosed),
    'face cachée': l.youFacedown,
    'dernier pli atout posé': l.lastTrickTM,
    'PCC': 'Partner Close Caps',
  };

  await tester.pumpWidget(Game304App(locale: Locale(lang)));
  await tester.tap(find.text(l.quickPlay));
  await tester.pumpAndSettle();

  var hands = 0, idle = 0, cardsPlayed = 0, bidsMade = 0, steps = 0;
  while (hands < deals) {
    // garde-fou : une donne ne demande jamais plus de ~200 actions
    if (++steps > 400 * deals) fail('aucune progression (blocage ?)');
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    for (final c in cases.entries) {
      if (find.textContaining(c.value).evaluate().isNotEmpty) seen.add(c.key);
    }
    if (onTexts != null) {
      onTexts([
        for (final e in find.byType(Text).evaluate())
          (e.widget as Text).data ?? '',
      ]);
    }

    // un dialogue « Dernier pli » ouvert se referme
    final close = find.text(l.close);
    if (close.evaluate().isNotEmpty) {
      await tester.tap(close.first);
      await tester.pumpAndSettle();
      continue;
    }

    final next = find.text(l.nextDeal);
    final again = find.text(l.playAgain);
    if (next.evaluate().isNotEmpty || again.evaluate().isNotEmpty) {
      await tester.tap(next.evaluate().isNotEmpty ? next : again);
      await tester.pumpAndSettle();
      hands++;
      idle = 0;
      continue;
    }

    final playable = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('play-'));
    if (playable.evaluate().isNotEmpty) {
      final n = playable.evaluate().length;
      await tester.tap(playable.at(rnd.nextInt(n)), warnIfMissed: false);
      cardsPlayed++;
      idle = 0;
      continue;
    }

    final buttons = find.descendant(
        of: find.byType(Wrap),
        matching: find.byWidgetPredicate(
            (w) => w is FilledButton || w is OutlinedButton));
    if (buttons.evaluate().isNotEmpty) {
      // surtout « Passe », parfois une enchère : le joueur devient aussi preneur
      final passe = find.descendant(of: buttons, matching: find.text(l.pass));
      final n = buttons.evaluate().length;
      if (passe.evaluate().isNotEmpty && rnd.nextInt(3) > 0) {
        await tester.tap(passe.first);
      } else {
        await tester.tap(buttons.at(rnd.nextInt(n)));
        bidsMade++;
      }
      idle = 0;
      continue;
    }

    if (++idle > 120) {
      fail('blocage : aucune action possible depuis 40 s (donne ${hands + 1})');
    }
  }
  // démonte l'écran puis laisse expirer les minuteurs des bots
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  expect(cardsPlayed, greaterThan(deals), reason: 'des cartes ont été jouées');
  // chaque donne terminée est comptée (statistiques de l'accueil)
  expect(stats.value.played, greaterThanOrEqualTo(deals));
  expect(stats.value.won + stats.value.lost, stats.value.played);
  expect(bidsMade, greaterThan(0), reason: 'des choix ont été faits');
  return hands;
}

void main() {
  // DEALS=300 flutter test test/ui_solo_test.dart : campagne longue
  const long = int.fromEnvironment('DEALS', defaultValue: 0);
  if (long > 0) {
    testWidgets('solo : $long donnes (campagne longue)', (tester) async {
      await playSolo(tester, size: const Size(390, 844), deals: long, seed: 7);
      // ignore: avoid_print
      print('cas couverts : $seen');
    });
    return;
  }

  testWidgets('solo : 25 donnes jouées via l\'interface (téléphone 390×844)',
      (tester) async {
    expect(
        await playSolo(tester, size: const Size(390, 844), deals: 25, seed: 1),
        25);
    // le joueur a été preneur et a choisi son atout via l'interface
    expect(seen, contains('preneur 1er tour'));
    expect(seen, contains('fermé/ouvert'));
  });

  testWidgets('solo : boutons Conseil et Dernier pli', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final l = lookupAppLocalizations(const Locale('fr'));
    await tester.pumpWidget(const Game304App(locale: Locale('fr')));
    await tester.tap(find.text(l.quickPlay));
    await tester.pumpAndSettle();
    final rnd = Random(5);
    var bidHint = false, playHint = false, lastTrick = false;
    for (var i = 0; i < 3000 && !(bidHint && playHint && lastTrick); i++) {
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      final hint = find.text(l.hint.replaceAll('💡', '').trim());
      final last = find.text(l.lastTrickBtn);
      final playable = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('play-'));
      if (find.text(l.nextDeal).evaluate().isNotEmpty) {
        await tester.tap(find.text(l.nextDeal));
        await tester.pumpAndSettle();
        continue;
      }
      if (hint.evaluate().isNotEmpty &&
          playable.evaluate().isEmpty &&
          !bidHint) {
        await tester.tap(hint.first); // enchères
        await tester.pump();
        expect(
            find.text(l.hintPass).evaluate().isNotEmpty ||
                find.textContaining('Conseil : annoncer').evaluate().isNotEmpty,
            isTrue);
        bidHint = true;
        continue;
      }
      if (hint.evaluate().isNotEmpty &&
          playable.evaluate().isNotEmpty &&
          !playHint) {
        await tester.tap(hint.first); // jeu
        await tester.pump();
        expect(
            find.text(l.hintPlay).evaluate().isNotEmpty ||
                find.text(l.hintDiscard).evaluate().isNotEmpty,
            isTrue);
        playHint = true;
        continue;
      }
      if (last.evaluate().isNotEmpty && !lastTrick) {
        await tester.tap(last.first);
        await tester.pumpAndSettle();
        expect(find.textContaining(l.lastTrickBtn), findsWidgets);
        await tester.tap(find.text(l.close));
        await tester.pumpAndSettle();
        lastTrick = true;
        continue;
      }
      if (playable.evaluate().isNotEmpty) {
        await tester.tap(playable.first, warnIfMissed: false);
        continue;
      }
      final pass = find.text(l.pass);
      final buttons = find.descendant(
          of: find.byType(Wrap),
          matching: find.byWidgetPredicate(
              (w) => w is FilledButton || w is OutlinedButton));
      if (pass.evaluate().isNotEmpty) {
        await tester.tap(pass.first);
      } else if (buttons.evaluate().isNotEmpty) {
        await tester.tap(buttons.at(rnd.nextInt(buttons.evaluate().length)));
      }
    }
    expect([bidHint, playHint, lastTrick], [true, true, true]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('solo : 10 donnes sur petit écran (360×640)', (tester) async {
    expect(
        await playSolo(tester, size: const Size(360, 640), deals: 10, seed: 2),
        10);
  });

  testWidgets('solo : 10 donnes sur tablette paysage (1024×768)',
      (tester) async {
    expect(
        await playSolo(tester, size: const Size(1024, 768), deals: 10, seed: 3),
        10);
  });
}
