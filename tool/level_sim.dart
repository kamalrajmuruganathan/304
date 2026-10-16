// Mesure de la difficulté « facile » : Nord-Sud joue avec l'IA normale,
// Est-Ouest avec des erreurs au hasard (probabilité `slip`). Affiche la part
// de parties gagnées par Nord-Sud (50 % attendu à slip = 0).
// Lancer : dart run tool/level_sim.dart [parties] [slip1 slip2 …]
// ignore_for_file: avoid_print

import 'dart:math';

import 'package:game304/ai/bots.dart';
import 'package:game304/engine/engine.dart';

void playHand(Engine e, double slip, Random rng) {
  e.newHand();
  var rc = 0;
  while (e.canRedeal() && rc < 8) {
    e.redeal();
    rc++;
  }
  e.startBidding1();
  while (e.phase == 'bid1') {
    e.placeBid(botBid(e, e.bidTurn));
    if (e.phase == 'allpass') return;
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
  while (e.phase == 'play') {
    final s = e.turn;
    if (e.hands[s].isEmpty && s == e.trumpMaker && e.indicatorOnTable) {
      e.playLastIndicator(s);
      continue;
    }
    if (botCallCaps(e, s)) e.callCaps(s);
    Object c = botPlay(e, s);
    if (s.isOdd && rng.nextDouble() < slip) {
      final legal = e.playableCards(s);
      if (legal.isNotEmpty) c = legal[rng.nextInt(legal.length)];
    }
    if (c is PlayIndicator) {
      e.playIndicatorToCut(s);
    } else {
      e.playCard(s, c as Card);
    }
  }
}

void main(List<String> args) {
  final games = args.isEmpty ? 1000 : int.parse(args[0]);
  final slips = args.length > 1
      ? args.skip(1).map(double.parse).toList()
      : [0.0, 0.25, 0.5, 0.75, 1.0];
  for (final slip in slips) {
    final rng = Random(7);
    var won = 0, deals = 0;
    for (var g = 0; g < games; g++) {
      final e = Engine(seed: 50000 + g);
      var guard = 0;
      while (e.tokens['NS']! > 0 && e.tokens['EW']! > 0 && ++guard < 2000) {
        playHand(e, slip, rng);
        deals++;
      }
      if (e.tokens['EW']! <= 0) won++;
    }
    print('slip ${slip.toStringAsFixed(2)} : NS gagne '
        '${(100 * won / games).toStringAsFixed(1)} % des parties '
        '(${(deals / games).toStringAsFixed(1)} donnes/partie)');
  }
}
