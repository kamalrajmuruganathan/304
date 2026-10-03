// ============================================================================
// Test d'interface Flutter (écran solo) : l'app est lancée sur un écran de
// téléphone et des donnes complètes sont jouées en touchant les vrais boutons
// et les vraies cartes. Échoue sur toute exception (dont les débordements de
// mise en page) et sur tout blocage. Équivalent Flutter de tools/ui-test.
// ============================================================================
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game304/main.dart';

/// Messages vus pendant les parties (pour vérifier la couverture des cas).
final seen = <String>{};

Future<int> playSolo(WidgetTester tester,
    {required Size size, required int deals, required int seed}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final rnd = Random(seed);

  await tester.pumpWidget(const Game304App());
  await tester.tap(find.text('Partie rapide contre les bots'));
  await tester.pumpAndSettle();

  var hands = 0, idle = 0, cardsPlayed = 0, bidsMade = 0;
  while (hands < deals) {
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    for (final m in const [
      'Vous gagnez le 1er tour',
      'Jeu fermé (atout caché) ou ouvert',
      'Vous ne pouvez pas suivre',
      'Dernier pli : le preneur joue son atout',
      'Partner Close Caps',
    ]) {
      if (find.textContaining(m).evaluate().isNotEmpty) seen.add(m);
    }

    final next = find.text('Donne suivante');
    final again = find.text('Rejouer');
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
      final passe = find.descendant(of: buttons, matching: find.text('Passe'));
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
    expect(seen, contains('Vous gagnez le 1er tour'));
    expect(seen, contains('Jeu fermé (atout caché) ou ouvert'));
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
