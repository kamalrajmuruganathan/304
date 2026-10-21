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

/// Un joueur déconnecté depuis ce délai est remplacé par un bot (jusqu'à son
/// retour) : la partie continue au lieu de rester bloquée sur son tour.
final Duration botTakeover = Duration(
    seconds: int.parse(Platform.environment['BOT_TAKEOVER_SECONDS'] ?? '20'));

final Random _rng = Random();

/// Serveurs ICE envoyés aux clients pour le chat vocal (WebRTC pair-à-pair).
/// STUN public gratuit par défaut ; un relais TURN (ex. compte gratuit Metered)
/// se configure par variables d'environnement, sans toucher au code :
///   STUN_URLS        (défaut : stun:stun.l.google.com:19302)
///   TURN_URLS        turn:…:80,turns:…:443 (séparées par des virgules)
///   TURN_USERNAME / TURN_CREDENTIAL
List<Map<String, dynamic>> iceServers([Map<String, String>? env]) {
  env ??= Platform.environment;
  List<String> urls(String? v) => (v ?? '')
      .split(',')
      .map((u) => u.trim())
      .where((u) => u.isNotEmpty)
      .toList();
  final stun = urls(env['STUN_URLS'] ?? 'stun:stun.l.google.com:19302');
  final turn = urls(env['TURN_URLS']);
  return [
    if (stun.isNotEmpty) {'urls': stun},
    if (turn.isNotEmpty)
      {
        'urls': turn,
        'username': env['TURN_USERNAME'] ?? '',
        'credential': env['TURN_CREDENTIAL'] ?? '',
      },
  ];
}

/// Message `joined` (création, arrivée, reconnexion) : place + serveurs ICE.
String joinedMsg(String code, int seat, String? token, {bool public = false}) =>
    jsonEncode({
      't': 'joined',
      'code': code,
      'seat': seat,
      'token': token,
      'public': public,
      'ice': iceServers(),
    });

/// Prénom reçu d'un client : une ligne, 24 caractères au plus, jamais vide.
String cleanName(Object? raw) {
  final t = '${raw ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return 'Joueur';
  final r = t.runes.toList();
  return r.length > 24 ? String.fromCharCodes(r.take(24)) : t;
}

/// Avatar choisi (indice de la liste de l'app, 0 à 11) ; null sinon.
int? cleanAvatar(Object? raw) =>
    raw is int && raw >= 0 && raw < 12 ? raw : null;

/// Spectateurs au plus par table.
const int maxSpectators = 20;

String genCode() {
  const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(4, (_) => abc[_rng.nextInt(abc.length)]).join();
}

class Seat {
  String? token;
  String name;
  bool isBot;
  WebSocket? socket;
  DateTime? offlineSince; // déconnexion du joueur humain (null = en ligne)
  bool voice = false; // a rejoint le chat vocal (micro ouvert ou coupé)
  bool voiceMuted = false; // micro coupé (les autres le voient)
  int? avatar; // avatar choisi dans l'app (indice), null pour un bot
  Seat({this.name = 'Bot', this.isBot = true});
  bool get isHuman => !isBot;
  bool get connected => socket != null && socket!.readyState == WebSocket.open;

  /// Humain absent depuis trop longtemps : un bot joue à sa place.
  bool get away =>
      isHuman &&
      !connected &&
      offlineSince != null &&
      DateTime.now().difference(offlineSince!) >= botTakeover;
}

class Room {
  final String code;

  /// Table publique : ouverte à « Jouer en ligne » (joueurs inconnus), lancée
  /// dès sa création, relancée seule après la fin d'une partie.
  final bool public;

  /// Spectateurs : reçoivent la vue d'un siège vide (aucune main visible).
  final List<WebSocket> spectators = [];
  final Engine engine = Engine();
  final List<Seat> seats = [
    for (var i = 0; i < 4; i++) Seat(name: 'Bot ${i + 1}')
  ];
  bool started = false;
  bool _looping = false;
  DateTime lastSeen = DateTime.now(); // dernier instant avec un joueur connecté

  Room(this.code, {this.public = false});

  /// Joueurs humains connectés.
  int get humansOnline => seats.where((s) => s.isHuman && s.connected).length;

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

  Map<String, dynamic> _decorate(Map<String, dynamic> view) => view
    ..['code'] = code
    ..['started'] = started
    ..['public'] = public
    ..['spectators'] = spectators.length
    ..['players'] = [
      for (final p in seats)
        {
          'name': p.name,
          'bot': p.isBot,
          'online': p.connected,
          'away': p.away,
          'voice': p.voice && p.connected,
          'muted': p.voice && p.voiceMuted,
          'avatar': p.isBot ? null : p.avatar,
        }
    ];

  void broadcast() {
    for (var i = 0; i < 4; i++) {
      final s = seats[i];
      if (s.isHuman && s.connected) {
        final view = _decorate(engine.viewFor(i));
        s.socket!.add(jsonEncode({'t': 'state', 'you': i, 'view': view}));
      }
    }
    // spectateurs : vue d'un siège vide (-1) — aucune main, atout caché
    spectators.removeWhere((w) => w.readyState != WebSocket.open);
    if (spectators.isNotEmpty) {
      final out = jsonEncode({
        't': 'state',
        'you': -1,
        'spectator': true,
        'view': _decorate(engine.viewFor(-1)),
      });
      for (final w in spectators) {
        w.add(out);
      }
    }
  }

  /// Message de chat : à tous les joueurs connectés et aux spectateurs.
  void sendAll(String out) {
    for (final s in seats) {
      if (s.connected) s.socket!.add(out);
    }
    for (final w in spectators) {
      if (w.readyState == WebSocket.open) w.add(out);
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
            // partie terminée : on stoppe (l'hôte relancera) ; table
            // publique : nouvelle partie automatique s'il reste quelqu'un
            if (!public || humansOnline == 0) return;
            engine.tokens = {'NS': 11, 'EW': 11};
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

        if (seats[actor].isHuman && !seats[actor].away) {
          // on attend l'action du client (reprise via applyAction) ; s'il
          // est déconnecté, un minuteur relancera la boucle (bot à sa place)
          return;
        }
        // personne à la table : on ne joue pas la partie tout seul
        if (!seats.any((s) => s.connected)) return;

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
        if (botCallCaps(e, seat)) e.callCaps(seat); // annonce Caps si certain
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
        case 'caps':
          // annonce « Caps » avant d'entamer ; jugée au décompte (Wrong Caps)
          if (!e.callCaps(seat)) throw StateError('Caps impossible');
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

  /// Le joueur du siège [seat] vient de se déconnecter : après [botTakeover],
  /// un bot joue pour lui s'il n'est pas revenu.
  void onDisconnect(int seat) {
    seats[seat]
      ..socket = null
      ..voice = false
      ..offlineSince = DateTime.now();
    lastSeen = DateTime.now();
    broadcast();
    Timer(botTakeover + const Duration(milliseconds: 50), () {
      if (seats[seat].away) {
        broadcast(); // les autres voient « bot » à sa place
        loop();
      }
    });
  }

  /// Le joueur quitte la table pour de bon : son siège redevient un bot
  /// (libre pour un nouvel arrivant), son jeton n'est plus valable.
  void leave(int seat) {
    seats[seat]
      ..isBot = true
      ..name = 'Bot ${seat + 1}'
      ..avatar = null
      ..token = null
      ..socket = null
      ..voice = false
      ..offlineSince = null;
    broadcast();
    loop();
  }

  void _send(int seat, Map msg) {
    final s = seats[seat];
    if (s.connected) s.socket!.add(jsonEncode(msg));
  }
}

// ---------------------------------------------------------------------------

/// Nouvelle table (code libre).
Room newRoom({bool public = false}) {
  var code = genCode();
  while (rooms.containsKey(code)) {
    code = genCode();
  }
  return rooms[code] = Room(code, public: public);
}

/// Assoit un humain au siège [seat] (prénom et avatar nettoyés).
void sit(Room room, int seat, WebSocket ws, Map msg) {
  room.seats[seat]
    ..isBot = false
    ..name = cleanName(msg['name'])
    ..avatar = cleanAvatar(msg['avatar'])
    ..socket = ws
    ..offlineSince = null
    ..voice = false
    ..token = '${room.code}:$seat:${_rng.nextInt(1 << 31)}';
  ws.add(
      joinedMsg(room.code, seat, room.seats[seat].token, public: room.public));
}

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
    final room = newRoom();
    sit(room, 0, ws, msg);
    room.broadcast();
    return;
  }

  if (t == 'quick') {
    // « Jouer en ligne » : une table publique avec une place libre et au
    // moins un joueur connecté (la plus remplie d'abord), sinon une nouvelle
    final open = rooms.values
        .where((r) =>
            r.public &&
            r.freeSeat() != null &&
            r.humansOnline > 0 &&
            !r.gameOver)
        .toList()
      ..sort((a, b) => b.humansOnline - a.humansOnline);
    if (open.isNotEmpty) {
      final room = open.first;
      sit(room, room.freeSeat()!, ws, msg);
      room.broadcast();
      room.loop(); // si la partie attendait ce siège
    } else {
      final room = newRoom(public: true);
      sit(room, 0, ws, msg);
      room.begin(); // les bots tiennent les places libres en attendant
    }
    return;
  }

  if (t == 'watch') {
    final code = (msg['code'] as String?)?.toUpperCase();
    final room = rooms[code];
    if (room == null) {
      ws.add(jsonEncode(err('tableNotFound', 'Table introuvable')));
      return;
    }
    if (room.spectators.length >= maxSpectators) {
      ws.add(jsonEncode(err('tableFull', 'Trop de spectateurs')));
      return;
    }
    if (!room.spectators.contains(ws)) room.spectators.add(ws);
    ws.add(jsonEncode({'t': 'watching', 'code': room.code}));
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
    sit(room, seat, ws, msg);
    room.broadcast();
    if (room.started) room.loop(); // partie en cours : elle reprend
    return;
  }

  if (t == 'reconnect') {
    final token = msg['token'] as String?;
    for (final room in rooms.values) {
      for (var i = 0; i < 4; i++) {
        if (token != null && room.seats[i].token == token) {
          room.seats[i]
            ..socket = ws
            ..voice = false // le client renvoie `voice` s'il parlait
            ..offlineSince = null; // de retour : il rejoue lui-même
          ws.add(joinedMsg(room.code, i, token, public: room.public));
          room.broadcast();
          if (room.started) room.loop(); // reprend si la table attendait
          return;
        }
      }
    }
    ws.add(jsonEncode(err('sessionExpired', 'Token inconnu')));
    return;
  }

  // spectateur : il ne peut que partir
  for (final r in rooms.values) {
    if (r.spectators.contains(ws)) {
      if (t == 'leave') {
        r.spectators.remove(ws);
        r.broadcast();
      }
      return;
    }
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
  if (t == 'leave') {
    room.leave(seat);
    return;
  }
  if (t == 'action') {
    room.applyAction(seat, msg['action'] as Map);
    return;
  }
  if (t == 'voice') {
    // rejoindre / quitter le chat vocal : les autres le voient (players[].voice)
    room.seats[seat]
      ..voice = msg['on'] == true
      ..voiceMuted = msg['muted'] == true;
    room.broadcast();
    return;
  }
  if (t == 'rtc') {
    // signalisation WebRTC (offre / réponse / candidat ICE) relayée telle
    // quelle à UN joueur de la même table ; l'audio, lui, ne passe pas ici
    final to = msg['to'];
    final data = msg['data'];
    if (to is! int || to < 0 || to > 3 || to == seat || data is! Map) return;
    final target = room.seats[to];
    if (!room.seats[seat].voice || !target.voice || !target.connected) return;
    final out = jsonEncode({'t': 'rtc', 'from': seat, 'data': data});
    if (out.length > 20000) return; // une offre SDP fait quelques Ko
    target.socket!.add(out);
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
    room.sendAll(out);
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
          // on garde le siège (reconnexion possible via token) ; on détache
          // la socket ; un bot le remplacera s'il ne revient pas à temps
          for (final r in rooms.values) {
            final s = r.seatOfSocket(ws);
            if (s != null) r.onDisconnect(s);
            if (r.spectators.remove(ws)) r.broadcast();
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
