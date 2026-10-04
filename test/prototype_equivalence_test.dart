// ============================================================================
// Test différentiel : moteur + IA Dart  ==  prototype JS validé.
//
// test/fixtures/prototype_trace.json.gz est produit par
// tools/diff-test/trace.js à partir de prototype/304.html (Math.random remplacé
// par mulberry32). Ici, le même générateur est injecté dans Engine(rng: …) et
// les mêmes donnes sont rejouées : distribution, enchères, atouts, chaque
// carte jouée, chaque pli, les scores et le journal doivent être identiques.
// ============================================================================
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:game304/ai/bots.dart';
import 'package:game304/engine/engine.dart';

/// mulberry32 — port exact de la version JS (arithmétique 32 bits non signée).
class Mulberry32 implements Random {
  int _a;
  Mulberry32(int seed) : _a = seed & _m;
  static const _m = 0xFFFFFFFF;
  static int _imul(int x, int y) => (x * y) & _m;

  @override
  double nextDouble() {
    _a = (_a + 0x6D2B79F5) & _m;
    var t = _imul(_a ^ (_a >> 15), 1 | _a);
    t = ((t + _imul(t ^ (t >> 7), 61 | t)) & _m) ^ t;
    return ((t ^ (t >> 14)) & _m) / 4294967296;
  }

  // identique à Math.floor(Math.random() * max) côté JS
  @override
  int nextInt(int max) => (nextDouble() * max).floor();

  @override
  bool nextBool() => nextDouble() < 0.5;
}

int fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

String k(Card c) => '${c.suit}${c.rank}';

/// Même pilotage que fullHand() dans tools/diff-test/trace.js.
void fullHand(Engine e, List<String> tr, String mode, int? forcePCC) {
  e.newHand();
  var rc = 0;
  while (e.canRedeal() && rc < 8) {
    e.redeal();
    rc++;
    tr.add('redeal');
  }
  tr.add(
      'deal ${e.dealer} ${e.hands.map((h) => h.map(k).join(',')).join('|')}');
  e.startBidding1();
  while (e.phase == 'bid1') {
    final s = e.bidTurn;
    final v = botBid(e, s);
    tr.add('bid1 $s $v');
    e.placeBid(v);
    if (e.phase == 'allpass') {
      tr.add('allpass');
      return;
    }
  }
  final c1 = botChooseTrump(e, e.trumpMaker1!);
  tr.add('trump1 ${e.trumpMaker1} ${k(c1)}');
  e.chooseTrump1(c1);
  while (e.phase == 'bid2') {
    final s = e.bid2Turn;
    final Object? v = (forcePCC != null && s == forcePCC && e.canPCC())
        ? 'PCC'
        : botBid2(e, s);
    tr.add('bid2 $s $v');
    e.placeBid2(v);
  }
  if (e.phase == 'chooseTrumpPCC' || e.phase == 'chooseTrump2') {
    final c = botChooseTrump(e, e.trumpMaker!);
    tr.add('${e.phase} ${e.trumpMaker} ${k(c)}');
    e.phase == 'chooseTrumpPCC' ? e.chooseTrumpPCC(c) : e.chooseTrump2(c);
  }
  if (e.phase == 'preplay') {
    mode == 'open' ? e.startPlayOpen() : e.startPlayClosed();
  }
  tr.add('play ${e.phase} bid=${e.bid} tm=${e.trumpMaker} trump=${e.trumpSuit} '
      'open=${e.trumpOpen} pcc=${e.pcc}');
  if (e.phase == 'spoilt') return;
  var guard = 0;
  while (e.tricks.length < 8 && guard++ < 200) {
    final s = e.turn;
    Map<String, dynamic> r;
    if (e.hands[s].isEmpty && s == e.trumpMaker && e.indicatorOnTable) {
      tr.add('lastInd $s');
      r = e.playLastIndicator(s);
    } else {
      final ch = botPlay(e, s);
      if (ch is PlayIndicator) {
        tr.add('ind $s');
        r = e.playIndicatorToCut(s);
      } else {
        final c = ch as Card;
        tr.add('card $s ${k(c)}');
        r = e.playCard(s, c);
      }
    }
    if (r['trickDone'] == true) {
      tr.add('trick ${r['winner']} ${r['points']} ${r['revealed'] == true} '
          'open=${e.trumpOpen}');
    }
  }
  tr.add('score NS=${e.pointsNS} EW=${e.pointsEW} '
      'tricks=${e.trickWinsNS}/${e.trickWinsEW} '
      'tokens=${e.tokens['NS']}/${e.tokens['EW']} dealer=${e.dealer}');
}

void main() {
  final data = jsonDecode(utf8.decode(gzip.decode(
          File('test/fixtures/prototype_trace.json.gz').readAsBytesSync())))
      as Map<String, dynamic>;
  final games = (data['games'] as List).cast<Map<String, dynamic>>();

  test('les ${games.length} parties de référence sont présentes', () {
    expect(games, isNotEmpty);
  });

  for (final g in games) {
    final seed = g['seed'] as int;
    test('partie graine $seed identique au prototype', () {
      final expected = (g['trace'] as List).cast<String>();
      final log = <String>[];
      final e = Engine(rng: Mulberry32(seed))..onLog = log.add;
      final tr = <String>[];
      var n = 0;
      while (e.tokens['NS']! > 0 && e.tokens['EW']! > 0 && n < 60) {
        final mode = n % 3 == 0 ? 'open' : 'closed';
        final forcePCC = (seed - 1000) % 4 == 0 && n % 5 == 2 ? n % 4 : null;
        tr.add('# hand $n $mode pcc=$forcePCC');
        fullHand(e, tr, mode, forcePCC);
        n++;
      }
      // première divergence, avec contexte, pour un diagnostic lisible
      final len = min(tr.length, expected.length);
      for (var i = 0; i < len; i++) {
        if (tr[i] != expected[i]) {
          final from = max(0, i - 6);
          fail('divergence ligne $i\n'
              '  prototype : ${expected[i]}\n'
              '  dart      : ${tr[i]}\n'
              'contexte prototype :\n  ${expected.sublist(from, i + 1).join('\n  ')}');
        }
      }
      expect(tr.length, expected.length, reason: 'longueur de trace');
      expect(log.length, g['logCount'], reason: 'nombre de lignes du journal');
      expect(fnv1a(log.join('\n')), g['logHash'], reason: 'texte du journal');
    });
  }
}
