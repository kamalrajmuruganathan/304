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

- Repo GitHub : `https://github.com/kamalrajmuruganathan/304` (code poussé, `main` = version publiée).
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
Dockerfile / .dockerignore serveur -> binaire natif -> Cloud Run (image dart, pubspec deploy/server.pubspec.yaml)
.gcloudignore              fichiers envoyés par `gcloud run deploy --source`
firebase.json              hosting de build/web (optionnel)
lib/
  engine/engine.dart       MOTEUR (Dart pur, aucune dépendance Flutter) + snapshot/viewFor réseau
  ai/bots.dart             IA v3 : est4/botBid, botBid2, botChooseTrump, botPlay (mémoire)
  net/client.dart          client WebSocket + GameView (vue rédigée reçue du serveur)
  ui/game_screen.dart      table « royale » solo vs 3 bots (UI Flutter)
  ui/online_screen.dart    salon (créer/rejoindre code, reprise de table) + table en ligne (chat, bandeau de reconnexion)
  ui/tutorial_screen.dart  tutoriel « Apprendre le 304 » en 4 langues
  ui/stats_screen.dart     statistiques détaillées (prises par palier, Caps, parties, séries)
  ui/recap.dart            DealRecap : récapitulatif de fin de donne (plis, points, jetons ±), solo et en ligne
  ui/leave.dart            LeaveGuard / confirmLeave : « Quitter la partie ? » (retour du téléphone, flèche)
  ui/anim.dart             animations : DealIn (distribution en cascade), GatherTo (pli ramassé vers le gagnant)
  settings.dart            préférences mémorisées (vitesse, son, dos, tapis, grandes cartes `size304`,
                           jeu 4 couleurs `deck304`, vibrations `vibe304`, stats `Stats`, table en cours)
  sound.dart               sons (playSfx) : assets/sounds/{card,trick,win,lose}.wav, bips du prototype
  main.dart                accueil : partie solo / table privée + choix de langue (mémorisé, clé `lang304`)
  l10n/app_{en,fr,ta,si}.arb  164 clés chacune, câblées via AppLocalizations (fichiers Dart générés, non commités)
bin/server.dart            serveur autoritatif WebSocket (dart:io), réutilise engine + bots
test/engine_test.dart      tests du moteur (régression + Partner Close Caps)
test/prototype_equivalence_test.dart  test différentiel Dart == prototype (coup par coup)
test/fixtures/prototype_trace.json.gz trace de référence produite par tools/diff-test/trace.js
test/ui_solo_test.dart     test d'interface Flutter : donnes jouées via les boutons/cartes (3 tailles d'écran)
test/ui_online_test.dart   test d'interface en ligne (en tamoul) contre le vrai serveur (lancé par le test)
                           + salon à l'écran (créer en cingalais, rejoindre par code, code inconnu refusé)
test/server_test.dart      serveur par WebSocket : codes d'erreur, table complète, ordre des sièges, nettoyage
test/i18n_test.dart        cohérence des ARB + donnes jouées en en/ta/si sans texte français + sélecteur de langue
tools/diff-test/trace.js   génère / vérifie (--check) la trace de référence du prototype
android/ ios/ web/         générés par `flutter create` (org com.kjtech)
prototype/304.html         PROTOTYPE WEB VALIDÉ — référence des règles, de l'IA et du design
tools/ui-test/             test d'interface jsdom du prototype (joue des donnes via les boutons)
deploy/server.sh           déploiement Cloud Run (une commande)
deploy/web.sh              build Flutter web + Firebase Hosting
deploy/mobile.sh           build .aab (Android) / .ipa (Mac)
assets/                    icon.svg, logo.svg, card_back_royal.svg
assets/fonts/Suits.ttf     ♠♣♦♥ seuls (sous-ensemble Noto Sans Symbols 2, 2,4 Ko, OFL) = police de secours du thème
assets/fonts/Lang*.ttf     « தமிழ் » / « සිංහල » seuls (sous-ensembles Noto Sans Tamil/Sinhala, ~4 Ko, OFL) : sélecteur de langue
docs/
  RULES.md                 règles de référence
  ARCHITECTURE.md          ADR multijoueur
  PROTOCOL.md              protocole client↔serveur
  MISE_EN_LIGNE.md         guide pas à pas (étapes, coûts, pièges) — À SUIVRE POUR PUBLIER
  STORE_LISTING.md         fiche store 4 langues (descriptions longues fr/en/ta/si) + réponses aux questionnaires
  PLAY_CONSOLE.md          publication Google Play pas à pas : contenu, IARC, sécurité des données, test fermé
  TRANSLATIONS.md          106 termes FR/EN/TA/SI (prototype)
  DEPLOY.md                notes de déploiement (ancien, voir MISE_EN_LIGNE.md)
  privacy.html             politique de confidentialité FR/EN (chat de table déclaré)
  store/                   visuels Play/App Store : icon-512/1024, feature-1024x500,
                           screenshots/{fr,en,ta,si} (téléphone) et screenshots/tablet7|tablet10/{fr,en}
.github/workflows/
  ci.yml                   flutter analyze --no-fatal-infos, flutter test, test UI prototype (en/ta/si)
  pages.yml                GitHub Pages : prototype (/304/), app Flutter web (/304/app/, SERVER_URL = variable
                           de dépôt `SERVER_URL` sinon wss://three04-bivu.onrender.com/ws), privacy.html
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
| Tests Dart | ✅ `flutter test` : 67/67 (quitter la partie avec confirmation, tablette portrait 800×1280, salon créer/rejoindre à l'écran, double toucher rapide sur une carte, stats, écran Statistiques en tamoul, grandes cartes + 4 couleurs sur 360×640, récap de donne, coupe à l'atout posé : 300 parties, régression 300 parties, PCC, 24 parties différentielles, serveur WebSocket dont chat et reconnexion, tests d'interface solo/en ligne, animations, i18n) ; `flutter analyze` : 0 remarque |
| i18n Flutter (FR/EN/TA/SI) | ✅ Câblée (§9) : `test/i18n_test.dart` joue des donnes en en/ta/si via l'UI et échoue sur tout texte français ou latin resté en dur (sensibilité vérifiée) ; l'écran en ligne est testé en tamoul. **Rendu vérifié à l'œil** (captures Chromium du build web, 360×640 et 390×844, ta/si/fr) |
| Serveur Dart | ✅ Compilé (`dart compile exe`) et lancé : `/health` = ok ; partie complète jouée par 2 clients WebSocket (créateur siège 0, partenaire siège 2) + 2 bots jusqu'à 0 jeton, 0 erreur, aucun blocage ; 20/20 coups illégaux rejetés |
| UI Flutter solo (game_screen, main) | ✅ **Testée par widget tests** (`test/ui_solo_test.dart`) : 45 donnes jouées en touchant les vrais boutons/cartes sur téléphone 390×844, petit écran 360×640 et tablette 1024×768 ; campagne longue `--dart-define=DEALS=300` : 300 donnes, 0 erreur, tous les cas couverts (preneur, choix d'atout, fermé/ouvert, face cachée, dernier pli à l'atout posé, PCC). Rendu regardé sur captures Chromium (build web) ; ⚠️ jamais vu sur un vrai téléphone |
| UI Flutter en ligne (online_screen, client) | ✅ **Testée contre le vrai serveur** (`test/ui_online_test.dart`) : table créée, démarrée, 2 donnes jouées via l'UI contre 3 bots serveur, 0 erreur ; relance après fin de partie vérifiée par client WebSocket. Coupure réseau simulée → bandeau puis reconnexion automatique ; envoi d'un message de chat. **Salon testé à l'écran** (08/10/2026) : créer une table (en cingalais), un ami la rejoint en partenaire (siège 2), démarrage ; rejoindre par code tapé en minuscules ; code inconnu → erreur traduite. Adresse du salon modifiable par les tests (`serverUrl`) |
| Dockerfile serveur | ✅ Image construite et lancée (05/10/2026) : `dart:stable` + `deploy/server.pubspec.yaml` (Dart pur, sans Flutter), exécution `scratch`, **16,3 Mo** ; conteneur testé : `/health` ok, partie complète par WebSocket jusqu'à 0 jeton, relance, 20/20 coups illégaux rejetés |
| Serveur en ligne | ✅ **Render.com, offre gratuite, sans carte bancaire** (05/10/2026) : service Docker `three04` sur la branche `claude/game304-dart-compile-kj2ik4`, https://three04-bivu.onrender.com (`/health`, WebSocket `wss://…/ws`). Build + démarrage OK dans les logs Render. **À faire par Kamal : dans Render, passer la branche du service sur `main`** (tant que ce n'est pas fait, Render déploie chaque push sur la branche de travail — y compris du code pas encore fusionné ; après chaque fusion la branche est remise au niveau de `main`). ⚠️ Non testé depuis la session Claude Code (domaine bloqué par la politique réseau de l'environnement). S'endort après 15 min sans joueur (réveil ≈ 30–60 s ; le salon réveille le serveur à l'ouverture) |
| GitHub Pages | ✅ Prototype https://kamalrajmuruganathan.github.io/304/ et **app Flutter https://kamalrajmuruganathan.github.io/304/app/** publiés par `pages.yml` (05/10/2026) |
| APK Android | ✅ Construit par `android.yml` à chaque PR et publié en release sur `main` (release `android-N`, ~54 Mo, signé clé de debug tant que la clé d'upload n'est pas dans les secrets ; `.aab` Play Store joint dès qu'elle l'est) : https://github.com/kamalrajmuruganathan/304/releases/latest/download/304.apk. ⚠️ Jamais installé sur un vrai téléphone (SDK Android injoignable depuis la session) |
| Scripts deploy (`server.sh`, `web.sh`, `mobile.sh`) | ⚠️ Jamais exécutés : Kamal ne veut **pas de carte bancaire** → pas de Cloud Run/Firebase ; Render + GitHub Pages à la place |
| CI GitHub | ✅ Verte sur `main` après les PR #1 à #5 (jobs `test`, `prototype-ui`, `apk`) |

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
2. ✅ **En grande partie FAIT (03/10/2026)** par tests automatiques (§6) ; reste à **regarder le rendu** :
   `flutter run -d chrome` (solo), puis `dart run bin/server.dart` +
   `flutter run -d chrome --dart-define=SERVER_URL=ws://localhost:8080/ws` dans 2 onglets
   pour tester une table privée (créer → code → rejoindre → démarrer → jouer une donne).
3. Pousser sur GitHub (`PUSH.md`), vérifier la CI, activer **Settings → Pages → GitHub Actions**.
4. ✅ Serveur déployé sur **Render** (gratuit, sans carte) — pas Cloud Run : Kamal refuse de renseigner une
   carte bancaire (Cloud Run/Cloud Build l'exigent). Projet GCP `game304-kamal` créé sans facturation (inutile).
5. ✅ i18n câblée (04/10/2026). Reste : relecture native ta/si, compléter les écrans (§9).
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

- ~~i18n Flutter non câblée~~ → **fait le 04/10/2026** : 87 clés (61 reprises du prototype, 25
  nouvelles pour l'écran en ligne/l'accueil, + titre). Les 25 nouvelles sont listées dans
  `docs/TRANSLATIONS.md` (traduction ta/si par Claude → **relecture native à faire**).
- ~~Messages d'erreur du serveur en français~~ → **fait** : le serveur envoie un `code`
  (notYourTurn, invalidAction, tableNotFound, tableFull, sessionExpired) traduit par l'app.
- Web : les polices tamoule/cingalaise sont téléchargées par Flutter (fonts.gstatic.com) au premier
  affichage ; Android/iOS ont des polices système. Les symboles ♠♣♦♥ sont embarqués (`Suits`).
- Tutoriel « Apprendre le 304 » : **app Flutter en 4 langues** (`lib/ui/tutorial_screen.dart`, score précisé :
  pénalités −2/−3/−4 ; ta/si par Claude → relecture native). Le prototype reste FR/EN.
- **Traductions ta/si** : traductions machine vérifiées (clés, repères `{n} {p} {b} {s}`, balises,
  écritures Unicode) mais **relecture native recommandée** (vocabulaire du 304).
- **UI Flutter** : Conseil, Dernier pli, lignes d'aide, vitesse des bots, tutoriel, statistiques, dos de cartes
  et tapis → **faits**. Sons (carte, pli, gagné/perdu ; réglage Son, clé `sound304`) et animations de distribution /
  ramassage → **faits (05/10/2026)**, en solo et en ligne. Sur le web, le son ne démarre qu'après un premier geste
  (règle des navigateurs) ; dans `flutter test`, le son est coupé (`test/flutter_test_config.dart`).
- Web : pas d'emoji dans les boutons (police emoji téléchargée à la volée → carrés) : icônes Material à la place.
- **Écran en ligne** : récapitulatif de chaque donne affiché 6 s (plis, points, jetons ±), **chat de table** (1 ligne, 200 caractères max,
  nettoyé par le serveur), **reconnexion automatique** après coupure (bandeau, nouvelles tentatives à 1/2/4/8 s,
  jeton de reprise ; table mémorisée `table304` → bouton « Reprendre » au salon) → faits (05/10/2026).
  Pas de voice chat (prévu : WebRTC via signaling serveur).
- ~~Personne ne peut couper avec l'atout posé depuis l'UI~~ → **fait (05/10/2026, décision de Kamal)** :
  bouton « Couper avec l'atout posé » (prototype, solo, en ligne) affiché seulement si
  `canCutWithIndicator(seat)` (moteur JS + Dart : phase play, son tour, preneur, atout posé sur la table,
  jeu fermé, pli entamé, ne peut pas fournir). En ligne, la vue contient `canCut` et le serveur
  valide avec la même fonction. Le Conseil propose la coupe quand l'IA la jouerait (avant : « défaussez »).
- **Fait (07/10/2026)** : statistiques détaillées (écran dédié, ancien format `stats304` relu sans
  perte), récapitulatif de donne (plis/points/jetons ±) en solo et en ligne — le serveur garde le
  résultat affiché **6 s** —, accessibilité (grandes cartes ×1,25, jeu 4 couleurs ♦ bleu ♣ vert,
  vibration légère au jeu d'une carte, sans effet sur le web), préparation Play Store (signature
  par clé d'upload via secrets GitHub, `.aab` dans la release si la clé est configurée, visuels
  `docs/store/`). **Reste à Kamal** : créer la clé d'upload et les 4 secrets (MISE_EN_LIGNE §4).
- **Fait (08/10/2026)** : cartes agrandies automatiquement sur grand écran (`autoCardScale` : min(l/390,
  h/844) borné à 1–1,7, multiplié par le réglage « grandes cartes » ; téléphone et tablette paysage
  inchangés) ; bandeau solo qui affichait « Nord joue… » sous la fenêtre de résultat → affiche le
  résultat ; captures store ta/si et tablettes 7"/10" ; guide `docs/PLAY_CONSOLE.md`.
- **Fait (10/10/2026, pour le téléphone)** : écran de démarrage Android sombre + icône (plus de flash
  blanc ; `values-v31` pour Android 12+), fond sombre de la page web ; confirmation avant de quitter
  une partie (geste retour, flèche de la barre en ligne, nouvelle flèche dans le tableau des scores
  solo — seul moyen de revenir à l'accueil sur le web/iPhone) ; écran gardé allumé pendant une
  partie (`wakelock_plus`, `keepScreenOn`). ⚠️ Écran de démarrage Android vérifié seulement par la
  construction de l'APK en CI, pas à l'œil.
- ~~Tables jamais nettoyées~~ → **fait** : table sans joueur connecté supprimée après `ROOM_TTL_SECONDS`
  (1800 par défaut, balayage toutes les `ROOM_SWEEP_SECONDS`=300). Toujours une seule instance.
- ~~privacy.html à compléter~~ → fait (date, hébergeurs Render/GitHub Pages/Google Fonts, contact = issues GitHub ;
  pas d'e-mail publié — à ajouter si Kamal le souhaite, les stores demandent souvent un e-mail).
- ~~Icônes PNG~~ → faites depuis `assets/icon.svg` (web, Android 5 densités, iOS carré opaque) ; nom affiché « 304 ».

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
- **Chat de table** : à déclarer dans les questionnaires (Play « interactions entre utilisateurs »,
  IARC) — voir `docs/STORE_LISTING.md`.
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
- UI solo : pendant qu'un **bot** posait son atout, les cartes du joueur restaient jouables → toucher
  une carte appelait `chooseTrump1` avec la carte du joueur pour le bot (« carte absente »). Corrigé
  (`_canPlay` vérifie que c'est le joueur qui choisit). Trouvé par `ui_solo_test`.
- UI solo : pendant la pause de fin de pli (0,95 s), le gagnant pouvait déjà jouer → 2 déroulés en
  parallèle, bots jouant deux fois, tour du joueur sauté, plantage en fin de donne. Corrigé
  (`_doneTrick` : pli terminé affiché pendant la pause, aucune carte jouable). La 4e carte d'un pli
  n'était jamais visible : elle l'est maintenant (le moteur renvoie `cards` comme le prototype).
- UI solo : tableau des scores qui débordait sur écran de 390 px → `FittedBox`/`Flexible`.
- En ligne : fin de partie = table bloquée (le serveur s'arrêtait, `start` ignoré). Corrigé : l'hôte
  voit « Nouvelle partie » (`room.restart()`).
- En ligne : 4e carte jamais visible → `lastTrick` dans la vue + pause serveur de 1 s après chaque pli.
- En ligne : double appui = 2 actions envoyées (« Ce n'est pas votre tour »). Corrigé : l'UI se
  bloque après chaque action jusqu'au nouvel état (ou erreur, ou 4 s).
- Nom de classe `Thuru304App` dans `main.dart` → renommé `Game304App`.
- Tests d'interface : `flutter_test` bloque le réseau (`HttpOverrides`) → `HttpOverrides.global =
  null` dans le test en ligne ; les écouteurs de flux ne tournent qu'aux `pump()`.
- Web : ♠♣♦♥ venaient de la police **Noto Color Emoji** téléchargée à la volée (lourde, échecs
  réseau → carrés barrés, style incohérent). Corrigé : police `Suits` embarquée (`fontFamilyFallback`).
- Boutons pleins : texte bleu foncé sur fond bleu (illisible) → `onPrimary: Colors.white`.
- Petit écran / langues longues (ta, si) : pastille d'atout sur le pion de Nord, pion « Vous » sous
  la main, cartes du pli sur les pions Est/Ouest → pions réduits à l'avatar (< 520 px de large).
- En ligne : code de table tronqué dans la barre du haut (score à côté) → score dans le bandeau ;
  score et plis affichés du point de vue de l'équipe du joueur (faux pour Est/Ouest) ; main de 8
  cartes qui défilait → cartes redimensionnées ; étiquettes Est/Ouest recouvertes par le pli.
- Dockerfile : partait de l'image Flutter (`ghcr.io/cirruslabs/flutter`, lourde) alors que le serveur
  est en Dart pur → image `dart:stable` + pubspec réduit, binaire dans `scratch` (16 Mo).
  `.gcloudignore` : n'envoie à Cloud Build que `bin/`, `lib/engine`, `lib/ai` et le Dockerfile.
- UI solo : la main capturait l'**indice** de la carte dans le `onTap` (`h[i]`) → un 2e toucher rapide sur
  la dernière carte, déjà jouée, lisait hors de la main (`RangeError`) ; sur le web avec l'accessibilité
  activée, le moteur web restait ensuite bloqué (toutes les touches en erreur). Corrigé (carte capturée
  par valeur + `_canPlay` vérifie que la carte est en main) ; test « double toucher rapide ». Trouvé par
  les captures automatiques du store (07/10/2026).
- UI solo, petit écran : pendant les enchères (3 rangées de boutons) la table devient basse et le
  pion « Vous » chevauchait celui d'Ouest. Corrigé : Est/Ouest placés dans la bande libre au-dessus
  du pion du joueur, pion du joueur masqué s'il n'y a pas la place ; `playSolo` vérifie à chaque
  étape qu'aucun pion n'en chevauche un autre.
- Test « animation de distribution » instable : une redistribution par un bot (600 ms) relançait
  l'animation avant la vérification à 1 s → vérification à 500 ms (animation la plus longue : 470 ms).
- Captures d'écran du build web : `flutter build web --no-web-resources-cdn` (sinon CanvasKit vient
  d'un CDN injoignable ici), Chromium via le proxy, accessibilité Flutter activée
  (`flt-semantics-placeholder`) pour cliquer les boutons par leur texte. Les cartes ne sont pas des
  nœuds d'accessibilité : les toucher par coordonnées (rangée au-dessus du panneau du bas). Sans le
  proxy, les polices tamoule/cingalaise (Google Fonts) ne chargent pas → carrés.

## 12. Prototype — repères dans `prototype/304.html`

Un seul fichier HTML autonome (CSS + JS inline, aucune dépendance sauf Google Fonts).
Dans le `<script>`, dans l'ordre : constantes et dictionnaire `I18N` (fr/en/ta/si, fonctions
`t()`, `tf()` avec repères `{n}`), sons/vitesse, `class Engine` (moteur), IA (`est4`, `botBid`,
`botBid2`, `botChooseTrump`, `unseenHigher`, `isMaster`, `botPlay`), puis le commentaire
**`UI / CONTRÔLEUR`** et le contrôleur (rendu, déroulé, réglages, tutoriel, accueil, stats).
Version publiée sur claude.ai (artifact) : v1.0. Les préférences (langue, son, vitesse, dos de
cartes, tapis, stats) sont dans `localStorage` (`lang304`, `sound304`, `speed304`, `back304`,
`felt304`, `stats304`).
