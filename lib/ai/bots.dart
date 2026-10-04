// ============================================================================
// IA des bots — port fidèle du prototype JS. Heuristiques volontairement
// simples et lisibles ; c'est le premier chantier à renforcer (voir roadmap).
// ============================================================================
import '../engine/engine.dart';

/// Estimation des points que réalisera l'équipe à partir des 4 premières cartes.
/// Modèle calibré sur 40 000 donnes simulées : la STRUCTURE (Valet/9 d'atout,
/// longueur, Valets à côté) compte bien plus que le total de points.
double est4(List<Card> h) {
  final bySuit = <String, List<Card>>{};
  for (final c in h) {
    bySuit.putIfAbsent(c.suit, () => []).add(c);
  }
  String? best;
  var bs = -1;
  for (final en in bySuit.entries) {
    final sc =
        en.value.fold<int>(0, (a, c) => a + c.points) + en.value.length * 2;
    if (sc > bs) {
      bs = sc;
      best = en.key;
    }
  }
  final tr = bySuit[best]!;
  final pts = h.fold<int>(0, (a, c) => a + c.points);
  return 124.8 +
      0.09 * pts +
      13.6 * tr.length +
      26.7 * (tr.any((c) => c.rank == 'J') ? 1 : 0) +
      9.2 * (tr.any((c) => c.rank == '9') ? 1 : 0) +
      20.7 * h.where((c) => c.rank == 'J' && c.suit != best).length;
}

/// 1er tour d'enchères (sur 4 cartes). Renvoie l'enchère, ou null pour passer.
/// Seuils retenus par duel : 97 % de victoires contre l'ancienne IA d'enchères.
int? botBid(Engine e, int seat) {
  final legal = e.legalBids();
  if (legal.isEmpty) return null;
  final est = est4(e.hands[seat]);
  var target = est >= 210
      ? 190
      : est >= 195
          ? 180
          : est >= 185
              ? 170
              : est >= 160
                  ? 160
                  : 0;
  if (target == 0) return null;
  final partnerLeads =
      e.highBidder != null && teamOf(e.highBidder!) == teamOf(seat);
  if (partnerLeads) target = est >= 230 ? 200 : 0;
  final opts = legal.where((b) => b <= target).toList();
  return opts.isEmpty ? null : opts.last;
}

/// 2e tour (sur 8 cartes). Renvoie un int, la chaîne 'PCC', ou null (passe).
Object? botBid2(Engine e, int seat) {
  final legal = e.legalBids2();
  final canPcc = e.canPCC();
  final h = e.hands[seat];
  final bySuit = <String, List<Card>>{};
  for (final c in h) {
    bySuit.putIfAbsent(c.suit, () => []).add(c);
  }
  var bestLen = 0;
  var bestSuit = 'S';
  for (final s in kSuits) {
    final arr = bySuit[s] ?? const [];
    if (arr.length > bestLen) {
      bestLen = arr.length;
      bestSuit = s;
    }
  }
  final tr = bySuit[bestSuit] ?? const [];
  final hasJ = tr.any((c) => c.rank == 'J');
  final has9 = tr.any((c) => c.rank == '9');
  final pts = h.fold(0, (a, c) => a + c.points);
  if (canPcc && bestLen >= 7 && hasJ && has9 && pts >= 200) return 'PCC';
  if (legal.isNotEmpty &&
      bestLen >= 5 &&
      hasJ &&
      has9 &&
      pts >= 150 &&
      legal.contains(250)) {
    return 250;
  }
  return null;
}

/// Choix de l'atout : couleur la plus forte, on pose une carte faible dedans.
Card botChooseTrump(Engine e, int seat) {
  final h = e.hands[seat];
  var best = 'S';
  var bestScore = -1;
  for (final s in kSuits) {
    final cards = h.where((c) => c.suit == s).toList();
    final sc = cards.fold(0, (a, c) => a + c.points) + cards.length * 2;
    if (sc > bestScore) {
      bestScore = sc;
      best = s;
    }
  }
  final inSuit = h.where((c) => c.suit == best).toList()
    ..sort((a, b) => kStrength[a.rank]! - kStrength[b.rank]!);
  return inSuit.isNotEmpty ? inSuit.first : h.first;
}

// ---- mémoire : cartes plus fortes de la même couleur encore invisibles ----
int _unseenHigher(Engine e, int seat, Card card) {
  final mine = e.hands[seat].map((c) => c.key).toSet();
  final inTrick = e.currentTrick
      .where((x) => !x.faceDown || e.trumpOpen)
      .map((x) => x.card.key)
      .toSet();
  var n = 0;
  for (final r in kRanks) {
    if (kStrength[r]! > kStrength[card.rank]!) {
      final k = '${card.suit}$r';
      if (!e.seen.contains(k) && !mine.contains(k) && !inTrick.contains(k)) n++;
    }
  }
  return n;
}

bool _isMaster(Engine e, int seat, Card c) => _unseenHigher(e, seat, c) == 0;

int _trumpsOut(Engine e, int seat) {
  final t = e.trumpSuit;
  if (t == null) return 8;
  final seenT = e.seen.where((k) => k.startsWith(t)).length;
  return 8 - seenT - e.hands[seat].where((c) => c.suit == t).length;
}

int _asc(Card a, Card b) => kStrength[a.rank]! - kStrength[b.rank]!;
int _ptsDesc(Card a, Card b) => b.points - a.points;

/// Décision de jeu d'un pli (IA à mémoire). Renvoie une [Card] ou le marqueur
/// [PlayIndicator] (le preneur coupe avec sa carte-atout cachée).
Object botPlay(Engine e, int seat) {
  final legal = e.playableCards(seat);
  final led = e.ledSuit;
  final trump = e.trumpSuit;
  final tk = e.currentTrick;
  final isTM = seat == e.trumpMaker;
  final pot = tk.fold<int>(0, (a, x) => a + x.card.points);
  final last = tk.length == e.trickSize - 1;

  // ---- ENTAME ----
  if (tk.isEmpty) {
    if (isTM && e.trumpOpen && trump != null) {
      final mt = legal
          .where((c) => c.suit == trump && _isMaster(e, seat, c))
          .toList()
        ..sort((a, b) => kStrength[b.rank]! - kStrength[a.rank]!);
      if (mt.isNotEmpty && _trumpsOut(e, seat) > 0) return mt.first;
    }
    final nonTrump = legal.where((c) => c.suit != trump).toList();
    final masters = nonTrump.where((c) => _isMaster(e, seat, c)).toList()
      ..sort(_ptsDesc);
    if (masters.isNotEmpty && masters.first.points > 0) return masters.first;
    final pool = List.of(nonTrump.isNotEmpty ? nonTrump : legal)..sort(_asc);
    return pool.firstWhere((c) => c.points == 0, orElse: () => pool.first);
  }

  // force actuelle du pli (cartes visibles)
  var bestStr = -1;
  int? bestSeat;
  Card? bestCard;
  for (final x in tk) {
    if (!x.faceDown || e.trumpOpen) {
      final st = trickStrength(x.card, trump, led);
      if (st > bestStr) {
        bestStr = st;
        bestSeat = x.seat;
        bestCard = x.card;
      }
    }
  }
  final partnerWinning = bestSeat != null && teamOf(bestSeat) == teamOf(seat);
  final partnerSafe = partnerWinning &&
      (last ||
          (bestCard != null &&
              _isMaster(e, seat, bestCard) &&
              bestCard.suit == led));

  // ---- JE PEUX SUIVRE ----
  if (legal.any((c) => c.suit == led)) {
    final follow = legal.where((c) => c.suit == led).toList()..sort(_asc);
    if (partnerWinning) {
      final riskyClosed = !e.trumpOpen &&
          e.trumpMaker != null &&
          teamOf(e.trumpMaker!) != teamOf(seat) &&
          !last;
      if (partnerSafe && !riskyClosed) {
        return (List.of(follow)..sort(_ptsDesc))
            .first; // on charge le partenaire
      }
      return follow.first;
    }
    final winners =
        follow.where((c) => trickStrength(c, trump, led) > bestStr).toList();
    if (winners.isEmpty) return follow.first;
    if (last) return winners.first; // dernier : plus petite gagnante
    final mw = winners.where((c) => _isMaster(e, seat, c)).toList();
    if (mw.isNotEmpty) return mw.first; // gagnante sûre
    return pot >= 10 ? winners.first : follow.first;
  }

  // ---- JE NE PEUX PAS SUIVRE ----
  if (e.trumpOpen) {
    final trumps = legal.where((c) => c.suit == trump).toList()..sort(_asc);
    final disc = legal.where((c) => c.suit != trump).toList();
    if (partnerWinning) {
      if (partnerSafe && disc.isNotEmpty) {
        return (List.of(disc)..sort(_ptsDesc)).first;
      }
      return disc.isNotEmpty ? (List.of(disc)..sort(_asc)).first : trumps.first;
    }
    final w =
        trumps.where((c) => trickStrength(c, trump, led) > bestStr).toList();
    if (w.isNotEmpty && (pot > 0 || disc.isEmpty)) return w.first;
    return disc.isNotEmpty ? (List.of(disc)..sort(_asc)).first : trumps.first;
  }

  // atout FERMÉ : le preneur connaît l'atout
  if (isTM) {
    final trumps = e.hands[seat].where((c) => c.suit == trump).toList()
      ..sort(_asc);
    if (!partnerWinning && trumps.isNotEmpty && pot >= 10) return trumps.first;
    if (!partnerWinning && e.indicatorOnTable && trumps.isEmpty && pot >= 20) {
      return const PlayIndicator();
    }
    final disc = e.hands[seat].where((c) => c.suit != trump).toList()
      ..sort(_asc);
    return disc.isNotEmpty ? disc.first : e.hands[seat].first;
  }

  // défenseur, atout caché : coupe « devinée » si le pli vaut le coup
  final sorted = List.of(legal)..sort(_asc);
  if (!partnerWinning && pot >= 13) {
    final bySuit = <String, List<Card>>{};
    for (final c in legal) {
      if (c.suit != led) bySuit.putIfAbsent(c.suit, () => []).add(c);
    }
    String? guess;
    var gl = 99;
    for (final en in bySuit.entries) {
      if (en.value.length < gl) {
        gl = en.value.length;
        guess = en.key;
      }
    }
    if (guess != null) return (bySuit[guess]!..sort(_asc)).first;
  }
  return sorted.firstWhere((c) => c.points == 0, orElse: () => sorted.first);
}

/// Marqueur : le preneur coupe en jouant sa carte-atout cachée.
class PlayIndicator {
  const PlayIndicator();
}
