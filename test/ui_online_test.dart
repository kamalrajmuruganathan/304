// ============================================================================
// Test d'interface Flutter (table en ligne) contre le VRAI serveur :
// bin/server.dart est lancé sur un port libre, le test crée une table, appuie
// sur « Démarrer » puis joue des donnes complètes en touchant les boutons et
// les cartes de OnlineGameScreen (3 bots côté serveur). Échoue sur toute
// exception, tout message d'erreur du serveur et tout blocage.
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game304/l10n/app_localizations.dart';
import 'package:game304/net/client.dart';
import 'package:game304/ui/online_screen.dart';

late Process server;
late int port;

Future<void> startServer() async {
  final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  port = sock.port;
  await sock.close();
  server = await Process.start('dart', ['run', 'bin/server.dart'],
      environment: {'PORT': '$port'});
  final ready = Completer<void>();
  server.stdout.transform(utf8.decoder).listen((l) {
    if (l.contains('304 server') && !ready.isCompleted) ready.complete();
  });
  server.stderr.transform(utf8.decoder).listen(stderr.write);
  await ready.future.timeout(const Duration(seconds: 90));
}

/// Langue de l'interface pendant le test (non latine : repère tout oubli).
const lang = 'ta';

void main() {
  setUpAll(startServer);
  tearDownAll(() => server.kill());

  testWidgets(
      'en ligne (tamoul) : table créée, démarrée, 2 donnes jouées via l\'UI',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final rnd = Random(4);
    final l = lookupAppLocalizations(const Locale(lang));
    final leaks = <String>{};
    // flutter_test bloque le réseau par défaut (HttpOverrides) : ce test a
    // besoin d'une vraie connexion WebSocket vers le serveur local
    HttpOverrides.global = null;

    final c = GameClient('ws://127.0.0.1:$port/ws');
    final errors = <String>[];
    final joined = Completer<void>();
    var scored = 0;
    String? lastPhase;
    c.events.listen((m) {
      if (m['t'] == 'joined' && !joined.isCompleted) joined.complete();
      if (m['t'] == 'error') errors.add('${m['msg']}');
    });
    c.states.listen((v) {
      if (v.phase == 'scored' && lastPhase != 'scored') scored++;
      lastPhase = v.phase;
    });
    await tester.runAsync(() async {
      c.connect();
      c.create('Testeur');
    });
    // les écouteurs vivent dans la zone de test : ils ne tournent qu'aux pump()
    for (var i = 0; i < 100 && (!joined.isCompleted || c.last == null); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(c.seat, 0);

    await tester.pumpWidget(MaterialApp(
        locale: const Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OnlineGameScreen(client: c)));
    expect(find.text(l.shareCode(c.code!)), findsOneWidget);

    var idle = 0, cards = 0;
    var sawLastTrick = false, sawScore = false;
    while (scored < 2) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)));
      // l'horloge du test avance aussi : animations (distribution, ramassage)
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull);
      for (final e in find.byType(Text).evaluate()) {
        final s = (e.widget as Text).data ?? '';
        // aucun texte latin hors noms de jeu / joueurs / code de table
        final rest = s
            .replaceAll(RegExp(r'Partner Close Caps|AI|Testeur'), '')
            .replaceAll(c.code!, '');
        if (RegExp(r'[A-Za-z]{3,}').hasMatch(rest)) leaks.add(s);
      }
      expect(errors, isEmpty, reason: 'erreur renvoyée par le serveur');

      final v = c.last!;
      if (v.phase == 'scored' && v.lastScore != null) {
        // le résultat de la donne s'affiche (calculé par le moteur serveur)
        if (find.byKey(const ValueKey('score-card')).evaluate().isNotEmpty) {
          sawScore = true;
        }
      }
      if (v.phase == 'play' &&
          v.currentTrick.isEmpty &&
          (v.lastTrick?.length ?? 0) >= 3) {
        sawLastTrick = true;
      }

      final playable = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('play-'));
      final buttons = find.descendant(
          of: find.byType(Wrap),
          matching: find.byWidgetPredicate(
              (w) => w is FilledButton || w is OutlinedButton));
      final cut = find.byKey(const ValueKey('cut-indicator'));
      if (cut.evaluate().isNotEmpty && rnd.nextBool()) {
        await tester.tap(cut); // coupe à l'atout posé (validée par le serveur)
        cards++;
      } else if (playable.evaluate().isNotEmpty) {
        await tester.tap(playable.at(rnd.nextInt(playable.evaluate().length)),
            warnIfMissed: false);
        cards++;
      } else if (buttons.evaluate().isNotEmpty) {
        final passe = find.descendant(of: buttons, matching: find.text(l.pass));
        await tester.tap(passe.evaluate().isNotEmpty && rnd.nextBool()
            ? passe.first
            : buttons.at(rnd.nextInt(buttons.evaluate().length)));
      } else {
        if (++idle > 400) fail('blocage (phase ${v.phase}, tour ${v.turn})');
        continue;
      }
      idle = 0;
      // laisse le temps au serveur de répondre avant le prochain geste
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(leaks, isEmpty, reason: 'textes non traduits en $lang');
    expect(cards, greaterThan(4), reason: 'des cartes jouées depuis l\'UI');
    expect(sawLastTrick, isTrue, reason: 'dernier pli affiché entre 2 plis');
    expect(sawScore, isTrue, reason: 'résultat de la donne affiché');

    // coupure réseau en pleine partie : bandeau, puis reconnexion automatique
    c.debugDropConnection();
    var sawOffline = false, back = false;
    for (var i = 0; i < 100 && !back; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      final offline = find.byKey(const ValueKey('offline'));
      if (offline.evaluate().isNotEmpty) sawOffline = true;
      if (sawOffline && offline.evaluate().isEmpty) back = true;
    }
    expect(sawOffline, isTrue, reason: 'bandeau de reconnexion affiché');
    expect(back, isTrue, reason: 'reconnecté automatiquement');

    // chat : message envoyé depuis l'écran, relayé par le serveur, affiché
    await tester.tap(find.byKey(const ValueKey('chat-open')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('chat-input')), 'vanakkam');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    var shown = false;
    for (var i = 0; i < 50 && !shown; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      shown = find
          .textContaining('vanakkam', findRichText: true)
          .evaluate()
          .isNotEmpty;
    }
    expect(shown, isTrue, reason: 'message de chat affiché');
    Navigator.of(tester.element(find.byKey(const ValueKey('chat-input'))))
        .pop();
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox()); // dispose -> ferme la socket
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
