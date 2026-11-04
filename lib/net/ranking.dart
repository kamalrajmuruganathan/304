// ============================================================================
// Classement entre amis (Supabase, tables g304_* : deploy/supabase/).
// Pas de compte : à la première ouverture de l'écran Classement, l'appli
// demande un identifiant + un secret au serveur et les garde sur l'appareil
// (`rank304`). Les amis s'ajoutent par code (6 caractères). On envoie : prénom,
// avatar, parties solo jouées / gagnées, score officiel de la donne du jour.
// L'URL et la clé « publishable » sont publiques (protégées par RLS : aucune
// table n'est lisible, tout passe par des fonctions qui vérifient le secret).
// ============================================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../daily.dart';
import '../settings.dart';

const kRankUrl = 'https://zxhxevucpuudknyfidla.supabase.co/rest/v1/rpc';
const kRankKey = 'sb_publishable_07OkmTas1JvRtODtJlWCzQ_uSX6Wre-';
const _kPref = 'rank304';

/// Erreur renvoyée au joueur (code traduit par l'écran).
class RankError implements Exception {
  /// network | unknown | code | self | tooMany | other
  final String code;
  const RankError(this.code);
  @override
  String toString() => 'RankError($code)';
}

/// Une ligne du classement (moi ou un ami).
class RankRow {
  final String id, name;
  final int avatar, won, played;
  final bool me;
  final int? delta, points; // score du jour (null : pas joué)
  const RankRow(
      {required this.id,
      required this.name,
      required this.avatar,
      required this.won,
      required this.played,
      required this.me,
      this.delta,
      this.points});

  static RankRow fromJson(Map m) => RankRow(
        id: m['id'] as String,
        name: (m['pseudo'] as String?) ?? '',
        avatar: (m['avatar'] as num?)?.toInt() ?? 0,
        won: (m['gagnees'] as num?)?.toInt() ?? 0,
        played: (m['jouees'] as num?)?.toInt() ?? 0,
        me: m['moi'] == true,
        delta: (m['delta'] as num?)?.toInt(),
        points: (m['points'] as num?)?.toInt(),
      );
}

class RankBoard {
  final String code; // mon code ami
  final List<RankRow> rows;
  final int total; // joueurs ayant joué la donne du jour
  final int? rank; // mon rang du jour (null : pas joué)
  const RankBoard(this.code, this.rows, this.total, this.rank);

  /// Classement du jour : ceux qui ont joué d'abord (jetons puis points),
  /// puis les autres par parties gagnées.
  List<RankRow> get daily {
    final r = [...rows];
    r.sort((a, b) {
      if ((a.delta == null) != (b.delta == null)) {
        return a.delta == null ? 1 : -1;
      }
      if (a.delta != null && a.delta != b.delta) {
        return b.delta!.compareTo(a.delta!);
      }
      if (a.points != null && a.points != b.points) {
        return b.points!.compareTo(a.points!);
      }
      return b.won.compareTo(a.won);
    });
    return r;
  }

  /// Classement général : parties gagnées, puis taux de victoire.
  List<RankRow> get games {
    final r = [...rows];
    r.sort((a, b) {
      if (a.won != b.won) return b.won.compareTo(a.won);
      return a.played.compareTo(b.played);
    });
    return r;
  }
}

/// Identité gardée sur l'appareil.
class RankId {
  final String id, secret, code;
  const RankId(this.id, this.secret, this.code);
}

class Ranking {
  Ranking({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  /// Client partagé de l'appli (remplaçable par les tests).
  static Ranking instance = Ranking();

  /// Identité enregistrée (null : jamais ouvert le classement).
  static final ValueNotifier<RankId?> me = ValueNotifier(null);

  static Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kPref);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map;
      me.value = RankId(m['id'] as String, m['secret'] as String,
          (m['code'] as String?) ?? '');
      // dernier score du jour envoyé (pour ne pas le renvoyer)
      _sentDay = m['sent'] as String?;
    } catch (_) {}
  }

  static String? _sentDay;

  /// Identité refusée par le serveur (supprimée) : on l'oublie.
  static Future<void> forget() async {
    me.value = null;
    _sentDay = null;
    try {
      await (await SharedPreferences.getInstance()).remove(_kPref);
    } catch (_) {}
  }

  static Future<void> _save() async {
    final i = me.value;
    if (i == null) return;
    try {
      await (await SharedPreferences.getInstance()).setString(
          _kPref,
          jsonEncode({
            'id': i.id,
            'secret': i.secret,
            'code': i.code,
            'sent': _sentDay
          }));
    } catch (_) {}
  }

  Future<dynamic> _call(String fn, Map<String, Object?> args) async {
    final http.Response r;
    try {
      r = await _http
          .post(Uri.parse('$kRankUrl/$fn'),
              headers: {
                'apikey': kRankKey,
                'Authorization': 'Bearer $kRankKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(args))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const RankError('network');
    }
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    }
    final body = utf8.decode(r.bodyBytes);
    if (body.contains('g304:inconnu')) throw const RankError('unknown');
    if (body.contains('g304:code')) throw const RankError('code');
    if (body.contains('g304:soi')) throw const RankError('self');
    if (body.contains('g304:trop')) throw const RankError('tooMany');
    throw const RankError('other');
  }

  Map<String, Object?> _auth() =>
      {'p_joueur': me.value!.id, 'p_secret': me.value!.secret};

  /// S'inscrit si besoin (premier passage), puis envoie profil et score du jour.
  Future<void> ensure() async {
    if (me.value == null) {
      final r = await _call('g304_inscrire',
          {'p_pseudo': playerName.value, 'p_avatar': avatar.value}) as Map;
      me.value =
          RankId(r['id'] as String, r['secret'] as String, r['code'] as String);
      await _save();
    }
    await syncProfile();
    await submitDaily();
  }

  Future<void> syncProfile() async {
    if (me.value == null) return;
    final st = stats.value;
    await _call('g304_profil', {
      ..._auth(),
      'p_pseudo': playerName.value,
      'p_avatar': avatar.value,
      'p_gagnees': st.gamesWon,
      'p_jouees': st.gamesWon + st.gamesLost,
    });
  }

  /// Envoie le score officiel de la donne du jour s'il ne l'a pas été.
  Future<void> submitDaily() async {
    final last = daily.value.last;
    if (me.value == null || last == null || last.day == _sentDay) return;
    // seuls la veille, aujourd'hui et demain sont acceptés par le serveur
    final d = DateTime.parse('${last.day}T12:00:00Z');
    if (DateTime.now().toUtc().difference(d).inHours.abs() > 36) return;
    await _call('g304_score_jour', {
      ..._auth(),
      'p_jour': last.day,
      'p_delta': last.delta,
      'p_points': last.points,
    });
    _sentDay = last.day;
    await _save();
  }

  /// Envoi silencieux après une donne du jour (si déjà inscrit).
  Future<void> submitDailyQuietly() async {
    try {
      await submitDaily();
    } catch (_) {}
  }

  Future<String> addFriend(String code) async {
    final r =
        await _call('g304_ajouter_ami', {..._auth(), 'p_code': code}) as Map;
    return (r['pseudo'] as String?) ?? '';
  }

  Future<void> removeFriend(String id) =>
      _call('g304_retirer_ami', {..._auth(), 'p_ami': id});

  Future<RankBoard> board([String? day]) async {
    final m =
        await _call('g304_classement', {..._auth(), 'p_jour': day ?? dayKey()})
            as Map;
    final code = (m['code'] as String?) ?? '';
    if (me.value != null && me.value!.code != code && code.isNotEmpty) {
      me.value = RankId(me.value!.id, me.value!.secret, code);
      await _save();
    }
    return RankBoard(
      code,
      [
        for (final x in (m['joueurs'] as List? ?? const []))
          RankRow.fromJson(x as Map)
      ],
      (m['total'] as num?)?.toInt() ?? 0,
      (m['rang'] as num?)?.toInt(),
    );
  }
}
