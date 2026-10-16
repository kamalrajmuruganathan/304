// ============================================================================
// Tests du moteur 304 — équivalents Dart des simulations JS validées.
// Lancer :  flutter test    (ou : dart test)
// ============================================================================
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:game304/engine/engine.dart';
import 'package:game304/ai/bots.dart';

/// Déroule une donne complète, tous sièges pilotés par l'IA.
/// [forcePCC] : si non nul, ce siège annonce Partner Close Caps quand il peut.
/// [cutRnd] : si non nul, le preneur coupe aussi avec l'atout posé au hasard
/// chaque fois que c'est permis (comme un joueur humain via le bouton) ;
/// [cuts] compte les coupes à l'atout posé.
/// Renvoie 'allpass', 'pcc' ou 'normal'.
int cuts = 0;
String fullHand(Engine e, {int? forcePCC, Random? cutRnd}) {
  e.newHand();
  var rc = 0;
  while (e.canRedeal() && rc < 8) {
    e.redeal();
    rc++;
  }
  e.startBidding1();
  while (e.phase == 'bid1') {
    e.placeBid(botBid(e, e.bidTurn));
    if (e.phase == 'allpass') return 'allpass';
  }
  e.chooseTrump1(botChooseTrump(e, e.trumpMaker1!));

  while (e.phase == 'bid2') {
    final s = e.bid2Turn;
    Object? v;
    if (forcePCC != null && s == forcePCC && e.canPCC()) {
      v = 'PCC';
    } else {
      v = botBid2(e, s);
    }
    e.placeBid2(v);
  }

  if (e.phase == 'chooseTrumpPCC') {
    e.chooseTrumpPCC(botChooseTrump(e, e.trumpMaker!));
  } else if (e.phase == 'chooseTrump2') {
    e.chooseTrump2(botChooseTrump(e, e.trumpMaker!));
  } else if (e.phase == 'preplay') {
    e.startPlayClosed();
  }
  if (e.phase == 'preplay') e.startPlayClosed();

  // total des cartes en jeu = 32 au démarrage du jeu
  final tot = e.hands.fold<int>(0, (a, h) => a + h.length) +
      (e.indicatorOnTable ? 1 : 0);
  expect(tot, 32, reason: 'total cartes en jeu');

  final muted = e.soloMode ? e.mutedSeat : -1;
  var guard = 0;
  while (e.tricks.length < 8) {
    if (++guard > 200) fail('boucle de jeu');
    final s = e.turn;
    expect(s == muted, isFalse, reason: 'le siège écarté ne doit pas jouer');
    if (e.hands[s].isEmpty && s == e.trumpMaker && e.indicatorOnTable) {
      e.playLastIndicator(s);
    } else {
      if (botCallCaps(e, s)) e.callCaps(s);
      final c = botPlay(e, s);
      if (c is PlayIndicator) {
        expect(e.canCutWithIndicator(s), isTrue,
            reason: 'l\'IA ne coupe à l\'atout posé que si c\'est permis');
      }
      if (c is PlayIndicator ||
          (cutRnd != null && e.canCutWithIndicator(s) && cutRnd.nextBool())) {
        cuts++;
        e.playIndicatorToCut(s);
      } else {
        e.playCard(s, c as Card);
      }
    }
  }

  expect(e.trickWinsNS + e.trickWinsEW, 8, reason: 'nombre de plis');
  if (e.soloMode) {
    expect(e.hands[muted!].length, 8, reason: 'écarté garde ses 8 cartes');
    expect(e.trumpOpen, isTrue, reason: 'PCC : atout révélé');
    return 'pcc';
  } else {
    expect(e.pointsNS + e.pointsEW, 304, reason: 'somme des points = 304');
    return 'normal';
  }
}

void main() {
  levelTests();
  capsTests();
  test('Coupe à l\'atout posé (bouton du joueur) : 300 parties, invariants',
      () {
    final rnd = Random(304);
    cuts = 0;
    var hands = 0;
    for (var g = 0; g < 300; g++) {
      final e = Engine(seed: 1000 + g);
      var safety = 0;
      while (e.tokens['NS']! > 0 && e.tokens['EW']! > 0) {
        if (++safety > 1000) fail('partie sans fin');
        if (fullHand(e, cutRnd: rnd) != 'allpass') hands++;
        expect(e.tokens['NS']! + e.tokens['EW']!, 22, reason: 'somme jetons');
      }
    }
    expect(hands, greaterThan(0));
    expect(cuts, greaterThan(50), reason: 'des coupes ont eu lieu');
  });

  test('canCutWithIndicator : seulement le preneur, à son tour, jeu fermé', () {
    var checked = 0;
    for (var g = 0; g < 100; g++) {
      final e = Engine(seed: g);
      if (!fullHandUntilPlay(e)) continue;
      checked++;
      for (var s = 0; s < 4; s++) {
        if (s != e.turn || s != e.trumpMaker) {
          expect(e.canCutWithIndicator(s), isFalse);
        }
      }
      // entame : impossible de couper sur un pli vide
      expect(e.canCutWithIndicator(e.turn), isFalse);
      expect(e.snapshot(forSeat: e.turn)['canCut'], isFalse);
    }
    expect(checked, greaterThan(0));
  });

  test('Régression : 300 parties complètes, invariants respectés', () {
    var hands = 0, allpass = 0;
    for (var g = 0; g < 300; g++) {
      final e = Engine(seed: g);
      var safety = 0;
      while (e.tokens['NS']! > 0 && e.tokens['EW']! > 0) {
        if (++safety > 1000) fail('partie sans fin');
        final r = fullHand(e);
        hands++;
        if (r == 'allpass') {
          allpass++;
          continue;
        }
        expect(e.tokens['NS']! + e.tokens['EW']!, 22, reason: 'somme jetons');
      }
    }
    expect(hands, greaterThan(0));
    expect(allpass, lessThan(hands), reason: 'pas que des allpass');
  });

  test('Partner Close Caps : jeu solo valide + barème ±4/±5', () {
    var pccPlayed = 0;
    for (var it = 0; it < 6000 && pccPlayed < 500; it++) {
      final e = Engine(seed: 100000 + it);
      final forced = it % 4;
      final before = e.tokens['NS']! + 0; // copie
      final beforeNS = e.tokens['NS']!;
      final beforeEW = e.tokens['EW']!;
      final r = fullHand(e, forcePCC: forced);
      if (r != 'pcc') continue;
      pccPlayed++;
      expect(e.tokens['NS']! + e.tokens['EW']!, 22, reason: 'somme jetons');
      // hors cas de clamp en fin de partie, le transfert vaut exactement 4 ou 5
      final deltaNS = (e.tokens['NS']! - beforeNS).abs();
      final noClamp = beforeNS >= 5 && beforeNS <= 17; // marge pour ±5
      if (noClamp) {
        expect(deltaNS == 4 || deltaNS == 5, isTrue,
            reason:
                'transfert PCC doit être 4 (réussi) ou 5 (raté), vu: $deltaNS');
      }
      before;
      beforeEW; // (évite warnings unused)
    }
    expect(pccPlayed, greaterThan(0), reason: 'au moins une donne PCC jouée');
  });
}

/// Amène une donne jusqu'au début du jeu des plis (false si tout le monde passe).
bool fullHandUntilPlay(Engine e) {
  e.newHand();
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
  return e.phase == 'play';
}

/// Partie complète où Est/Ouest jouent au niveau « facile » (botPlayLevel).
/// Renvoie true si Nord-Sud (IA normale) gagne.
bool gameVsEasy(int seed, Random rng) {
  final e = Engine(seed: seed);
  var guard = 0;
  while (e.tokens['NS']! > 0 && e.tokens['EW']! > 0) {
    if (++guard > 2000) fail('partie sans fin');
    if (!fullHandUntilPlay(e)) continue;
    while (e.phase == 'play') {
      final s = e.turn;
      if (e.hands[s].isEmpty && s == e.trumpMaker && e.indicatorOnTable) {
        e.playLastIndicator(s);
        continue;
      }
      final c = botPlayLevel(e, s, easy: s.isOdd, rng: rng);
      if (c is PlayIndicator) {
        expect(e.canCutWithIndicator(s), isTrue);
        e.playIndicatorToCut(s);
      } else {
        expect(e.playableCards(s).any((x) => x.key == (c as Card).key), isTrue,
            reason: 'carte légale');
        e.playCard(s, c as Card);
      }
    }
    expect(e.tokens['NS']! + e.tokens['EW']!, 22, reason: 'somme jetons');
  }
  return e.tokens['EW']! <= 0;
}

void levelTests() {
  test('Niveau facile : coups légaux, adversaires nettement plus faibles', () {
    final rng = Random(304);
    var won = 0;
    const games = 300;
    for (var g = 0; g < games; g++) {
      if (gameVsEasy(70000 + g, rng)) won++;
    }
    // mesuré (tool/level_sim.dart, 1000 parties) : 89 % ; à niveau égal : 50 %
    expect(won / games, greaterThan(0.75),
        reason: 'Nord-Sud gagne ${100 * won ~/ games} % des parties');
  });
}

/// Position de jeu construite : [seat] entame le pli n° [played] (son équipe
/// a gagné les précédents), atout [trump] ouvert ou non, mains imposées.
Engine capsPosition(
    {required List<List<String>> hands,
    String trump = 'S',
    bool open = true,
    int trumpMaker = 0,
    int seat = 0,
    List<String> seenCards = const []}) {
  Card c(String k) => Card(k[0], k.substring(1));
  final e = Engine(seed: 1)
    ..phase = 'play'
    ..trumpSuit = trump
    ..trumpOpen = open
    ..trumpMaker = trumpMaker
    ..bid = 160
    ..indicatorOnTable = false
    ..hands = [for (final h in hands) h.map(c).toList()]
    ..leader = seat
    ..turn = seat
    ..seen = seenCards.toSet();
  return e;
}

void capsTests() {
  test('Caps certain : atouts maîtres + cartes maîtres, sinon non', () {
    // Sud : J 9 de pique (atout), A ♥ ; il reste 6 atouts plus faibles
    // chez les autres -> 2 tours d'atout ne suffisent pas à les faire tomber
    var e = capsPosition(hands: [
      ['SJ', 'S9', 'HA'],
      ['SA', 'S10', 'CK'],
      ['SK', 'SQ', 'C7'],
      ['S8', 'S7', 'D7'],
    ]);
    expect(e.capsCertain(0), isFalse, reason: 'atouts adverses restants');
    // tous les atouts restants sont à Sud (les autres ont été vus) -> certain
    e = capsPosition(hands: [
      ['SJ', 'S9', 'HA', 'HJ'],
      ['CK', 'C8', 'D8', 'D7'],
      ['CQ', 'C7', 'DQ', 'DK'],
      ['C9', 'CJ', 'H7', 'H8'],
    ], seenCards: [
      'SA', 'S10', 'SK', 'SQ', 'S8', 'S7', 'H9', 'HQ', 'HK', 'H10', //
      'CA', 'C10', 'DJ', 'D9', 'DA', 'D10'
    ]);
    expect(e.capsCertain(0), isTrue);
    // même main, mais un cœur plus fort (le 9) n'a pas été vu -> pas certain
    e = capsPosition(hands: [
      ['SJ', 'S9', 'HA', 'HJ'],
      ['CK', 'C8', 'D8', 'D7'],
      ['CQ', 'C7', 'DQ', 'DK'],
      ['C9', 'CJ', 'H7', 'H9'],
    ], seenCards: [
      'SA', 'S10', 'SK', 'SQ', 'S8', 'S7', 'H8', 'HQ', 'HK', 'H10', //
      'CA', 'C10', 'DJ', 'D9', 'DA', 'D10'
    ]);
    expect(e.capsCertain(0), isFalse, reason: 'le 9 de cœur bat l\'as');
    // atout caché et Sud n'est pas le preneur : il ne peut pas savoir
    e = capsPosition(trumpMaker: 1, open: false, hands: [
      ['SJ', 'S9', 'HA', 'HJ'],
      ['CK', 'C8', 'D8', 'D7'],
      ['CQ', 'C7', 'DQ', 'DK'],
      ['C9', 'CJ', 'H7', 'H8'],
    ], seenCards: [
      'SA', 'S10', 'SK', 'SQ', 'S8', 'S7', 'H9', 'HQ', 'HK', 'H10', //
      'CA', 'C10', 'DJ', 'D9', 'DA', 'D10'
    ]);
    expect(e.capsCertain(0), isFalse);
    expect(e.canCallCaps(0), isTrue, reason: 'annoncer reste possible');
  });

  /// Parties complètes ; le siège 0 suit la politique [caps0] pour Caps.
  ({int calls, int good, int wrong, int missed}) capsGames(
      String caps0, int games) {
    var calls = 0, good = 0, wrong = 0, missed = 0;
    for (var g = 0; g < games; g++) {
      final e = Engine(seed: 90000 + g);
      var guard = 0;
      while (e.tokens['NS']! > 0 && e.tokens['EW']! > 0) {
        if (++guard > 2000) fail('partie sans fin');
        if (!fullHandUntilPlay(e)) continue;
        final before = Map.of(e.tokens);
        Map<String, dynamic>? r;
        while (e.phase == 'play') {
          final s = e.turn;
          final call = s == 0 && caps0 != 'bot'
              ? caps0 == 'eager' && e.canCallCaps(s)
              : botCallCaps(e, s);
          if (call) {
            expect(e.callCaps(s), isTrue);
            calls++;
          }
          if (e.hands[s].isEmpty && s == e.trumpMaker && e.indicatorOnTable) {
            r = e.playLastIndicator(s);
            continue;
          }
          final c = botPlay(e, s);
          r = c is PlayIndicator
              ? e.playIndicatorToCut(s)
              : e.playCard(s, c as Card);
        }
        if (e.phase != 'scored') continue; // atout gâché
        final sc = r!['score'] as Map;
        expect(e.tokens['NS']! + e.tokens['EW']!, 22);
        if (sc['capsTeam'] != null) good++;
        if (sc['wrongCaps'] != null) {
          wrong++;
          if (e.capsCall == null) missed++;
        }
        // jamais de bonus Caps sans les 8 plis
        if (sc['capsTeam'] == 'NS') expect(e.trickWinsNS, 8);
        if (sc['capsTeam'] == 'EW') expect(e.trickWinsEW, 8);
        before;
      }
    }
    return (calls: calls, good: good, wrong: wrong, missed: missed);
  }

  test('Caps : bots parfaits = jamais de Wrong Caps ; bonus seulement à 8 plis',
      () {
    final r = capsGames('bot', 300);
    expect(r.calls, greaterThan(0));
    expect(r.good, r.calls, reason: 'chaque annonce de bot est juste');
    expect(r.wrong, 0);
  });

  test('Wrong Caps : occasion manquée ou annonce trop tôt = pénalité', () {
    final never = capsGames('never', 300);
    expect(never.missed, greaterThan(0), reason: 'Sud oublie d\'annoncer');
    final eager = capsGames('eager', 100);
    expect(eager.wrong, greaterThan(eager.good),
        reason: 'annonces sans certitude pénalisées');
  });
}
