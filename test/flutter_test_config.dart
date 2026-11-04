import 'dart:async';

import 'package:game304/settings.dart';
import 'package:game304/ui/skin.dart';

/// Configuration commune à tous les tests : son coupé (pas de lecteur audio
/// natif dans l'environnement de test) et décor immobile (les animations en
/// boucle empêcheraient `pumpAndSettle` de finir).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  sound.value = 'off';
  skinMotion.value = false;
  await testMain();
}
