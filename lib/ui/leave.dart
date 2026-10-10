// ============================================================================
// Quitter une partie : demande confirmation (geste « retour » accidentel sur
// téléphone, flèche de la barre du haut, bouton de l'écran solo).
// ============================================================================
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Demande « Quitter la partie ? » ; vrai si le joueur confirme.
Future<bool> confirmLeave(BuildContext context) async {
  final l = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.leaveGame),
      actions: [
        TextButton(
            key: const ValueKey('leave-stay'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.stay)),
        FilledButton(
            key: const ValueKey('leave-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.leave)),
      ],
    ),
  );
  return ok == true;
}

/// Bloque le retour arrière tant que le joueur n'a pas confirmé.
class LeaveGuard extends StatelessWidget {
  const LeaveGuard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = Navigator.of(context);
          if (await confirmLeave(context)) nav.pop();
        },
        child: child,
      );
}
