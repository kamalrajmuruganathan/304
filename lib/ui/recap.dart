// ============================================================================
// Récapitulatif d'une donne terminée, vu de l'équipe du joueur : plis,
// points et jetons (avec leur variation). Partagé par le solo et l'en ligne ;
// toutes les valeurs viennent du moteur (aucun recalcul des règles ici).
// ============================================================================
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class DealRecap extends StatelessWidget {
  const DealRecap({
    super.key,
    required this.tricks,
    required this.points,
    required this.tokens,
    required this.delta,
    this.color = const Color(0xFFF3E9D2),
    this.dim = const Color(0xFFB9A98A),
  });

  /// (nous, eux) pour chaque ligne.
  final (int, int) tricks, points, tokens;

  /// Variation des jetons de notre équipe pendant la donne.
  final int delta;
  final Color color, dim;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    String signed(int n) => n > 0 ? '+$n' : '$n';
    TableRow row(String label, String us, String them, {bool head = false}) {
      final st = TextStyle(
          color: head ? dim : color,
          fontWeight: head ? FontWeight.normal : FontWeight.bold,
          fontSize: head ? 12 : 15);
      Widget cell(String s, TextAlign a) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          child: Text(s, textAlign: a, style: st));
      return TableRow(children: [
        cell(label, TextAlign.start),
        cell(us, TextAlign.end),
        cell(them, TextAlign.end),
      ]);
    }

    return Table(
      key: const ValueKey('deal-recap'),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      columnWidths: const {0: FlexColumnWidth()},
      children: [
        row('', l.us, l.them, head: true),
        row(l.tricks, '${tricks.$1}', '${tricks.$2}'),
        row(l.points, '${points.$1}', '${points.$2}'),
        row(l.tokens, '${tokens.$1} (${signed(delta)})',
            '${tokens.$2} (${signed(-delta)})'),
      ],
    );
  }
}
