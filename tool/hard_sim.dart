// Mesure du niveau « difficile » : mêmes donnes jouées deux fois, Est-Ouest
// avec l'IA normale puis avec l'IA difficile (Nord-Sud toujours normal).
// Affiche le gain moyen d'Est-Ouest par donne (jetons) dans les deux cas et
// l'écart apparié avec son intervalle de confiance à 95 %.
// Lancer : dart run tool/hard_sim.dart [donnes] [échantillons] [parties]
// ignore_for_file: avoid_print

import 'dart:math';

import 'package:game304/ai/bots.dart';
import 'package:game304/ai/hard.dart';
import 'package:game304/engine/engine.dart';

/// Joue une donne complète ; [hard] : Est-Ouest jouent avec l'IA difficile.
/// Renvoie false si tout le monde a passé.
bool playHand(Engine e, {required bool hard, required int samples, Random? r}) {
  e.newHand();
  var rc = 0;
  while (e.canRedeal() && rc < 8) {
    e.redeal();
    rc++;
  }
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
  while (e.phase == 'play') {
    final s = e.turn;
    if (e.hands[s].isEmpty && s == e.trumpMaker && e.indicatorOnTable) {
      e.playLastIndicator(s);
      continue;
    }
    if (botCallCaps(e, s)) e.callCaps(s);
    final c = hard && s.isOdd
        ? botPlayHard(e, s, rng: r, samples: samples)
        : botPlay(e, s);
    if (c is PlayIndicator) {
      e.playIndicatorToCut(s);
    } else {
      e.playCard(s, c as Card);
    }
  }
  return true;
}

void main(List<String> args) {
  final deals = args.isNotEmpty ? int.parse(args[0]) : 400;
  final samples = args.length > 1 ? int.parse(args[1]) : kHardSamples;
  final games = args.length > 2 ? int.parse(args[2]) : 0;
  final sw = Stopwatch()..start();
  final diffs = <int>[];
  var sumN = 0, sumH = 0;
  for (var d = 0; d < deals; d++) {
    int run(bool hard) {
      final e = Engine(seed: 90000 + d)..tokens = {'NS': 11, 'EW': 11};
      if (!playHand(e, hard: hard, samples: samples, r: Random(d))) return 0;
      return e.tokens['EW']! - 11;
    }

    final n = run(false), h = run(true);
    sumN += n;
    sumH += h;
    diffs.add(h - n);
  }
  final mean = diffs.fold(0, (a, b) => a + b) / deals;
  final varc =
      diffs.fold(0.0, (a, b) => a + (b - mean) * (b - mean)) / (deals - 1);
  final ci = 1.96 * sqrt(varc / deals);
  final changed = diffs.where((x) => x != 0).length;
  print('$deals donnes, $samples échantillons, ${sw.elapsed.inSeconds} s');
  print(
      'Est-Ouest normal    : ${(sumN / deals).toStringAsFixed(3)} jeton/donne');
  print(
      'Est-Ouest difficile : ${(sumH / deals).toStringAsFixed(3)} jeton/donne');
  print('écart apparié : ${mean.toStringAsFixed(3)} ± ${ci.toStringAsFixed(3)} '
      '($changed donnes au résultat différent)');

  if (games > 0) {
    // parties complètes : Nord-Sud normal contre Est-Ouest difficile
    var ewWins = 0;
    for (var g = 0; g < games; g++) {
      final e = Engine(seed: 70000 + g);
      final r = Random(g);
      var guard = 0;
      while (e.tokens['NS']! > 0 && e.tokens['EW']! > 0 && ++guard < 500) {
        playHand(e, hard: true, samples: samples, r: r);
      }
      if (e.tokens['NS']! <= 0) ewWins++;
    }
    print('parties : Est-Ouest difficile gagne '
        '${(100 * ewWins / games).toStringAsFixed(1)} % ($games parties, '
        '${sw.elapsed.inSeconds} s au total)');
  }
}
