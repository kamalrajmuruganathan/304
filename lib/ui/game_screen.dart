import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;
import '../engine/engine.dart';
import '../ai/bots.dart';
import '../ai/hard.dart';
import '../l10n/app_localizations.dart';
import '../daily.dart';
import '../settings.dart';
import 'skin.dart';
import '../sound.dart';
import 'anim.dart';
import 'recap.dart';
import 'caps.dart';
import 'leave.dart';
import 'replay.dart';
import 'invite.dart' show shareDaily;

// Palette « table royale » (miroir du prototype web validé).
Color get _gold => sk.accent;
Color get _goldD => sk.accentDim;
Color get _woodB => sk.bg;
const _cream = Color(0xFFF6F1E2);
const _ink = Color(0xFF1A160F);
const _red = Color(0xFFB12B2B);
Color get _txt => sk.text;
Color get _dim => sk.dim;

/// Écran de jeu : table royale câblée au moteur (solo vs 3 bots).
/// La logique de flux reflète le contrôleur du prototype validé ; toute la
/// logique de règles reste dans Engine. Prévu pour basculer plus tard sur
/// lib/net/client.dart (multijoueur).
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.resume = false, this.daily = false});

  /// Reprendre la partie mémorisée (`soloSave`) au lieu d'en commencer une.
  final bool resume;

  /// Donne du jour : une seule donne, la même pour tout le monde
  /// (lib/daily.dart), adversaires au niveau normal.
  final bool daily;
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  /// Taille des cartes : réglage « grandes cartes » × agrandissement automatique
  /// sur grand écran.
  double get _k => cardScale * autoCardScale(MediaQuery.sizeOf(context));

  late final Engine e =
      widget.daily ? Engine(rng: DailyRandom(dailySeed(_day))) : Engine();

  /// Jour de la donne du jour (fixé à l'ouverture de l'écran).
  final String _day = dayKey();

  /// Cet essai de la donne du jour compte-t-il ? (1er essai du jour)
  bool _official = false;
  String _msg = '';
  String get msg => _msg;

  /// Changer le message efface la ligne d'aide et le conseil affichés.
  set msg(String v) {
    _msg = v;
    tip = '';
    _hinted = null;
  }

  /// Ligne d'aide sous le message (comme le prototype).
  String tip = '';

  /// Carte mise en valeur par « 💡 Conseil ».
  String? _hinted;

  /// Dernier pli terminé de la donne (bouton « Dernier pli »).
  Map<String, dynamic>? _lastTrick;
  List<Widget> actions = [];

  /// Pli terminé, affiché pendant la pause de fin de pli. Tant qu'il est non
  /// nul, aucune carte n'est jouable (sinon un 2e déroulé démarre en parallèle).
  List<TrickPlay>? _doneTrick;
  int _doneWinner = 0; // gagnant du pli affiché pendant la pause
  static const int human = 0;

  AppLocalizations get l => AppLocalizations.of(context)!;
  String _seat(int s) => [l.mSud, l.seatEast, l.seatNorth, l.seatWest][s];

  @override
  void initState() {
    super.initState();
    e.onLog = (_) {};
    final saved = soloSave.value;
    if (widget.daily) {
      _official = daily.value.officialNow();
      // noté après l'affichage (l'accueil, qui l'affiche, est encore construit)
      WidgetsBinding.instance
          .addPostFrameCallback((_) => startDaily(day: _day));
    } else if (widget.resume && saved != null) {
      e.tokens = {'NS': saved.ns, 'EW': saved.ew};
      e.dealer = saved.dealer;
    }
    keepScreenOn(true); // l'écran ne s'éteint pas pendant la partie
    WidgetsBinding.instance.addPostFrameCallback((_) => _startHand());
  }

  @override
  void dispose() {
    keepScreenOn(false);
    super.dispose();
  }

  void _bots(void Function() f) => Future.delayed(botDelay(600), () {
        if (mounted) setState(f);
      });

  // ======================= déroulé d'une donne =======================
  /// Jetons au début de la donne (variation affichée dans le récapitulatif).
  Map<String, int> _tokensAtStart = {'NS': 11, 'EW': 11};

  void _startHand() {
    _lastTrick = null;
    _tokensAtStart = Map.of(e.tokens);
    // la donne du jour ne touche pas à la partie solo mémorisée
    if (!widget.daily) saveSolo(e.tokens['NS']!, e.tokens['EW']!, e.dealer);
    e.newHand();
    _handleRedeal(0);
  }

  void _handleRedeal(int safety) {
    if (safety > 6 || !e.canRedeal()) {
      e.startBidding1();
      _stepBid();
      return;
    }
    if (e.eldest == human) {
      setState(() {
        msg = l.weakHand(e.handPoints(human));
        actions = [
          _btn(
              l.redeal,
              () => setState(() {
                    e.redeal();
                    _handleRedeal(safety + 1);
                  }),
              primary: true),
          _btn(
              l.keep,
              () => setState(() {
                    e.startBidding1();
                    _stepBid();
                  })),
        ];
      });
    } else {
      setState(() {
        msg = l.botRedeals(_seat(e.eldest));
        actions = [];
      });
      _bots(() {
        e.redeal();
        _handleRedeal(safety + 1);
      });
    }
  }

  void _stepBid() {
    if (e.phase == 'allpass') {
      setState(() {
        msg = l.allPass;
        actions = [];
      });
      _bots(_startHand);
      return;
    }
    if (e.phase != 'bid1') {
      _afterRound1();
      return;
    }
    if (e.bidTurn == human) {
      final legal = e.legalBids();
      setState(() {
        msg =
            '${l.bid1You(e.handPoints(human))} ${e.highBid != null ? l.bestBid('${e.highBid}', _seat(e.highBidder!)) : l.noBidYet}';
        tip = l.bid1Hint;
        actions = [
          for (final v in legal)
            _btn('$v', () {
              e.placeBid(v);
              setState(_nextBid);
            }),
          _btn(l.pass, () {
            e.placeBid(null);
            setState(_nextBid);
          }),
          _btn(_hintLabel, () {
            final v = botBid(e, human);
            // estimation de la main (même modèle que l'IA), arrondie à 5
            final est = (est4(e.hands[human]) / 5).round() * 5;
            setState(() => tip =
                '${v != null ? l.hintBid('$v') : l.hintPass} ${l.hintEst(est)}');
          }),
        ];
      });
    } else {
      setState(() {
        msg = l.thinking(_seat(e.bidTurn));
        actions = [];
      });
      _bots(() {
        e.placeBid(botBid(e, e.bidTurn));
        _nextBid();
      });
    }
  }

  void _nextBid() {
    if (e.phase == 'allpass') {
      msg = l.allPass;
      actions = [];
      _bots(_startHand);
      return;
    }
    if (e.phase == 'chooseTrump1') {
      _afterRound1();
      return;
    }
    _stepBid();
  }

  void _afterRound1() {
    final tm = e.trumpMaker1!;
    if (tm == human) {
      setState(() {
        msg = l.youWinR1;
        tip = l.trumpTip;
        actions = [];
      });
    } else {
      setState(() {
        msg = l.botSetsTrump(_seat(tm));
        actions = [];
      });
      _bots(() {
        e.chooseTrump1(botChooseTrump(e, tm));
        _stepBid2();
      });
    }
  }

  void _stepBid2() {
    if (e.phase != 'bid2') {
      _afterRound2();
      return;
    }
    if (e.bid2Turn == human) {
      final legal = e.legalBids2();
      if (legal.isEmpty && !e.canPCC()) {
        setState(() {
          msg = l.mustPass2;
          actions = [];
        });
        _bots(() {
          e.placeBid2(null);
          _stepBid2();
        });
        return;
      }
      setState(() {
        msg = l.bid2You(e.handPoints(human));
        tip = l.bid2Hint;
        actions = [
          for (final v in legal.take(5))
            _btn('$v', () {
              e.placeBid2(v);
              setState(_stepBid2);
            }),
          if (e.canPCC())
            _btn('Partner Close Caps', () {
              e.placeBid2('PCC');
              setState(_stepBid2);
            }, gold: true),
          _btn(l.pass, () {
            e.placeBid2(null);
            setState(_stepBid2);
          }),
          _btn(_hintLabel, () {
            final r = botBid2Why(e, human);
            final v = r.bid;
            setState(() => tip = switch (r.why) {
                  Bid2Why.pcc =>
                    '${l.hintBid('Partner Close Caps')} ${l.hintPccWhy}',
                  Bid2Why.strong => '${l.hintBid('$v')} ${l.hintBid2Strong}',
                  Bid2Why.weakSuit => '${l.hintPass} ${l.hintBid2Why}',
                  Bid2Why.fewPoints => '${l.hintPass} ${l.hintBid2Points}',
                  Bid2Why.tooHigh => '${l.hintPass} ${l.hintBid2High}',
                });
          }),
        ];
      });
    } else {
      setState(() {
        msg = l.botRound2(_seat(e.bid2Turn));
        actions = [];
      });
      _bots(() {
        e.placeBid2(botBid2(e, e.bid2Turn));
        _stepBid2();
      });
    }
  }

  void _afterRound2() {
    if (e.phase == 'chooseTrumpPCC') {
      final tm = e.trumpMaker!;
      if (tm == human) {
        setState(() {
          msg = l.pccYou;
          tip = l.pccHint;
          actions = [];
        });
      } else {
        setState(() {
          msg = l.botPcc(_seat(tm));
          actions = [];
        });
        _bots(() {
          e.chooseTrumpPCC(botChooseTrump(e, tm));
          _stepPlay();
        });
      }
      return;
    }
    if (e.phase == 'chooseTrump2') {
      final tm = e.trumpMaker!;
      if (tm == human) {
        setState(() {
          msg = l.youTakeR2;
          tip = l.trumpTip;
          actions = [];
        });
      } else {
        setState(() {
          msg = l.botNewTrump(_seat(tm));
          actions = [];
        });
        _bots(() {
          e.chooseTrump2(botChooseTrump(e, tm));
          _preplay();
        });
      }
      return;
    }
    _preplay();
  }

  void _preplay() {
    final tm = e.trumpMaker!;
    if (tm == human) {
      setState(() {
        msg = l.openOrClosed;
        tip = l.openHint;
        actions = [
          _btn(l.closedGame, () {
            e.startPlayClosed();
            setState(_stepPlay);
          }, primary: true),
          _btn(l.openGame, () {
            e.startPlayOpen();
            if (e.phase == 'spoilt') {
              setState(() {
                msg = l.spoilt;
                actions = [];
              });
              _bots(_startHand);
            } else {
              setState(_stepPlay);
            }
          }),
        ];
      });
    } else {
      e.startPlayClosed();
      _stepPlay();
    }
  }

  void _stepPlay() {
    if (e.tricks.length == 8) return;
    final seat = e.turn;
    if (e.hands[seat].isEmpty && seat == e.trumpMaker && e.indicatorOnTable) {
      setState(() {
        msg = l.lastTrickTM;
        actions = [];
      });
      _bots(() => _afterPlay(e.playLastIndicator(seat)));
      return;
    }
    if (seat == human) {
      setState(() {
        final facedown = e.currentTrick.isNotEmpty &&
            !e.trumpOpen &&
            !e.hands[human].any((c) => c.suit == e.ledSuit);
        msg = e.currentTrick.isEmpty
            ? l.youLead
            : facedown
                ? l.youFacedown
                : l.youFollow;
        final t = e.trumpSuit;
        tip = e.trumpOpen && t != null
            ? l.trumpOpenHint('${kSuitSym[t]} ${_suitName(t)}')
            : l.trumpHiddenHint;
        actions = [
          _btn(_hintLabel, _showPlayHint),
          if (_lastTrick != null) _btn(l.lastTrickBtn, _openLastTrick),
          if (e.canCutWithIndicator(human))
            _btn(l.cutIndicator, _humanCutIndicator,
                primary: true, key: const ValueKey('cut-indicator')),
          // annonce « Caps » avant d'entamer (jugée au décompte : Wrong Caps)
          if (e.canCallCaps(human))
            _btn(l.callCaps, _humanCallCaps,
                gold: true, key: const ValueKey('call-caps')),
        ];
      });
    } else {
      setState(() {
        msg = l.botPlays(_seat(seat));
        if (e.soloMode && e.mutedSeat == human) tip = l.pccOut;
        actions = [];
      });
      if (botCallCaps(e, seat)) {
        e.callCaps(seat); // le bot annonce Caps avant d'entamer
        // bandeau : reste visible pendant les plis suivants
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.capsCalledBy(_seat(seat)))));
      }
      _bots(() {
        // niveaux : seuls les adversaires (Est/Ouest) changent — « facile » :
        // erreurs au hasard ; « difficile » : IA Monte-Carlo (lib/ai/hard.dart)
        final opp = teamOf(seat) != teamOf(human) && !widget.daily;
        final c = botLevel.value == 'hard' && opp
            ? botPlayHard(e, seat)
            : botPlayLevel(e, seat, easy: botLevel.value == 'easy' && opp);
        final r = c is PlayIndicator
            ? e.playIndicatorToCut(seat)
            : e.playCard(seat, c as Card);
        _afterPlay(r);
      });
    }
  }

  /// Le joueur annonce « Caps » (il entame ; jugé au décompte), après
  /// confirmation : une annonce sans certitude coûte 2 jetons.
  Future<void> _humanCallCaps() async {
    if (!e.canCallCaps(human) || !await confirmCaps(context)) return;
    if (!mounted || !e.callCaps(human)) return;
    setState(() {
      tip = l.capsCalledBy(l.mSud);
      actions.removeWhere((w) => w.key == const ValueKey('call-caps'));
    });
  }

  /// Le joueur (preneur, jeu fermé) coupe avec l'atout posé.
  void _humanCutIndicator() {
    if (!e.canCutWithIndicator(human) || _doneTrick != null) return;
    haptic();
    setState(() => actions = []);
    _afterPlay(e.playIndicatorToCut(human));
  }

  /// Libellé « Conseil » sans l'emoji 💡 du prototype (rendu par une police
  /// emoji téléchargée à la volée sur le web) : l'ampoule est mise en icône.
  String get _hintLabel => l.hint.replaceAll('💡', '').trim();

  String _suitName(String s) =>
      {'S': l.suitS, 'C': l.suitC, 'D': l.suitD, 'H': l.suitH}[s]!;

  /// 💡 Conseil pendant le jeu : la carte que jouerait l'IA (comme le prototype).
  void _showPlayHint() {
    if (e.phase != 'play' || e.turn != human || e.hands[human].isEmpty) return;
    // atout caché pour le joueur : le conseil ne doit pas s'en servir (l'IA
    // normale lit l'atout) — il est calculé sur une répartition imaginée
    final knows = e.trumpOpen || e.trumpMaker == human;
    final view = knows ? e : (sampleWorld(e, human, math.Random()) ?? e);
    final r = botPlayWhy(view, human);
    final ch = r.choice;
    setState(() {
      if (ch is PlayIndicator) {
        tip = e.canCutWithIndicator(human)
            ? '${l.hintCut} ${whyText(l, PlayWhy.cutIndicator)}'
            : l.hintDiscard;
      } else if (e.capsCertain(human)) {
        _hinted = (ch as Card).key;
        tip = l.hintCaps;
      } else {
        _hinted = (ch as Card).key;
        // la carte, et pourquoi
        tip = '${l.hintPlay} ${whyText(l, r.why)}';
      }
    });
  }

  /// Dernier pli : les 4 cartes, le gagnant entouré d'or.
  void _openLastTrick() {
    final t = _lastTrick;
    if (t == null) return;
    final names = [l.seatYou, l.seatEast, l.seatNorth, l.seatWest];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: sk.dialog,
        title: Text(
            l.lastTrickTitle(t['points'] as int, names[t['winner'] as int]),
            style: TextStyle(color: _gold, fontSize: 16)),
        content: Wrap(spacing: 10, runSpacing: 10, children: [
          for (final p in t['cards'] as List<TrickPlay>)
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(names[p.seat], style: TextStyle(color: _dim, fontSize: 11)),
              const SizedBox(height: 4),
              Container(
                decoration: p.seat == t['winner']
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: _gold, width: 3))
                    : null,
                child: p.faceDown && !e.trumpOpen && p.seat != human
                    ? _facedown()
                    : _cardWidget(p.card, big: true),
              ),
            ]),
        ]),
        actions: [
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(), child: Text(l.close)),
        ],
      ),
    );
  }

  void _afterPlay(Map<String, dynamic> r) {
    playSfx(r['trickDone'] == true ? Sfx.trick : Sfx.card);
    if (r['trickDone'] == true) {
      _lastTrick = r;
      setState(() {
        _doneTrick = r['cards'] as List<TrickPlay>;
        _doneWinner = r['winner'] as int;
      });
      Future.delayed(botDelay(950), () {
        if (!mounted) return;
        setState(() => _doneTrick = null);
        if (r['handDone'] == true) {
          _showResult(r);
        } else {
          setState(_stepPlay);
        }
      });
    } else {
      setState(_stepPlay);
    }
  }

  void _onHumanCard(Card c) {
    if (!_canPlay(c)) return;
    if (e.phase == 'chooseTrumpPCC') {
      e.chooseTrumpPCC(c);
      _stepPlay();
      return;
    }
    if (e.phase == 'chooseTrump2') {
      e.chooseTrump2(c);
      _preplay();
      return;
    }
    if (e.phase == 'chooseTrump1') {
      e.chooseTrump1(c);
      _stepBid2();
      return;
    }
    if (e.phase == 'play' && e.turn == human) {
      haptic();
      setState(
          () => actions = []); // plus de Conseil / Dernier pli une fois joué
      _afterPlay(e.playCard(human, c));
    }
  }

  bool _canPlay(Card c) {
    // carte déjà jouée (toucher en double) : rien à faire
    if (!e.hands[human].any((x) => x.key == c.key)) return false;
    // choix d'atout : seulement quand c'est le joueur qui choisit (pas pendant
    // qu'un bot pose le sien)
    if (e.phase == 'chooseTrump1') return e.trumpMaker1 == human;
    if (e.phase == 'chooseTrump2' || e.phase == 'chooseTrumpPCC') {
      return e.trumpMaker == human;
    }
    if (e.phase != 'play' || e.turn != human || _doneTrick != null) {
      return false;
    }
    final facedown = e.currentTrick.isNotEmpty &&
        !e.trumpOpen &&
        !e.hands[human].any((x) => x.suit == e.ledSuit);
    if (facedown) return true;
    return e.playableCards(human).any((x) => x.key == c.key);
  }

  void _showResult(Map<String, dynamic> r) {
    final s = r['score'] as Map<String, dynamic>;
    final nsWon =
        s['success'] == true ? s['tmTeam'] == 'NS' : s['tmTeam'] == 'EW';
    final over = r['gameOver'] == true;
    // score mémorisé dès le résultat (l'app peut être fermée sur la fenêtre) ;
    // partie finie : rien à reprendre
    if (widget.daily) {
      if (_official) {
        finishDaily(e.tokens['NS']! - 11, e.pointsNS, day: _day);
      }
    } else if (over) {
      clearSolo();
    } else {
      saveSolo(e.tokens['NS']!, e.tokens['EW']!, e.dealer);
    }
    final wonBefore = stats.value.gamesWon;
    recordDeal(
        won: nsWon,
        score: s,
        takerIsMe: e.trumpMaker == human,
        gameWinner: over && !widget.daily ? r['gameWinner'] as String? : null);
    // partie gagnée : dos de cartes / tapis débloqués
    final unlocked = newlyUnlocked(wonBefore, stats.value.gamesWon)
        .map((k) => l.unlocked(_unlockName(k)))
        .join('\n');
    if (widget.daily) {
      _showDailyResult(nsWon, s, replay: DealReplay.fromJson(e.replayJson()));
      return;
    }
    playSfx(nsWon ? Sfx.win : Sfx.lose);
    final replay = DealReplay.fromJson(e.replayJson());
    // bandeau sous la fenêtre : le résultat, plus « Nord joue… »
    setState(() {
      msg = nsWon ? l.dealWon : l.dealLost;
      actions = [];
    });
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        scrollable: true, // petit écran : le contenu défile
        backgroundColor: sk.dialog,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _goldD)),
        title: Text(nsWon ? l.dealWon : l.dealLost,
            style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            '${s['pcc'] == true ? 'Partner Close Caps · ${s['tricks']}/8 — ${s['success'] == true ? l.succeeded : l.failedPcc}' : '${l.bid} ${s['bid']} · ${l.pointsN(s['tmPoints'] as int)} — ${s['success'] == true ? l.succeeded : l.failedBid}${s['caps'] == true ? ' · ${l.caps}' : ''}'}${s['wrongCaps'] != null ? '\n${s['wrongCaps'] == 'NS' ? l.wrongCapsUs(kWrongCapsPenalty) : l.wrongCapsThem(kWrongCapsPenalty)}' : ''}\n${l.tokens} — ${l.us} ${e.tokens['NS']} · ${l.them} ${e.tokens['EW']}${over ? '\n\n${r['gameWinner'] == 'NS' ? l.gameWon : l.gameLost}' : ''}',
            style: TextStyle(color: _dim),
          ),
          if (unlocked.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(unlocked,
                key: const ValueKey('unlocked'),
                style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
          ],
          const SizedBox(height: 12),
          DealRecap(
            tricks: (e.trickWinsNS, e.trickWinsEW),
            points: (e.pointsNS, e.pointsEW),
            tokens: (e.tokens['NS']!, e.tokens['EW']!),
            delta: e.tokens['NS']! - _tokensAtStart['NS']!,
          ),
        ]),
        actions: [
          if (replay != null)
            TextButton.icon(
              key: const ValueKey('open-replay'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ReplayScreen(replay: replay, names: [
                        l.seatYou,
                        l.seatEast,
                        l.seatNorth,
                        l.seatWest
                      ]))),
              icon: const Icon(Icons.history),
              label: Text(l.replayTitle),
            ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (over) e.tokens = {'NS': 11, 'EW': 11};
              _startHand();
            },
            child: Text(over ? l.playAgain : l.nextDeal),
          ),
        ],
      ),
    );
  }

  /// Fin de la donne du jour : score (jetons ±, points), partage, retour.
  void _showDailyResult(bool nsWon, Map<String, dynamic> s,
      {DealReplay? replay}) {
    final delta = e.tokens['NS']! - 11;
    final score = l.dailyScore(delta > 0 ? '+$delta' : '$delta', e.pointsNS);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('daily-result'),
        scrollable: true,
        backgroundColor: sk.dialog,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _goldD)),
        title: Text('${l.dailyDeal} — ${nsWon ? l.dealWon : l.dealLost}',
            style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            '${s['pcc'] == true ? 'Partner Close Caps · ${s['tricks']}/8' : '${l.bid} ${s['bid']} · ${l.pointsN(s['tmPoints'] as int)}'} — ${s['success'] == true ? l.succeeded : l.failedBid}',
            style: TextStyle(color: _dim),
          ),
          const SizedBox(height: 10),
          Text(score,
              key: const ValueKey('daily-score'),
              style: TextStyle(
                  color: _gold, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(_official ? l.dailyOfficial : l.dailyPractice,
              textAlign: TextAlign.center,
              style: TextStyle(color: _dim, fontSize: 12)),
          if (_official && daily.value.streak > 1) ...[
            const SizedBox(height: 4),
            Text(l.dailyStreak(daily.value.streak),
                style: TextStyle(color: _dim, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          DealRecap(
            tricks: (e.trickWinsNS, e.trickWinsEW),
            points: (e.pointsNS, e.pointsEW),
            tokens: (e.tokens['NS']!, e.tokens['EW']!),
            delta: delta,
          ),
        ]),
        actions: [
          if (replay != null)
            TextButton.icon(
              key: const ValueKey('open-replay'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ReplayScreen(replay: replay, names: [
                        l.seatYou,
                        l.seatEast,
                        l.seatNorth,
                        l.seatWest
                      ]))),
              icon: const Icon(Icons.history),
              label: Text(l.replayTitle),
            ),
          TextButton.icon(
            key: const ValueKey('daily-share'),
            onPressed: () => shareDaily(context, _day, score),
            icon: const Icon(Icons.share),
            label: Text(l.dailyShareBtn),
          ),
          FilledButton(
            key: const ValueKey('daily-home'),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: Text(l.backHome),
          ),
        ],
      ),
    );
  }

  /// Nom d'un dos de cartes / tapis débloqué ('back:emerald'…).
  String _unlockName(String k) => switch (k) {
        'back:emerald' => '${l.cardBack} · ${l.backEmerald}',
        'back:ruby' => '${l.cardBack} · ${l.backRuby}',
        'back:peacock' => '${l.cardBack} · ${l.backPeacock}',
        'felt:crimson' => '${l.tableFelt} · ${l.feltCrimson}',
        'felt:midnight' => '${l.tableFelt} · ${l.feltMidnight}',
        'felt:sand' => '${l.tableFelt} · ${l.feltSand}',
        _ => k,
      };

  // ============================ widgets ============================
  Widget _btn(String label, VoidCallback onTap,
      {bool primary = false, bool gold = false, Key? key}) {
    if (label == _hintLabel) {
      return OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.lightbulb_outline, size: 18),
          label: Text(label));
    }
    if (gold) {
      return FilledButton(
          key: key,
          onPressed: onTap,
          style: FilledButton.styleFrom(
              backgroundColor: _gold, foregroundColor: sk.onAccent),
          child: Text(label));
    }
    if (primary) {
      return FilledButton(key: key, onPressed: onTap, child: Text(label));
    }
    return OutlinedButton(onPressed: onTap, child: Text(label));
  }

  bool _isActive(int s) =>
      (e.phase == 'bid1' && e.bidTurn == s) ||
      (e.phase == 'bid2' && e.bid2Turn == s) ||
      (e.phase == 'play' && e.turn == s);

  Widget _cardWidget(Card c,
      {Key? key,
      bool big = false,
      bool playable = false,
      bool hinted = false,
      VoidCallback? onTap}) {
    final col = suitColor(c.suit, ink: _ink, red: _red);
    final k = _k; // grandes cartes (réglage d'accessibilité)
    final w = (big ? 52.0 : 46.0) * k, h = (big ? 74.0 : 66.0) * k;
    final card = Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, _cream]),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
            color: hinted
                ? const Color(0xFF7FD7FF)
                : playable
                    ? _gold
                    : Colors.black26,
            width: hinted ? 3 : (playable ? 2 : 1)),
        boxShadow: [
          const BoxShadow(
              color: Colors.black45, blurRadius: 5, offset: Offset(0, 2)),
          if (hinted) const BoxShadow(color: Color(0xAA7FD7FF), blurRadius: 14),
        ],
      ),
      alignment: Alignment.center,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(c.rank,
            style: TextStyle(
                color: col,
                fontWeight: FontWeight.bold,
                fontSize: (big ? 19 : 17) * k,
                height: 1)),
        Text(kSuitSym[c.suit]!,
            style: TextStyle(
                color: col, fontSize: (big ? 17 : 15) * k, height: 1)),
      ]),
    );
    return onTap != null
        ? GestureDetector(key: key, onTap: onTap, child: card)
        : KeyedSubtree(key: key, child: card);
  }

  Widget _facedown({bool big = true}) => Container(
        width: big ? 52 * _k : 24,
        height: big ? 74 * _k : 34,
        decoration: cardBackDecoration(), // dos choisi dans les réglages
      );

  /// [compact] : avatar seul (écran étroit, évite le chevauchement avec la main).
  Widget _pod(int seat, {bool compact = false}) {
    final active = _isActive(seat);
    final muted = e.soloMode && e.mutedSeat == seat;
    // le joueur : son prénom (s'il en a choisi un) et son avatar
    final base = seat == 0 && playerName.value.isNotEmpty
        ? playerName.value
        : [l.seatYou, l.seatEast, l.seatNorth, l.seatWest][seat];
    var meta = seat == 0
        ? l.mSud
        : seat == 2
            ? l.mPartner
            : l.mAI;
    if (e.trumpMaker == seat) meta = e.pcc ? l.mSolo : l.mMaker;
    if (muted) meta = l.mOut;
    return Opacity(
      key: ValueKey('pod-$seat'),
      opacity: muted ? 0.55 : 1,
      child: Container(
        padding: EdgeInsets.fromLTRB(3, 3, compact ? 3 : 10, 3),
        decoration: BoxDecoration(
          color: sk.pod,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: active ? _gold : sk.line, width: active ? 2 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [sk.surface, sk.bg]),
              // avatar seul : bordure dorée épaisse = preneur
              border: Border.all(
                  color: active || (compact && e.trumpMaker == seat)
                      ? _gold
                      : _goldD,
                  width: compact && e.trumpMaker == seat ? 3 : 2),
            ),
            child: seat == 0
                ? Icon(kAvatars[avatar.value].$1,
                    size: 17, color: kAvatars[avatar.value].$2)
                : Text(base.characters.first,
                    style: TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
          ),
          if (!compact) const SizedBox(width: 6),
          if (!compact)
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(base, style: TextStyle(color: _txt, fontSize: 12)),
                  Text(meta.toUpperCase(),
                      style: TextStyle(
                          color: e.trumpMaker == seat ? _gold : _dim,
                          fontSize: 9,
                          letterSpacing: 0.4)),
                ]),
        ]),
      ),
    );
  }

  Alignment _seatAlign(int s) {
    switch (s) {
      case 0:
        return Alignment.bottomCenter;
      case 1:
        return Alignment.centerRight;
      case 2:
        return Alignment.topCenter;
      default:
        return Alignment.centerLeft;
    }
  }

  Widget _trickArea() {
    return SizedBox(
      width: 176 * _k,
      height: 168 * _k,
      child: Stack(
        children: [
          for (final p in _doneTrick ?? e.currentTrick)
            Align(
              alignment: _seatAlign(p.seat),
              child: _doneTrick == null
                  ? _trickCard(p)
                  : GatherTo(
                      key: ValueKey('gather-${e.tricks.length}-${p.seat}'),
                      toward: _seatAlign(_doneWinner),
                      duration: botDelay(950),
                      child: _trickCard(p)),
            ),
        ],
      ),
    );
  }

  Widget _trickCard(TrickPlay p) => (p.faceDown && !e.trumpOpen)
      ? _facedown()
      : _cardWidget(p.card, big: true);

  Widget _handFan() {
    final h = e.hands[human];
    final k = _k;
    if (h.isEmpty) return SizedBox(height: 118 * k);
    return LayoutBuilder(builder: (ctx, cons) {
      final n = h.length;
      final spacing =
          n > 1 ? ((cons.maxWidth - 60 * k) / n).clamp(26.0, 42.0 * k) : 0.0;
      final totalW = spacing * (n - 1) + 56 * k;
      final startX = (cons.maxWidth - totalW) / 2;
      final mid = (n - 1) / 2;
      return SizedBox(
        height: 118 * k,
        width: cons.maxWidth,
        child: Stack(
          children: [
            // la carte est capturée par valeur : un 2e toucher rapide sur une
            // carte déjà jouée ne lit plus une case de la main qui a changé
            for (final (i, c) in List.of(h).indexed)
              Positioned(
                key: ValueKey('deal-${c.key}'),
                left: startX + i * spacing,
                bottom: 6.0 + (mid - (i - mid).abs()) * 3.0,
                child: DealIn(
                  index: i,
                  child: Transform.rotate(
                    angle: (i - mid) * 0.06,
                    child: _cardWidget(
                      c,
                      key:
                          ValueKey('${_canPlay(c) ? 'play' : 'hand'}-${c.key}'),
                      big: true,
                      playable: _canPlay(c),
                      hinted: _hinted == c.key,
                      onTap: _canPlay(c) ? () => _onHumanCard(c) : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _trumpChip() {
    final t = e.trumpSuit;
    final txt = (t != null && e.trumpOpen)
        ? '${l.trump} ${kSuitSym[t]}'
        : l.trumpHidden;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: sk.pod,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _goldD),
      ),
      child: Text(txt, style: TextStyle(color: _txt, fontSize: 12)),
    );
  }

  Widget _stat(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(k.toUpperCase(),
              style: TextStyle(color: _dim, fontSize: 9, letterSpacing: 0.6)),
          Text(v,
              style: TextStyle(
                  color: color ?? _txt,
                  fontWeight: FontWeight.w800,
                  fontSize: 17)),
        ]),
      );

  Widget _teamPanel(String label, int tok, Color c) => Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: sk.pod,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sk.line),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: _dim, fontSize: 11)),
          Text('$tok',
              style: TextStyle(
                  color: c,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  height: 1)),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: tok / 22,
              minHeight: 5,
              backgroundColor: sk.line,
              valueColor: AlwaysStoppedAnimation<Color>(_gold),
            ),
          ),
        ]),
      );

  Widget _scoreboard() {
    final t = e.trumpSuit;
    String trumpTxt;
    Color trumpColor = _txt;
    if (t != null && e.trumpOpen) {
      trumpTxt = kSuitSym[t]!;
      trumpColor = (t == 'D' || t == 'H') ? const Color(0xFFE06666) : _txt;
    } else if (t != null) {
      trumpTxt = l.closed;
    } else {
      trumpTxt = '—';
    }
    String tgtUs = '—', tgtThem = '—';
    if (e.bid != null && e.trumpMaker != null) {
      if (e.pcc) {
        tgtUs = teamOf(e.trumpMaker!) == 'NS' ? l.eightTricks : l.def;
        tgtThem = teamOf(e.trumpMaker!) == 'EW' ? l.eightTricks : l.def;
      } else {
        final us = teamOf(e.trumpMaker!) == 'NS' ? e.bid! : 305 - e.bid!;
        tgtUs = '$us';
        tgtThem = '${305 - us}';
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [sk.bar.$1, sk.bar.$2]),
      ),
      child: Column(children: [
        Row(children: [
          // retour à l'accueil (avec confirmation) : seul moyen sur le web/iPhone
          IconButton(
            key: const ValueKey('leave-game'),
            tooltip: l.backHome,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.arrow_back, color: _dim, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          _teamPanel(l.us, e.tokens['NS']!, _gold),
          Expanded(
            // réduit l'ensemble sur les écrans étroits au lieu de déborder
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _stat(l.bid, e.pcc ? 'PCC' : (e.bid?.toString() ?? '—')),
                _stat(l.trump, trumpTxt, color: trumpColor),
                _stat(l.tricks, '${e.trickWinsNS}–${e.trickWinsEW}'),
              ]),
            ),
          ),
          _teamPanel(l.them, e.tokens['EW']!, sk.accent2),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(
            child: Text('${l.tgtUs} $tgtUs',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _dim, fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text('${l.tgtThem} $tgtThem',
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: _dim, fontSize: 11)),
          ),
        ]),
      ]),
    );
  }

  Widget _table() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
              center: const Alignment(0, -0.1),
              radius: 0.95,
              colors: [
                sk.tableColors.$1,
                sk.tableColors.$2
              ]), // thème (Bois : tapis choisi)
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sk.tableBorder, width: 2),
          boxShadow: [
            const BoxShadow(
                color: Colors.black54, blurRadius: 16, offset: Offset(0, 8)),
            // Cristal / Nuit : liseré lumineux autour de la table
            if (sk.glow != null)
              BoxShadow(
                  color: sk.glow!.withValues(alpha: 0.35), blurRadius: 30),
          ],
        ),
        child: LayoutBuilder(builder: (context, cons) {
          // écran étroit : la pastille d'atout passe sous la rangée de Nord et
          // le pion du joueur se réduit à son avatar (textes longs en ta/si)
          final narrow = cons.maxWidth < 520;
          const podH = 46.0; // hauteur d'un pion réduit (avatar)
          final h = cons.maxHeight;
          // écran étroit : bande libre entre la pastille d'atout et la main
          final bandTop = narrow ? 96.0 : 0.0;
          final youBottom = narrow ? 118 * _k + 4 : 8.0;
          final bandBottom = h - youBottom;
          // pion du joueur au-dessus de la main s'il y a la place pour lui ET
          // pour Est/Ouest au-dessus ; sinon masqué (table basse pendant les
          // enchères sur petit écran, surtout avec les grandes cartes)
          final showYou = !narrow || bandBottom - bandTop >= 2 * podH + 10;
          final sideTop = math.max(
              0.0,
              narrow
                  ? (showYou
                      ? math.min((h - podH) / 2, bandBottom - 2 * podH - 10)
                      : (bandTop + bandBottom - podH) / 2)
                  : (h - podH) / 2);
          return Stack(
            children: [
              Positioned(top: narrow ? 58 : 10, left: 12, child: _trumpChip()),
              Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                      padding: const EdgeInsets.only(top: 6), child: _pod(2))),
              // Est / Ouest : au milieu, mais toujours au-dessus du pion du
              // joueur (table basse sur petit écran pendant les enchères)
              Positioned(
                  right: 6, top: sideTop, child: _pod(1, compact: narrow)),
              Positioned(
                  left: 6, top: sideTop, child: _pod(3, compact: narrow)),
              Align(alignment: Alignment.center, child: _trickArea()),
              if (showYou)
                Positioned(
                    left: 10,
                    bottom: youBottom, // au-dessus de la main
                    child: _pod(0, compact: narrow)),
              Align(alignment: Alignment.bottomCenter, child: _handFan()),
            ],
          );
        }),
      ),
    );
  }

  Widget _panel() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [sk.panel.$1, sk.panel.$2]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.daily)
            Text('${l.dailyDeal} · $_day',
                key: const ValueKey('daily-label'),
                style: TextStyle(color: _gold, fontSize: 11)),
          Text(msg, style: TextStyle(color: _txt, fontSize: 13)),
          if (tip.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(tip, style: TextStyle(color: _dim, fontSize: 11.5)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LeaveGuard(
      child: Scaffold(
        backgroundColor: _woodB,
        body: SafeArea(
          child: Column(
            children: [
              _scoreboard(),
              Expanded(child: _table()),
              _panel(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Raison d'un conseil de jeu, dans la langue du joueur.
String whyText(AppLocalizations l, PlayWhy w) => switch (w) {
      PlayWhy.capsRun => l.whyCapsRun,
      PlayWhy.drawTrumps => l.whyDrawTrumps,
      PlayWhy.cashMaster => l.whyCashMaster,
      PlayWhy.leadLow => l.whyLeadLow,
      PlayWhy.loadPartner => l.whyLoadPartner,
      PlayWhy.partnerLow => l.whyPartnerLow,
      PlayWhy.cantWin => l.whyCantWin,
      PlayWhy.lastSmallWin => l.whyLastSmallWin,
      PlayWhy.sureWin => l.whySureWin,
      PlayWhy.worthTaking => l.whyWorthTaking,
      PlayWhy.notWorth => l.whyNotWorth,
      PlayWhy.ruff => l.whyRuff,
      PlayWhy.discard => l.whyDiscard,
      PlayWhy.ruffSmall => l.whyRuffSmall,
      PlayWhy.cutIndicator => l.whyCutIndicator,
      PlayWhy.guessRuff => l.whyGuessRuff,
    };
