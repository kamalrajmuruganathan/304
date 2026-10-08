import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Future<void> setVibrate(String v) async {
  vibrate.value = v;
  await _savePref('vibe304', v);
}

/// Apparence (comme `back304` / `felt304` du prototype).
final ValueNotifier<String> cardBack = ValueNotifier<String>('royal');
final ValueNotifier<String> felt = ValueNotifier<String>('green');
const kBacks = ['royal', 'classic', 'dark'];
const kFelts = ['green', 'blue', 'violet'];

/// Couleurs du tapis (centre, bord), reprises du CSS du prototype.
const kFeltColors = <String, (Color, Color)>{
  'green': (Color(0xFF0F5A3C), Color(0xFF063421)),
  'blue': (Color(0xFF155A7A), Color(0xFF082A3D)),
  'violet': (Color(0xFF4A2A6A), Color(0xFF241338)),
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
    final b = prefs.getString('back304');
    if (b != null && kBacks.contains(b)) cardBack.value = b;
    final f = prefs.getString('felt304');
    if (f != null && kFelts.contains(f)) felt.value = f;
    final v = prefs.getDouble(_kSpeedPref);
    if (v != null && kSpeeds.contains(v)) botSpeed.value = v;
    final raw = prefs.getString(_kStatsPref);
    if (raw != null) {
      stats.value = Stats.fromJson(jsonDecode(raw) as Map);
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
    if (score['caps'] == true && score['tmTeam'] == 'NS') caps++;
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
