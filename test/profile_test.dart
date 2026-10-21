// ============================================================================
// Profil (prénom + avatar) et dos de cartes / tapis à débloquer.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:game304/l10n/app_localizations.dart';
import 'package:game304/main.dart';
import 'package:game304/settings.dart';

void main() {
  test('prénom nettoyé (une ligne, 16 caractères)', () {
    expect(cleanName('  Kamal \n  Raj  '), 'Kamal Raj');
    expect(cleanName('x' * 30).length, kMaxName);
    // caractères tamouls composés : coupés entre deux lettres, jamais dedans
    final ta = cleanName('கமல்ராஜ் முருகநாதன் கமல்ராஜ்');
    expect(ta.characters.length, lessThanOrEqualTo(kMaxName));
  });

  test('déverrouillage par parties gagnées', () {
    expect(winsToUnlock('back', 'royal', 0), 0);
    expect(winsToUnlock('back', 'emerald', 0), 1);
    expect(winsToUnlock('back', 'emerald', 1), 0);
    expect(winsToUnlock('felt', 'sand', 5), 7);
    expect(newlyUnlocked(0, 1), ['back:emerald']);
    expect(newlyUnlocked(2, 3), ['back:ruby']);
    expect(newlyUnlocked(3, 4), isEmpty);
    // chaque objet verrouillé a un décor
    for (final k in kUnlockWins.keys) {
      final id = k.split(':')[1];
      expect(k.startsWith('back') ? kBacks.contains(id) : kFelts.contains(id),
          isTrue,
          reason: k);
    }
  });

  testWidgets('accueil : profil enregistré, cadenas puis déverrouillage',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    stats.value = const Stats();
    cardBack.value = 'royal';
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final l = lookupAppLocalizations(const Locale('fr'));
    await t.pumpWidget(const Game304App(locale: Locale('fr')));

    // profil : prénom + avatar, mémorisés
    await t.tap(find.byKey(const ValueKey('profile')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('profile-name')), '  Kamal  ');
    await t.tap(find.byKey(const ValueKey('avatar-3')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('profile-save')));
    await t.pumpAndSettle();
    expect(find.text('Kamal'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('name304'), 'Kamal');
    expect(prefs.getInt('avatar304'), 3);

    // dos « Émeraude » verrouillé (0 partie gagnée) : non sélectionnable
    final emerald = find.byKey(const ValueKey('back-emerald'));
    await t.ensureVisible(emerald);
    await t.pumpAndSettle();
    expect(t.widget<ChoiceChip>(emerald).onSelected, isNull);
    expect(find.descendant(of: emerald, matching: find.byIcon(Icons.lock)),
        findsOneWidget);
    expect(find.byTooltip(l.unlockHint(1)), findsOneWidget);

    // une partie gagnée : il se débloque et se choisit
    stats.value = const Stats(gamesWon: 1);
    await t.pump();
    expect(t.widget<ChoiceChip>(emerald).onSelected, isNotNull);
    await t.tap(emerald);
    await t.pump();
    expect(cardBack.value, 'emerald');
    expect(prefs.getString('back304'), 'emerald');
    // toujours verrouillé : « Rubis » (3 parties)
    expect(
        t.widget<ChoiceChip>(find.byKey(const ValueKey('back-ruby'))).onSelected,
        isNull);
    stats.value = const Stats();
    cardBack.value = 'royal';
    playerName.value = '';
    avatar.value = 0;
  });

  test('préférence d\'un objet encore verrouillé : repli sur le défaut',
      () async {
    SharedPreferences.setMockInitialValues(
        {'back304': 'peacock', 'felt304': 'crimson', 'stats304': '{"gamesWon":2}'});
    await loadSettings();
    expect(cardBack.value, 'royal', reason: 'Paon : 8 parties');
    expect(felt.value, 'crimson', reason: 'Bordeaux : 2 parties, débloqué');
    cardBack.value = 'royal';
    felt.value = 'green';
    stats.value = const Stats();
  });
}
