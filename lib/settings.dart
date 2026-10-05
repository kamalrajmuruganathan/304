import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Vitesse des bots (multiplicateur des délais, comme `SPEED` du prototype) :
/// 1.6 = lente, 1 = normale, 0.5 = rapide. Mémorisée sous `speed304`.
final ValueNotifier<double> botSpeed = ValueNotifier<double>(1);
const kSpeeds = <double>[1.6, 1, 0.5];
const _kSpeedPref = 'speed304';

/// Statistiques des donnes jouées en solo (comme `stats304` du prototype).
final ValueNotifier<({int played, int won, int lost})> stats =
    ValueNotifier((played: 0, won: 0, lost: 0));
const _kStatsPref = 'stats304';

Future<void> loadSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble(_kSpeedPref);
    if (v != null && kSpeeds.contains(v)) botSpeed.value = v;
    final raw = prefs.getString(_kStatsPref);
    if (raw != null) {
      final m = jsonDecode(raw) as Map;
      stats.value = (
        played: (m['played'] as num?)?.toInt() ?? 0,
        won: (m['won'] as num?)?.toInt() ?? 0,
        lost: (m['lost'] as num?)?.toInt() ?? 0,
      );
    }
  } catch (_) {
    // préférences indisponibles : vitesse normale
  }
}

Future<void> setBotSpeed(double v) async {
  botSpeed.value = v;
  try {
    await (await SharedPreferences.getInstance()).setDouble(_kSpeedPref, v);
  } catch (_) {}
}

/// Délai d'animation des bots ajusté à la vitesse choisie.
Duration botDelay(int ms) =>
    Duration(milliseconds: (ms * botSpeed.value).round());

/// Compte une donne terminée (gagnée par l'équipe du joueur ou non).
Future<void> recordDeal({required bool won}) async {
  final s = stats.value;
  stats.value = (
    played: s.played + 1,
    won: s.won + (won ? 1 : 0),
    lost: s.lost + (won ? 0 : 1),
  );
  try {
    await (await SharedPreferences.getInstance()).setString(
        _kStatsPref,
        jsonEncode({
          'played': stats.value.played,
          'won': stats.value.won,
          'lost': stats.value.lost,
        }));
  } catch (_) {}
}
