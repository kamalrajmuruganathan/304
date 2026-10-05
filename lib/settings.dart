import 'dart:convert';

import 'package:flutter/material.dart';
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

/// Apparence (comme `back304` / `felt304` du prototype).
final ValueNotifier<String> cardBack = ValueNotifier<String>('royal');
final ValueNotifier<String> felt = ValueNotifier<String>('green');
const kBacks = ['royal', 'classic', 'dark'];
const kFelts = ['green', 'blue', 'violet'];

/// Couleurs du tapis (centre, bord), reprises du CSS du prototype.
const kFeltColors = <String, (Color, Color)>{
  'green': (Color(0xFF0F5A3C), Color(0xFF063421)),
  'blue': (Color(0xFF155A7A), Color(0xFF082A3D)),
  'violet': (Color(0xFF4A2A6A), Color(0xFF241338)),
};

(Color, Color) get feltColors =>
    kFeltColors[felt.value] ?? kFeltColors['green']!;

/// Décor du dos des cartes : royal (dégradé or), classique (rayures bleues),
/// sombre (rayures anthracite) — reprises du CSS du prototype.
BoxDecoration cardBackDecoration({double radius = 7}) {
  switch (cardBack.value) {
    case 'classic':
      return BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFF0D1117)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment(-0.8, -0.8),
          colors: [
            Color(0xFF1F6FEB),
            Color(0xFF1F6FEB),
            Color(0xFF144FB0),
            Color(0xFF144FB0)
          ],
          stops: [0, 0.5, 0.5, 1],
          tileMode: TileMode.repeated,
        ),
      );
    case 'dark':
      return BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x66E3C565)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment(-0.8, -0.8),
          colors: [
            Color(0xFF2B2B33),
            Color(0xFF2B2B33),
            Color(0xFF17171C),
            Color(0xFF17171C)
          ],
          stops: [0, 0.5, 0.5, 1],
          tileMode: TileMode.repeated,
        ),
      );
    default:
      return BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8A6A2E), Color(0xFF6B5122)]),
        border: Border.all(color: const Color(0xFF4A370F)),
      );
  }
}

Future<void> setCardBack(String v) async {
  cardBack.value = v;
  try {
    await (await SharedPreferences.getInstance()).setString('back304', v);
  } catch (_) {}
}

Future<void> setFelt(String v) async {
  felt.value = v;
  try {
    await (await SharedPreferences.getInstance()).setString('felt304', v);
  } catch (_) {}
}

Future<void> loadSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final b = prefs.getString('back304');
    if (b != null && kBacks.contains(b)) cardBack.value = b;
    final f = prefs.getString('felt304');
    if (f != null && kFelts.contains(f)) felt.value = f;
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
