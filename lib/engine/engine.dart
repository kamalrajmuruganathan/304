// ============================================================================
// 304 — MOTEUR DE RÈGLES (Dart pur, sans dépendance Flutter)
// ----------------------------------------------------------------------------
// Port fidèle du moteur JavaScript validé sur 100 000+ donnes simulées.
// Sièges (ordre de tour ANTI-HORAIRE) : 0=Sud 1=Est 2=Nord 3=Ouest
// Partenaires : {0,2}=NS   {1,3}=EW
// Rang faible->fort : 7 8 Q K 10 A 9 J   |  Valeurs : J30 920 A11 1010 K3 Q2 80 70
// Total du paquet = 304 points.
// ============================================================================
import 'dart:math';

const List<String> kSuits = ['S', 'C', 'D', 'H']; // ♠ ♣ ♦ ♥
const Map<String, String> kSuitSym = {'S': '♠', 'C': '♣', 'D': '♦', 'H': '♥'};
const Map<String, String> kSuitName = {
  'S': 'Pique',
  'C': 'Trèfle',
  'D': 'Carreau',
  'H': 'Cœur'
};
const List<String> kRanks = [
  '7',
  '8',
  'Q',
  'K',
  '10',
  'A',
  '9',
  'J'
]; // faible->fort
const Map<String, int> kValue = {
  'J': 30,
  '9': 20,
  'A': 11,
  '10': 10,
  'K': 3,
  'Q': 2,
  '8': 0,
  '7': 0
};
const List<String> kSeatName = ['Sud', 'Est', 'Nord', 'Ouest'];

final Map<String, int> kStrength = {
  for (var i = 0; i < kRanks.length; i++) kRanks[i]: i
};

int nextSeat(int s) => (s + 1) % 4;
String teamOf(int s) => s % 2 == 0 ? 'NS' : 'EW';

class Card {
  final String suit;
  final String rank;
  const Card(this.suit, this.rank);
  int get points => kValue[rank]!;
  String get key => '$suit$rank';
  @override
  String toString() => '${kSuitSym[suit]}$rank';
}

class TrickPlay {
  final int seat;
  final Card card;
  final bool faceDown;
  final bool isIndicator;
  TrickPlay(this.seat, this.card,
      {this.faceDown = false, this.isIndicator = false});
}

int trickStrength(Card card, String? trumpSuit, String? ledSuit) {
  if (card.suit == trumpSuit) return 200 + kStrength[card.rank]!;
  if (card.suit == ledSuit) return 100 + kStrength[card.rank]!;
  return kStrength[card.rank]!;
}

void sortHand(List<Card> h) {
  h.sort((a, b) => a.suit != b.suit
      ? kSuits.indexOf(a.suit) - kSuits.indexOf(b.suit)
      : kStrength[b.rank]! - kStrength[a.rank]!);
}

List<Card> buildDeck() {
  final d = <Card>[];
  for (final s in kSuits) {
    for (final r in kRanks) {
      d.add(Card(s, r));
    }
  }
  return d;
}

/// Moteur d'une partie de 304. Toute la logique de règles vit ici ;
/// l'UI (Flutter) ne fait que lire l'état et appeler les méthodes.
class Engine {
  final Random _rng;
  void Function(String)? onLog;

  Map<String, int> tokens = {'NS': 11, 'EW': 11};
  int dealer = 0;

  late List<Card> deck;
  List<List<Card>> hands = [[], [], [], []];
  int dealt = 0;

  String? trumpSuit;
  int? trumpMaker;
  int? trumpMaker1;
  int? bid1;
  int? bid; // enchère finale (250 en sentinel pour Partner Close Caps)
  Card? indicator;
  bool indicatorOnTable = true;
  bool trumpOpen = false;
  bool pcc = false; // Partner Close Caps
  bool soloMode = false;
  int? mutedSeat;

  List<Map<String, dynamic>> tricks = [];
  int trickWinsNS = 0, trickWinsEW = 0, pointsNS = 0, pointsEW = 0;
  int trumpsPlayed = 0; // atouts tombés (règle des atouts épuisés)
  Set<String> seen = {}; // mémoire publique : cartes vues face visible

  String phase = 'idle';
  int eldest = 0;

  // Enchères — 1er tour
  int bidTurn = 0;
  int? highBid;
  int? highBidder;
  int passStreak = 0;
  Set<int> spoken = {};

  // Enchères — 2e tour
  int bid2Turn = 0;
  int bid2Count = 0;
  int? bid2High;
  int? bid2Bidder;
  bool bid2Pcc = false;

  // Jeu
  List<TrickPlay> currentTrick = [];
  String? ledSuit;
  int leader = 0;
  int turn = 0;

  /// [rng] permet d'injecter un générateur (test différentiel avec le prototype).
  Engine({int? seed, Random? rng})
      : _rng = rng ?? (seed == null ? Random() : Random(seed)) {
    dealer = _rng.nextInt(4);
  }

  void _log(String m) => onLog?.call(m);

  void _shuffle(List<Card> a) {
    for (var i = a.length - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final t = a[i];
      a[i] = a[j];
      a[j] = t;
    }
  }

  // ---- nouvelle donne : 1er temps, 4 cartes chacun ----------------------
  void newHand() {
    deck = buildDeck();
    _shuffle(deck);
    hands = [[], [], [], []];
    dealt = 0;
    _dealBatch(); // 1er temps : 4 cartes chacun
    trumpSuit = null;
    trumpMaker = null;
    trumpMaker1 = null;
    bid1 = null;
    bid = null;
    indicator = null;
    indicatorOnTable = true;
    trumpOpen = false;
    pcc = false;
    soloMode = false;
    mutedSeat = null;
    tricks = [];
    trickWinsNS = trickWinsEW = pointsNS = pointsEW = 0;
    trumpsPlayed = 0;
    seen = {};
    eldest = nextSeat(dealer);
    phase = 'redeal';
    bidTurn = eldest;
    highBid = null;
    highBidder = null;
    passStreak = 0;
    spoken = {};
  }

  void _dealBatch() {
    for (var k = 0; k < 4; k++) {
      for (var n = 0; n < 4; n++) {
        final seat = (dealer + 1 + n) % 4;
        hands[seat].add(deck[dealt++]);
      }
    }
    for (final h in hands) {
      sortHand(h);
    }
  }

  int handPoints(int seat) => hands[seat].fold(0, (a, c) => a + c.points);

  // REDEAL : le joueur à droite du donneur peut l'exiger si ses 4 cartes < 15 pts
  bool canRedeal() => phase == 'redeal' && handPoints(eldest) < 15;
  void redeal() {
    _log('Redistribution (main du joueur à droite du donneur < 15 pts).');
    newHand();
  }

  void startBidding1() => phase = 'bid1';

  // ---- ENCHÈRES · 1er tour (sur les 4 premières cartes) -----------------
  List<int> legalBids() {
    var min = highBid != null ? highBid! + 10 : 160;
    final seat = bidTurn;
    final secondTurn = spoken.contains(seat);
    final partnerLeads =
        highBidder != null && teamOf(highBidder!) == teamOf(seat);
    if (secondTurn || partnerLeads) min = max(min, 200);
    final out = <int>[];
    for (var b = max(160, min); b <= 240; b += 10) {
      out.add(b);
    }
    return out;
  }

  /// value == null => pass
  Map<String, dynamic> placeBid(int? value) {
    final seat = bidTurn;
    spoken.add(seat);
    if (value == null) {
      passStreak++;
      _log('${kSeatName[seat]} passe.');
    } else {
      highBid = value;
      highBidder = seat;
      passStreak = 0;
      _log('${kSeatName[seat]} annonce $value.');
    }
    if (highBidder != null && passStreak >= 3) return _endBidding();
    if (highBidder == null && spoken.length >= 4 && passStreak >= 4) {
      phase = 'allpass';
      return {'allPass': true};
    }
    bidTurn = nextSeat(bidTurn);
    return {'continue': true};
  }

  Map<String, dynamic> _endBidding() {
    trumpMaker1 = highBidder;
    bid1 = highBid;
    trumpMaker = highBidder;
    bid = highBid;
    phase = 'chooseTrump1';
    _log(
        '${kSeatName[trumpMaker1!]} gagne le 1er tour ($bid1) et pose l\'atout.');
    return {'biddingDone': true, 'round': 1};
  }

  // ---- CHOIX ATOUT (1er tour) : pose 1 des 4 cartes face cachée ----------
  Map<String, dynamic> chooseTrump1(Card card) {
    final h = hands[trumpMaker1!];
    final idx = h.indexWhere((c) => c.suit == card.suit && c.rank == card.rank);
    if (idx < 0) throw StateError('carte absente');
    indicator = h.removeAt(idx);
    trumpSuit = indicator!.suit;
    indicatorOnTable = true;
    _dealBatch(); // 2e temps : +4 cartes -> 8
    phase = 'bid2';
    bid2Turn = trumpMaker1!;
    bid2Count = 0;
    bid2High = null;
    bid2Bidder = null;
    bid2Pcc = false;
    return {'trumpChosen1': true, 'phase': 'bid2'};
  }

  // ---- ENCHÈRES · 2e tour (sur 8 cartes, >= 250) ------------------------
  List<int> legalBids2() {
    final seat = bid2Turn;
    if (bid2Bidder != null && teamOf(bid2Bidder!) == teamOf(seat)) return [];
    var floor = max(250, bid1! + 10);
    if (bid2High != null) floor = max(floor, bid2High! + 10);
    final out = <int>[];
    for (var b = floor; b <= 300; b += 10) {
      out.add(b);
    }
    return out;
  }

  bool canPCC() {
    final seat = bid2Turn;
    return !(bid2Bidder != null && teamOf(bid2Bidder!) == teamOf(seat));
  }

  /// value : null => pass ; int => surenchère ; 'PCC' => Partner Close Caps
  Map<String, dynamic> placeBid2(Object? value) {
    final seat = bid2Turn;
    if (value == 'PCC') {
      bid2Bidder = seat;
      bid2Pcc = true;
      _log('${kSeatName[seat]} annonce PARTNER CLOSE CAPS !');
      return _endBidding2();
    }
    if (value != null) {
      bid2High = value as int;
      bid2Bidder = seat;
      _log('${kSeatName[seat]} surenchérit à $value (2e tour) !');
    } else {
      _log('${kSeatName[seat]} passe (2e tour).');
    }
    bid2Count++;
    if (bid2Count >= 4) return _endBidding2();
    bid2Turn = nextSeat(bid2Turn);
    return {'continue': true};
  }

  Map<String, dynamic> _endBidding2() {
    if (bid2Pcc) {
      hands[trumpMaker1!].add(indicator!);
      sortHand(hands[trumpMaker1!]);
      indicator = null;
      trumpSuit = null;
      indicatorOnTable = false;
      trumpMaker = bid2Bidder;
      pcc = true;
      bid = 250; // sentinel numérique (règle de révélation ≥250)
      phase = 'chooseTrumpPCC';
      return {'pcc': true};
    }
    if (bid2Bidder != null) {
      hands[trumpMaker1!].add(indicator!);
      sortHand(hands[trumpMaker1!]);
      indicator = null;
      trumpSuit = null;
      indicatorOnTable = false;
      trumpMaker = bid2Bidder;
      bid = bid2High;
      phase = 'chooseTrump2';
      _log(
          '${kSeatName[trumpMaker!]} devient preneur ($bid) et choisit un nouvel atout.');
      return {'round2Winner': true};
    }
    trumpMaker = trumpMaker1;
    bid = bid1;
    phase = 'preplay';
    return {'round2AllPass': true};
  }

  Map<String, dynamic> chooseTrump2(Card card) {
    final h = hands[trumpMaker!];
    final idx = h.indexWhere((c) => c.suit == card.suit && c.rank == card.rank);
    if (idx < 0) throw StateError('carte absente');
    indicator = h.removeAt(idx);
    trumpSuit = indicator!.suit;
    indicatorOnTable = true;
    phase = 'preplay';
    return {'trumpChosen2': true};
  }

  // ---- PARTNER CLOSE CAPS : le preneur joue seul contre les 2 adversaires -
  Map<String, dynamic> chooseTrumpPCC(Card card) {
    final h = hands[trumpMaker!];
    final idx = h.indexWhere((c) => c.suit == card.suit && c.rank == card.rank);
    if (idx < 0) throw StateError('carte absente');
    indicator = h.removeAt(idx);
    trumpSuit = indicator!.suit;
    indicatorOnTable = true;
    _beginPlayPCC();
    return {'pccStarted': true};
  }

  // ---- CHOIX JEU OUVERT / FERMÉ puis début du jeu -----------------------
  void startPlayClosed() => _beginPlay(false);
  void startPlayOpen() {
    if (indicatorOnTable) {
      hands[trumpMaker!].add(indicator!);
      sortHand(hands[trumpMaker!]);
      indicatorOnTable = false;
    }
    trumpOpen = true;
    _beginPlay(true);
    if (_checkSpoilt()) phase = 'spoilt';
  }

  /// ATOUT GÂCHÉ : en jeu ouvert, aucun adversaire du preneur n'a d'atout
  /// -> donne annulée (phase 'spoilt', l'appelant redistribue).
  bool _checkSpoilt() {
    if (soloMode || !trumpOpen || trumpSuit == null) return false;
    final tm = teamOf(trumpMaker!);
    var opp = 0;
    for (var i = 0; i < 4; i++) {
      if (teamOf(i) != tm) {
        opp += hands[i].where((c) => c.suit == trumpSuit).length;
      }
    }
    return opp == 0;
  }

  void _beginPlay(bool open) {
    phase = 'play';
    soloMode = false;
    leader = nextSeat(dealer);
    turn = leader;
    currentTrick = [];
    ledSuit = null;
    _log(
        'Jeu ! Atout ${open ? 'ouvert' : 'caché'} · enchère $bid. ${kSeatName[leader]} entame.');
  }

  void _beginPlayPCC() {
    phase = 'play';
    soloMode = true;
    mutedSeat = (trumpMaker! + 2) % 4;
    leader = trumpMaker!;
    turn = trumpMaker!;
    currentTrick = [];
    ledSuit = null;
    _log('PARTNER CLOSE CAPS ! ${kSeatName[trumpMaker!]} joue seul contre '
        '${kSeatName[(trumpMaker! + 1) % 4]} & ${kSeatName[(trumpMaker! + 3) % 4]}. '
        '${kSeatName[mutedSeat!]} est écarté.');
  }

  int nextActiveSeat(int s) {
    var n = nextSeat(s);
    if (soloMode && n == mutedSeat) n = nextSeat(n);
    return n;
  }

  int get trickSize => soloMode ? 3 : 4;
  void _advanceTurn() =>
      turn = soloMode ? nextActiveSeat(turn) : nextSeat(turn);

  // ---- JEU D'UN PLI ------------------------------------------------------
  List<Card> playableCards(int seat) {
    final h = hands[seat];
    if (currentTrick.isEmpty) {
      // ATOUTS ÉPUISÉS : le preneur qui détient tous les atouts restants doit mener atout
      if (seat == trumpMaker && trumpOpen && trumpSuit != null) {
        final myTr = h.where((c) => c.suit == trumpSuit).toList();
        final remaining = 8 - trumpsPlayed;
        if (myTr.isNotEmpty &&
            myTr.length == remaining &&
            myTr.length < h.length) {
          return myTr;
        }
      }
      return List.of(h);
    }
    final canFollow = h.where((c) => c.suit == ledSuit).toList();
    if (trumpOpen) return canFollow.isNotEmpty ? canFollow : List.of(h);
    if (canFollow.isNotEmpty) return canFollow;
    return List.of(h); // jouée face cachée
  }

  Map<String, dynamic> playCard(int seat, Card card) {
    final h = hands[seat];
    final canFollow =
        currentTrick.isNotEmpty && h.any((c) => c.suit == ledSuit);
    var faceDown = false;
    if (!trumpOpen && currentTrick.isNotEmpty && !canFollow) faceDown = true;
    final idx = h.indexWhere((c) => c.suit == card.suit && c.rank == card.rank);
    if (idx < 0) throw StateError('carte absente de la main');
    h.removeAt(idx);
    if (currentTrick.isEmpty) ledSuit = card.suit;
    currentTrick.add(TrickPlay(seat, card, faceDown: faceDown));
    _advanceTurn();
    if (currentTrick.length == trickSize) return _resolveTrick();
    return {'played': true, 'faceDown': faceDown};
  }

  Map<String, dynamic> playIndicatorToCut(int seat) {
    currentTrick
        .add(TrickPlay(seat, indicator!, faceDown: true, isIndicator: true));
    indicatorOnTable = false;
    _advanceTurn();
    if (currentTrick.length == trickSize) return _resolveTrick();
    return {'played': true, 'faceDown': true};
  }

  Map<String, dynamic> playLastIndicator(int seat) {
    final leading = currentTrick.isEmpty;
    if (leading) {
      ledSuit = indicator!.suit;
      trumpOpen = true;
    }
    currentTrick
        .add(TrickPlay(seat, indicator!, faceDown: false, isIndicator: true));
    indicatorOnTable = false;
    _advanceTurn();
    if (currentTrick.length == trickSize) return _resolveTrick();
    return {'played': true};
  }

  Map<String, dynamic> _resolveTrick() {
    final t = currentTrick;
    var reveal = false;
    if (!trumpOpen) {
      final anyTrumpFaceDown =
          t.any((x) => x.faceDown && x.card.suit == trumpSuit);
      if (anyTrumpFaceDown) {
        reveal = true;
        trumpOpen = true;
      }
    }
    var win = t[0];
    var winStr = trickStrength(t[0].card, trumpSuit, ledSuit);
    for (var i = 1; i < t.length; i++) {
      final s = trickStrength(t[i].card, trumpSuit, ledSuit);
      if (s > winStr) {
        winStr = s;
        win = t[i];
      }
    }
    final pts = t.fold(0, (a, x) => a + x.card.points);
    if (teamOf(win.seat) == 'NS') {
      pointsNS += pts;
      trickWinsNS++;
    } else {
      pointsEW += pts;
      trickWinsEW++;
    }
    final res = <String, dynamic>{
      'trickDone': true,
      'winner': win.seat,
      'points': pts,
      'revealed': reveal,
      'ledSuit': ledSuit,
    };
    for (final x in t) {
      if (trumpSuit != null && x.card.suit == trumpSuit) trumpsPlayed++;
      if (!x.faceDown || trumpOpen) seen.add(x.card.key);
    }
    tricks.add(res);
    _log(
        'Pli ${tricks.length} : ${kSeatName[win.seat]} remporte ($pts pts)${reveal ? ' — atout révélé !' : ''}');
    // règle des enchères >= 250 (et PCC) : atout révélé après le 1er pli
    if (!trumpOpen &&
        (pcc || (bid != null && bid! >= 250)) &&
        tricks.length == 1) {
      if (indicatorOnTable) {
        hands[trumpMaker!].add(indicator!);
        sortHand(hands[trumpMaker!]);
        indicatorOnTable = false;
      }
      trumpOpen = true;
      res['reveal250'] = true;
      _log(
          'Enchère ≥ 250 : atout révélé après le 1er pli — tout se joue face visible.');
    }
    leader = win.seat;
    turn = win.seat;
    currentTrick = [];
    ledSuit = null;
    if (tricks.length == 8) {
      res['handDone'] = true;
      _scoreHand(res);
    }
    return res;
  }

  void _scoreHand(Map<String, dynamic> res) {
    phase = 'scored';
    final tmTeam = teamOf(trumpMaker!);
    final other = tmTeam == 'NS' ? 'EW' : 'NS';

    // ---- Partner Close Caps : réussite = les 8 plis ; +4 / -5 ----------
    if (pcc) {
      final wins = tmTeam == 'NS' ? trickWinsNS : trickWinsEW;
      final success = wins == 8;
      final transfer = success ? 4 : 5;
      if (success) {
        tokens[tmTeam] = tokens[tmTeam]! + transfer;
        tokens[other] = tokens[other]! - transfer;
      } else {
        tokens[tmTeam] = tokens[tmTeam]! - transfer;
        tokens[other] = tokens[other]! + transfer;
      }
      _clampTokens();
      res['score'] = {
        'tmTeam': tmTeam,
        'pcc': true,
        'tricks': wins,
        'bid': 'Partner Close Caps',
        'success': success,
        'transfer': transfer,
        'caps': success,
      };
      _finishHand(res);
      return;
    }

    final tmPoints = tmTeam == 'NS' ? pointsNS : pointsEW;
    final success = tmPoints >= bid!;
    int delta;
    if (bid! < 200) {
      delta = success ? 1 : -2;
    } else if (bid! < 250) {
      delta = success ? 2 : -3;
    } else {
      delta = success ? 3 : -4;
    }
    final capsNS = trickWinsNS == 8, capsEW = trickWinsEW == 8;
    var capsBonus = 0;
    if ((tmTeam == 'NS' && capsNS) || (tmTeam == 'EW' && capsEW)) capsBonus = 1;
    final transfer = success ? delta.abs() + capsBonus : delta.abs();
    if (success) {
      tokens[tmTeam] = tokens[tmTeam]! + transfer;
      tokens[other] = tokens[other]! - transfer;
    } else {
      tokens[tmTeam] = tokens[tmTeam]! - transfer;
      tokens[other] = tokens[other]! + transfer;
    }
    _clampTokens();
    res['score'] = {
      'tmTeam': tmTeam,
      'tmPoints': tmPoints,
      'bid': bid,
      'success': success,
      'transfer': transfer,
      'caps': capsBonus > 0,
    };
    _finishHand(res);
  }

  void _clampTokens() {
    tokens['NS'] = tokens['NS']!.clamp(0, 22);
    tokens['EW'] = tokens['EW']!.clamp(0, 22);
  }

  void _finishHand(Map<String, dynamic> res) {
    res['gameOver'] = tokens['NS']! <= 0 || tokens['EW']! <= 0;
    if (res['gameOver'] == true) {
      res['gameWinner'] = tokens['NS']! <= 0 ? 'EW' : 'NS';
    }
    dealer = nextSeat(dealer);
  }

  // ==========================================================================
  // SÉRIALISATION / VUE RÉSEAU
  // --------------------------------------------------------------------------
  // snapshot(forSeat) renvoie l'état du jeu **rédigé pour un joueur donné** :
  //  - il ne voit que SA main (les autres = un simple compte de cartes) ;
  //  - l'atout n'est visible que s'il est ouvert, ou pour le preneur ;
  //  - les cartes jouées face cachée restent cachées (sauf les siennes).
  // forSeat == null => vue complète (serveur / debug), rien n'est masqué.
  // C'est cette vue que le serveur autoritatif envoie à chaque client.
  // ==========================================================================
  static Map<String, String> cardJson(Card c) => {'s': c.suit, 'r': c.rank};
  static Card cardFromJson(Map j) => Card(j['s'] as String, j['r'] as String);

  Map<String, dynamic> snapshot({int? forSeat}) {
    final open = trumpOpen;
    final handInfo = <dynamic>[];
    for (var i = 0; i < 4; i++) {
      if (forSeat == null || i == forSeat) {
        handInfo.add(hands[i].map(cardJson).toList());
      } else {
        handInfo.add({'count': hands[i].length});
      }
    }
    final trick = currentTrick.map((p) {
      final hide =
          p.faceDown && !open && !(forSeat != null && p.seat == forSeat);
      return {
        'seat': p.seat,
        'faceDown': p.faceDown,
        'card': hide ? null : cardJson(p.card),
      };
    }).toList();
    final showTrump = forSeat == null || open || forSeat == trumpMaker;
    return {
      'phase': phase,
      'dealer': dealer,
      'eldest': eldest,
      'turn': turn,
      'leader': leader,
      'bidTurn': bidTurn,
      'bid2Turn': bid2Turn,
      'tokens': tokens,
      'bid': bid,
      'bid1': bid1,
      'highBid': highBid,
      'highBidder': highBidder,
      'trumpMaker': trumpMaker,
      'trumpMaker1': trumpMaker1,
      'pcc': pcc,
      'soloMode': soloMode,
      'mutedSeat': mutedSeat,
      'trumpOpen': open,
      'trumpSuit': showTrump ? trumpSuit : null,
      'ledSuit': ledSuit,
      'indicatorOnTable': indicatorOnTable,
      'trickWinsNS': trickWinsNS,
      'trickWinsEW': trickWinsEW,
      'pointsNS': pointsNS,
      'pointsEW': pointsEW,
      'tricksPlayed': tricks.length,
      'hands': handInfo,
      'currentTrick': trick,
      'legalBids': phase == 'bid1'
          ? legalBids()
          : (phase == 'bid2' ? legalBids2() : <int>[]),
      'canPCC': phase == 'bid2' ? canPCC() : false,
      'yourTurn': forSeat != null && _isSeatToAct(forSeat),
    };
  }

  Map<String, dynamic> viewFor(int seat) => snapshot(forSeat: seat);

  /// Le siège doit-il agir maintenant ? (utilisé par le serveur pour savoir
  /// s'il attend une action humaine ou s'il fait avancer un bot.)
  bool _isSeatToAct(int seat) {
    switch (phase) {
      case 'bid1':
        return bidTurn == seat;
      case 'chooseTrump1':
        return trumpMaker1 == seat;
      case 'bid2':
        return bid2Turn == seat;
      case 'chooseTrump2':
      case 'chooseTrumpPCC':
      case 'preplay':
        return trumpMaker == seat;
      case 'play':
        return turn == seat;
      case 'redeal':
        return eldest == seat;
      default:
        return false;
    }
  }

  int? get seatToAct {
    for (var i = 0; i < 4; i++) {
      if (_isSeatToAct(i)) return i;
    }
    return null;
  }
}
