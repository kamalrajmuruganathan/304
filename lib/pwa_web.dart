// Web : fonctions JavaScript définies dans web/index.html.
import 'dart:js_interop';

@JS('pwaCanInstall')
external JSBoolean? _canInstall();

@JS('pwaStandalone')
external JSBoolean? _standalone();

@JS('pwaInstall')
external JSPromise<JSBoolean?>? _install();

bool canInstall() {
  try {
    return _canInstall()?.toDart ?? false;
  } catch (_) {
    return false; // page servie sans index.html du projet
  }
}

bool standalone() {
  try {
    return _standalone()?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

Future<bool> install() async {
  try {
    final p = _install();
    if (p == null) return false;
    return (await p.toDart)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}
