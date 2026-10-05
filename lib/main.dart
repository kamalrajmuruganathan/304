import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';
import 'ui/game_screen.dart';
import 'ui/online_screen.dart';
import 'ui/tutorial_screen.dart';

/// Langue choisie par le joueur (null = langue de l'appareil, repli anglais).
final ValueNotifier<Locale?> appLocale = ValueNotifier<Locale?>(null);
const _kLangPref = 'lang304'; // même nom que dans le prototype

/// Langues proposées, chacune écrite dans sa propre langue.
const kLanguages = <String, String>{
  'fr': 'Français',
  'en': 'English',
  'ta': 'தமிழ்',
  'si': 'සිංහල',
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final code = (await SharedPreferences.getInstance()).getString(_kLangPref);
    if (code != null && kLanguages.containsKey(code)) {
      appLocale.value = Locale(code);
    }
  } catch (_) {
    // préférences indisponibles : langue de l'appareil
  }
  await loadSettings();
  runApp(const Game304App());
}

Future<void> setAppLanguage(String code) async {
  appLocale.value = Locale(code);
  try {
    await (await SharedPreferences.getInstance()).setString(_kLangPref, code);
  } catch (_) {}
}

class Game304App extends StatelessWidget {
  /// [locale] force une langue (tests) ; sinon choix du joueur ou appareil.
  const Game304App({super.key, this.locale});
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      // symboles des couleurs fournis par la police embarquée
      fontFamilyFallback: const ['Suits'],
    );
    return ValueListenableBuilder<Locale?>(
      valueListenable: appLocale,
      builder: (context, chosen, _) => MaterialApp(
        onGenerateTitle: (ctx) => AppLocalizations.of(ctx)!.appTitle,
        debugShowCheckedModeBanner: false,
        locale: locale ?? chosen,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // langue de l'appareil si elle est proposée, sinon anglais
        localeResolutionCallback: (device, supported) => supported.firstWhere(
            (s) => s.languageCode == device?.languageCode,
            orElse: () => const Locale('en')),
        theme: base.copyWith(
          scaffoldBackgroundColor: const Color(0xFF0D1117),
          colorScheme: base.colorScheme.copyWith(
            primary: const Color(0xFF2F81F7),
            onPrimary: Colors.white, // texte lisible sur les boutons pleins
            secondary: const Color(0xFFD4A72C),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final current = Localizations.localeOf(context).languageCode;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('304',
                    style: TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFD4A72C))),
                const SizedBox(height: 4),
                Text('three-nought-four',
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                ValueListenableBuilder(
                  valueListenable: stats,
                  builder: (context, st, _) => st.played == 0
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(l.statsLine(st.played, st.won, st.lost),
                              key: const ValueKey('stats'),
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 13)),
                        ),
                ),
                const SizedBox(height: 40),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GameScreen())),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                    child: Text(l.quickPlay, textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const OnlineLobbyScreen())),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                    child: Text(l.privateTableFriends,
                        textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TutorialScreen())),
                  child: Text('📖 ${l.learn304}'),
                ),
                const SizedBox(height: 24),
                Text(l.language,
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final e in kLanguages.entries)
                      ChoiceChip(
                        key: ValueKey('lang-${e.key}'),
                        label: Text(e.value),
                        selected: current == e.key,
                        onSelected: (_) => setAppLanguage(e.key),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(l.speed,
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                const SizedBox(height: 8),
                ValueListenableBuilder<double>(
                  valueListenable: botSpeed,
                  builder: (context, speed, _) => Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final (v, label) in [
                        (1.6, l.slow),
                        (1.0, l.normal),
                        (0.5, l.fast),
                      ])
                        ChoiceChip(
                          key: ValueKey('speed-$v'),
                          label: Text(label),
                          selected: speed == v,
                          onSelected: (_) => setBotSpeed(v),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
