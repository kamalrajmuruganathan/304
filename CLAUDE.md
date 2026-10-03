# CLAUDE.md — Projet 304 (game304)

Contexte complet pour reprendre le projet dans Claude Code. À lire en entier avant toute modification.

## 0. Consignes de travail

- **Répondre en français**, de façon concise et directe. L'utilisateur (Kamal) est Data Engineer
  (NiFi, GCP, Groovy) : pas besoin d'expliquer les bases du dev, mais Flutter/Dart et les stores
  sont nouveaux pour lui.
- **Ne jamais affirmer qu'un code marche sans l'avoir exécuté.** Lancer `flutter analyze`,
  `flutter test`, le test d'interface du prototype, et dire clairement ce qui est validé ou non.
- **Toute modification des règles se fait aux deux endroits** (prototype JS + moteur Dart) et
  doit être revalidée (simulations + tests). Le prototype est la référence validée.
- Ne jamais réutiliser le nom **« Thuru »** (marque de l'app concurrente).
- Ne pas dupliquer la logique de règles dans l'UI ou le client réseau : le moteur est l'unique
  source de vérité, et en ligne c'est le **serveur** qui fait autorité.

## 1. Le projet

Implémentation du **304**, jeu de plis par équipes populaire à Jaffna (Sri Lanka) et en Inde du
Sud, famille du Jass. Objectif : **publication** sur Android, iOS et web.

- Repo GitHub : `https://github.com/kamalrajmuruganathan/304` (le code n'y est pas encore poussé).
- Paquet Dart : **`game304`** (renommé depuis `thuru304`, nom trop proche du concurrent).
- Concurrent : **Thuru 304** (Shamrocks Games / Shamil Niyas) — iPhone uniquement, anglais
  uniquement, tables privées, voice chat, bots, tutoriel, cosmétiques.
- Différenciateurs visés : **Android + iOS + web**, **4 langues (FR, EN, தமிழ், සිංහල)**,
  web jouable instantanément sans store.

## 2. Arborescence

```
CLAUDE.md                  ce fichier
README.md                  vitrine + statut
PUSH.md                    pousser sur GitHub
pubspec.yaml               paquet game304 (Flutter ≥3.22, web_socket_channel, intl, l10n)
analysis_options.yaml      flutter_lints (+ prefer_const_constructors, prefer_final_locals)
l10n.yaml                  génération AppLocalizations depuis lib/l10n/*.arb
Dockerfile / .dockerignore serveur -> binaire natif -> Cloud Run
firebase.json              hosting de build/web (optionnel)
lib/
  engine/engine.dart       MOTEUR (Dart pur, aucune dépendance Flutter) + snapshot/viewFor réseau
  ai/bots.dart             IA v3 : est4/botBid, botBid2, botChooseTrump, botPlay (mémoire)
  net/client.dart          client WebSocket + GameView (vue rédigée reçue du serveur)
  ui/game_screen.dart      table « royale » solo vs 3 bots (UI Flutter)
  ui/online_screen.dart    salon (créer/rejoindre code) + table en ligne
  main.dart                accueil : partie solo / table privée
  l10n/app_{en,fr,ta,si}.arb  30 clés chacune (voir §9 : pas encore câblées dans l'UI)
bin/server.dart            serveur autoritatif WebSocket (dart:io), réutilise engine + bots
test/engine_test.dart      tests du moteur (régression + Partner Close Caps)
test/prototype_equivalence_test.dart  test différentiel Dart == prototype (coup par coup)
test/fixtures/prototype_trace.json.gz trace de référence produite par tools/diff-test/trace.js
tools/diff-test/trace.js   génère / vérifie (--check) la trace de référence du prototype
android/ ios/ web/         générés par `flutter create` (org com.kjtech)
prototype/304.html         PROTOTYPE WEB VALIDÉ — référence des règles, de l'IA et du design
tools/ui-test/             test d'interface jsdom du prototype (joue des donnes via les boutons)
deploy/server.sh           déploiement Cloud Run (une commande)
deploy/web.sh              build Flutter web + Firebase Hosting
deploy/mobile.sh           build .aab (Android) / .ipa (Mac)
assets/                    icon.svg, logo.svg, card_back_royal.svg
docs/
  RULES.md                 règles de référence
  ARCHITECTURE.md          ADR multijoueur
  PROTOCOL.md              protocole client↔serveur
  MISE_EN_LIGNE.md         guide pas à pas (étapes, coûts, pièges) — À SUIVRE POUR PUBLIER
  STORE_LISTING.md         fiche store 4 langues + réponses aux questionnaires
  TRANSLATIONS.md          106 termes FR/EN/TA/SI (prototype)
  DEPLOY.md                notes de déploiement (ancien, voir MISE_EN_LIGNE.md)
  privacy.html             politique de confidentialité FR/EN (placeholders [DATE], [EMAIL])
.github/workflows/
  ci.yml                   flutter analyze --no-fatal-infos, flutter test, test UI prototype (en/ta/si)
  pages.yml                publie prototype/304.html (index) + privacy.html sur GitHub Pages
```

## 3. Règles exactes implémentées (identiques JS et Dart)

**Sièges** : 0=Sud, 1=Est, 2=Nord, 3=Ouest. Ordre de jeu **anti-horaire** = `(s+1)%4`.
Équipes : **NS = {0,2}**, **EW = {1,3}**. Humain local = siège 0.

**Cartes** : 32 (7,8,9,10,J,Q,K,A × ♠♣♦♥). Force faible→fort : `7 8 Q K 10 A 9 J`.
Valeurs : J=30, 9=20, A=11, 10=10, K=3, Q=2, 8=0, 7=0 → **total 304**.

**Déroulé d'une donne**
1. Distribution 4 cartes chacun, en partant de la droite du donneur (`eldest = (dealer+1)%4`).
2. **Redistribution** : si les 4 cartes de `eldest` valent **< 15 pts**, il peut exiger un redeal.
3. **1er tour d'enchères** (sur 4 cartes), commence par `eldest` : multiples de 10, **160 → 240**,
   strictement > enchère courante. Contrainte des 200 : un joueur qui reparle, ou dont le
   partenaire mène, doit annoncer **≥ 200**. Fin après 3 passes consécutives derrière une enchère ;
   4 passes sans enchère = `allpass` (nouvelle donne).
4. Le gagnant (`trumpMaker1`) pose **une carte face cachée** (indicator) : sa couleur = atout.
5. Distribution de 4 cartes de plus (preneur : 7 en main + indicator ; autres : 8).
6. **2e tour** (sur 8 cartes), un seul tour de table à partir de `trumpMaker1` :
   enchères **≥ max(250, bid1+10)**, ≤ 300, multiples de 10 ; interdit de surenchérir sur son
   partenaire (liste vide). Un nouveau preneur récupère/repose un atout (l'ancien indicator
   retourne dans la main de trumpMaker1).
   - **Partner Close Caps (PCC)** : enchère max, fin immédiate des enchères. Le preneur joue
     **seul** contre les 2 adversaires, son partenaire est écarté (`mutedSeat`), **le preneur mène**,
     plis de **3 cartes**, atout révélé après le 1er pli, réussite = **8 plis**. `bid=250` sert de
     sentinelle numérique.
7. Le preneur choisit **jeu fermé** (atout caché) ou **ouvert** (indicator remis en main, atout visible).
8. **8 plis**, `eldest` mène le 1er pli (sauf PCC).

**Jeu des plis**
- Suivre la couleur demandée si possible.
- Atout fermé et impossible de suivre → carte jouée **face cachée** ; en fin de pli, si une carte
  cachée est atout → **révélation** (`trumpOpen = true`).
- Le preneur peut couper avec l'indicator (`playIndicatorToCut`) ; s'il ne lui reste que
  l'indicator, il doit le jouer (`playLastIndicator`).
- **Enchère ≥ 250 ou PCC** : atout révélé après le 1er pli.
- **Atouts épuisés** : si le preneur (atout ouvert) détient tous les atouts restants et a d'autres
  cartes, il doit mener atout (compteur `trumpsPlayed`).
- **Atout gâché (spoilt)** : vérifié **uniquement au démarrage d'un jeu ouvert** ; si aucun
  adversaire n'a d'atout → phase `spoilt`, redistribution. (La détection en cours de partie a été
  retirée : elle déclenchait ~14 % de redistributions, pénible et non visible en jeu fermé.)

**Score (jetons)** : 11 chacun, total toujours 22, partie perdue à 0 (clamp 0–22).

| Enchère | Réussie | Ratée |
|---|---|---|
| < 200 | +1 | −2 |
| 200–249 | +2 | −3 |
| ≥ 250 | +3 | −4 |
| PCC | +4 | −5 |

Caps (8 plis, hors PCC) : **+1** bonus. Le donneur tourne d'un siège après chaque donne.
Non implémenté : « Wrong Caps » (pénalité de timing d'annonce) — remplacé par le bonus automatique.

**Phases du moteur** : `idle → redeal → bid1 → (allpass) → chooseTrump1 → bid2 →
(chooseTrump2 | chooseTrumpPCC) → preplay → play → (spoilt) → scored`.

## 4. IA (v3) — chiffres mesurés sur le prototype

- **Enchères 1er tour** (`est4`, modèle calibré sur 40 000 donnes simulées) :
  `124.8 + 0.09·pts + 13.6·nbAtouts + 26.7·(J d'atout) + 9.2·(9 d'atout) + 20.7·(J hors atout)`
  (couleur d'atout = celle que choisirait `botChooseTrump`). Seuils : est ≥ 210 → 190, ≥ 195 → 180,
  ≥ 185 → 170, ≥ 160 → 160, sinon passe ; surenchérir son partenaire seulement si est ≥ 230 (→ 200).
  Résultat : réussite du preneur 57 % → 67 %, gain moyen par prise −0,29 → +0,02 jeton,
  97 % de parties gagnées contre l'ancienne IA d'enchères.
- **2e tour** : volontairement très prudent. Mesuré : même avec 6 atouts dont J et 9, P(≥250) ≈ 0,53
  → gain moyen négatif. Ne pas rendre plus agressif sans nouvelle mesure.
- **Choix d'atout** : couleur maximisant points + 2·longueur ; pose sa plus petite carte.
  (Une variante « longueur + maîtres » testée : 50,1 % → aucun gain, non retenue.)
- **Jeu des plis** (mémoire `seen` = cartes vues face visible) : encaisse les cartes maîtres avec
  points, charge le partenaire quand son pli est sûr, plus petite carte gagnante en dernier,
  gagnante sûre sinon, preneur tire les atouts s'il est maître, coupe seulement si le pli rapporte,
  défenseur en atout caché tente une coupe « devinée » si le pli vaut ≥ 13.
  Mesuré : 56,5 % vs IA précédente ; IA complète v3 = **98,7 %** des parties vs IA de départ.

## 5. Multijoueur

- **Serveur autoritatif** (`bin/server.dart`) : une `Room` = une instance `Engine`. Codes de table
  à 4 caractères. Sièges humains attribués dans l'ordre **0, 2, 1, 3** (le 2e joueur = partenaire).
  Sièges vides = bots (le serveur les fait jouer). Reconnexion par token. Les tables vivent en
  mémoire → **Cloud Run `--max-instances 1` + `--session-affinity`**.
- Le serveur envoie à chaque humain `engine.viewFor(seat)` (**vue rédigée** : sa main seulement,
  `{count}` pour les autres, atout masqué sauf ouvert/preneur, cartes face cachée → `card: null`),
  enrichie de `code`, `started`, `players[{name,bot,online}]`.
- Protocole : voir `docs/PROTOCOL.md` (messages `create/join/reconnect/start/action/chat`,
  réponses `joined/state/error/chat`).
- Client (`lib/net/client.dart`) : garde le **dernier état** (`last`) car le serveur l'envoie
  avant l'ouverture de l'écran de table.
- Adresse serveur côté app : `--dart-define=SERVER_URL=wss://…/ws` (défaut `ws://localhost:8080/ws`).

## 6. État réel de validation — IMPORTANT

| Élément | Statut |
|---|---|
| Prototype web `prototype/304.html` | ✅ **Validé** : >100 000 donnes simulées (invariants : points=304, 8 plis, jetons=22, coups légaux) + test d'interface jsdom (80 donnes via les boutons, 0 erreur, en FR/EN/TA/SI) |
| Moteur Dart, IA Dart | ✅ **Compilés (Flutter 3.47.6 / Dart 3.13.5) et identiques au prototype** : test différentiel `test/prototype_equivalence_test.dart` — 24 parties / 1 074 donnes (dont 60 PCC, 2 atouts gâchés, coupes à l'atout posé, jeu ouvert et fermé) rejouées avec le même générateur aléatoire : chaque enchère, carte, pli, score et ligne du journal est identique |
| Tests Dart | ✅ `flutter test` : 27/27 (régression 300 parties, PCC, 24 parties différentielles) ; `flutter analyze` : 0 remarque |
| Serveur Dart | ✅ Compilé (`dart compile exe`) et lancé : `/health` = ok ; partie complète jouée par 2 clients WebSocket (créateur siège 0, partenaire siège 2) + 2 bots jusqu'à 0 jeton, 0 erreur, aucun blocage ; 20/20 coups illégaux rejetés |
| UI Flutter (game_screen, online_screen, main) | ⚠️ **Compile** (`flutter build web` OK) mais **jamais lancée ni testée à l'écran** (pas de navigateur interactif dans la session Claude Code) |
| Dockerfile, scripts deploy | ⚠️ Syntaxe vérifiée (`bash -n`), jamais exécutés |
| CI GitHub | ⚠️ Écrite, jamais lancée (YAML valide) |

Validation faite le 03/10/2026 (session Claude Code, branche `claude/game304-dart-compile-kj2ik4`).
Commandes : `flutter analyze`, `flutter test`, `flutter build web`, `dart compile exe bin/server.dart`,
`cd tools/ui-test && DEALS=20 L=en|ta|si node run.js` (0 erreur JS, 0 blocage ; `L=fr` n'a pas de
sens pour ce test, qui vérifie qu'il ne reste pas de français après bascule).

**Test différentiel** : `tools/diff-test/trace.js` charge le moteur + l'IA du prototype dans Node avec
`Math.random` = mulberry32(graine) et écrit `test/fixtures/prototype_trace.json.gz` ; le test Dart
injecte le même générateur (`Engine(rng: …)`) et compare ligne à ligne (première divergence affichée).
Après toute modification des règles ou de l'IA : modifier les deux côtés, relancer
`node tools/diff-test/trace.js`, puis `flutter test`. La CI vérifie que la trace est à jour (`--check`).

## 7. Prochaines étapes (dans l'ordre)

1. ✅ **FAIT (03/10/2026)** — Préparer et compiler (voir `docs/MISE_EN_LIGNE.md` §1) :
   ```bash
   flutter create --platforms=android,ios,web --org com.kjtech --project-name game304 .
   rm -f test/widget_test.dart      # flutter create en ajoute un, incompatible (MyApp)
   flutter pub get
   flutter analyze --no-fatal-infos
   flutter test
   ```
   Corriger toutes les erreurs/avertissements. Vérifier que le comportement Dart = prototype
   → fait : test différentiel (§6).
2. Lancer en local : `flutter run -d chrome` (solo), puis `dart run bin/server.dart` +
   `flutter run -d chrome --dart-define=SERVER_URL=ws://localhost:8080/ws` dans 2 onglets
   pour tester une table privée (créer → code → rejoindre → démarrer → jouer une donne).
3. Pousser sur GitHub (`PUSH.md`), vérifier la CI, activer **Settings → Pages → GitHub Actions**.
4. Déployer le serveur : `./deploy/server.sh <PROJET_GCP>`.
5. Câbler l'i18n dans l'UI Flutter (§9), compléter les écrans.
6. Stores (§10).

## 8. Commandes utiles

```bash
flutter analyze --no-fatal-infos && flutter test
dart run bin/server.dart                       # ws://localhost:8080/ws ; GET /health -> ok
cd tools/ui-test && npm install && DEALS=30 node run.js   # test UI du prototype
L=ta DEALS=20 node run.js                      # idem en tamoul (L=en|ta|si)
./deploy/server.sh <PROJET_GCP> [region]       # Cloud Run (europe-west1 par défaut)
./deploy/web.sh <PROJET_FIREBASE> wss://…/ws   # Flutter web -> Firebase Hosting
./deploy/mobile.sh wss://…/ws                  # .aab (+ .ipa sur Mac)
```

Valider le moteur JS du prototype sans navigateur : extraire le `<script>` jusqu'au commentaire
`UI / CONTRÔLEUR` et l'exécuter dans Node avec une boucle de simulation (c'est ainsi que toutes les
mesures du §4 ont été faites). Le test UI (`tools/ui-test/run.js`) échoue (code 1) sur toute erreur
JS, blocage, ou texte non traduit après bascule de langue.

## 9. Lacunes connues (à traiter)

- **i18n Flutter non câblée** : les ARB (30 clés, 4 langues) existent mais `AppLocalizations`
  n'est pas utilisé ; les textes de `game_screen.dart`, `online_screen.dart` et `main.dart` sont en
  **français en dur**. Le prototype, lui, est entièrement traduit (106 clés, dictionnaire `I18N`).
  → Reprendre les 106 clés du prototype dans les ARB et câbler `AppLocalizations`.
- **Tutoriel « Apprendre le 304 »** : FR et EN seulement (repli EN pour ta/si) — prototype.
- **Traductions ta/si** : traductions machine vérifiées (clés, repères `{n} {p} {b} {s}`, balises,
  écritures Unicode) mais **relecture native recommandée** (vocabulaire du 304).
- **UI Flutter** moins aboutie que le prototype : pas de Conseil, Dernier pli, sons, cosmétiques,
  accueil avec stats, animations de distribution/ramassage, réglages (tous présents dans le prototype).
- **Écran en ligne** : pas d'écran de fin de donne détaillé (le serveur repasse en donne suivante
  après 1,2 s), pas de chat, pas de voice chat (prévu : WebRTC via signaling serveur).
- Serveur : tables jamais nettoyées (fuite mémoire si beaucoup de tables) ; une seule instance.
- `docs/privacy.html` : remplacer `[DATE]` et `[EMAIL DE CONTACT]`.
- Icônes PNG à générer depuis `assets/icon.svg` (ex. `flutter_launcher_icons`).

## 10. Publication — pièges déjà identifiés

- **Nom store** : pas « Thuru ». Propositions dans `docs/STORE_LISTING.md` (304 — Jaffna Card Game,
  304 Royal, Three-Nought-Four) ; vérifier la disponibilité.
- **Google Play** : 25 $ une fois ; un **nouveau compte personnel** doit faire un **test fermé
  avec ≥ 12 testeurs pendant 14 jours** avant production (pas pour un compte organisation, qui
  demande un D-U-N-S). Clé d'upload à créer et sauvegarder (`android/key.properties`, ignoré par Git).
- **App Store** : 99 $/an, **Mac + Xcode obligatoires**.
- Toujours indiquer « **sans argent réel** » (évite la classification jeu d'argent).
- Confidentialité : aucun compte, préférences locales, pseudonyme multijoueur non conservé
  → « aucune donnée collectée ».
- URL de confidentialité prévue : `https://kamalrajmuruganathan.github.io/304/privacy.html`.

## 11. Historique des bugs trouvés (pour ne pas les réintroduire)

- Prototype : `currentTrick` non initialisé avant la phase de jeu → **la partie se figeait au clic
  sur « Jouer »** (présent dans plusieurs versions publiées, trouvé par le test jsdom). Corrigé
  (constructeur + `newHand` + garde dans `renderTrick`). En Dart, le champ est initialisé à la
  déclaration.
- Prototype : bouton Conseil resté visible pendant l'animation du pli → plantage main vide.
  Corrigé (`clearControls()` dans `humanPlay` + garde dans `showPlayHint`).
- Dart : `late hands` lu par `snapshot()` à la création d'une table → plantage serveur. Corrigé
  (`hands = [[],[],[],[]]`).
- Serveur : le 2e humain arrivait en Est (adversaire). Corrigé (ordre 0,2,1,3).
- Client : premier état perdu (envoyé avant l'abonnement de l'écran). Corrigé (`last`).
- Atout gâché : déclenchement trop fréquent. Limité au démarrage d'un jeu ouvert.
- Reste d'une ancienne ébauche de mémoire IA (`seen` en tableau + `isMaster` à 2 arguments) qui
  écrasait le `Set` → supprimée.
- CI : `flutter analyze` échoue par défaut sur de simples infos de style → `--no-fatal-infos`.
- Dart (1re compilation) : la classe `Card` du moteur entrait en conflit avec le widget `Card` de
  Material → `import 'package:flutter/material.dart' hide Card;` dans `game_screen.dart` et
  `online_screen.dart`.
- Serveur : `play` n'était pas validé → un client pouvait jouer une carte sans fournir à la couleur
  ou couper avec l'atout posé sans y avoir droit. Corrigé (rejet via `engine.playableCards` et
  conditions de `playIndicatorToCut`), vérifié par le test WebSocket.
- Journal Dart : 2 messages (PCC, révélation ≥ 250) formulés autrement que dans le prototype →
  alignés (détecté par le test différentiel).

## 12. Prototype — repères dans `prototype/304.html`

Un seul fichier HTML autonome (CSS + JS inline, aucune dépendance sauf Google Fonts).
Dans le `<script>`, dans l'ordre : constantes et dictionnaire `I18N` (fr/en/ta/si, fonctions
`t()`, `tf()` avec repères `{n}`), sons/vitesse, `class Engine` (moteur), IA (`est4`, `botBid`,
`botBid2`, `botChooseTrump`, `unseenHigher`, `isMaster`, `botPlay`), puis le commentaire
**`UI / CONTRÔLEUR`** et le contrôleur (rendu, déroulé, réglages, tutoriel, accueil, stats).
Version publiée sur claude.ai (artifact) : v1.0. Les préférences (langue, son, vitesse, dos de
cartes, tapis, stats) sont dans `localStorage` (`lang304`, `sound304`, `speed304`, `back304`,
`felt304`, `stats304`).
