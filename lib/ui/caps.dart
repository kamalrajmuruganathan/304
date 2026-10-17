// ============================================================================
// Annonce « Caps » : confirmation avant d'annoncer (une annonce sans certitude
// coûte 2 jetons — Wrong Caps). Ne dit pas si l'annonce serait juste.
// ============================================================================
import 'package:flutter/material.dart';
import '../engine/engine.dart' show kWrongCapsPenalty;
import '../l10n/app_localizations.dart';

/// Demande « Annoncer Caps ? » ; vrai si le joueur confirme.
Future<bool> confirmCaps(BuildContext context) async {
  final l = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(l.capsConfirm(kWrongCapsPenalty)),
      actions: [
        TextButton(
            key: const ValueKey('caps-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel)),
        FilledButton(
            key: const ValueKey('caps-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.callCaps)),
      ],
    ),
  );
  return ok == true;
}
