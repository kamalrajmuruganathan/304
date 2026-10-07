// ============================================================================
// Serveur 304 — AUTORITATIF, réutilise lib/engine + lib/ai (aucune dépendance
// externe : dart:io suffit).  SQUELETTE fonctionnel à lancer et itérer.
//
//   dart run bin/server.dart            # écoute ws://localhost:8080/ws
//   (déploiement cible : conteneur -> Cloud Run)
//
// Le serveur détient l'unique instance de règles. Les clients envoient des
// ACTIONS ; le serveur valide, applique, puis diffuse à chacun SA vue rédigée
// (engine.viewFor(seat)). Voir docs/ARCHITECTURE.md et docs/PROTOCOL.md.
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:game304/engine/engine.dart';
import 'package:game304/ai/bots.dart';

final Map<String, Room> rooms = {};

/// Erreur envoyée au client : `code` stable (traduit par l'app), `msg` lisible
/// (journaux, anciens clients). Codes : notYourTurn, invalidAction,
/// tableNotFound, tableFull, sessionExpired.
Map<String, String> err(String code, String msg) =>
    {'t': 'error', 'code': code, 'msg': msg};

/// Une table sans aucun joueur connecté depuis [roomTtl] est supprimée
/// (sinon la mémoire grossit indéfiniment). Réglable pour les tests.
final Duration roomTtl = Duration(
    seconds: int.parse(Platform.environment['ROOM_TTL_SECONDS'] ?? '1800'));
final Duration sweepEvery = Duration(
    seconds: int.parse(Platform.environment['ROOM_SWEEP_SECONDS'] ?? '300'));

void sweepRooms() {
  final now = DateTime.now();
  rooms.removeWhere((code, r) {
    if (r.seats.any((s) => s.connected)) {
      r.lastSeen = now;
      return false;
    }
    return now.difference(r.lastSeen) > roomTtl;
  });
}

final Random _rng = Random();

String genCode() {
  const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(4, (_) => abc[_rng.nextInt(abc.length)]).join();
}

class Seat {
  String? token;
  String name;
  bool isBot;
  WebSocket? socket;
  Seat({this.name = 'Bot', this.isBot = true});
  bool get isHuman => !isBot;
  bool get connected => socket != null && socket!.readyState == WebSocket.open;
}

class Room {
  final String code;
  final Engine engine = Engine();
  final List<Seat> seats = [
    for (var i = 0; i < 4; i++) Seat(name: 'Bot ${i + 1}')
  ];
  bool started = false;
  bool _looping = false;
  DateTime lastSeen = DateTime.now(); // dernier instant avec un joueur connecté

  Room(this.code);

  int? seatOfSocket(WebSocket ws) {
    for (var i = 0; i < 4; i++) {
      if (seats[i].socket == ws) return i;
    }
    return null;
  }

  /// Siège libre pour un humain : d'abord le partenaire du créateur (Nord),
  /// puis Est, puis Ouest — deux amis jouent ainsi ensemble.
  int? freeSeat() {
    for (final i in const [0, 2, 1, 3]) {
      if (!seats[i].isHuman) return i;
    }
    return null;
  }

  void broadcast() {
    for (var i = 0; i < 4; i++) {
      final s = seats[i];
      if (s.isHuman && s.connected) {
        final view = engine.viewFor(i)
          ..['code'] = code
          ..['started'] = started
          ..['players'] = [
            for (final p in seats)
              {'name': p.name, 'bot': p.isBot, 'online': p.connected}
          ];
        s.socket!.add(jsonEncode({'t': 'state', 'you': i, 'view': view}));
      }
    }
  }

  void begin() {
    started = true;
    engine.newHand();
    loop();
  }

  // partie finie ET boucle arrêtée (évite une double donne pendant la pause)
  bool get gameOver =>
      !_looping &&
      engine.phase == 'scored' &&
      (engine.tokens['NS']! <= 0 || engine.tokens['EW']! <= 0);

  void restart() {
    engine.tokens = {'NS': 11, 'EW': 11};
    engine.newHand();
    loop();
  }

  /// Nombre de plis déjà montrés : après chaque pli terminé, courte pause
  /// pour que les joueurs voient les 4 cartes avant l'entame suivante.
  int _shownTricks = 0;

  /// Fait avancer la partie tant qu'aucune décision HUMAINE n'est requise.
  Future<void> loop() async {
    if (_looping) return;
    _looping = true;
    try {
      while (true) {
        broadcast();
        final phase = engine.phase;

        if (phase == 'spoilt') {
          await Future.delayed(const Duration(milliseconds: 900));
          engine.newHand();
          continue;
        }
        if (phase == 'allpass') {
          await Future.delayed(const Duration(milliseconds: 700));
          engine.newHand();
          continue;
        }
        if (phase == 'scored') {
          // le temps de lire le résultat affiché par les clients
          // récapitulatif de la donne affiché chez les joueurs
          await Future.delayed(const Duration(milliseconds: 6000));
          if (engine.tokens['NS']! <= 0 || engine.tokens['EW']! <= 0) {
            // partie terminée : on stoppe (l'hôte relancera)
            return;
          }
          engine.newHand();
          continue;
        }

        if (phase == 'play') {
          if (engine.tricks.length > _shownTricks) {
            _shownTricks = engine.tricks.length;
            await Future.delayed(const Duration(milliseconds: 1000));
            continue;
          }
        } else {
          _shownTricks = 0;
        }

        final actor = _actorSeat();
        if (actor == null) return; // rien à faire (ne devrait pas arriver)

        // coup forcé : dernier pli, le preneur n'a que l'atout
        if (phase == 'play' &&
            engine.hands[actor].isEmpty &&
            actor == engine.trumpMaker &&
            engine.indicatorOnTable) {
          engine.playLastIndicator(actor);
          await Future.delayed(const Duration(milliseconds: 400));
          continue;
        }

        if (seats[actor].isHuman) {
          // on attend l'action du client (reprise via applyAction)
          return;
        }

        // --- c'est un bot : le serveur joue pour lui ---
        _botMove(actor);
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      _looping = false;
    }
  }

  int? _actorSeat() {
    switch (engine.phase) {
      case 'redeal':
        return engine.eldest;
      case 'chooseTrump1':
        return engine.trumpMaker1;
      case 'chooseTrump2':
      case 'chooseTrumpPCC':
      case 'preplay':
        return engine.trumpMaker;
      default:
        return engine.seatToAct;
    }
  }

  void _botMove(int seat) {
    final e = engine;
    switch (e.phase) {
      case 'redeal':
        if (e.canRedeal()) {
          e.redeal();
        } else {
          e.startBidding1();
        }
        break;
      case 'bid1':
        e.placeBid(botBid(e, seat));
        break;
      case 'chooseTrump1':
        e.chooseTrump1(botChooseTrump(e, seat));
        break;
      case 'bid2':
        e.placeBid2(botBid2(e, seat));
        break;
      case 'chooseTrump2':
        e.chooseTrump2(botChooseTrump(e, seat));
        break;
      case 'chooseTrumpPCC':
        e.chooseTrumpPCC(botChooseTrump(e, seat));
        break;
      case 'preplay':
        e.startPlayClosed(); // les bots jouent fermé
        break;
      case 'play':
        final c = botPlay(e, seat);
        if (c is PlayIndicator) {
          e.playIndicatorToCut(seat);
        } else {
          e.playCard(seat, c as Card);
        }
        break;
    }
  }

  /// Applique une action reçue d'un client humain, puis relance la boucle.
  void applyAction(int seat, Map action) {
    final e = engine;
    if (_actorSeat() != seat) {
      _send(seat, err('notYourTurn', 'Ce n\'est pas votre tour.'));
      return;
    }
    final type = action['type'];
    Card card() => Engine.cardFromJson(action['card'] as Map);
    try {
      switch (type) {
        case 'redeal':
          (action['keep'] == true) ? e.startBidding1() : e.redeal();
          break;
        case 'bid':
          e.placeBid(action['value'] as int?);
          break;
        case 'chooseTrump1':
          e.chooseTrump1(card());
          break;
        case 'bid2':
          e.placeBid2(action['value']); // int | 'PCC' | null
          break;
        case 'chooseTrump2':
          e.chooseTrump2(card());
          break;
        case 'chooseTrumpPCC':
          e.chooseTrumpPCC(card());
          break;
        case 'open':
          (action['open'] == true) ? e.startPlayOpen() : e.startPlayClosed();
          break;
        case 'play':
          // le serveur fait autorité : un coup illégal envoyé par un client
          // (couleur non fournie, coupe à l'atout posé injustifiée) est rejeté
          if (action['indicator'] == true) {
            if (!e.canCutWithIndicator(seat)) {
              throw StateError('coupe à l\'atout impossible');
            }
            e.playIndicatorToCut(seat);
          } else {
            final c = card();
            if (!e
                .playableCards(seat)
                .any((x) => x.suit == c.suit && x.rank == c.rank)) {
              throw StateError('carte non jouable');
            }
            e.playCard(seat, c);
          }
          break;
        default:
          _send(seat, err('invalidAction', 'Action inconnue: $type'));
          return;
      }
    } catch (e) {
      _send(seat, err('invalidAction', 'Action invalide: $e'));
      return;
    }
    loop();
  }

  void _send(int seat, Map msg) {
    final s = seats[seat];
    if (s.connected) s.socket!.add(jsonEncode(msg));
  }
}

// ---------------------------------------------------------------------------

void handleMessage(WebSocket ws, String data) {
  Map msg;
  try {
    msg = jsonDecode(data) as Map;
  } catch (_) {
    ws.add(jsonEncode(err('invalidAction', 'JSON invalide')));
    return;
  }
  final t = msg['t'];

  if (t == 'create') {
    final code = genCode();
    final room = Room(code);
    rooms[code] = room;
    const seat = 0;
    room.seats[seat]
      ..isBot = false
      ..name = (msg['name'] as String?) ?? 'Joueur'
      ..socket = ws
      ..token = '$code:$seat:${_rng.nextInt(1 << 31)}';
    ws.add(jsonEncode({
      't': 'joined',
      'code': code,
      'seat': seat,
      'token': room.seats[seat].token
    }));
    room.broadcast();
    return;
  }

  if (t == 'join') {
    final code = (msg['code'] as String?)?.toUpperCase();
    final room = rooms[code];
    if (room == null) {
      ws.add(jsonEncode(err('tableNotFound', 'Table introuvable')));
      return;
    }
    final seat = room.freeSeat();
    if (seat == null) {
      ws.add(jsonEncode(err('tableFull', 'Table complète')));
      return;
    }
    room.seats[seat]
      ..isBot = false
      ..name = (msg['name'] as String?) ?? 'Joueur'
      ..socket = ws
      ..token = '$code:$seat:${_rng.nextInt(1 << 31)}';
    ws.add(jsonEncode({
      't': 'joined',
      'code': code,
      'seat': seat,
      'token': room.seats[seat].token
    }));
    room.broadcast();
    return;
  }

  if (t == 'reconnect') {
    final token = msg['token'] as String?;
    for (final room in rooms.values) {
      for (var i = 0; i < 4; i++) {
        if (room.seats[i].token == token) {
          room.seats[i].socket = ws;
          ws.add(jsonEncode(
              {'t': 'joined', 'code': room.code, 'seat': i, 'token': token}));
          room.broadcast();
          return;
        }
      }
    }
    ws.add(jsonEncode(err('sessionExpired', 'Token inconnu')));
    return;
  }

  // à partir d'ici il faut être assis quelque part
  Room? room;
  int? seat;
  for (final r in rooms.values) {
    final s = r.seatOfSocket(ws);
    if (s != null) {
      room = r;
      seat = s;
      break;
    }
  }
  if (room == null || seat == null) {
    ws.add(jsonEncode(err('sessionExpired', 'Pas de table')));
    return;
  }

  if (t == 'start') {
    if (!room.started) {
      room.begin();
    } else if (seat == 0 && room.gameOver) {
      room.restart(); // l'hôte relance une partie après la fin
    }
    return;
  }
  if (t == 'action') {
    room.applyAction(seat, msg['action'] as Map);
    return;
  }
  if (t == 'chat') {
    // texte nettoyé : une ligne, 200 caractères au plus, jamais vide
    final text = '${msg['text'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return;
    final out = jsonEncode({
      't': 'chat',
      'seat': seat,
      'name': room.seats[seat].name,
      'text': text.length > 200 ? text.substring(0, 200) : text,
    });
    for (final s in room.seats) {
      if (s.connected) s.socket!.add(out);
    }
    return;
  }
}

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('304 server — ws://localhost:$port/ws');
  Timer.periodic(sweepEvery, (_) => sweepRooms());
  await for (final req in server) {
    if (req.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen(
        (data) => handleMessage(ws, data as String),
        onDone: () {
          // on garde le siège (reconnexion possible via token) ; on détache la socket
          for (final r in rooms.values) {
            final s = r.seatOfSocket(ws);
            if (s != null) {
              r.seats[s].socket = null;
              r.lastSeen = DateTime.now();
            }
          }
        },
        onError: (_) {},
      );
    } else if (req.uri.path == '/health') {
      req.response
        ..statusCode = 200
        ..write('ok')
        ..close();
    } else {
      req.response
        ..statusCode = 404
        ..close();
    }
  }
}
