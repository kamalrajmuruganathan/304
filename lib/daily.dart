// ============================================================================
// Donne du jour : la même donne pour tout le monde, chaque jour (date UTC).
// Le mélange vient d'un générateur simple (xorshift32) dont le résultat est
// identique sur téléphone et sur le web (Random(graine) de Dart n'en donne
// pas la garantie). Le premier essai terminé du jour est le score officiel ;
// les suivants sont de l'entraînement.
// ============================================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/daily_random.dart';
export 'engine/daily_random.dart';

/// Résultat officiel de la donne du jour (1er essai terminé).
class DailyResult {
  final String day;
  final int delta; // jetons gagnés (+) ou perdus (−) par votre équipe
  final int points; // points de cartes de votre équipe
  const DailyResult(this.day, this.delta, this.points);

  Map<String, Object> toJson() =>
      {'day': day, 'delta': delta, 'points': points};
  static DailyResult fromJson(Map m) => DailyResult(m['day'] as String,
      (m['delta'] as num).toInt(), (m['points'] as num).toInt());
}

/// État mémorisé (`daily304`) : dernier résultat officiel, essai commencé
/// aujourd'hui, série de jours consécutifs.
class DailyState {
  final DailyResult? last;
  final String? started; // jour du dernier essai officiel commencé
  final int streak; // jours consécutifs joués
  const DailyState({this.last, this.started, this.streak = 0});

  /// Score officiel d'aujourd'hui (null : pas encore joué).
  DailyResult? today([DateTime? now]) =>
      last != null && last!.day == dayKey(now) ? last : null;

  /// Un nouvel essai aujourd'hui compte-t-il ? (pas de score ni d'essai
  /// officiel commencé aujourd'hui : quitter puis rejouer ne compte pas)
  bool officialNow([DateTime? now]) =>
      today(now) == null && started != dayKey(now);

  Map<String, Object?> toJson() =>
      {'last': last?.toJson(), 'started': started, 'streak': streak};
  static DailyState fromJson(Map m) => DailyState(
        last: m['last'] == null ? null : DailyResult.fromJson(m['last'] as Map),
        started: m['started'] as String?,
        streak: (m['streak'] as num?)?.toInt() ?? 0,
      );
}

final ValueNotifier<DailyState> daily = ValueNotifier(const DailyState());
const _kDailyPref = 'daily304';

Future<void> loadDaily() async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString(_kDailyPref);
    if (raw != null) daily.value = DailyState.fromJson(jsonDecode(raw) as Map);
  } catch (_) {}
}

Future<void> _save() async {
  try {
    await (await SharedPreferences.getInstance())
        .setString(_kDailyPref, jsonEncode(daily.value.toJson()));
  } catch (_) {}
}

/// Début d'un essai : renvoie true s'il est officiel (et le note).
Future<bool> startDaily([DateTime? now]) async {
  final s = daily.value;
  if (!s.officialNow(now)) return false;
  daily.value =
      DailyState(last: s.last, started: dayKey(now), streak: s.streak);
  await _save();
  return true;
}

/// Fin d'un essai officiel : mémorise le score et met à jour la série.
Future<void> finishDaily(int delta, int points, [DateTime? now]) async {
  final s = daily.value;
  final day = dayKey(now);
  final yesterday =
      dayKey((now ?? DateTime.now()).toUtc().subtract(const Duration(days: 1)));
  final streak = s.last?.day == yesterday ? s.streak + 1 : 1;
  daily.value = DailyState(
      last: DailyResult(day, delta, points), started: day, streak: streak);
  await _save();
}
