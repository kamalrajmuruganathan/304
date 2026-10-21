// ============================================================================
// Serveur (bin/server.dart) testé par de vraies connexions WebSocket :
// codes d'erreur traduisibles, table complète, coup hors tour, et nettoyage
// des tables abandonnées (délai réduit à 2 s via ROOM_TTL_SECONDS).
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game304/net/client.dart';

late Process server;
late int port;

/// Client minimal : file des messages reçus, attente par type.
class C {
  final WebSocket ws;
  final _q = <Map>[];
  Map? lastView; // dernière vue reçue (message state)
  int states = 0; // nombre de messages state reçus
  final _waiters = <Completer<void>>[];
  C._(this.ws) {
    ws.listen((d) {
      final m = jsonDecode(d as String) as Map;
      if (m['t'] == 'state') {
        lastView = m['view'] as Map;
        states++;
      } else {
        _q.add(m);
      }
      for (final w in _waiters) {
        if (!w.isCompleted) w.complete();
      }
      _waiters.clear();
    });
  }
  static Future<C> open() async =>
      C._(await WebSocket.connect('ws://127.0.0.1:$port/ws'));
  void send(Map m) => ws.add(jsonEncode(m));

  /// Prochain message de type [t] (les autres sont ignorés).
  Future<Map> next(String t) async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(end)) {
      final i = _q.indexWhere((m) => m['t'] == t);
      if (i >= 0) return _q.removeAt(i);
      final w = Completer<void>();
      _waiters.add(w);
      await w.future.timeout(const Duration(seconds: 1), onTimeout: () {});
    }
    throw TimeoutException('aucun message $t');
  }
}

void main() {
  setUpAll(() async {
    HttpOverrides.global = null;
    final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = sock.port;
    await sock.close();
    server = await Process.start('dart', [
      'run',
      'bin/server.dart'
    ], environment: {
      'PORT': '$port',
      'ROOM_TTL_SECONDS': '2',
      'ROOM_SWEEP_SECONDS': '1',
      'BOT_TAKEOVER_SECONDS': '1',
      // relais TURN fictif : vérifie qu'il est transmis aux clients
      'TURN_URLS': 'turn:turn.example.org:3478, turns:turn.example.org:443',
      'TURN_USERNAME': 'u304',
      'TURN_CREDENTIAL': 'p304',
    });
    final ready = Completer<void>();
    server.stdout.transform(utf8.decoder).listen((l) {
      if (l.contains('304 server') && !ready.isCompleted) ready.complete();
    });
    await ready.future.timeout(const Duration(seconds: 90));
  });
  tearDownAll(() => server.kill());

  test('code inconnu -> tableNotFound', () async {
    final c = await C.open();
    c.send({'t': 'join', 'code': 'ZZZZ', 'name': 'x'});
    final e = await c.next('error');
    expect(e['code'], 'tableNotFound');
    await c.ws.close();
  });

  test('action sans table -> sessionExpired ; jeton inconnu idem', () async {
    final c = await C.open();
    c.send({'t': 'start'});
    expect((await c.next('error'))['code'], 'sessionExpired');
    c.send({'t': 'reconnect', 'token': 'nope'});
    expect((await c.next('error'))['code'], 'sessionExpired');
    await c.ws.close();
  });

  test('4 humains max -> tableFull ; ordre des sièges 0, 2, 1, 3', () async {
    final host = await C.open();
    host.send({'t': 'create', 'name': 'h'});
    final j = await host.next('joined');
    final code = j['code'];
    final seats = <int>[j['seat'] as int];
    final others = <C>[];
    for (var i = 0; i < 3; i++) {
      final c = await C.open();
      c.send({'t': 'join', 'code': code, 'name': 'p$i'});
      seats.add((await c.next('joined'))['seat'] as int);
      others.add(c);
    }
    expect(seats, [0, 2, 1, 3]);
    final extra = await C.open();
    extra.send({'t': 'join', 'code': code, 'name': 'trop'});
    expect((await extra.next('error'))['code'], 'tableFull');
    for (final c in [host, ...others, extra]) {
      await c.ws.close();
    }
  });

  test('coup hors tour -> notYourTurn ; coup invalide -> invalidAction',
      () async {
    final a = await C.open();
    a.send({'t': 'create', 'name': 'a'});
    final code = (await a.next('joined'))['code'];
    final b = await C.open();
    b.send({'t': 'join', 'code': code, 'name': 'b'});
    await b.next('joined');
    a.send({'t': 'start'});
    // attend que ce soit le tour de a ou de b (les bots jouent entre-temps)
    late C mover, other;
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (a.lastView?['yourTurn'] == true) {
        mover = a;
        other = b;
        break;
      }
      if (b.lastView?['yourTurn'] == true) {
        mover = b;
        other = a;
        break;
      }
      if (i == 199) fail('aucun tour humain');
    }
    other.send({
      't': 'action',
      'action': {'type': 'bid', 'value': null}
    });
    expect((await other.next('error'))['code'], 'notYourTurn');
    mover.send({
      't': 'action',
      'action': {'type': 'inconnue'}
    });
    expect((await mover.next('error'))['code'], 'invalidAction');
    await a.ws.close();
    await b.ws.close();
  });

  test('table abandonnée supprimée après le délai (ROOM_TTL_SECONDS)',
      () async {
    final a = await C.open();
    a.send({'t': 'create', 'name': 'a'});
    final code = (await a.next('joined'))['code'];
    await a.ws.close(); // plus personne de connecté
    await Future<void>.delayed(const Duration(seconds: 4));
    final b = await C.open();
    b.send({'t': 'join', 'code': code, 'name': 'b'});
    expect((await b.next('error'))['code'], 'tableNotFound');
    await b.ws.close();
  });

  test('table active conservée tant qu\'un joueur est connecté', () async {
    final a = await C.open();
    a.send({'t': 'create', 'name': 'a'});
    final code = (await a.next('joined'))['code'];
    await Future<void>.delayed(const Duration(seconds: 4));
    final b = await C.open();
    b.send({'t': 'join', 'code': code, 'name': 'b'});
    expect((await b.next('joined'))['seat'], 2);
    await a.ws.close();
    await b.ws.close();
  });

  test('chat : relayé à la table, nettoyé (une ligne, 200 car.), nom joint',
      () async {
    final a = await C.open();
    a.send({'t': 'create', 'name': 'Ana'});
    final code = (await a.next('joined'))['code'];
    final b = await C.open();
    b.send({'t': 'join', 'code': code, 'name': 'Bala'});
    await b.next('joined');
    a.send({'t': 'chat', 'text': '   '}); // vide : ignoré
    a.send({'t': 'chat', 'text': '  vanakkam\n  à   tous ${'x' * 300}'});
    final m = await b.next('chat');
    expect(m['seat'], 0);
    expect(m['name'], 'Ana');
    expect((m['text'] as String).startsWith('vanakkam à tous x'), isTrue);
    expect((m['text'] as String).length, 200);
    expect((await a.next('chat'))['text'], m['text']); // l'auteur le voit aussi
    await a.ws.close();
    await b.ws.close();
  });

  test('table publique : créée et lancée, puis remplie ; jamais une privée',
      () async {
    final priv = await C.open();
    priv.send({'t': 'create', 'name': 'priv'});
    final privCode = (await priv.next('joined'))['code'];
    final players = <C>[];
    final seats = <int>[];
    String? code;
    for (var i = 0; i < 4; i++) {
      final c = await C.open();
      c.send({'t': 'quick', 'name': 'p$i', 'avatar': i});
      final j = await c.next('joined');
      expect(j['public'], isTrue);
      expect(j['code'], isNot(privCode));
      code ??= j['code'] as String;
      expect(j['code'], code, reason: 'même table publique');
      seats.add(j['seat'] as int);
      players.add(c);
    }
    expect(seats, [0, 2, 1, 3]);
    // la partie a démarré sans attendre (bots aux places libres)
    for (var i = 0; i < 50 && players[0].lastView?['started'] != true; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(players[0].lastView!['started'], isTrue);
    expect(players[0].lastView!['public'], isTrue);
    // table pleine : le suivant ouvre une nouvelle table publique
    final extra = await C.open();
    extra.send({'t': 'quick', 'name': 'extra'});
    final j = await extra.next('joined');
    expect(j['code'], isNot(code));
    expect(j['seat'], 0);
    for (final c in [priv, ...players, extra]) {
      await c.ws.close();
    }
  });

  test('table publique : réactions seulement, ni texte libre ni vocal',
      () async {
    final a = await C.open();
    a.send({'t': 'quick', 'name': 'a'});
    final code = (await a.next('joined'))['code'];
    final b = await C.open();
    b.send({'t': 'quick', 'name': 'b'});
    expect((await b.next('joined'))['code'], code);
    a.send({'t': 'chat', 'text': 'mon numéro : 06…'}); // texte libre : ignoré
    a.send({'t': 'voice', 'on': true}); // vocal : ignoré
    a.send({'t': 'chat', 'text': ':r:wellPlayed'});
    final m = await b.next('chat');
    expect(m['text'], ':r:wellPlayed',
        reason: 'le texte libre n\'est pas relayé');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final p = b.lastView!['players'] as List;
    expect((p[0] as Map)['voice'], isFalse);
    await a.ws.close();
    await b.ws.close();
  });

  test('messages piégés : le serveur ne tombe pas', () async {
    final c = await C.open();
    c.ws.add([1, 2, 3]); // trame binaire : ignorée
    for (final m in [
      {'t': 'watch', 'code': 5},
      {'t': 'join', 'code': 42, 'name': 'x'},
      {'t': 'reconnect', 'token': 7},
      {'t': 'create', 'name': 12345, 'avatar': 'x'},
    ]) {
      c.send(m);
    }
    c.send({'t': 'action', 'action': null});
    c.send({
      't': 'action',
      'action': {'type': 'play', 'card': 'pas une carte'}
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // toujours vivant : une nouvelle connexion crée une table
    final d = await C.open();
    d.send({'t': 'create', 'name': 'ok'});
    expect((await d.next('joined'))['seat'], 0);
    final h = await HttpClient()
        .getUrl(Uri.parse('http://127.0.0.1:$port/health'))
        .then((r) => r.close());
    expect(h.statusCode, 200);
    await c.ws.close();
    await d.ws.close();
  });

  test('une connexion = une seule place (pas deux mains)', () async {
    final a = await C.open();
    a.send({'t': 'quick', 'name': 'a'});
    final code = (await a.next('joined'))['code'];
    final cheat = await C.open();
    cheat.send({'t': 'quick', 'name': 'c'});
    expect((await cheat.next('joined'))['code'], code);
    for (final m in [
      {'t': 'quick', 'name': 'c'},
      {'t': 'join', 'code': code, 'name': 'c'},
      {'t': 'create', 'name': 'c'},
      {'t': 'watch', 'code': code},
    ]) {
      cheat.send(m);
      expect((await cheat.next('error'))['code'], 'invalidAction');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final p = a.lastView!['players'] as List;
    expect(p.where((x) => (x as Map)['bot'] == false).length, 2);
    await a.ws.close();
    await cheat.ws.close();
  });

  test('table publique : prénoms masqués, place d\'un absent reprise',
      () async {
    final players = <C>[];
    String? code;
    for (var i = 0; i < 4; i++) {
      final c = await C.open();
      c.send({'t': 'quick', 'name': 'P\u202Ei$i'});
      final j = await c.next('joined');
      code ??= j['code'] as String;
      expect(j['code'], code);
      players.add(c);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final p in players[0].lastView!['players'] as List) {
      expect((p as Map)['name'], '', reason: 'pas de prénom entre inconnus');
    }
    // le 4e ferme l'appli sans « Quitter » : absent après 1 s (bot)
    await players[3].ws.close();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final n = await C.open();
    n.send({'t': 'quick', 'name': 'nouveau'});
    final j = await n.next('joined');
    expect(j['code'], code, reason: 'la place abandonnée est reprise');
    expect(j['seat'], 3);
    for (final c in [...players.take(3), n]) {
      await c.ws.close();
    }
  });

  test('table publique sans joueur connecté : pas proposée', () async {
    final a = await C.open();
    a.send({'t': 'quick', 'name': 'a'});
    final code = (await a.next('joined'))['code'];
    await a.ws.close();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final b = await C.open();
    b.send({'t': 'quick', 'name': 'b'});
    final j = await b.next('joined');
    expect(j['code'], isNot(code));
    expect(j['seat'], 0);
    await b.ws.close();
  });

  test('prénom et avatar nettoyés et transmis aux autres', () async {
    final a = await C.open();
    a.send({
      't': 'create',
      'name': '  Kamal\n   Raj ${'x' * 50}',
      'avatar': 3,
    });
    final code = (await a.next('joined'))['code'];
    final b = await C.open();
    b.send({'t': 'join', 'code': code, 'name': '   ', 'avatar': 99});
    await b.next('joined');
    for (var i = 0; i < 30; i++) {
      final p = b.lastView?['players'] as List?;
      if (p != null && (p[2] as Map)['bot'] == false) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final p = b.lastView!['players'] as List;
    expect((p[0] as Map)['name'], 'Kamal Raj ${'x' * 14}');
    expect((p[0] as Map)['avatar'], 3);
    expect((p[2] as Map)['name'], 'Joueur');
    expect((p[2] as Map)['avatar'], isNull);
    expect((p[1] as Map)['avatar'], isNull); // bot
    await a.ws.close();
    await b.ws.close();
  });

  test('spectateur : aucune main visible, ne joue pas, voit le chat', () async {
    final unknown = await C.open();
    unknown.send({'t': 'watch', 'code': 'ZZZZ'});
    expect((await unknown.next('error'))['code'], 'tableNotFound');
    await unknown.ws.close();

    final a = await C.open();
    a.send({'t': 'create', 'name': 'a'});
    final code = (await a.next('joined'))['code'];
    a.send({'t': 'start'});
    final s = await C.open();
    s.send({'t': 'watch', 'code': (code as String).toLowerCase()});
    expect((await s.next('watching'))['code'], code);
    // pendant ~4 s de jeu : jamais une carte en main ni un atout fermé
    var views = 0;
    final end = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final v = s.lastView;
      if (v == null) continue;
      views++;
      for (final h in v['hands'] as List) {
        expect(h, isA<Map>(), reason: 'main visible par le spectateur');
      }
      if (v['trumpOpen'] != true) expect(v['trumpSuit'], isNull);
      expect(v['yourTurn'], isFalse);
      expect(v['playable'], isEmpty);
      for (final p in v['currentTrick'] as List) {
        if ((p as Map)['faceDown'] == true && v['trumpOpen'] != true) {
          expect(p['card'], isNull);
        }
      }
    }
    expect(views, greaterThan(10));
    expect(a.lastView!['spectators'], 1);
    // une action du spectateur est ignorée ; le chat des joueurs lui arrive
    s.send({
      't': 'action',
      'action': {'type': 'bid', 'value': null}
    });
    s.send({'t': 'chat', 'text': 'je triche'});
    a.send({'t': 'chat', 'text': 'bonjour'});
    expect((await s.next('chat'))['text'], 'bonjour');
    expect((await a.next('chat'))['text'], 'bonjour',
        reason: 'le message du spectateur n\'est pas relayé');
    await s.ws.close();
    for (var i = 0; i < 30 && a.lastView!['spectators'] != 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(a.lastView!['spectators'], 0);
    await a.ws.close();
  });

  /// Attend un événement du client réseau de l'app.
  Future<Map> event(GameClient c, String t) => c.events
      .firstWhere((m) => m['t'] == t)
      .timeout(const Duration(seconds: 15));

  test('reconnexion automatique après coupure : même siège, état reçu',
      () async {
    final c = GameClient('ws://127.0.0.1:$port/ws')..connect();
    final joined = event(c, 'joined');
    c.create('Kamal');
    final j = await joined;
    expect(j['seat'], 0);
    final code = c.code;
    final reco = event(c, 'reconnecting');
    final back = event(c, 'reconnected');
    c.debugDropConnection(); // coupure réseau simulée
    await reco;
    final r = await back;
    expect(r['seat'], 0);
    expect(r['code'], code);
    await c.states.first.timeout(const Duration(seconds: 5)); // l'état revient
    c.dispose();
  });

  test('reprise par un nouveau client avec le jeton mémorisé', () async {
    final a = GameClient('ws://127.0.0.1:$port/ws')..connect();
    final joined = event(a, 'joined');
    a.create('Kamal');
    await joined;
    final token = a.token!, code = a.code;
    final b = GameClient('ws://127.0.0.1:$port/ws');
    final back = event(b, 'reconnected');
    b.resume(token);
    final r = await back;
    expect(r['code'], code);
    expect(r['seat'], 0);
    a.dispose();
    b.dispose();
  });

  test('jeton périmé : sessionExpired et le client abandonne', () async {
    final c = GameClient('ws://127.0.0.1:$port/ws');
    final err = event(c, 'error');
    c.resume('inconnu');
    expect((await err)['code'], 'sessionExpired');
    expect(c.token, isNull);
    c.dispose();
  });

  /// Joue automatiquement pour [c] (humain de test) : garde sa main, passe
  /// aux enchères, fournit la couleur quand il peut.
  Future<void> autoPlay(C c, bool Function() until,
      {bool Function(Map view)? stopAt, int seconds = 40}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    var lastSent = -1;
    while (!until()) {
      if (DateTime.now().isAfter(end)) fail('la partie n\'avance pas');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final v = c.lastView;
      if (v == null || v['yourTurn'] != true) continue;
      if (stopAt != null && stopAt(v)) return; // à ce joueur d'agir lui-même
      // une réponse par état reçu (une signature phase/pli se répète après
      // une donne où tout le monde passe : la partie restait bloquée)
      if (c.states == lastSent) continue;
      lastSent = c.states;
      Map action;
      switch (v['phase']) {
        case 'redeal':
          action = {'type': 'redeal', 'keep': true};
        case 'bid1':
          action = {'type': 'bid', 'value': null};
        case 'bid2':
          action = {'type': 'bid2', 'value': null};
        case 'play':
          final hand =
              ((v['hands'] as List)[v['you'] ?? 0] as List).cast<Map>();
          final trick = (v['currentTrick'] as List);
          final led = v['ledSuit'];
          final follow = trick.isEmpty
              ? <Map>[]
              : hand.where((x) => x['s'] == led).toList();
          action = {
            'type': 'play',
            'card': (follow.isNotEmpty ? follow : hand).first
          };
        default:
          continue;
      }
      c.send({'t': 'action', 'action': action});
    }
  }

  test(
      'joueur parti (« leave ») : un bot reprend son siège, libre pour un autre',
      () async {
    final a = await C.open();
    a.send({'t': 'create', 'name': 'Ana'});
    final code = (await a.next('joined'))['code'];
    final b = await C.open();
    b.send({'t': 'join', 'code': code, 'name': 'Bala'});
    expect((await b.next('joined'))['seat'], 2);
    b.send({'t': 'leave'});
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final p = (a.lastView?['players'] as List?)?[2] as Map?;
      if (p?['bot'] == true) break;
      if (i == 49) fail('le siège 2 n\'est pas redevenu un bot');
    }
    // un autre ami prend la place libérée
    final c = await C.open();
    c.send({'t': 'join', 'code': code, 'name': 'Chitra'});
    expect((await c.next('joined'))['seat'], 2);
    await a.ws.close();
    await b.ws.close();
    await c.ws.close();
  });

  test('joueur déconnecté : un bot joue à sa place, il reprend en revenant',
      () async {
    final a = await C.open();
    a.send({'t': 'create', 'name': 'Ana'});
    final code = (await a.next('joined'))['code'];
    final b = await C.open();
    b.send({'t': 'join', 'code': code, 'name': 'Bala'});
    final token = (await b.next('joined'))['token'];
    await b.ws.close(); // coupure (téléphone en veille, réseau perdu…)
    a.send({'t': 'start'});
    // la partie avance malgré l'absence de Bala (BOT_TAKEOVER_SECONDS=1)
    var sawAway = false;
    await autoPlay(a, () {
      final p = (a.lastView?['players'] as List?)?[2] as Map?;
      if (p?['away'] == true) sawAway = true;
      return ((a.lastView?['tricksPlayed'] as int?) ?? 0) >= 1;
    });
    expect(sawAway, isTrue, reason: 'Bala affiché comme remplacé par un bot');
    // Bala revient avec son jeton : il reprend son siège
    final b2 = await C.open();
    b2.send({'t': 'reconnect', 'token': token});
    expect((await b2.next('joined'))['seat'], 2);
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final p = (a.lastView?['players'] as List?)?[2] as Map?;
      if (p?['away'] == false && p?['online'] == true) break;
      if (i == 49) fail('Bala n\'a pas repris sa place');
    }
    await a.ws.close();
    await b2.ws.close();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('table sans joueur connecté : les bots ne jouent pas seuls', () async {
    final a = await C.open();
    a.send({'t': 'create', 'name': 'Ana'});
    final j = await a.next('joined');
    a.send({'t': 'start'});
    // coupure pendant SON tour : la boucle du serveur l'attend
    for (var i = 0; i < 200 && a.lastView?['yourTurn'] != true; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(a.lastView?['yourTurn'], isTrue);
    String sig(Map? v) => [
          v?['phase'],
          v?['turn'],
          v?['bidTurn'],
          v?['bid2Turn'],
          (v?['currentTrick'] as List?)?.length,
          v?['tricksPlayed'],
        ].join('/');
    final before = sig(a.lastView);
    await a.ws.close();
    // > délai de remplacement (1 s), < suppression de la table (2 s)
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final a2 = await C.open();
    a2.send({'t': 'reconnect', 'token': j['token']});
    await a2.next('joined');
    for (var i = 0; i < 30 && a2.lastView == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(sig(a2.lastView), before,
        reason: 'aucun coup joué pendant que personne n\'était là');
    await a2.ws.close();
  });

  test('chat vocal : serveurs ICE, présence « voice », signalisation relayée',
      () async {
    final a = await C.open();
    a.send({'t': 'create', 'name': 'Ana'});
    final ja = await a.next('joined');
    // STUN public par défaut + relais TURN des variables d'environnement
    final ice = (ja['ice'] as List).cast<Map>();
    expect(ice.first['urls'], ['stun:stun.l.google.com:19302']);
    expect(ice[1]['urls'],
        ['turn:turn.example.org:3478', 'turns:turn.example.org:443']);
    expect(ice[1]['username'], 'u304');
    expect(ice[1]['credential'], 'p304');
    final code = ja['code'];
    final b = await C.open();
    b.send({'t': 'join', 'code': code, 'name': 'Bala'});
    expect((await b.next('joined'))['seat'], 2);

    Future<void> until(bool Function() ok, String why) async {
      for (var i = 0; i < 50 && !ok(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ok(), isTrue, reason: why);
    }

    bool voiceOf(C c, int seat) =>
        ((c.lastView?['players'] as List?)?[seat] as Map?)?['voice'] == true;

    // Ana seule dans le vocal : sa signalisation vers Bala n'est pas relayée
    a.send({'t': 'voice', 'on': true});
    await until(() => voiceOf(b, 0), 'Bala voit Ana dans le vocal');
    a.send({
      't': 'rtc',
      'to': 2,
      'data': {'type': 'offer', 'sdp': 'x'}
    });
    // Bala rejoint : l'offre d'Ana lui parvient avec l'expéditeur
    b.send({'t': 'voice', 'on': true});
    await until(() => voiceOf(a, 2), 'Ana voit Bala dans le vocal');
    a.send({
      't': 'rtc',
      'to': 2,
      'data': {'type': 'offer', 'sdp': 'v=0 offre'}
    });
    final got = await b.next('rtc');
    expect(got['from'], 0);
    expect((got['data'] as Map)['sdp'], 'v=0 offre',
        reason: 'la 1re offre (Bala hors vocal) a été ignorée');
    // réponse dans l'autre sens ; destinataires invalides ignorés
    b.send({'t': 'rtc', 'to': 9, 'data': {}});
    b.send({'t': 'rtc', 'to': 2, 'data': {}}); // à soi-même
    b.send({'t': 'rtc', 'to': 1, 'data': {}}); // un bot
    b.send({
      't': 'rtc',
      'to': 0,
      'data': {'type': 'answer', 'sdp': 'v=0 reponse'}
    });
    final ans = await a.next('rtc');
    expect(ans['from'], 2);
    expect((ans['data'] as Map)['type'], 'answer');
    // Bala coupe son micro : Ana le voit (et le revoit ouvert ensuite)
    bool mutedOf(C c, int seat) =>
        ((c.lastView?['players'] as List?)?[seat] as Map?)?['muted'] == true;
    expect(mutedOf(a, 2), isFalse);
    b.send({'t': 'voice', 'on': true, 'muted': true});
    await until(() => mutedOf(a, 2), 'Ana voit le micro coupé de Bala');
    expect(voiceOf(a, 2), isTrue,
        reason: 'micro coupé = toujours dans le vocal');
    b.send({'t': 'voice', 'on': true, 'muted': false});
    await until(() => !mutedOf(a, 2), 'micro de Bala rétabli');
    // Bala se déconnecte : il n'est plus affiché dans le vocal
    await b.ws.close();
    await until(() => !voiceOf(a, 2), 'Bala retiré du vocal');
    await a.ws.close();
  });

  test('Caps : annonce acceptée à l\'entame, refusée sinon, visible de tous',
      () async {
    final a = await C.open();
    a.send({'t': 'create', 'name': 'Ana'});
    await a.next('joined');
    a.send({'t': 'start'});
    // jusqu'à ce qu'Ana puisse annoncer (elle entame, son équipe a tout pris)
    var reached = false;
    // (Ana entame avec son équipe sans pli perdu : ~1 donne sur 3 ou 4,
    // ~15 s par donne avec les pauses du serveur)
    await autoPlay(a, () => reached, seconds: 200, stopAt: (v) {
      if (v['canCaps'] == true) reached = true;
      return reached;
    });
    expect(a.lastView?['capsBy'], isNull);
    a.send({
      't': 'action',
      'action': {'type': 'caps'}
    });
    for (var i = 0; i < 50 && a.lastView?['capsBy'] == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(a.lastView?['capsBy'], 0, reason: 'annonce enregistrée');
    expect(a.lastView?['canCaps'], isFalse, reason: 'une seule annonce');
    // une 2e annonce est refusée
    a.send({
      't': 'action',
      'action': {'type': 'caps'}
    });
    expect((await a.next('error'))['code'], 'invalidAction');
    await a.ws.close();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
