import 'dart:async';

import 'package:game304/settings.dart';

/// Configuration commune à tous les tests : son coupé (pas de lecteur audio
/// natif dans l'environnement de test).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  sound.value = 'off';
  await testMain();
}
