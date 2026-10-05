// ============================================================================
// « Apprendre le 304 » : règles résumées, dans la langue de l'app.
// FR/EN repris du tutoriel du prototype (score précisé : pénalités −2/−3/−4).
// TA/SI : traduction par Claude, vocabulaire du dictionnaire du prototype
// (துருப்பு, ஏலம், கை / තුරුම්පුව, ලංසුව, අත) — relecture native à faire.
// ============================================================================
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Sections (titre, texte) par langue.
const kTutorial = <String, List<(String, String)>>{
  'fr': [
    (
      'But du jeu',
      '4 joueurs, 2 équipes : vous et Nord contre Est et Ouest. On enchérit des '
          'points, puis on essaie de les réaliser en remportant des plis. Chaque '
          'équipe commence avec 11 jetons ; chaque donne en fait passer d\'une '
          'équipe à l\'autre. L\'équipe qui n\'a plus de jetons perd.'
    ),
    (
      'Les 32 cartes et leurs points',
      'Valet (J) = 30 · 9 = 20 · As = 11 · 10 = 10 · Roi = 3 · Dame = 2 · '
          '8 et 7 = 0.\nTotal : 304 points. Ordre de force : '
          'J > 9 > A > 10 > K > Q > 8 > 7.'
    ),
    (
      'Déroulé d\'une donne',
      '4 cartes chacun → 1er tour d\'enchères (de 160 à 240) → le gagnant pose '
          'une carte face cachée : sa couleur est l\'atout → 4 cartes de plus → '
          '2e tour possible (250 et plus) → le preneur choisit le jeu fermé '
          '(atout caché) ou ouvert → 8 plis.'
    ),
    (
      'Atout caché',
      'Suivez la couleur demandée si vous pouvez. Sinon, jouez une carte face '
          'cachée : si c\'est un atout, elle peut couper. À la fin du pli, '
          'l\'atout est révélé si l\'une des cartes cachées en est un.'
    ),
    (
      'Partner Close Caps',
      'L\'annonce maximale du 2e tour : le preneur joue seul (son partenaire '
          'est écarté) et doit remporter les 8 plis. +4 jetons si c\'est '
          'réussi, −5 sinon.'
    ),
    (
      'Marquer',
      'Enchère réussie (points de l\'équipe du preneur ≥ enchère) : moins de '
          '200 → +1, de 200 à 249 → +2, 250 et plus → +3 ; les 8 plis (Caps) → '
          '+1 de bonus. Enchère chutée : −2, −3 ou −4.'
    ),
    ('Astuce', 'Touchez 💡 Conseil pour voir ce que jouerait l\'IA.'),
  ],
  'en': [
    (
      'Goal',
      '4 players, 2 teams: you and North against East and West. Bid for '
          'points, then try to make them by winning tricks. Each team starts '
          'with 11 tokens; every deal moves tokens from one team to the other. '
          'The team that runs out of tokens loses.'
    ),
    (
      'The 32 cards and their points',
      'Jack (J) = 30 · 9 = 20 · Ace = 11 · 10 = 10 · King = 3 · Queen = 2 · '
          '8 and 7 = 0.\nTotal: 304 points. Order: '
          'J > 9 > A > 10 > K > Q > 8 > 7.'
    ),
    (
      'How a deal goes',
      '4 cards each → round 1 bidding (160 to 240) → the winner places one '
          'card face down: its suit is trump → 4 more cards → optional round 2 '
          '(250 and up) → the declarer chooses a closed (hidden trump) or open '
          'game → 8 tricks.'
    ),
    (
      'Hidden trump',
      'Follow the led suit if you can. Otherwise play a card face down: if it '
          'is a trump, it can cut. At the end of the trick, the trump is '
          'revealed if one of the hidden cards is a trump.'
    ),
    (
      'Partner Close Caps',
      'The top bid of round 2: the declarer plays alone (their partner sits '
          'out) and must win all 8 tricks. +4 tokens if made, −5 if not.'
    ),
    (
      'Scoring',
      'Bid made (declarer\'s team points ≥ bid): under 200 → +1, 200 to 249 → '
          '+2, 250 and up → +3; all 8 tricks (Caps) → +1 bonus. Bid failed: '
          '−2, −3 or −4.'
    ),
    ('Tip', 'Tap 💡 Hint to see what the AI would play.'),
  ],
  'ta': [
    (
      'ஆட்டத்தின் நோக்கம்',
      '4 வீரர்கள், 2 அணிகள்: நீங்களும் வடக்கும் ஒரு அணி, கிழக்கும் மேற்கும் '
          'மற்றொரு அணி. முதலில் புள்ளிகளுக்கு ஏலம் கேட்கப்படும்; பின்னர் '
          'கைகளை வென்று அந்தப் புள்ளிகளை அடைய முயல வேண்டும். ஒவ்வொரு அணியும் '
          '11 நாணயங்களுடன் தொடங்கும்; ஒவ்வொரு பகிர்வும் ஓர் அணியிடமிருந்து '
          'மற்றொன்றுக்கு நாணயங்களை மாற்றும். நாணயங்கள் தீர்ந்த அணி தோற்கும்.'
    ),
    (
      '32 சீட்டுகளும் அவற்றின் புள்ளிகளும்',
      'J = 30 · 9 = 20 · A = 11 · 10 = 10 · K = 3 · Q = 2 · 8, 7 = 0.\n'
          'மொத்தம்: 304 புள்ளிகள். வலிமை வரிசை: '
          'J > 9 > A > 10 > K > Q > 8 > 7.'
    ),
    (
      'ஒரு பகிர்வின் ஓட்டம்',
      'ஒவ்வொருவருக்கும் 4 சீட்டுகள் → 1ஆம் சுற்று ஏலம் (160 முதல் 240 வரை) '
          '→ வென்றவர் ஒரு சீட்டைக் கவிழ்த்து வைப்பார்: அதன் வகையே துருப்பு → '
          'மேலும் 4 சீட்டுகள் → விருப்பமான 2ஆம் சுற்று (250 அல்லது அதற்கு மேல்) '
          '→ ஏலதாரர் மூடிய ஆட்டம் (துருப்பு மறைவு) அல்லது திறந்த ஆட்டத்தைத் '
          'தேர்ந்தெடுப்பார் → 8 கைகள்.'
    ),
    (
      'மறைந்த துருப்பு',
      'முடிந்தால் கேட்கப்பட்ட வகையையே இறக்குங்கள். முடியாவிட்டால், ஒரு '
          'சீட்டைக் கவிழ்த்து இறக்குங்கள்: அது துருப்பாக இருந்தால் வெட்டலாம். '
          'கையின் முடிவில், கவிழ்த்த சீட்டுகளில் ஒன்று துருப்பாக இருந்தால் '
          'துருப்பு வெளிப்படுத்தப்படும்.'
    ),
    (
      'Partner Close Caps',
      '2ஆம் சுற்றின் உச்ச ஏலம்: ஏலதாரர் தனியாக விளையாடுவார் (அவரது கூட்டாளி '
          'வெளியே இருப்பார்), 8 கைகளையும் வெல்ல வேண்டும். வென்றால் +4 '
          'நாணயங்கள், இல்லையெனில் −5.'
    ),
    (
      'புள்ளிக் கணக்கு',
      'ஏலம் வெற்றி (ஏலதாரர் அணியின் புள்ளிகள் ≥ ஏலம்): 200-க்குக் குறைவு → '
          '+1, 200 முதல் 249 வரை → +2, 250 அல்லது அதற்கு மேல் → +3; 8 கைகளும் '
          '(Caps) → +1 கூடுதல். ஏலம் தோல்வி: −2, −3 அல்லது −4.'
    ),
    (
      'குறிப்பு',
      'கணினி என்ன இறக்கும் என்று பார்க்க 💡 குறிப்பு பொத்தானைத் தொடுங்கள்.'
    ),
  ],
  'si': [
    (
      'ක්‍රීඩාවේ අරමුණ',
      'ක්‍රීඩකයන් 4ක්, කණ්ඩායම් 2ක්: ඔබ සහ උතුර එක් කණ්ඩායමක්, නැගෙනහිර සහ '
          'බටහිර අනෙක් කණ්ඩායම. මුලින් ලකුණු සඳහා ලංසු තබයි; ඉන්පසු අත් දිනා '
          'එම ලකුණු ලබා ගැනීමට උත්සාහ කරයි. සෑම කණ්ඩායමක්ම කාසි 11කින් ආරම්භ '
          'කරයි; සෑම බෙදීමක්ම එක් කණ්ඩායමකින් අනෙකට කාසි මාරු කරයි. කාසි '
          'අවසන් වූ කණ්ඩායම පරාජය වේ.'
    ),
    (
      'කාඩ්පත් 32 සහ ඒවායේ ලකුණු',
      'J = 30 · 9 = 20 · A = 11 · 10 = 10 · K = 3 · Q = 2 · 8, 7 = 0.\n'
          'මුළු එකතුව: ලකුණු 304. බල අනුපිළිවෙළ: '
          'J > 9 > A > 10 > K > Q > 8 > 7.'
    ),
    (
      'බෙදීමක පියවර',
      'එක් අයෙකුට කාඩ් 4 බැගින් → 1 වන වටයේ ලංසු (160 සිට 240 දක්වා) → '
          'ජයග්‍රාහකයා කාඩ්පතක් මුණින් තබයි: එහි වර්ගය තුරුම්පුව වේ → තවත් කාඩ් '
          '4ක් → අවශ්‍ය නම් 2 වන වටය (250 හෝ ඊට වැඩි) → ලංසුකරු වසා ඇති '
          '(තුරුම්පුව සැඟවූ) හෝ විවෘත ක්‍රීඩාව තෝරයි → අත් 8.'
    ),
    (
      'සැඟවුණු තුරුම්පුව',
      'හැකි නම් ඉල්ලූ වර්ගයේම කාඩ්පතක් දමන්න. නොහැකි නම්, කාඩ්පතක් මුණින් '
          'දමන්න: එය තුරුම්පුවක් නම් කැපිය හැක. අත අවසානයේ, මුණින් දැමූ '
          'කාඩ්පතක් තුරුම්පුවක් නම් තුරුම්පුව හෙළි වේ.'
    ),
    (
      'Partner Close Caps',
      '2 වන වටයේ උපරිම ලංසුව: ලංසුකරු තනිව ක්‍රීඩා කරයි (එම ක්‍රීඩකයාගේ සහකරු '
          'ඉවත් වේ) සහ අත් 8ම දිනිය යුතුය. සාර්ථක නම් කාසි +4, නැතහොත් −5.'
    ),
    (
      'ලකුණු ගණනය',
      'ලංසුව සාර්ථකයි (ලංසුකරුගේ කණ්ඩායමේ ලකුණු ≥ ලංසුව): 200ට අඩු → +1, '
          '200 සිට 249 දක්වා → +2, 250 හෝ ඊට වැඩි → +3; අත් 8ම (Caps) → +1 '
          'අමතර. ලංසුව අසාර්ථකයි: −2, −3 හෝ −4.'
    ),
    ('ඉඟිය', 'AI කුමක් දමයිද යන්න බැලීමට 💡 ඉඟිය බොත්තම ස්පර්ශ කරන්න.'),
  ],
};

class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final lang = Localizations.localeOf(context).languageCode;
    final sections = kTutorial[lang] ?? kTutorial['en']!;
    return Scaffold(
      appBar: AppBar(title: Text(l.learn304)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final (title, body) in sections) ...[
              Text(title,
                  style: const TextStyle(
                      color: Color(0xFFD4A72C),
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(fontSize: 14, height: 1.45)),
              const SizedBox(height: 18),
            ],
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.gotIt),
            ),
          ],
        ),
      ),
    );
  }
}
