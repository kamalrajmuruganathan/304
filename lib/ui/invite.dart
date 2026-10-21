// ============================================================================
// Inviter des amis à une table privée : lien direct (?table=CODE) partagé par
// la feuille de partage du téléphone (WhatsApp…), sinon copié dans le
// presse-papiers. Et réactions rapides du chat (codes traduits chez chacun).
// ============================================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
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

/// Code de table d'un lien d'invitation : `…/304/app/?table=ABCD` (web, ou
/// lien https reçu par l'appli) ou `game304://table/ABCD` (appli Android
/// ouverte depuis la page web). Sans argument : adresse de la page (web).
String? tableFromUrl([Uri? uri]) {
  if (!kIsWeb && uri == null) return null;
  final u = uri ?? Uri.base;
  final raw = u.scheme == kAppScheme && u.host == 'table'
      ? (u.pathSegments.isEmpty ? null : u.pathSegments.first)
      : u.queryParameters['table'];
  final c = raw?.toUpperCase();
  return (c != null && RegExp(r'^[A-Z0-9]{4}$').hasMatch(c)) ? c : null;
}

/// Schéma des liens qui ouvrent l'appli Android (`game304://table/ABCD`).
const String kAppScheme = 'game304';
const String kAndroidPackage = 'com.kjtech.game304';

/// Page de téléchargement de l'APK (si l'appli n'est pas installée).
const String kApkPage =
    'https://github.com/kamalrajmuruganathan/304/releases/latest';

/// Lien « intent » de Chrome Android : ouvre l'appli à la table [code] si elle
/// est installée, sinon la page de téléchargement de l'APK.
String appIntentLink(String code) => 'intent://table/$code#Intent;'
    'scheme=$kAppScheme;package=$kAndroidPackage;'
    'S.browser_fallback_url=${Uri.encodeComponent(kApkPage)};end';

/// Page web ouverte sur un téléphone Android : on propose l'appli.
bool get offerAndroidApp =>
    kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<void> openInAndroidApp(String code) async {
  try {
    await launchUrl(Uri.parse(appIntentLink(code)), webOnlyWindowName: '_self');
  } catch (_) {}
}

/// Partage l'invitation. Téléphone : feuille de partage du système.
/// Ordinateur (web) : copie dans le presse-papiers.
Future<void> shareInvite(BuildContext context, String code) async {
  final l = AppLocalizations.of(context)!;
  await _shareText(context, l.inviteText(inviteLink(code), code), l.linkCopied);
}

/// Lien qui ouvre directement la donne du jour (app web).
String dailyLink() {
  final base = kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : kInviteBase;
  return '$base?daily=1';
}

/// L'adresse de la page demande-t-elle la donne du jour ? (`?daily=1`)
bool dailyFromUrl([Uri? uri]) {
  if (!kIsWeb && uri == null) return false;
  return (uri ?? Uri.base).queryParameters['daily'] == '1';
}

/// Partage le score de la donne du jour (même logique que l'invitation).
Future<void> shareDaily(BuildContext context, String day, String score) async {
  final l = AppLocalizations.of(context)!;
  await _shareText(
      context, l.dailyShareText(day, score, dailyLink()), l.scoreCopied);
}

/// Feuille de partage du téléphone, sinon copie (message [copied]).
Future<void> _shareText(
    BuildContext context, String text, String copied) async {
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
  messenger.showSnackBar(SnackBar(content: Text(copied)));
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
