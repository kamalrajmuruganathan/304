// ============================================================================
// Classement entre amis : donne du jour et parties gagnées (lib/net/ranking.dart).
// Rien n'est envoyé avant que le joueur touche « Activer le classement ».
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../net/ranking.dart';
import '../settings.dart';
import 'skin.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});
  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _code = TextEditingController();
  RankBoard? _board;
  String? _error; // code d'erreur (RankError.code)
  String? _info; // message après un ajout
  bool _busy = false;

  AppLocalizations get l => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (Ranking.me.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _code.dispose();
    super.dispose();
  }

  String _err(String c) => switch (c) {
        'network' => l.rankErrNetwork,
        'code' => l.rankErrCode,
        'self' => l.rankErrSelf,
        'tooMany' => l.rankErrTooMany,
        _ => l.rankErrOther,
      };

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on RankError catch (e) {
      if (e.code == 'unknown') await Ranking.forget();
      if (mounted) setState(() => _error = e.code);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _refresh() => _run(() async {
        await Ranking.instance.ensure();
        final b = await Ranking.instance.board();
        if (mounted) setState(() => _board = b);
      });

  Future<void> _add() async {
    final c = _code.text.trim();
    if (c.isEmpty) return;
    await _run(() async {
      final name = await Ranking.instance.addFriend(c);
      _code.clear();
      _info = l.rankAdded(name.isEmpty ? c.toUpperCase() : name);
      final b = await Ranking.instance.board();
      if (mounted) setState(() => _board = b);
    });
  }

  Future<void> _remove(RankRow r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.rankRemove(r.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel)),
          FilledButton(
              key: const ValueKey('rank-remove-ok'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.rankRemoveOk)),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await Ranking.instance.removeFriend(r.id);
      final b = await Ranking.instance.board();
      if (mounted) setState(() => _board = b);
    });
  }

  Future<void> _share(String code) async {
    final text = l.rankShareText(
        code, 'https://kamalrajmuruganathan.github.io/304/app/');
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final joined = Ranking.me.value != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.rankTitle),
        bottom: joined && _board != null
            ? TabBar(controller: _tabs, tabs: [
                Tab(key: const ValueKey('rank-tab-daily'), text: l.rankToday),
                Tab(key: const ValueKey('rank-tab-games'), text: l.rankGames),
              ])
            : null,
      ),
      body: SafeArea(
        child: !joined
            ? _intro()
            : _board == null
                ? _loading()
                : _boardView(_board!),
      ),
    );
  }

  Widget _errorLine() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_err(_error!),
              key: const ValueKey('rank-error'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFE5534B))),
        );

  Widget _intro() => ListView(padding: const EdgeInsets.all(24), children: [
        Icon(Icons.emoji_events_outlined, size: 56, color: sk.accent),
        const SizedBox(height: 16),
        Text(l.rankIntro, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        SkinPrimaryButton(
          key: const ValueKey('rank-join'),
          label: l.rankJoin,
          icon: Icons.group_add,
          onPressed: _busy ? () {} : _refresh,
        ),
        if (_busy)
          const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator())),
        _errorLine(),
      ]);

  Widget _loading() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_busy) const CircularProgressIndicator(),
            _errorLine(),
            if (!_busy && _error != null)
              TextButton(
                  key: const ValueKey('rank-retry'),
                  onPressed: _refresh,
                  child: Text(l.rankRetry)),
          ]),
        ),
      );

  Widget _boardView(RankBoard b) {
    final friends = b.rows.where((r) => !r.me).length;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: SelectableText(l.rankMyCode(b.code),
                key: const ValueKey('rank-code'),
                style: TextStyle(
                    color: sk.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          IconButton(
              key: const ValueKey('rank-share'),
              tooltip: l.rankShareCode,
              onPressed: () => _share(b.code),
              icon: const Icon(Icons.share)),
        ]),
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('rank-code-field'),
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: InputDecoration(
                  hintText: l.rankAddHint, counterText: '', isDense: true),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
              key: const ValueKey('rank-add'),
              onPressed: _busy ? null : _add,
              child: Text(l.rankAdd)),
        ]),
        if (_info != null && _error == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_info!,
                key: const ValueKey('rank-info'),
                style: TextStyle(color: sk.dim)),
          ),
        _errorLine(),
        if (friends == 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l.rankNoFriends,
                key: const ValueKey('rank-no-friends'),
                style: TextStyle(color: sk.dim)),
          ),
      ]),
    );
    return Column(children: [
      header,
      Expanded(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: TabBarView(controller: _tabs, children: [
            ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                    b.rank == null
                        ? l.rankPlayDaily
                        : l.rankPosition(b.rank!, b.total),
                    key: const ValueKey('rank-position'),
                    style: TextStyle(color: sk.dim)),
              ),
              for (final (i, r) in b.daily.indexed)
                _tile(
                    i + 1,
                    r,
                    r.delta == null
                        ? l.rankNotPlayed
                        : l.dailyScore(
                            r.delta! > 0 ? '+${r.delta}' : '${r.delta}',
                            r.points ?? 0)),
            ]),
            ListView(children: [
              for (final (i, r) in b.games.indexed)
                _tile(i + 1, r, l.rankWon(r.won, r.played)),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _tile(int pos, RankRow r, String detail) => ListTile(
        key: ValueKey('rank-row-${r.id}'),
        leading: SizedBox(
          width: 64,
          child: Row(children: [
            SizedBox(
                width: 24,
                child: Text('$pos',
                    style: TextStyle(
                        color: sk.accent, fontWeight: FontWeight.bold))),
            avatarIcon(r.avatar, size: 34),
          ]),
        ),
        title: Text(
            r.me
                ? (r.name.isEmpty ? l.seatYou : '${r.name} (${l.seatYou})')
                : r.name,
            style: TextStyle(
                fontWeight: r.me ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text(detail),
        trailing: r.me
            ? null
            : IconButton(
                key: ValueKey('rank-remove-${r.id}'),
                tooltip: l.rankRemoveOk,
                onPressed: _busy ? null : () => _remove(r),
                icon: const Icon(Icons.person_remove_outlined)),
      );
}
