// ============================================================================
// Classement entre amis : client (requêtes, erreurs, envoi du score du jour)
// et écran, contre un faux serveur qui imite les fonctions g304_* de
// deploy/supabase/g304_classement.sql.
// ============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:game304/daily.dart';
import 'package:game304/l10n/app_localizations.dart';
import 'package:game304/net/ranking.dart';
import 'package:game304/settings.dart';
import 'package:game304/ui/ranking_screen.dart';

/// Faux serveur : mêmes règles que le SQL (secret, code, soi, jour).
class FakeServer {
  final players = <String, Map<String, dynamic>>{};
  final friends = <String, Set<String>>{};
  final scores = <String, Map<String, (int, int)>>{}; // jour -> joueur -> score
  final calls = <String>[];
  bool down = false;
  var _n = 0;

  String add(String name, {int avatar = 0, int won = 0, int played = 0}) {
    final id = 'id${_n++}';
    players[id] = {
      'secret': 's$id',
      'code': 'C${id.toUpperCase().padLeft(5, 'X')}'.substring(0, 6),
      'pseudo': name,
      'avatar': avatar,
      'gagnees': won,
      'jouees': played,
    };
    friends[id] = {};
    return id;
  }

  http.Response _err(String m) =>
      http.Response(jsonEncode({'code': 'P0001', 'message': m}), 400,
          headers: {'content-type': 'application/json'});

  Future<http.Response> handle(http.Request r) async {
    if (down) throw Exception('réseau coupé');
    final fn = r.url.pathSegments.last;
    calls.add(fn);
    expect(r.headers['apikey'], kRankKey);
    final a = jsonDecode(r.body) as Map<String, dynamic>;
    http.Response ok(Object? v) =>
        http.Response.bytes(utf8.encode(v == null ? '' : jsonEncode(v)), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
    if (fn == 'g304_inscrire') {
      final id = add(a['p_pseudo'] as String, avatar: a['p_avatar'] as int);
      final p = players[id]!;
      return ok({'id': id, 'secret': p['secret'], 'code': p['code']});
    }
    final me = players[a['p_joueur']];
    if (me == null || me['secret'] != a['p_secret']) {
      return _err('g304:inconnu');
    }
    final id = a['p_joueur'] as String;
    switch (fn) {
      case 'g304_profil':
        me['pseudo'] = a['p_pseudo'];
        me['avatar'] = a['p_avatar'];
        me['gagnees'] = a['p_gagnees'];
        me['jouees'] = a['p_jouees'];
        return ok(null);
      case 'g304_score_jour':
        scores
            .putIfAbsent(a['p_jour'] as String, () => {})
            .putIfAbsent(id, () => (a['p_delta'] as int, a['p_points'] as int));
        return ok(null);
      case 'g304_ajouter_ami':
        final code = (a['p_code'] as String).trim().toUpperCase();
        final f = players.entries.where((e) => e.value['code'] == code);
        if (f.isEmpty) return _err('g304:code');
        if (f.first.key == id) return _err('g304:soi');
        friends[id]!.add(f.first.key);
        friends[f.first.key]!.add(id);
        return ok({'id': f.first.key, 'pseudo': f.first.value['pseudo']});
      case 'g304_retirer_ami':
        friends[id]!.remove(a['p_ami']);
        friends[a['p_ami']]?.remove(id);
        return ok(null);
      case 'g304_classement':
        final day = scores[a['p_jour']] ?? {};
        final rows = [
          for (final pid in [id, ...friends[id]!])
            {
              'id': pid,
              'pseudo': players[pid]!['pseudo'],
              'avatar': players[pid]!['avatar'],
              'moi': pid == id,
              'gagnees': players[pid]!['gagnees'],
              'jouees': players[pid]!['jouees'],
              'delta': day[pid]?.$1,
              'points': day[pid]?.$2,
            }
        ];
        int? rang;
        final mine = day[id];
        if (mine != null) {
          rang = 1 +
              day.values
                  .where((s) =>
                      s.$1 > mine.$1 || (s.$1 == mine.$1 && s.$2 > mine.$2))
                  .length;
        }
        return ok({
          'code': me['code'],
          'joueurs': rows,
          'total': day.length,
          'rang': rang
        });
    }
    return _err('?');
  }
}

Future<void> reset() async {
  SharedPreferences.setMockInitialValues({});
  await Ranking.forget();
  daily.value = const DailyState();
  stats.value = const Stats();
  playerName.value = '';
  avatar.value = 0;
}

void main() {
  late FakeServer srv;
  setUp(() async {
    await reset();
    srv = FakeServer();
    Ranking.instance = Ranking(client: MockClient(srv.handle));
  });

  test('inscription, identité gardée, score du jour envoyé une seule fois',
      () async {
    playerName.value = 'Kamal';
    avatar.value = 3;
    stats.value = const Stats(gamesWon: 4, gamesLost: 2);
    final today = dayKey();
    daily.value = DailyState(last: DailyResult(today, 2, 180), started: today);
    await Ranking.instance.ensure();
    final id = Ranking.me.value!;
    expect(srv.players[id.id]!['pseudo'], 'Kamal');
    expect(srv.players[id.id]!['gagnees'], 4);
    expect(srv.players[id.id]!['jouees'], 6);
    expect(srv.scores[today]![id.id], (2, 180));
    // relu depuis les préférences
    Ranking.me.value = null;
    await Ranking.load();
    expect(Ranking.me.value!.id, id.id);
    expect(Ranking.me.value!.code, id.code);
    // déjà envoyé : pas de 2e appel
    srv.calls.clear();
    await Ranking.instance.submitDaily();
    expect(srv.calls, isEmpty);
    // score d'il y a 3 jours : refusé par le serveur, donc pas envoyé
    daily.value = const DailyState(last: DailyResult('2020-01-01', 1, 160));
    await Ranking.instance.submitDaily();
    expect(srv.calls, isEmpty);
  });

  test('pas inscrit : rien n\'est envoyé après une donne du jour', () async {
    daily.value = DailyState(last: DailyResult(dayKey(), 1, 170));
    await Ranking.instance.submitDailyQuietly();
    expect(srv.calls, isEmpty);
  });

  test('erreurs : code inconnu, son propre code, réseau coupé', () async {
    await Ranking.instance.ensure();
    await expectLater(() => Ranking.instance.addFriend('ZZZZZZ'),
        throwsA(isA<RankError>().having((e) => e.code, 'code', 'code')));
    await expectLater(() => Ranking.instance.addFriend(Ranking.me.value!.code),
        throwsA(isA<RankError>().having((e) => e.code, 'code', 'self')));
    srv.down = true;
    await expectLater(() => Ranking.instance.board(),
        throwsA(isA<RankError>().having((e) => e.code, 'code', 'network')));
  });

  test('ordre du classement : jetons, puis points, puis non joués', () {
    RankRow r(String id, int? d, int? p, int won) => RankRow(
        id: id,
        name: id,
        avatar: 0,
        won: won,
        played: 10,
        me: false,
        delta: d,
        points: p);
    final b = RankBoard(
        'X',
        [
          r('a', null, null, 9),
          r('b', 1, 170, 0),
          r('c', 3, 150, 1),
          r('d', 1, 200, 2),
          r('e', -2, 90, 5),
        ],
        4,
        2);
    expect(b.daily.map((x) => x.id), ['c', 'd', 'b', 'e', 'a']);
    expect(b.games.map((x) => x.id), ['a', 'e', 'd', 'c', 'b']);
  });

  for (final lang in ['fr', 'ta']) {
    testWidgets('écran : activer, ajouter un ami, classement du jour ($lang)',
        (t) async {
      t.view.physicalSize = const Size(360, 640) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final l = lookupAppLocalizations(Locale(lang));
      final today = dayKey();
      final ami = srv.add('Priya', avatar: 5, won: 7, played: 9);
      srv.scores[today] = {ami: (3, 210)};
      daily.value = DailyState(last: DailyResult(today, 1, 175));
      playerName.value = 'Kamal';
      await t.pumpWidget(MaterialApp(
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const RankingScreen(),
      ));
      // rien n'est envoyé avant d'activer
      expect(find.text(l.rankIntro), findsOneWidget);
      expect(srv.calls, isEmpty);
      await t.tap(find.byKey(const ValueKey('rank-join')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final me = Ranking.me.value!;
      expect(find.text(l.rankMyCode(me.code)), findsOneWidget);
      expect(find.byKey(const ValueKey('rank-no-friends')), findsOneWidget);
      expect(find.text(l.rankPosition(2, 2)), findsOneWidget);

      // code inconnu
      await t.enterText(
          find.byKey(const ValueKey('rank-code-field')), 'zzzzzz');
      await t.tap(find.byKey(const ValueKey('rank-add')));
      await t.pumpAndSettle();
      expect(find.text(l.rankErrCode), findsOneWidget);

      // vrai code (en minuscules)
      await t.enterText(find.byKey(const ValueKey('rank-code-field')),
          (srv.players[ami]!['code'] as String).toLowerCase());
      await t.tap(find.byKey(const ValueKey('rank-add')));
      await t.pumpAndSettle();
      expect(find.text(l.rankAdded('Priya')), findsOneWidget);
      expect(find.byKey(const ValueKey('rank-no-friends')), findsNothing);
      // Priya (+3) devant moi (+1)
      final yPriya = t.getTopLeft(find.byKey(ValueKey('rank-row-$ami'))).dy;
      final yMe = t.getTopLeft(find.byKey(ValueKey('rank-row-${me.id}'))).dy;
      expect(yPriya, lessThan(yMe));
      expect(find.text(l.dailyScore('+3', 210)), findsOneWidget);

      // onglet parties gagnées
      await t.tap(find.byKey(const ValueKey('rank-tab-games')));
      await t.pumpAndSettle();
      expect(find.text(l.rankWon(7, 9)), findsOneWidget);

      // retirer l'ami
      await t.tap(find.byKey(ValueKey('rank-remove-$ami')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('rank-remove-ok')));
      await t.pumpAndSettle();
      expect(srv.friends[me.id], isEmpty);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('identité supprimée côté serveur : retour à l\'activation',
      (t) async {
    await Ranking.instance.ensure();
    srv.players.clear();
    final l = lookupAppLocalizations(const Locale('fr'));
    await t.pumpWidget(const MaterialApp(
      locale: Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RankingScreen(),
    ));
    await t.pumpAndSettle();
    expect(Ranking.me.value, isNull);
    expect(find.text(l.rankIntro), findsOneWidget);
    // réactiver crée une nouvelle identité
    await t.tap(find.byKey(const ValueKey('rank-join')));
    await t.pumpAndSettle();
    expect(Ranking.me.value, isNotNull);
    expect(find.text(l.rankMyCode(Ranking.me.value!.code)), findsOneWidget);
  });
}
