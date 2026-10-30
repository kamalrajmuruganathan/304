// ============================================================================
// Test d'interface Flutter (écran solo) : l'app est lancée sur un écran de
// téléphone et des donnes complètes sont jouées en touchant les vrais boutons
// et les vraies cartes. Échoue sur toute exception (dont les débordements de
// mise en page) et sur tout blocage. Équivalent Flutter de tools/ui-test.
// ============================================================================
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:game304/l10n/app_localizations.dart';
import 'package:game304/main.dart';
import 'package:game304/settings.dart';
import 'package:game304/ui/anim.dart';

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
    // les pions ne se chevauchent pas (petit écran, table basse aux enchères)
    final pods = [
      for (final k in [0, 1, 2, 3])
        if (find.byKey(ValueKey('pod-$k')).evaluate().isNotEmpty)
          tester.getRect(find.byKey(ValueKey('pod-$k')))
    ];
    for (var a = 0; a < pods.length; a++) {
      for (var b = a + 1; b < pods.length; b++) {
        expect(pods[a].overlaps(pods[b]), isFalse,
            reason: 'pions qui se chevauchent : ${pods[a]} / ${pods[b]}');
      }
    }
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
      // récapitulatif (plis, points, jetons) dans le résultat de la donne
      expect(find.byKey(const ValueKey('deal-recap')), findsOneWidget);
      // « Revoir la donne » (1re donne) : les 8 plis, puis retour au résultat
      if (hands == 0) {
        await tester.tap(find.byKey(const ValueKey('open-replay')));
        await tester.pumpAndSettle();
        expect(find.text(l.replayStart), findsWidgets);
        var steps = 0;
        while (tester
                .widget<IconButton>(find.byKey(const ValueKey('replay-next')))
                .onPressed !=
            null) {
          await tester.tap(find.byKey(const ValueKey('replay-next')));
          await tester.pump();
          expect(tester.takeException(), isNull);
          steps++;
        }
        expect(steps, 8, reason: '8 plis à revoir');
        expect(find.textContaining('8/8'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        seen.add('revoir la donne');
      }
      await tester.tap(next.evaluate().isNotEmpty ? next : again);
      await tester.pumpAndSettle();
      hands++;
      idle = 0;
      continue;
    }

    // coupe à l'atout posé : proposée seulement au preneur en jeu fermé
    final cut = find.byKey(const ValueKey('cut-indicator'));
    if (cut.evaluate().isNotEmpty) {
      seen.add('bouton coupe atout posé');
      if (rnd.nextBool()) {
        await tester.tap(cut);
        seen.add('coupe atout posé (joueur)');
        cardsPlayed++;
        idle = 0;
        continue;
      }
    }

    // annonce « Caps » : proposée au joueur qui entame quand son équipe a
    // gagné tous les plis ; touchée parfois (juste ou trop tôt)
    final caps = find.byKey(const ValueKey('call-caps'));
    if (caps.evaluate().isNotEmpty) {
      seen.add('bouton Caps');
      if (rnd.nextInt(4) == 0) {
        // confirmation (rappel de la pénalité) : parfois « Annuler »
        await tester.tap(caps);
        await tester.pumpAndSettle();
        expect(find.text(l.capsConfirm(2)), findsOneWidget);
        if (rnd.nextBool()) {
          await tester.tap(find.byKey(const ValueKey('caps-cancel')));
          await tester.pumpAndSettle();
          expect(caps, findsOneWidget, reason: 'annulé : bouton toujours là');
          seen.add('Caps annulé');
        } else {
          await tester.tap(find.byKey(const ValueKey('caps-confirm')));
          await tester.pumpAndSettle();
          expect(caps, findsNothing, reason: 'une seule annonce par donne');
          expect(find.textContaining(l.capsCalledBy(l.mSud)), findsOneWidget);
          seen.add('Caps annoncé (joueur)');
        }
        idle = 0;
        continue;
      }
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

  testWidgets('solo, niveau difficile : 4 donnes via l\'interface',
      (tester) async {
    botLevel.value = 'hard'; // Est/Ouest : IA Monte-Carlo (lib/ai/hard.dart)
    addTearDown(() => botLevel.value = 'normal');
    expect(
        await playSolo(tester, size: const Size(360, 640), deals: 4, seed: 21),
        4);
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
            find.textContaining(l.hintPass).evaluate().isNotEmpty ||
                find.textContaining('Conseil : annoncer').evaluate().isNotEmpty,
            isTrue);
        // avec l'estimation de la main
        expect(find.textContaining('Votre main vaut environ'), findsOneWidget);
        bidHint = true;
        continue;
      }
      if (hint.evaluate().isNotEmpty &&
          playable.evaluate().isNotEmpty &&
          !playHint) {
        await tester.tap(hint.first); // jeu
        await tester.pump();
        // la carte conseillée, et pourquoi (une des raisons traduites)
        final tips = [
          for (final e in find.byType(Text).evaluate())
            (e.widget as Text).data ?? ''
        ].where((t) =>
            t.startsWith(l.hintPlay) ||
            t.startsWith(l.hintCut) ||
            t == l.hintDiscard ||
            t == l.hintCaps);
        expect(tips, isNotEmpty);
        if (tips.first.startsWith(l.hintPlay)) {
          expect(tips.first.length, greaterThan(l.hintPlay.length + 10),
              reason: 'raison du conseil : ${tips.first}');
        }
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

  testWidgets('solo : double toucher rapide sur une carte (sans exception)',
      (tester) async {
    final l = lookupAppLocalizations(const Locale('fr'));
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const Game304App(locale: Locale('fr')));
    await tester.tap(find.text(l.quickPlay));
    await tester.pumpAndSettle();
    var doubles = 0;
    for (var step = 0; step < 3000 && doubles < 5; step++) {
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      for (final t in [l.close, l.nextDeal, l.playAgain, l.pass, l.keep]) {
        if (find.text(t).evaluate().isNotEmpty) {
          await tester.tap(find.text(t).first);
          await tester.pumpAndSettle();
          break;
        }
      }
      final playable = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('play-'));
      final hand = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          RegExp(r'^(play|hand)-').hasMatch((w.key as ValueKey<String>).value));
      if (playable.evaluate().isEmpty) {
        // choix d'atout / jeu fermé : premier bouton d'action
        final buttons = find.descendant(
            of: find.byType(Wrap),
            matching: find.byWidgetPredicate(
                (w) => w is FilledButton || w is OutlinedButton));
        if (buttons.evaluate().isNotEmpty) {
          await tester.tap(buttons.first, warnIfMissed: false);
        }
        continue;
      }
      // carte la plus à droite = dernière case de la main
      Finder rightmost(Finder f) {
        var best = f.first;
        for (var k = 0; k < f.evaluate().length; k++) {
          if (tester.getCenter(f.at(k)).dx > tester.getCenter(best).dx) {
            best = f.at(k);
          }
        }
        return best;
      }

      final last = rightmost(hand);
      final target = last.evaluate().first.widget.key as ValueKey<String>;
      if (!target.value.startsWith('play-') || e2eChooseTrump(tester)) {
        await tester.tap(playable.first, warnIfMissed: false);
        continue;
      }
      // deux touchers sans reconstruction entre les deux
      await tester.tap(last, warnIfMissed: false);
      await tester.tap(last, warnIfMissed: false);
      expect(tester.takeException(), isNull, reason: 'double toucher');
      doubles++;
    }
    expect(doubles, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('solo : quitter la partie demande confirmation', (tester) async {
    final l = lookupAppLocalizations(const Locale('fr'));
    await tester.pumpWidget(const Game304App(locale: Locale('fr')));
    await tester.tap(find.text(l.quickPlay));
    await tester.pumpAndSettle();
    // geste « retour » du téléphone : confirmation, « Rester » garde la partie
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(l.leaveGame), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leave-stay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('leave-game')), findsOneWidget);
    // bouton retour de l'écran : « Quitter » ramène à l'accueil
    await tester.tap(find.byKey(const ValueKey('leave-game')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('leave-confirm')));
    await tester.pumpAndSettle();
    expect(find.text(l.quickPlay), findsOneWidget);
    expect(find.byKey(const ValueKey('leave-game')), findsNothing);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('solo : partie interrompue reprise depuis l\'accueil',
      (tester) async {
    final l = lookupAppLocalizations(const Locale('fr'));
    addTearDown(() => soloSave.value = null);
    // partie mémorisée par une session précédente (app fermée à 14 - 8)
    SharedPreferences.setMockInitialValues(
        {'solo304': jsonEncode({'ns': 14, 'ew': 8, 'dealer': 2})});
    await loadSettings();
    expect(soloSave.value?.ns, 14);
    await tester.pumpWidget(const Game304App(locale: Locale('fr')));
    final resume = find.byKey(const ValueKey('resume-solo'));
    expect(resume, findsOneWidget);
    expect(find.textContaining(l.resumeGame), findsOneWidget);
    await tester.tap(resume);
    await tester.pumpAndSettle();
    // le score reprend : 14 pour nous, 8 pour eux, même donneur
    expect(find.text('14'), findsOneWidget);
    expect(find.text('8'), findsWidgets);
    expect(soloSave.value?.ns, 14);
    expect(soloSave.value?.dealer, 2);
    // retour à l'accueil : la partie reste à reprendre
    await tester.tap(find.byKey(const ValueKey('leave-game')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('leave-confirm')));
    await tester.pumpAndSettle();
    expect(resume, findsOneWidget);
    // score de départ (11-11) : rien à reprendre
    soloSave.value = const SoloSave(11, 11, 0);
    await tester.pump();
    expect(resume, findsNothing);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('solo : le score est mémorisé après chaque donne',
      (tester) async {
    addTearDown(() => soloSave.value = null);
    soloSave.value = null;
    await playSolo(tester, size: const Size(390, 844), deals: 2, seed: 1);
    final s = soloSave.value;
    expect(s, isNotNull);
    expect(s!.ns + s.ew, 22); // jetons toujours au total de 22
  });

  testWidgets('solo : niveau « facile » choisi à l\'accueil, 4 donnes jouées',
      (tester) async {
    final l = lookupAppLocalizations(const Locale('fr'));
    addTearDown(() => botLevel.value = 'normal');
    await tester.pumpWidget(const Game304App(locale: Locale('fr')));
    // titre de carte (en majuscules dans les thèmes Cristal et Nuit)
    expect(
        find.text(l.botLevel).evaluate().length +
            find.text(l.botLevel.toUpperCase()).evaluate().length,
        1);
    await tester.ensureVisible(find.byKey(const ValueKey('level-easy')));
    await tester.tap(find.byKey(const ValueKey('level-easy')));
    await tester.pump();
    expect(botLevel.value, 'easy');
    await tester.pumpWidget(const SizedBox());
    expect(
        await playSolo(tester, size: const Size(390, 844), deals: 4, seed: 9),
        4);
  });

  testWidgets('solo : animation de distribution', (tester) async {
    final l = lookupAppLocalizations(const Locale('fr'));
    await tester.pumpWidget(const Game304App(locale: Locale('fr')));
    await tester.tap(find.text(l.quickPlay));
    List<double> opacities() => [
          for (final e in find
              .descendant(
                  of: find.byType(DealIn), matching: find.byType(Opacity))
              .evaluate())
            (e.widget as Opacity).opacity
        ];
    // attend la distribution (cartes à l'écran), sans laisser finir l'animation
    for (var i = 0; i < 50 && opacities().length < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // les 4 cartes arrivent en cascade : en cours d'apparition…
    expect(opacities(), hasLength(4));
    expect(opacities().where((o) => o < 1), isNotEmpty);
    // animation la plus longue : 260 + 3×70 = 470 ms ; vérifié avant le
    // premier coup d'un bot (600 ms), qui peut redistribuer et relancer l'animation
    await tester.pump(const Duration(milliseconds: 500));
    // … puis toutes posées
    expect(opacities().every((o) => o == 1), isTrue);
    // écran quitté : laisse expirer les minuteurs des bots
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('solo : grandes cartes + 4 couleurs sur petit écran (360×640)',
      (tester) async {
    cardSize.value = 'large';
    deckColors.value = 'four';
    addTearDown(() {
      cardSize.value = 'normal';
      deckColors.value = 'two';
    });
    expect(
        await playSolo(tester, size: const Size(360, 640), deals: 6, seed: 5),
        6);
  });

  testWidgets('solo : 10 donnes sur petit écran (360×640)', (tester) async {
    expect(
        await playSolo(tester, size: const Size(360, 640), deals: 10, seed: 2),
        10);
  });

  testWidgets(
      'solo : 6 donnes sur tablette portrait (800×1280, cartes agrandies)',
      (tester) async {
    expect(autoCardScale(const Size(800, 1280)), greaterThan(1.4));
    expect(autoCardScale(const Size(390, 844)), 1.0);
    expect(
        await playSolo(tester, size: const Size(800, 1280), deals: 6, seed: 9),
        6);
  });

  testWidgets('solo : 10 donnes sur tablette paysage (1024×768)',
      (tester) async {
    expect(
        await playSolo(tester, size: const Size(1024, 768), deals: 10, seed: 3),
        10);
  });
}

/// Vrai pendant le choix d'atout (les cartes servent à choisir, pas à jouer).
bool e2eChooseTrump(WidgetTester tester) {
  final l = lookupAppLocalizations(const Locale('fr'));
  String head(String s) => s.split(RegExp(r'[.!:(]')).first.trim();
  return find.textContaining(head(l.youWinR1)).evaluate().isNotEmpty ||
      find.textContaining(head(l.youTakeR2)).evaluate().isNotEmpty ||
      find.textContaining(head(l.pccYou)).evaluate().isNotEmpty;
}
