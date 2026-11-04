// ============================================================================
// Tournoi contre les bots : 3 matchs à élimination directe, adversaires de plus
// en plus forts (quart : Facile, demi : Normal, finale : Difficile).
// Un match = 6 donnes (jetons de départ 11-11, barème habituel) ; l'équipe qui
// a le plus de jetons gagne. Égalité après 6 donnes : donnes en plus jusqu'à
// ce qu'une équipe mène. Une équipe à 0 jeton perd tout de suite.
// Les règles du jeu ne changent pas : seule la durée du match est raccourcie.
// État mémorisé (`tour304`) : on reprend le match là où il en était (au début
// de la donne interrompue, comme la partie solo).
// ============================================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Niveau des adversaires à chaque tour.
const kTourLevels = ['easy', 'normal', 'hard'];
const kTourDeals = 6;
const _kPref = 'tour304';

@immutable
class TourState {
  final int round; // 0 quart, 1 demi, 2 finale
  final int deal; // donnes jouées dans le match
  final int ns, ew; // jetons du match
  final int dealer;
  final int titles; // tournois gagnés (gardé d'un tournoi à l'autre)
  const TourState(
      {this.round = 0,
      this.deal = 0,
      this.ns = 11,
      this.ew = 11,
      this.dealer = 0,
      this.titles = 0});

  String get level => kTourLevels[round];

  /// Match terminé ? (0 jeton, ou 6 donnes et une équipe devant)
  bool get matchOver => ns <= 0 || ew <= 0 || (deal >= kTourDeals && ns != ew);
  bool get matchWon => matchOver && ns > ew;

  /// Donne en plus (égalité après 6 donnes).
  bool get extra => deal >= kTourDeals;

  /// Au début : rien à reprendre.
  bool get fresh => round == 0 && deal == 0;

  /// Après une donne : nouveaux jetons et donneur.
  TourState afterDeal(int ns, int ew, int dealer) => TourState(
      round: round,
      deal: deal + 1,
      ns: ns,
      ew: ew,
      dealer: dealer,
      titles: titles);

  /// Match gagné : tour suivant ; finale gagnée : titre + nouveau tournoi.
  TourState next() => round >= kTourLevels.length - 1
      ? TourState(titles: titles + 1)
      : TourState(round: round + 1, dealer: dealer, titles: titles);

  /// Match perdu : nouveau tournoi (les titres restent).
  TourState restart() => TourState(titles: titles);

  Map<String, int> toJson() => {
        'round': round,
        'deal': deal,
        'ns': ns,
        'ew': ew,
        'dealer': dealer,
        'titles': titles
      };
  static TourState fromJson(Map m) {
    int g(String k, int d) => (m[k] as num?)?.toInt() ?? d;
    return TourState(
      round: g('round', 0).clamp(0, kTourLevels.length - 1),
      deal: g('deal', 0).clamp(0, 99),
      ns: g('ns', 11).clamp(0, 22),
      ew: g('ew', 11).clamp(0, 22),
      dealer: g('dealer', 0) & 3,
      titles: g('titles', 0).clamp(0, 1 << 20),
    );
  }
}

final ValueNotifier<TourState> tour = ValueNotifier(const TourState());

Future<void> loadTour() async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString(_kPref);
    if (raw != null) tour.value = TourState.fromJson(jsonDecode(raw) as Map);
  } catch (_) {}
}

Future<void> saveTour(TourState s) async {
  tour.value = s;
  try {
    await (await SharedPreferences.getInstance())
        .setString(_kPref, jsonEncode(s.toJson()));
  } catch (_) {}
}
