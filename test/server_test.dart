// ============================================================================
// Serveur (bin/server.dart) testé par de vraies connexions WebSocket :
// codes d'erreur traduisibles, table complète, coup hors tour, et nettoyage
// des tables abandonnées (délai réduit à 2 s via ROOM_TTL_SECONDS).
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

late Process server;
late int port;

/// Client minimal : file des messages reçus, attente par type.
class C {
  final WebSocket ws;
  final _q = <Map>[];
  Map? lastView; // dernière vue reçue (message state)
  final _waiters = <Completer<void>>[];
  C._(this.ws) {
    ws.listen((d) {
      final m = jsonDecode(d as String) as Map;
      if (m['t'] == 'state') {
        lastView = m['view'] as Map;
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
}
