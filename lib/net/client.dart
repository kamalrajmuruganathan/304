// ============================================================================
// Client réseau — parle au serveur autoritatif (voir docs/PROTOCOL.md).
// Cross-platform (mobile + web) via web_socket_channel.
// L'UI écoute `states` (l'état rédigé du jeu) et `events` (joined/erreurs/chat),
// et appelle les méthodes d'action (bid, play, …).
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../engine/engine.dart';

/// Main d'un siège : soit tes cartes (en clair), soit juste un compte.
class SeatHand {
  final List<Card>? cards; // non-null uniquement pour TA main
  final int count;
  SeatHand.mine(List<Card> c)
      : cards = c,
        count = c.length;
  SeatHand.hidden(this.count) : cards = null;
  bool get isMine => cards != null;
}

class TrickCardView {
  final int seat;
  final bool faceDown;
  final Card? card; // null si face cachée pour toi
  TrickCardView(this.seat, this.faceDown, this.card);
}

/// Vue du jeu telle que reçue par CE joueur (déjà rédigée par le serveur).
class GameView {
  final int you;
  final String phase;
  final int turn;
  final bool yourTurn;
  final Map<String, int> tokens;
  final int? bid;
  final int? trumpMaker;
  final bool pcc;
  final bool soloMode;
  final int? mutedSeat;
  final bool trumpOpen;
  final String? trumpSuit; // null si caché pour toi
  final String? ledSuit;
  final int trickWinsNS;
  final int trickWinsEW;
  final List<SeatHand> hands;
  final List<TrickCardView> currentTrick;
  final List<TrickCardView>? lastTrick; // dernier pli terminé (null au début)
  final int? lastTrickWinner;
  final Map?
      lastScore; // résultat de la donne (phase scored), calculé par le moteur
  final List<int> legalBids;
  final bool canPCC;
  final String? code;
  final bool started;
  final List<Map> players; // [{name, bot, online}] par siège

  GameView._({
    required this.you,
    required this.phase,
    required this.turn,
    required this.yourTurn,
    required this.tokens,
    required this.bid,
    required this.trumpMaker,
    required this.pcc,
    required this.soloMode,
    required this.mutedSeat,
    required this.trumpOpen,
    required this.trumpSuit,
    required this.ledSuit,
    required this.trickWinsNS,
    required this.trickWinsEW,
    required this.hands,
    required this.currentTrick,
    required this.lastTrick,
    required this.lastTrickWinner,
    required this.lastScore,
    required this.legalBids,
    required this.canPCC,
    required this.code,
    required this.started,
    required this.players,
  });

  bool get gameOver =>
      phase == 'scored' && (tokens['NS']! <= 0 || tokens['EW']! <= 0);

  factory GameView.fromJson(Map j, int you) {
    final hands = (j['hands'] as List).map<SeatHand>((h) {
      if (h is List) {
        return SeatHand.mine(
            h.map((c) => Engine.cardFromJson(c as Map)).toList());
      }
      return SeatHand.hidden((h as Map)['count'] as int);
    }).toList();

    List<TrickCardView> plays(List l) => l.map<TrickCardView>((p) {
          final m = p as Map;
          final c = m['card'];
          return TrickCardView(
            m['seat'] as int,
            m['faceDown'] as bool,
            c == null ? null : Engine.cardFromJson(c as Map),
          );
        }).toList();

    final trick = plays(j['currentTrick'] as List);
    final last = j['lastTrick'] as Map?;

    return GameView._(
      you: you,
      phase: j['phase'] as String,
      turn: (j['turn'] as int?) ?? 0,
      yourTurn: (j['yourTurn'] as bool?) ?? false,
      tokens:
          (j['tokens'] as Map).map((k, v) => MapEntry(k as String, v as int)),
      bid: j['bid'] as int?,
      trumpMaker: j['trumpMaker'] as int?,
      pcc: (j['pcc'] as bool?) ?? false,
      soloMode: (j['soloMode'] as bool?) ?? false,
      mutedSeat: j['mutedSeat'] as int?,
      trumpOpen: (j['trumpOpen'] as bool?) ?? false,
      trumpSuit: j['trumpSuit'] as String?,
      ledSuit: j['ledSuit'] as String?,
      trickWinsNS: (j['trickWinsNS'] as int?) ?? 0,
      trickWinsEW: (j['trickWinsEW'] as int?) ?? 0,
      hands: hands,
      currentTrick: trick,
      lastTrick: last == null ? null : plays(last['cards'] as List),
      lastTrickWinner: last?['winner'] as int?,
      lastScore: j['lastScore'] as Map?,
      legalBids: (j['legalBids'] as List).map((e) => e as int).toList(),
      canPCC: (j['canPCC'] as bool?) ?? false,
      code: j['code'] as String?,
      started: (j['started'] as bool?) ?? false,
      players: ((j['players'] as List?) ?? const []).cast<Map>(),
    );
  }
}

/// Client WebSocket. Exemple :
///   final c = GameClient('wss://mon-serveur/ws')..connect();
///   c.states.listen((v) => setState(...));
///   c.create('Kamal');   // ou c.join('AB2K', 'Kamal');
class GameClient {
  final String url;
  WebSocketChannel? _ch;

  int? seat;
  GameView? last; // dernier état reçu (un écran ouvert après coup ne rate rien)
  String? code;
  String? token;

  final _states = StreamController<GameView>.broadcast();
  final _events = StreamController<Map>.broadcast();
  Stream<GameView> get states => _states.stream;

  /// joined / error / chat / disconnected / reconnecting / reconnected
  Stream<Map> get events => _events.stream;

  bool _disposed = false;
  bool _reconnecting = false; // un `reconnect` est en cours
  int _retry = 0;
  Timer? _retryTimer;

  GameClient(this.url);

  void connect() => _open();

  /// Ouvre une socket. Les messages envoyés avant l'ouverture sont mis en
  /// file par web_socket_channel. Après une coupure, si une place est déjà
  /// acquise (jeton), on la reprend automatiquement.
  void _open() {
    final ch = WebSocketChannel.connect(Uri.parse(url));
    _ch = ch;
    ch.stream.listen(_onMessage,
        onError: (e) {
          // pendant une reconnexion, les échecs sont silencieux (on réessaie)
          if (token == null && !_disposed) {
            _events.add({'t': 'error', 'msg': '$e'});
          }
        },
        onDone: () => _onClosed(ch));
    if (token != null) {
      _reconnecting = true;
      ch.sink.add(jsonEncode({'t': 'reconnect', 'token': token}));
    }
  }

  void _onClosed(WebSocketChannel ch) {
    if (_disposed || !identical(ch, _ch)) return;
    if (token == null) {
      // jamais entré à une table : rien à reprendre
      _events.add({'t': 'disconnected'});
      return;
    }
    _events.add({'t': 'reconnecting'});
    final delay = Duration(seconds: [1, 2, 4, 8][_retry.clamp(0, 3)]);
    _retry++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!_disposed) _open();
    });
  }

  /// Reprend une place connue (jeton mémorisé) sur une nouvelle connexion.
  void resume(String savedToken) {
    token = savedToken;
    _open();
  }

  /// Coupe la connexion comme le ferait le réseau (tests de reconnexion).
  void debugDropConnection() => _ch?.sink.close();

  void _onMessage(dynamic data) {
    final Map m = jsonDecode(data as String) as Map;
    switch (m['t']) {
      case 'joined':
        seat = m['seat'] as int?;
        code = m['code'] as String?;
        token = m['token'] as String?;
        _retry = 0;
        if (_reconnecting) {
          _reconnecting = false;
          _events.add({...m, 't': 'reconnected'});
        } else {
          _events.add(m);
        }
        break;
      case 'state':
        last = GameView.fromJson(m['view'] as Map, m['you'] as int);
        _states.add(last!);
        break;
      case 'error':
        if (_reconnecting && m['code'] == 'sessionExpired') {
          // la table n'existe plus : inutile de réessayer
          _reconnecting = false;
          token = null;
        }
        _events.add(m);
        break;
      default:
        _events.add(m);
    }
  }

  // ---- commandes de table ----
  void create(String name) => _send({'t': 'create', 'name': name});
  void join(String code, String name) =>
      _send({'t': 'join', 'code': code, 'name': name});
  void start() => _send({'t': 'start'});
  void chat(String text) => _send({'t': 'chat', 'text': text});

  // ---- actions de jeu ----
  void bid(int? value) => _action({'type': 'bid', 'value': value});
  void pass() => bid(null);
  void chooseTrump1(Card c) =>
      _action({'type': 'chooseTrump1', 'card': Engine.cardJson(c)});
  void bid2(Object? value) =>
      _action({'type': 'bid2', 'value': value}); // int | 'PCC' | null
  void partnerCloseCaps() => bid2('PCC');
  void chooseTrump2(Card c) =>
      _action({'type': 'chooseTrump2', 'card': Engine.cardJson(c)});
  void chooseTrumpPCC(Card c) =>
      _action({'type': 'chooseTrumpPCC', 'card': Engine.cardJson(c)});
  void setOpen(bool open) => _action({'type': 'open', 'open': open});
  void play(Card c) => _action({'type': 'play', 'card': Engine.cardJson(c)});
  void playIndicator() => _action({'type': 'play', 'indicator': true});
  void redeal({required bool keep}) =>
      _action({'type': 'redeal', 'keep': keep});

  void _action(Map a) => _send({'t': 'action', 'action': a});
  void _send(Map m) => _ch?.sink.add(jsonEncode(m));

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _ch?.sink.close();
    _states.close();
    _events.close();
  }
}
