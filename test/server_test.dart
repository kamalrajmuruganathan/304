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
    expect(voiceOf(a, 2), isTrue, reason: 'micro coupé = toujours dans le vocal');
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
