import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/app_localizations.dart';
import 'daily.dart';
import 'pwa.dart';
import 'settings.dart';
import 'ui/game_screen.dart';
import 'ui/online_screen.dart';
import 'ui/profile.dart';
import 'ui/skin.dart';
import 'ui/invite.dart';
import 'ui/stats_screen.dart';
import 'ui/tutorial_screen.dart';

/// Langue choisie par le joueur (null = langue de l'appareil, repli anglais).
final ValueNotifier<Locale?> appLocale = ValueNotifier<Locale?>(null);
const _kLangPref = 'lang304'; // même nom que dans le prototype

/// Langues proposées, chacune écrite dans sa propre langue.
/// Polices embarquées pour les noms de langue (assets/fonts/Lang*.ttf).
const _kLangFont = <String, String>{'ta': 'LangTamil', 'si': 'LangSinhala'};

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
  await loadSkin();
  await loadDaily();
  // appli Android ouverte par un lien d'invitation (game304://table/ABCD)
  String? code;
  if (!kIsWeb) {
    try {
      final link = await AppLinks().getInitialLink();
      if (link != null) code = tableFromUrl(link);
    } catch (_) {}
  }
  runApp(Game304App(inviteCode: code));
}

Future<void> setAppLanguage(String code) async {
  appLocale.value = Locale(code);
  try {
    await (await SharedPreferences.getInstance()).setString(_kLangPref, code);
  } catch (_) {}
}

class Game304App extends StatelessWidget {
  /// [locale] force une langue (tests) ; sinon choix du joueur ou appareil.
  const Game304App({super.key, this.locale, this.inviteCode});
  final Locale? locale;

  /// Code de table d'un lien d'invitation (?table=ABCD) ; par défaut lu dans
  /// l'adresse de la page (web).
  final String? inviteCode;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: skinCode, // thème : toute l'appli suit
      builder: (context, skin, _) => ValueListenableBuilder<Locale?>(
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
          theme: skinTheme(skinOf(skin)),
          home: HomeScreen(
              inviteCode: inviteCode ?? tableFromUrl(),
              openDaily: inviteCode == null && dailyFromUrl()),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.inviteCode, this.openDaily = false});
  final String? inviteCode;

  /// Lien de partage de la donne du jour (`?daily=1`) : on y va directement.
  final bool openDaily;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    watchPwa(); // web : bouton « Installer l'appli » quand c'est possible
    // lien d'invitation reçu pendant que l'appli est déjà ouverte
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        _links = AppLinks().uriLinkStream.listen((uri) {
          final c = tableFromUrl(uri);
          if (c == null || !mounted) return;
          Navigator.of(context).popUntil((r) => r.isFirst);
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => OnlineLobbyScreen(initialCode: c)));
        }, onError: (_) {});
      } catch (_) {}
    }
    if (widget.openDaily) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const GameScreen(daily: true)));
      });
    }
    // lien d'invitation : on arrive directement au salon, code pré-rempli
    final code = widget.inviteCode;
    if (code != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => OnlineLobbyScreen(initialCode: code)));
      });
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final current = Localizations.localeOf(context).languageCode;
    Theme.of(context); // reconstruit l'accueil quand le thème change
    return Scaffold(
      // fond du thème : halo, bandeau LED et sol quadrillé (Cristal, Nuit)…
      body: Ambiance(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // titre dans le style du thème (lueur, dorures…)
                  const SkinTitle(),
                  const SizedBox(height: 6),
                  Text('three-nought-four',
                      style: TextStyle(color: sk.dim, fontSize: 16)),
                  const SizedBox(height: 10),
                  // profil : avatar + prénom (touche : modifier)
                  const ProfileChip(),
                  ValueListenableBuilder(
                    valueListenable: stats,
                    builder: (context, st, _) => st.played == 0
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 6),
                            // touche : statistiques détaillées
                            child: TextButton.icon(
                              key: const ValueKey('open-stats'),
                              onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const StatsScreen())),
                              icon: Icon(Icons.bar_chart,
                                  size: 18, color: sk.dim),
                              label: Text(
                                  l.statsLine(st.played, st.won, st.lost),
                                  key: const ValueKey('stats'),
                                  style:
                                      TextStyle(color: sk.dim, fontSize: 13)),
                            ),
                          ),
                  ),
                  const SizedBox(height: 40),
                  // partie solo interrompue (app fermée) : la reprendre
                  ValueListenableBuilder(
                    valueListenable: soloSave,
                    builder: (context, save, _) => save == null || save.fresh
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  key: const ValueKey('resume-solo'),
                                  onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const GameScreen(resume: true))),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 6),
                                    child: Text(
                                        '${l.resumeGame}\n${l.us} ${save.ns} · ${l.them} ${save.ew}',
                                        textAlign: TextAlign.center),
                                  ),
                                )),
                          ),
                  ),
                  // bouton principal : dégradé lumineux du thème (comme Thaayam)
                  SkinPrimaryButton(
                    key: const ValueKey('quick-play'),
                    label: l.quickPlay,
                    icon: Icons.play_arrow_rounded,
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const GameScreen())),
                  ),
                  const SizedBox(height: 12),
                  // donne du jour : la même pour tout le monde
                  ValueListenableBuilder(
                    valueListenable: daily,
                    builder: (context, d, _) {
                      final today = d.today();
                      return SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const ValueKey('daily'),
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const GameScreen(daily: true))),
                            icon: const Icon(Icons.today),
                            label: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                  today == null
                                      ? '${l.dailyDeal}\n${l.dailyNew}'
                                      : '${l.dailyDeal}\n${l.dailyDone(l.dailyScore(today.delta > 0 ? '+${today.delta}' : '${today.delta}', today.points))}',
                                  textAlign: TextAlign.center),
                            ),
                          ));
                    },
                  ),
                  const SizedBox(height: 12),
                  // table publique : d'autres joueurs, sans code
                  SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey('home-public'),
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const OnlineLobbyScreen(autoQuick: true))),
                        icon: const Icon(Icons.public),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child:
                              Text(l.publicTable, textAlign: TextAlign.center),
                        ),
                      )),
                  const SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const OnlineLobbyScreen())),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 6),
                          child: Text(l.privateTableFriends,
                              textAlign: TextAlign.center),
                        ),
                      )),
                  const SizedBox(height: 12),
                  // web : installer l'appli (jouable sans internet en solo)
                  ValueListenableBuilder<bool>(
                    valueListenable: pwaInstallable,
                    builder: (context, can, _) => can || pwaIosHint
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextButton.icon(
                              key: const ValueKey('install-app'),
                              onPressed: () => can
                                  ? installPwa()
                                  : showDialog<void>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                            title: Text(l.installApp),
                                            content: Text(
                                                '${l.installIos}\n\n${l.installInfo}'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(ctx).pop(),
                                                  child: Text(l.close)),
                                            ],
                                          )),
                              icon: const Icon(Icons.install_mobile),
                              label: Text(l.installApp),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const TutorialScreen())),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(l.learn304),
                  ),
                  const SizedBox(height: 10),
                  SkinCard(
                    title: l.language,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in kLanguages.entries)
                          ChoiceChip(
                            key: ValueKey('lang-${e.key}'),
                            label: Text(e.value,
                                style:
                                    TextStyle(fontFamily: _kLangFont[e.key])),
                            selected: current == e.key,
                            onSelected: (_) => setAppLanguage(e.key),
                          ),
                      ],
                    ),
                  ),
                  // apparence : thème (comme Thaayam), dos des cartes, tapis
                  SkinCard(
                    title: l.appearance,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SkinPicker(),
                          const SizedBox(height: 14),
                          _OptionRow(
                              label: l.cardBack,
                              notifier: cardBack,
                              options: {
                                'royal': l.royal,
                                'classic': l.classic,
                                'dark': l.dark,
                                'emerald': l.backEmerald,
                                'ruby': l.backRuby,
                                'peacock': l.backPeacock,
                              },
                              onSelect: setCardBack,
                              lockKind: 'back',
                              keyPrefix: 'back'),
                          // le tapis ne compte que dans le thème Bois (les autres
                          // thèmes ont leur propre table)
                          if (skinCode.value == 'bois') ...[
                            const SizedBox(height: 14),
                            _OptionRow(
                                label: l.tableFelt,
                                notifier: felt,
                                options: {
                                  'green': l.green,
                                  'blue': l.blue,
                                  'violet': l.violet,
                                  'crimson': l.feltCrimson,
                                  'midnight': l.feltMidnight,
                                  'sand': l.feltSand,
                                },
                                onSelect: setFelt,
                                lockKind: 'felt',
                                keyPrefix: 'felt'),
                          ],
                        ]),
                  ),
                  SkinCard(
                    title: l.botLevel,
                    child: _OptionRow(
                        label: null,
                        notifier: botLevel,
                        options: {
                          'easy': l.levelEasy,
                          'normal': l.normal,
                          'hard': l.levelHard
                        },
                        onSelect: setBotLevel,
                        keyPrefix: 'level'),
                  ),
                  SkinCard(
                    title: l.options,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _OptionRow(
                              label: l.cardSize,
                              notifier: cardSize,
                              options: {'normal': l.normal, 'large': l.large},
                              onSelect: setCardSize,
                              keyPrefix: 'size'),
                          const SizedBox(height: 14),
                          _OptionRow(
                              label: l.deckColors,
                              notifier: deckColors,
                              options: {
                                'two': l.twoColors,
                                'four': l.fourColors
                              },
                              onSelect: setDeckColors,
                              keyPrefix: 'deck'),
                          const SizedBox(height: 14),
                          _OptionRow(
                              label: l.vibration,
                              notifier: vibrate,
                              options: {'on': l.on, 'off': l.off},
                              onSelect: setVibrate,
                              keyPrefix: 'vibe'),
                          const SizedBox(height: 14),
                          _OptionRow(
                              label: l.sound,
                              notifier: sound,
                              options: {'on': l.on, 'off': l.off},
                              onSelect: setSound,
                              keyPrefix: 'sound'),
                          const SizedBox(height: 14),
                          Text(l.speed,
                              style: TextStyle(color: sk.dim, fontSize: 13)),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<double>(
                            valueListenable: botSpeed,
                            builder: (context, speed, _) => Wrap(
                              spacing: 8,
                              runSpacing: 8,
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
                        ]),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Choix du thème (comme Thaayam) : 4 boutons avec icône.
class _SkinPicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    Theme.of(context); // suit le thème choisi
    final names = {
      'cristal': l.themeCristal,
      'temple': l.themeTemple,
      'nuit': l.themeNuit,
      'bois': l.themeBois,
    };
    final s = sk;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3.4,
      children: [
        for (final code in kSkins)
          Builder(builder: (context) {
            final on = skinCode.value == code;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('skin-$code'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => setSkin(code),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: on ? s.accent : s.line),
                    color: on ? null : s.surface.withValues(alpha: 0.6),
                    gradient: on
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [s.accent, s.accent2])
                        : null,
                    boxShadow: on ? s.shadow(blur: 14, opacity: 0.4) : null,
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(skinIcon(code),
                            size: 18, color: on ? s.onAccent : s.accent),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(names[code]!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: on ? s.onAccent : s.text)),
                        ),
                      ]),
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// Ligne de réglage à choix unique (dos de cartes, tapis).
class _OptionRow extends StatelessWidget {
  const _OptionRow(
      {required this.label,
      required this.notifier,
      required this.options,
      required this.onSelect,
      required this.keyPrefix,
      this.lockKind});
  final String? label;

  /// 'back' / 'felt' : certains choix se débloquent en gagnant des parties.
  final String? lockKind;
  final ValueNotifier<String> notifier;
  final Map<String, String> options;
  final Future<void> Function(String) onSelect;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(label!, style: TextStyle(color: sk.dim, fontSize: 13)),
            const SizedBox(height: 8),
          ],
          ValueListenableBuilder<String>(
            valueListenable: notifier,
            builder: (context, v, _) => ValueListenableBuilder(
              valueListenable: stats, // parties gagnées : déverrouillages
              builder: (context, st, _) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in options.entries)
                    if (lockKind != null &&
                        winsToUnlock(lockKind!, e.key, st.gamesWon) > 0)
                      // verrouillé : cadenas + nombre de parties à gagner
                      Tooltip(
                        message: AppLocalizations.of(context)!
                            .unlockHint(kUnlockWins['$lockKind:${e.key}']!),
                        triggerMode: TooltipTriggerMode.tap,
                        child: ChoiceChip(
                          key: ValueKey('$keyPrefix-${e.key}'),
                          avatar: const Icon(Icons.lock, size: 16),
                          label: Text(e.value),
                          selected: false,
                          onSelected: null,
                        ),
                      )
                    else
                      ChoiceChip(
                        key: ValueKey('$keyPrefix-${e.key}'),
                        label: Text(e.value),
                        selected: v == e.key,
                        onSelected: (_) => onSelect(e.key),
                      ),
                ],
              ),
            ),
          ),
        ]);
  }
}
