// ============================================================================
// Inviter des amis à une table privée : lien direct (?table=CODE) partagé par
// la feuille de partage du téléphone (WhatsApp…), sinon copié dans le
// presse-papiers. Et réactions rapides du chat (codes traduits chez chacun).
// ============================================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';

/// Adresse de l'app web (le lien ouvre la table directement, sans store).
const String kInviteBase = String.fromEnvironment('INVITE_URL',
    defaultValue: 'https://kamalrajmuruganathan.github.io/304/app/');

/// Lien d'invitation : sur le web, l'adresse de la page en cours (marche
/// quel que soit l'hébergement) ; sinon l'app web publiée.
String inviteLink(String code) {
  final base = kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : kInviteBase;
  return '$base?table=$code';
}

/// Code de table présent dans l'adresse (?table=ABCD), sur le web.
String? tableFromUrl([Uri? uri]) {
  if (!kIsWeb && uri == null) return null;
  final c = (uri ?? Uri.base).queryParameters['table']?.toUpperCase();
  return (c != null && RegExp(r'^[A-Z0-9]{4}$').hasMatch(c)) ? c : null;
}

/// Partage l'invitation. Téléphone : feuille de partage du système.
/// Ordinateur (web) : copie dans le presse-papiers.
Future<void> shareInvite(BuildContext context, String code) async {
  final l = AppLocalizations.of(context)!;
  final text = l.inviteText(inviteLink(code), code);
  final messenger = ScaffoldMessenger.of(context);
  final mobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (mobile) {
    try {
      final r = await SharePlus.instance.share(ShareParams(text: text));
      if (r.status != ShareResultStatus.unavailable) return;
    } catch (_) {}
  }
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (_) {}
  messenger.showSnackBar(SnackBar(content: Text(l.linkCopied)));
}

/// Réactions rapides : envoyées comme message de chat « :r:clé », affichées
/// traduites dans la langue de chaque joueur.
const kReactions = [
  'wellPlayed',
  'comeOn',
  'oops',
  'thanks',
  'hurry',
  'goodGame'
];

String reactionCode(String key) => ':r:$key';

/// Texte affiché d'un message de chat (réaction traduite, sinon tel quel).
String chatText(AppLocalizations l, String text) {
  final m = RegExp(r'^:r:(\w+)$').firstMatch(text);
  if (m == null) return text;
  switch (m[1]) {
    case 'wellPlayed':
      return l.rWellPlayed;
    case 'comeOn':
      return l.rComeOn;
    case 'oops':
      return l.rOops;
    case 'thanks':
      return l.rThanks;
    case 'hurry':
      return l.rHurry;
    case 'goodGame':
      return l.rGoodGame;
  }
  return text;
}
