// ============================================================================
// Statistiques détaillées des parties solo (mémorisées sous `stats304`).
// ============================================================================
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../settings.dart';

const _gold = Color(0xFFD4A72C);

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.statsTitle)),
      body: SafeArea(
        child: ValueListenableBuilder<Stats>(
          valueListenable: stats,
          builder: (context, st, _) {
            if (st.played == 0) {
              return Center(
                  child: Text(l.noStats, key: const ValueKey('no-stats')));
            }
            String pct(int a, int b) =>
                b == 0 ? '—' : '${(100 * a / b).round()} %';
            final tierLabel = {
              'lt200': l.tierLt200,
              'lt250': l.tierLt250,
              'ge250': l.tierGe250,
              'pcc': 'Partner Close Caps',
            };
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _Row(l.dealsPlayed, '${st.played}'),
                _Row(l.dealsWonPct, '${st.won} · ${pct(st.won, st.played)}',
                    key: const ValueKey('stat-won')),
                _Row(l.capsMade, '${st.caps}'),
                const SizedBox(height: 8),
                Text(l.gamesRecord(st.gamesWon, st.gamesLost)),
                const SizedBox(height: 4),
                Text(l.streaks(st.streak, st.bestStreak)),
                const SizedBox(height: 24),
                Text(l.yourBids,
                    style: const TextStyle(
                        color: _gold,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final t in Stats.tiers)
                  _Row(
                    tierLabel[t]!,
                    '${l.madeOf(st.made[t] ?? 0, st.taken[t] ?? 0)}'
                    ' · ${pct(st.made[t] ?? 0, st.taken[t] ?? 0)}',
                    key: ValueKey('tier-$t'),
                  ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  key: const ValueKey('reset-stats'),
                  onPressed: resetStats,
                  icon: const Icon(Icons.restart_alt),
                  label: Text(l.resetStats),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {super.key});
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ]),
      );
}
