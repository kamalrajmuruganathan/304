import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Vitesse des bots (multiplicateur des délais, comme `SPEED` du prototype) :
/// 1.6 = lente, 1 = normale, 0.5 = rapide. Mémorisée sous `speed304`.
final ValueNotifier<double> botSpeed = ValueNotifier<double>(1);
const kSpeeds = <double>[1.6, 1, 0.5];
const _kSpeedPref = 'speed304';

Future<void> loadSettings() async {
  try {
    final v = (await SharedPreferences.getInstance()).getDouble(_kSpeedPref);
    if (v != null && kSpeeds.contains(v)) botSpeed.value = v;
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
