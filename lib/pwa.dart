// ============================================================================
// Appli web installable (écran d'accueil du téléphone ou de l'ordinateur) :
// bouton « Installer l'appli » de l'accueil. Le navigateur fournit
// l'invitation (Chrome, Edge, Android) ; sur iPhone, il faut passer par
// « Partager → Sur l'écran d'accueil ». Hors web : rien.
// ============================================================================
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pwa_stub.dart' if (dart.library.js_interop) 'pwa_web.dart' as impl;

/// L'invitation à installer est disponible (bouton affiché).
final ValueNotifier<bool> pwaInstallable = ValueNotifier(false);

/// iPhone / iPad dans Safari, appli pas encore installée : on explique.
bool get pwaIosHint =>
    kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && !impl.standalone();

Timer? _poll;

/// Surveille l'invitation du navigateur (elle arrive après le chargement).
void watchPwa() {
  if (!kIsWeb || _poll != null) return;
  var n = 0;
  _poll = Timer.periodic(const Duration(seconds: 1), (t) {
    pwaInstallable.value = !impl.standalone() && impl.canInstall();
    if (++n >= 120) t.cancel();
  });
}

/// Ouvre l'invitation du navigateur ; true si le joueur a accepté.
Future<bool> installPwa() async {
  final ok = await impl.install();
  pwaInstallable.value = false;
  return ok;
}
