// ============================================================================
// IA « difficile » (partie solo, adversaires Est/Ouest) — Monte-Carlo.
// Avant chaque carte, le bot imagine [kHardSamples] répartitions possibles des
// cartes qu'il n'a pas vues (en respectant ce qu'il sait : nombre de cartes de
// chacun, couleurs où un joueur n'a pas fourni, atout s'il le connaît), puis,
// pour chaque carte jouable, joue la fin de la donne avec l'IA normale et garde
// la carte qui rapporte le plus de jetons en moyenne. Il ne triche pas : il ne
// lit jamais les mains des autres ni un atout caché.
// Les enchères restent celles de l'IA normale. Mesure : tool/hard_sim.dart.
// ============================================================================
import 'dart:math';

import '../engine/engine.dart';
import 'bots.dart';

/// Nombre de répartitions imaginées par décision (compromis force / vitesse).
const int kHardSamples = 24;

/// Carte (ou [PlayIndicator]) choisie par l'IA difficile pour [seat].
Object botPlayHard(Engine e, int seat,
    {Random? rng, int samples = kHardSamples}) {
  // après une annonce Caps : l'ordre sûr de l'IA normale
  if (e.capsCall?.seat == seat) return botPlay(e, seat);
  final options = <Object>[
    ...e.playableCards(seat),
    if (e.canCutWithIndicator(seat)) const PlayIndicator(),
  ];
  if (options.length <= 1) return botPlay(e, seat);
  final r = rng ?? Random();
  final team = teamOf(seat);
  final total = List<double>.filled(options.length, 0);
  var worlds = 0;
  Engine? first;
  for (var k = 0; k < samples; k++) {
    final w = sampleWorld(e, seat, r);
    if (w == null) continue;
    worlds++;
    first ??= w;
    for (var i = 0; i < options.length; i++) {
      total[i] += _rollout(w, seat, options[i], team);
    }
  }
  if (worlds == 0) return botPlay(e, seat);
  // à égalité, la carte de l'IA normale (stable, déjà bien réglée), calculée
  // sur une répartition imaginée : l'IA normale lit l'atout même caché
  final normal = botPlay(first!, seat);
  var best = options.indexWhere((o) => _same(o, normal));
  if (best < 0) best = 0;
  for (var i = 0; i < options.length; i++) {
    if (total[i] > total[best] + 1e-9) best = i;
  }
  return options[best];
}

bool _same(Object a, Object b) {
  if (a is PlayIndicator || b is PlayIndicator) {
    return a is PlayIndicator && b is PlayIndicator;
  }
  return (a as Card).key == (b as Card).key;
}

/// Joue [first] pour [seat] puis termine la donne avec l'IA normale ; renvoie
/// le gain de l'équipe [team] (jetons, départagés par les points de cartes).
double _rollout(Engine world, int seat, Object first, String team) {
  final e = world.copy()..tokens = {'NS': 11, 'EW': 11};
  if (first is PlayIndicator) {
    e.playIndicatorToCut(seat);
  } else {
    e.playCard(seat, first as Card);
  }
  var guard = 0;
  while (e.phase == 'play' && ++guard < 64) {
    final s = e.turn;
    if (e.hands[s].isEmpty && s == e.trumpMaker && e.indicatorOnTable) {
      e.playLastIndicator(s);
      continue;
    }
    if (e.hands[s].isEmpty) break; // ne devrait pas arriver
    if (botCallCaps(e, s)) e.callCaps(s);
    final c = botPlay(e, s);
    if (c is PlayIndicator) {
      e.playIndicatorToCut(s);
    } else {
      e.playCard(s, c as Card);
    }
  }
  final delta = e.tokens[team]! - 11;
  final pts = team == 'NS' ? e.pointsNS : e.pointsEW;
  return delta * 100.0 + pts;
}

/// Une répartition possible des cartes que [seat] n'a pas vues, compatible
/// avec ce qu'il sait. Renvoie une copie de la partie, ou null si le tirage
/// échoue (contraintes trop serrées après plusieurs essais).
Engine? sampleWorld(Engine e, int seat, Random r) {
  final trumpKnown = e.trumpOpen || seat == e.trumpMaker;
  // --- ce que [seat] connaît ---
  final known = <String>{...e.seen};
  for (final c in e.hands[seat]) {
    known.add(c.key);
  }
  if (seat == e.trumpMaker && e.indicatorOnTable && e.indicator != null) {
    known.add(e.indicator!.key);
  }
  for (final t in e.tricks) {
    for (final p in t['cards'] as List<TrickPlay>) {
      if (p.seat == seat) known.add(p.card.key);
    }
  }
  bool hiddenNow(TrickPlay p) => p.faceDown && !e.trumpOpen && p.seat != seat;
  for (final p in e.currentTrick) {
    if (!hiddenNow(p)) known.add(p.card.key);
  }

  // --- couleurs manquantes (le joueur n'a pas fourni) ---
  final voids = [<String>{}, <String>{}, <String>{}, <String>{}];
  void noteVoids(List<TrickPlay> plays, String? led) {
    if (led == null) return;
    for (var i = 1; i < plays.length; i++) {
      final p = plays[i];
      if (p.isIndicator && !p.faceDown) continue; // dernière carte imposée
      final visible = !p.faceDown || known.contains(p.card.key);
      if (p.faceDown || (visible && p.card.suit != led)) voids[p.seat].add(led);
    }
  }

  for (final t in e.tricks) {
    noteVoids(t['cards'] as List<TrickPlay>, t['ledSuit'] as String?);
  }
  noteVoids(e.currentTrick, e.ledSuit);

  // --- cases à remplir : cartes cachées déjà jouées, atout posé, mains ---
  final slots = <({String? notSuit, bool notTrump})>[];
  for (final t in e.tricks) {
    final revealed = t['revealed'] == true;
    for (final p in t['cards'] as List<TrickPlay>) {
      if (p.faceDown && p.seat != seat && !known.contains(p.card.key)) {
        // pli resté fermé : une carte cachée n'était pas de l'atout
        slots.add((notSuit: t['ledSuit'] as String?, notTrump: !revealed));
      }
    }
  }
  final hiddenCurrent = <int>[]; // indices du pli en cours à remplacer
  for (var i = 0; i < e.currentTrick.length; i++) {
    if (hiddenNow(e.currentTrick[i])) hiddenCurrent.add(i);
  }
  final needIndicator =
      e.indicatorOnTable && e.indicator != null && seat != e.trumpMaker;

  final pool = buildDeck().where((c) => !known.contains(c.key)).toList();
  var need = slots.length + hiddenCurrent.length + (needIndicator ? 1 : 0);
  for (var p = 0; p < 4; p++) {
    if (p != seat) need += e.hands[p].length;
  }
  if (need != pool.length) return null; // incohérence : on ne devine pas

  for (var attempt = 0; attempt < 40; attempt++) {
    final left = List.of(pool)..shuffle(r);
    Card? take(bool Function(Card) ok) {
      final i = left.indexWhere(ok);
      return i < 0 ? null : left.removeAt(i);
    }

    // l'atout : connu, sinon déduit de l'atout posé imaginé
    String? trump = trumpKnown ? e.trumpSuit : null;
    Card? indicator = needIndicator ? null : e.indicator;
    if (needIndicator) {
      indicator =
          trump == null ? take((_) => true) : take((c) => c.suit == trump);
      if (indicator == null) continue;
      trump ??= indicator.suit;
    }
    // atout posé coupé face cachée dans le pli en cours : c'est de l'atout
    Card? cutCard;
    final cutIdx =
        hiddenCurrent.where((i) => e.currentTrick[i].isIndicator).firstOrNull;
    if (cutIdx != null) {
      cutCard =
          trump == null ? take((_) => true) : take((c) => c.suit == trump);
      if (cutCard == null) continue;
      trump ??= cutCard.suit;
    }
    trump ??= e.trumpSuit; // ne devrait pas arriver

    var fail = false;
    for (final s in slots) {
      final c = take((c) =>
          c.suit != s.notSuit &&
          !(s.notTrump && trump != null && c.suit == trump));
      if (c == null) {
        fail = true;
        break;
      }
    }
    if (fail) continue;
    final current = List<TrickPlay>.of(e.currentTrick);
    for (final i in hiddenCurrent) {
      final p = current[i];
      final c = i == cutIdx ? cutCard : take((c) => c.suit != e.ledSuit);
      if (c == null) {
        fail = true;
        break;
      }
      current[i] =
          TrickPlay(p.seat, c, faceDown: true, isIndicator: p.isIndicator);
    }
    if (fail) continue;
    // mains : les plus contraints d'abord
    final order = [
      for (var p = 0; p < 4; p++)
        if (p != seat) p
    ]..sort((a, b) => voids[b].length - voids[a].length);
    final hands = [for (final h in e.hands) List.of(h)];
    for (final p in order) {
      final h = <Card>[];
      for (var n = 0; n < e.hands[p].length; n++) {
        final c = take((c) => !voids[p].contains(c.suit));
        if (c == null) {
          fail = true;
          break;
        }
        h.add(c);
      }
      if (fail) break;
      sortHand(h);
      hands[p] = h;
    }
    if (fail) continue;
    final w = e.copy()
      ..hands = hands
      ..currentTrick = current
      ..indicator = indicator
      ..trumpSuit = trump;
    return w;
  }
  return null;
}
