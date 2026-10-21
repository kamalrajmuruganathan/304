import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Vitesse des bots (multiplicateur des délais, comme `SPEED` du prototype) :
/// 1.6 = lente, 1 = normale, 0.5 = rapide. Mémorisée sous `speed304`.
final ValueNotifier<double> botSpeed = ValueNotifier<double>(1);
const kSpeeds = <double>[1.6, 1, 0.5];
const _kSpeedPref = 'speed304';

/// Statistiques des donnes jouées en solo (`stats304`, compatible avec le
/// format du prototype : played/won/lost, enrichi des détails ci-dessous).
class Stats {
  const Stats({
    this.played = 0,
    this.won = 0,
    this.lost = 0,
    this.taken = const {},
    this.made = const {},
    this.caps = 0,
    this.gamesWon = 0,
    this.gamesLost = 0,
    this.streak = 0,
    this.bestStreak = 0,
  });

  /// Donnes jouées / gagnées / perdues par l'équipe du joueur.
  final int played, won, lost;

  /// Prises du joueur (siège Sud) par palier d'enchère, et prises réussies.
  /// Paliers : 'lt200', 'lt250', 'ge250', 'pcc'.
  final Map<String, int> taken, made;

  /// Caps (8 plis) réalisés par l'équipe du joueur.
  final int caps;

  /// Parties (jusqu'à 0 jeton) gagnées / perdues.
  final int gamesWon, gamesLost;

  /// Série en cours de donnes gagnées, et meilleure série.
  final int streak, bestStreak;

  static const tiers = ['lt200', 'lt250', 'ge250', 'pcc'];

  int get takenTotal => taken.values.fold(0, (a, b) => a + b);
  int get madeTotal => made.values.fold(0, (a, b) => a + b);

  Map<String, Object> toJson() => {
        'played': played,
        'won': won,
        'lost': lost,
        'taken': taken,
        'made': made,
        'caps': caps,
        'gamesWon': gamesWon,
        'gamesLost': gamesLost,
        'streak': streak,
        'bestStreak': bestStreak,
      };

  static Stats fromJson(Map m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    Map<String, int> map(String k) => {
          for (final e in ((m[k] as Map?) ?? const {}).entries)
            if (tiers.contains(e.key)) e.key as String: (e.value as num).toInt()
        };
    return Stats(
      played: n('played'),
      won: n('won'),
      lost: n('lost'),
      taken: map('taken'),
      made: map('made'),
      caps: n('caps'),
      gamesWon: n('gamesWon'),
      gamesLost: n('gamesLost'),
      streak: n('streak'),
      bestStreak: n('bestStreak'),
    );
  }
}

final ValueNotifier<Stats> stats = ValueNotifier(const Stats());
const _kStatsPref = 'stats304';

/// Palier d'enchère d'une prise (pour les statistiques).
String bidTier(Map<String, dynamic> score) {
  if (score['pcc'] == true) return 'pcc';
  final b = score['bid'] as int;
  return b < 200 ? 'lt200' : (b < 250 ? 'lt250' : 'ge250');
}

/// Accessibilité : grandes cartes, jeu 4 couleurs, vibrations.
final ValueNotifier<String> cardSize = ValueNotifier<String>('normal');
final ValueNotifier<String> deckColors = ValueNotifier<String>('two');
final ValueNotifier<String> vibrate = ValueNotifier<String>('on');

/// Facteur d'agrandissement des cartes de la main et du pli.
double get cardScale => cardSize.value == 'large' ? 1.25 : 1.0;

/// Agrandissement automatique selon l'écran (tablette en portrait : la table
/// est grande, les cartes taille téléphone y paraissent minuscules). Référence
/// : téléphone 390×844 → 1 ; jamais en dessous de 1 ni au-dessus de 1,7.
double autoCardScale(Size screen) =>
    math.min(screen.width / 390, screen.height / 844).clamp(1.0, 1.7);

/// Couleur d'une enseigne. En jeu 4 couleurs (aide aux daltoniens et
/// lecture rapide) : ♠ noir, ♥ rouge, ♦ bleu, ♣ vert.
Color suitColor(String suit, {required Color ink, required Color red}) {
  if (deckColors.value == 'four') {
    switch (suit) {
      case 'D':
        return const Color(0xFF1A5FC2);
      case 'C':
        return const Color(0xFF1E7B34);
    }
  }
  return (suit == 'D' || suit == 'H') ? red : ink;
}

/// Garde l'écran allumé pendant une partie (sinon il s'éteint pendant que les
/// bots jouent ou qu'on réfléchit). Sans effet si la plateforme ne le permet pas.
void keepScreenOn(bool on) {
  try {
    WakelockPlus.toggle(enable: on).catchError((_) {});
  } catch (_) {}
}

/// Petite vibration au moment de jouer une carte (téléphones ; sans effet
/// sur le web et dans les tests).
void haptic() {
  if (vibrate.value != 'on') return;
  try {
    HapticFeedback.selectionClick();
  } catch (_) {}
}

Future<void> _savePref(String key, String v) async {
  try {
    await (await SharedPreferences.getInstance()).setString(key, v);
  } catch (_) {}
}

Future<void> setCardSize(String v) async {
  cardSize.value = v;
  await _savePref('size304', v);
}

Future<void> setDeckColors(String v) async {
  deckColors.value = v;
  await _savePref('deck304', v);
}

/// Niveau des adversaires en solo : 'normal' (IA complète), 'easy'
/// (Est/Ouest font des erreurs, voir `kEasySlip`) ou 'hard' (Est/Ouest jouent
/// avec l'IA Monte-Carlo, lib/ai/hard.dart). Clé `level304`.
final ValueNotifier<String> botLevel = ValueNotifier<String>('normal');

Future<void> setBotLevel(String v) async {
  botLevel.value = v;
  await _savePref('level304', v);
}

Future<void> setVibrate(String v) async {
  vibrate.value = v;
  await _savePref('vibe304', v);
}

/// Apparence (comme `back304` / `felt304` du prototype).
final ValueNotifier<String> cardBack = ValueNotifier<String>('royal');
final ValueNotifier<String> felt = ValueNotifier<String>('green');
const kBacks = ['royal', 'classic', 'dark', 'emerald', 'ruby', 'peacock'];
const kFelts = ['green', 'blue', 'violet', 'crimson', 'midnight', 'sand'];

/// Dos de cartes et tapis à débloquer : nombre de parties solo gagnées
/// nécessaires (`stats.gamesWon`). Les autres sont disponibles d'emblée.
const kUnlockWins = <String, int>{
  'back:emerald': 1,
  'felt:crimson': 2,
  'back:ruby': 3,
  'felt:midnight': 5,
  'back:peacock': 8,
  'felt:sand': 12,
};

/// Parties gagnées encore nécessaires pour [kind]:[id] (0 = disponible).
int winsToUnlock(String kind, String id, [int? won]) {
  final need = kUnlockWins['$kind:$id'] ?? 0;
  final have = won ?? stats.value.gamesWon;
  return need > have ? need - have : 0;
}

/// Objets débloqués en passant de [before] à [after] parties gagnées.
List<String> newlyUnlocked(int before, int after) => [
      for (final e in kUnlockWins.entries)
        if (e.value > before && e.value <= after) e.key
    ];

/// Couleurs du tapis (centre, bord), reprises du CSS du prototype.
const kFeltColors = <String, (Color, Color)>{
  'green': (Color(0xFF0F5A3C), Color(0xFF063421)),
  'blue': (Color(0xFF155A7A), Color(0xFF082A3D)),
  'violet': (Color(0xFF4A2A6A), Color(0xFF241338)),
  'crimson': (Color(0xFF6A1F2B), Color(0xFF3A0D15)),
  'midnight': (Color(0xFF1B2440), Color(0xFF0B1020)),
  'sand': (Color(0xFF8A7448), Color(0xFF4E3F22)),
};

(Color, Color) get feltColors =>
    kFeltColors[felt.value] ?? kFeltColors['green']!;

/// Décor du dos des cartes : royal (dégradé or), classique (rayures bleues),
/// sombre (rayures anthracite) — reprises du CSS du prototype.
BoxDecoration cardBackDecoration({double radius = 7}) {
  switch (cardBack.value) {
    case 'classic':
      return BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFF0D1117)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment(-0.8, -0.8),
          colors: [
            Color(0xFF1F6FEB),
            Color(0xFF1F6FEB),
            Color(0xFF144FB0),
            Color(0xFF144FB0)
          ],
          stops: [0, 0.5, 0.5, 1],
          tileMode: TileMode.repeated,
        ),
      );
    case 'dark':
      return BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x66E3C565)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment(-0.8, -0.8),
          colors: [
            Color(0xFF2B2B33),
            Color(0xFF2B2B33),
            Color(0xFF17171C),
            Color(0xFF17171C)
          ],
          stops: [0, 0.5, 0.5, 1],
          tileMode: TileMode.repeated,
        ),
      );
    case 'emerald':
      return BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE3C565), width: 1.5),
        gradient: const RadialGradient(
            colors: [Color(0xFF14855C), Color(0xFF07402B)]),
      );
    case 'ruby':
      return BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE3C565)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment(-0.7, -0.7),
          colors: [
            Color(0xFF9B1B30),
            Color(0xFF9B1B30),
            Color(0xFF6A0F20),
            Color(0xFF6A0F20)
          ],
          stops: [0, 0.5, 0.5, 1],
          tileMode: TileMode.repeated,
        ),
      );
    case 'peacock':
      return BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE3C565), width: 1.5),
        gradient: const SweepGradient(colors: [
          Color(0xFF0B5E7E),
          Color(0xFF1E8C6E),
          Color(0xFF3A2C7A),
          Color(0xFF0B5E7E)
        ]),
      );
    default:
      return BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8A6A2E), Color(0xFF6B5122)]),
        border: Border.all(color: const Color(0xFF4A370F)),
      );
  }
}

Future<void> setCardBack(String v) async {
  cardBack.value = v;
  try {
    await (await SharedPreferences.getInstance()).setString('back304', v);
  } catch (_) {}
}

Future<void> setFelt(String v) async {
  felt.value = v;
  try {
    await (await SharedPreferences.getInstance()).setString('felt304', v);
  } catch (_) {}
}

/// Son activé ('on') ou coupé ('off'), comme `sound304` du prototype.
final ValueNotifier<String> sound = ValueNotifier<String>('on');
bool get soundEnabled => sound.value == 'on';

Future<void> setSound(String v) async {
  sound.value = v;
  try {
    await (await SharedPreferences.getInstance()).setString('sound304', v);
  } catch (_) {}
}

Future<void> loadSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('sound304') == 'off') sound.value = 'off';
    if (prefs.getString('size304') == 'large') cardSize.value = 'large';
    if (prefs.getString('deck304') == 'four') deckColors.value = 'four';
    if (prefs.getString('vibe304') == 'off') vibrate.value = 'off';
    final lv = prefs.getString('level304');
    if (lv == 'easy' || lv == 'hard') botLevel.value = lv!;
    final b = prefs.getString('back304');
    if (b != null && kBacks.contains(b)) cardBack.value = b;
    final f = prefs.getString('felt304');
    if (f != null && kFelts.contains(f)) felt.value = f;
    playerName.value = cleanName(prefs.getString('name304') ?? '');
    final av = prefs.getInt('avatar304');
    if (av != null && av >= 0 && av < kAvatars.length) avatar.value = av;
    final v = prefs.getDouble(_kSpeedPref);
    if (v != null && kSpeeds.contains(v)) botSpeed.value = v;
    final raw = prefs.getString(_kStatsPref);
    if (raw != null) {
      stats.value = Stats.fromJson(jsonDecode(raw) as Map);
    }
    // dos / tapis encore verrouillés (préférences d'une autre version)
    if (winsToUnlock('back', cardBack.value) > 0) cardBack.value = 'royal';
    if (winsToUnlock('felt', felt.value) > 0) felt.value = 'green';
    final solo = prefs.getString(_kSoloPref);
    if (solo != null) {
      soloSave.value = SoloSave.fromJson(jsonDecode(solo) as Map);
    }
  } catch (_) {
    // préférences indisponibles : vitesse normale
  }
}

Future<void> setBotSpeed(double v) async {
  botSpeed.value = v;
  try {
    await (await SharedPreferences.getInstance()).setDouble(_kSpeedPref, v);
  } catch (_) {}
}

/// Délai d'animation des bots ajusté à la vitesse choisie.
Duration botDelay(int ms) =>
    Duration(milliseconds: (ms * botSpeed.value).round());

/// Compte une donne terminée (gagnée par l'équipe du joueur ou non).
/// [score] : résultat calculé par le moteur (`res['score']`) ; [takerIsMe] :
/// le joueur (Sud) était le preneur ; [gameWinner] : 'NS'/'EW' si la partie
/// se termine avec cette donne.
Future<void> recordDeal(
    {required bool won,
    Map<String, dynamic>? score,
    bool takerIsMe = false,
    String? gameWinner}) async {
  final s = stats.value;
  final taken = Map<String, int>.of(s.taken),
      made = Map<String, int>.of(s.made);
  var caps = s.caps;
  if (score != null) {
    if (takerIsMe) {
      final t = bidTier(score);
      taken[t] = (taken[t] ?? 0) + 1;
      if (score['success'] == true) made[t] = (made[t] ?? 0) + 1;
    }
    // Caps de notre équipe (preneuse) : bonus des 8 plis ou PCC réussi
    // équipe qui a réussi Caps (annonce juste) ; ancien format : le preneur
    final capsTeam =
        score['capsTeam'] ?? (score['caps'] == true ? score['tmTeam'] : null);
    if (capsTeam == 'NS') caps++;
  }
  final streak = won ? s.streak + 1 : 0;
  stats.value = Stats(
    played: s.played + 1,
    won: s.won + (won ? 1 : 0),
    lost: s.lost + (won ? 0 : 1),
    taken: taken,
    made: made,
    caps: caps,
    gamesWon: s.gamesWon + (gameWinner == 'NS' ? 1 : 0),
    gamesLost: s.gamesLost + (gameWinner == 'EW' ? 1 : 0),
    streak: streak,
    bestStreak: streak > s.bestStreak ? streak : s.bestStreak,
  );
  await _savePref(_kStatsPref, jsonEncode(stats.value.toJson()));
}

/// Remet les statistiques à zéro.
Future<void> resetStats() async {
  stats.value = const Stats();
  await _savePref(_kStatsPref, jsonEncode(stats.value.toJson()));
}

/// Table en ligne en cours (code + jeton), pour la reprendre après un
/// rechargement de la page ou un arrêt de l'app. Effacée en quittant la table.
Future<({String code, String token})?> loadSavedTable() async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString('table304');
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map;
    return (code: m['code'] as String, token: m['token'] as String);
  } catch (_) {
    return null;
  }
}

Future<void> saveTable(String code, String token) async {
  try {
    await (await SharedPreferences.getInstance())
        .setString('table304', jsonEncode({'code': code, 'token': token}));
  } catch (_) {}
}

Future<void> clearSavedTable() async {
  try {
    await (await SharedPreferences.getInstance()).remove('table304');
  } catch (_) {}
}

/// Partie solo en cours : jetons et donneur au début de la dernière donne.
/// Permet de la reprendre après la fermeture de l'app (la donne en cours,
/// elle, est redistribuée). Effacée à la fin de la partie.
class SoloSave {
  final int ns, ew, dealer;
  const SoloSave(this.ns, this.ew, this.dealer);
  factory SoloSave.fromJson(Map j) =>
      SoloSave(j['ns'] as int, j['ew'] as int, j['dealer'] as int);
  Map<String, int> toJson() => {'ns': ns, 'ew': ew, 'dealer': dealer};

  /// Score de départ (11-11) : rien à reprendre.
  bool get fresh => ns == 11 && ew == 11;
}

final ValueNotifier<SoloSave?> soloSave = ValueNotifier(null);
const _kSoloPref = 'solo304';

Future<void> saveSolo(int ns, int ew, int dealer) async {
  soloSave.value = SoloSave(ns, ew, dealer);
  await _savePref(_kSoloPref, jsonEncode(soloSave.value!.toJson()));
}

Future<void> clearSolo() async {
  soloSave.value = null;
  try {
    await (await SharedPreferences.getInstance()).remove(_kSoloPref);
  } catch (_) {}
}

/// Profil du joueur : prénom (affiché aux autres en ligne, « Vous » en solo
/// s'il est vide) et avatar (icône + couleur, pas d'emoji : rendu fiable sur
/// le web). Clés `name304` et `avatar304`.
final ValueNotifier<String> playerName = ValueNotifier<String>('');
final ValueNotifier<int> avatar = ValueNotifier<int>(0);

const kAvatars = <(IconData, Color)>[
  (Icons.person, Color(0xFF2F81F7)),
  (Icons.face, Color(0xFFD4A72C)),
  (Icons.star, Color(0xFFE06666)),
  (Icons.pets, Color(0xFF6AA84F)),
  (Icons.local_florist, Color(0xFFC27BA0)),
  (Icons.sports_cricket, Color(0xFF45818E)),
  (Icons.waves, Color(0xFF3D85C6)),
  (Icons.wb_sunny, Color(0xFFF1A33C)),
  (Icons.music_note, Color(0xFF8E7CC3)),
  (Icons.rocket_launch, Color(0xFFCC4125)),
  (Icons.eco, Color(0xFF38A169)),
  (Icons.diamond, Color(0xFF4FC3F7)),
];

/// Longueur maximale d'un prénom (même règle que le serveur).
const kMaxName = 16;

/// Prénom nettoyé : une ligne, espaces réduits, [kMaxName] caractères au plus.
String cleanName(String s) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  final c = t.characters;
  return c.length > kMaxName ? c.take(kMaxName).toString() : t;
}

Future<void> setProfile(String name, int av) async {
  playerName.value = cleanName(name);
  avatar.value = av.clamp(0, kAvatars.length - 1);
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('name304', playerName.value);
    await p.setInt('avatar304', avatar.value);
  } catch (_) {}
}

/// Pastille ronde de l'avatar [index] (repli : icône neutre).
Widget avatarIcon(int? index, {double size = 30}) {
  final a = index != null && index >= 0 && index < kAvatars.length
      ? kAvatars[index]
      : (Icons.person, const Color(0xFF5A6B80));
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: a.$2.withValues(alpha: 0.25),
      border: Border.all(color: a.$2, width: 2),
    ),
    alignment: Alignment.center,
    child: Icon(a.$1, size: size * 0.6, color: a.$2),
  );
}
