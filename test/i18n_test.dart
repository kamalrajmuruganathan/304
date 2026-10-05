// ============================================================================
// Traductions : cohérence des 4 fichiers ARB, aucun texte français resté en
// dur quand l'app est en anglais / tamoul / cingalais (donnes jouées via
// l'interface), mise en page sans débordement dans chaque langue, et
// sélecteur de langue de l'accueil.
// ============================================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game304/l10n/app_localizations.dart';
import 'package:game304/main.dart';
import 'package:game304/settings.dart';

import 'ui_solo_test.dart' show playSolo;

/// Mots/expressions qui ne doivent apparaître qu'en français.
final french = RegExp(
    r"\b(Vous|Nous|Eux|Passe|Enchère|Atout|atout|Plis|Donne|preneur|partenaire|"
    r"écarté|réfléchit|Redistribuer|Garder|Jeu fermé|Jeu ouvert|Objectif|"
    r"Jetons|Rejouer|joue…|Partie)\b|À vous");

/// Textes latins autorisés dans les langues non latines.
final latinOk = RegExp(r'Partner Close Caps|Caps|PCC|AI|three-nought-four');

Map<String, dynamic> arb(String l) =>
    jsonDecode(File('lib/l10n/app_$l.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  const langs = ['en', 'fr', 'ta', 'si'];

  test('les 4 ARB ont les mêmes clés et les mêmes repères', () {
    Set<String> keys(Map<String, dynamic> m) =>
        m.keys.where((k) => !k.startsWith('@')).toSet();
    final ref = arb('en');
    for (final l in langs) {
      final m = arb(l);
      expect(keys(m), keys(ref), reason: 'clés de app_$l.arb');
      for (final k in keys(ref)) {
        Set<String> ph(String s) =>
            RegExp(r'\{(\w+)\}').allMatches(s).map((x) => x[1]!).toSet();
        expect(ph(m[k] as String), ph(ref[k] as String),
            reason: 'repères de $k en $l');
        expect((m[k] as String).trim(), isNotEmpty, reason: '$k vide en $l');
      }
    }
  });

  for (final lang in ['en', 'ta', 'si']) {
    testWidgets('solo en $lang : 6 donnes, aucun texte français', (t) async {
      final leaks = <String>{};
      await playSolo(t,
          size: const Size(360, 640),
          deals: 6,
          seed: 11,
          lang: lang, onTexts: (texts) {
        for (final s in texts) {
          if (french.hasMatch(s)) leaks.add(s);
          if (lang != 'en' &&
              RegExp(r'[A-Za-z]{3,}').hasMatch(s.replaceAll(latinOk, ''))) {
            leaks.add(s);
          }
        }
      });
      expect(leaks, isEmpty, reason: 'textes non traduits en $lang');
    });
  }

  testWidgets('accueil : vitesse des bots', (t) async {
    addTearDown(() => botSpeed.value = 1);
    await t.pumpWidget(const Game304App(locale: Locale('fr')));
    await t.tap(find.byKey(const ValueKey('speed-0.5')));
    await t.pumpAndSettle();
    expect(botSpeed.value, 0.5);
    expect(botDelay(600), const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('speed-1.6')));
    await t.pumpAndSettle();
    expect(botDelay(600), const Duration(milliseconds: 960));
  });

  testWidgets('accueil : le sélecteur change la langue', (t) async {
    addTearDown(() => appLocale.value = null);
    await t.pumpWidget(const Game304App());
    for (final lang in ['ta', 'si', 'fr', 'en']) {
      await t.tap(find.byKey(ValueKey('lang-$lang')));
      await t.pumpAndSettle();
      expect(find.text(lookupAppLocalizations(Locale(lang)).quickPlay),
          findsOneWidget,
          reason: 'accueil en $lang');
    }
  });
}
