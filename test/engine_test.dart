// ============================================================================
// Tests du moteur 304 — équivalents Dart des simulations JS validées.
// Lancer :  flutter test    (ou : dart test)
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:game304/engine/engine.dart';
import 'package:game304/ai/bots.dart';

/// Déroule une donne complète, tous sièges pilotés par l'IA.
/// [forcePCC] : si non nul, ce siège annonce Partner Close Caps quand il peut.
/// Renvoie 'allpass', 'pcc' ou 'normal'.
String fullHand(Engine e, {int? forcePCC}) {
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
      final c = botPlay(e, s);
      if (c is PlayIndicator) {
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
            reason: 'transfert PCC doit être 4 (réussi) ou 5 (raté), vu: $deltaNS');
      }
      before; beforeEW; // (évite warnings unused)
    }
    expect(pccPlayed, greaterThan(0), reason: 'au moins une donne PCC jouée');
  });
}
