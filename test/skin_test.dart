// ============================================================================
// Thèmes (comme Thaayam) : choix mémorisé, accueil et donnes jouées dans
// chacun des 4 thèmes sur petit écran, sans débordement ni exception.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:game304/main.dart';
import 'package:game304/ui/skin.dart';

import 'ui_solo_test.dart' show playSolo;

void main() {
  testWidgets('accueil : choix du thème mémorisé, Cristal par défaut',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    skinCode.value = kDefaultSkin;
    addTearDown(() => skinCode.value = kDefaultSkin);
    t.view.physicalSize = const Size(360, 640) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(const Game304App(locale: Locale('fr')));
    expect(skinCode.value, 'cristal');
    for (final code in ['temple', 'nuit', 'bois', 'cristal']) {
      await t.ensureVisible(find.byKey(ValueKey('skin-$code')));
      await t.tap(find.byKey(ValueKey('skin-$code')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(skinCode.value, code);
      // le fond de l'accueil suit le thème
      final app = t.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme!.scaffoldBackgroundColor, skinOf(code).bg);
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme304'), 'cristal');
    // relu au démarrage ; une valeur inconnue est ignorée
    SharedPreferences.setMockInitialValues({'theme304': 'nuit'});
    await loadSkin();
    expect(skinCode.value, 'nuit');
    SharedPreferences.setMockInitialValues({'theme304': 'licorne'});
    skinCode.value = kDefaultSkin;
    await loadSkin();
    expect(skinCode.value, kDefaultSkin);
  });

  for (final code in kSkins) {
    testWidgets('thème $code : 4 donnes jouées sur 360×640', (t) async {
      skinCode.value = code;
      addTearDown(() => skinCode.value = kDefaultSkin);
      expect(
          await playSolo(t, size: const Size(360, 640), deals: 4, seed: 1),
          4);
    });
  }
}
