// Statistiques détaillées (settings.dart) et écran Statistiques.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game304/l10n/app_localizations.dart';
import 'package:game304/settings.dart';
import 'package:game304/ui/stats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget home, String lang) => MaterialApp(
    locale: Locale(lang),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home);

void main() {
  setUp(() {
    // préférences simulées (pas de plugin natif dans les tests)
    SharedPreferences.setMockInitialValues({});
    stats.value = const Stats();
  });
  tearDown(() => stats.value = const Stats());

  test('recordDeal : paliers, Caps, séries, parties', () async {
    // prise du joueur à 170 réussie avec Caps
    await recordDeal(
        won: true,
        takerIsMe: true,
        score: {'tmTeam': 'NS', 'bid': 170, 'success': true, 'caps': true});
    // prise du joueur à 220 ratée
    await recordDeal(
        won: false,
        takerIsMe: true,
        score: {'tmTeam': 'NS', 'bid': 220, 'success': false, 'caps': false});
    // prise d'un adversaire à 250 ratée : gagnée par nous, fin de partie
    await recordDeal(
        won: true,
        score: {'tmTeam': 'EW', 'bid': 250, 'success': false, 'caps': false},
        gameWinner: 'NS');
    // PCC du joueur réussie (comptée comme Caps)
    await recordDeal(won: true, takerIsMe: true, score: {
      'tmTeam': 'NS',
      'pcc': true,
      'bid': 'Partner Close Caps',
      'success': true,
      'caps': true
    });
    final s = stats.value;
    expect((s.played, s.won, s.lost), (4, 3, 1));
    expect(s.taken, {'lt200': 1, 'lt250': 1, 'pcc': 1});
    expect(s.made, {'lt200': 1, 'pcc': 1});
    expect(s.takenTotal, 3);
    expect(s.madeTotal, 2);
    expect(s.caps, 2);
    expect((s.gamesWon, s.gamesLost), (1, 0));
    expect((s.streak, s.bestStreak), (2, 2));
    // aller-retour JSON
    final back = Stats.fromJson(s.toJson());
    expect(back.toJson(), s.toJson());
  });

  test('ancien format stats304 (played/won/lost) relu sans perte', () {
    final s = Stats.fromJson({'played': 5, 'won': 3, 'lost': 2});
    expect((s.played, s.won, s.lost), (5, 3, 2));
    expect(s.takenTotal, 0);
  });

  testWidgets('écran Statistiques en tamoul : traduit, remise à zéro',
      (t) async {
    await t.runAsync(() => recordDeal(
        won: true,
        takerIsMe: true,
        score: {'tmTeam': 'NS', 'bid': 160, 'success': true, 'caps': false}));
    await t.pumpWidget(app(const StatsScreen(), 'ta'));
    await t.pumpAndSettle();
    final latinOk = RegExp(r'Partner Close Caps|Caps');
    for (final e in find.byType(Text).evaluate()) {
      final s = (e.widget as Text).data ?? '';
      expect(
          RegExp(r'[A-Za-z]{3,}').hasMatch(s.replaceAll(latinOk, '')), isFalse,
          reason: 'texte latin en tamoul : $s');
    }
    expect(find.byKey(const ValueKey('tier-lt200')), findsOneWidget);
    expect(find.textContaining('100 %'), findsWidgets);
    await t.ensureVisible(find.byKey(const ValueKey('reset-stats')));
    await t.tap(find.byKey(const ValueKey('reset-stats')));
    await t.pumpAndSettle();
    expect(stats.value.played, 0);
    expect(find.byKey(const ValueKey('no-stats')), findsOneWidget);
  });
}
