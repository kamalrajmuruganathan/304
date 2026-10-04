# 304 — three-nought-four

> **Pour publier : suivre [`docs/MISE_EN_LIGNE.md`](docs/MISE_EN_LIGNE.md).**

Implémentation **cross-platform** (Android · iOS · Web) et **multilingue** du 304, le jeu de plis par équipes populaire au Sri Lanka et dans le sud de l'Inde.

> Jeu de pure stratégie, sans argent réel. 4 joueurs, 2 équipes, paquet de 32 cartes, enchères + atout caché.

## Pourquoi ce projet

Le 304 a déjà des joueurs (diaspora sri-lankaise / sud-indienne), mais l'offre existante est limitée. Ce projet vise trois différenciateurs clairs :

- **Cross-platform** : Android **+** iOS **+** Web depuis un seul codebase Flutter (les apps existantes sont souvent iOS-only alors qu'une grande partie du public est sur Android).
- **Multilingue** : tamoul, singhalais, français, anglais (l'i18n est prévue dès la fondation).
- **Web instantané** : une version jouable dans le navigateur, sans passer par un store.

## État actuel

| Brique | État |
|---|---|
| Règles officielles (moteur) | ✅ complet (redeal, double enchère, atout caché/ouvert, révélation ≥250, Partner Close Caps, barème + Caps) |
| Moteur porté en Dart (`lib/engine`) | ✅ port fidèle du prototype validé |
| Bots (IA de base) | ✅ fonctionnels |
| IA v3 (enchères calibrées + jeu à mémoire) | ✅ 98,7 % de victoires vs l'IA de départ ; **portée en Dart** (à valider par la CI) |
| Règles complètes (atouts épuisés, atout gâché) | ✅ prototype + moteur Dart |
| Test d'interface automatique (`tools/ui-test`) | ✅ joue des donnes via les vrais boutons, lancé par la CI |
| Prototype web jouable (`prototype/304.html`) | ✅ validé sur 100 000+ donnes simulées |
| Tests Dart (`test/`) | ✅ écrits (`flutter test`) |
| UI Flutter « table royale » | 🟡 portée (à valider par la CI au 1er push) |
| Design « table royale » (spec) | ✅ validé dans le prototype web (`prototype/304.html`) |
| Sérialisation moteur + vue par joueur (`snapshot`/`viewFor`) | ✅ (clé du multijoueur, anti-triche) |
| Serveur autoritatif (`bin/server.dart`) | 🟡 squelette Dart à lancer/itérer |
| Archi & protocole multijoueur | ✅ `docs/ARCHITECTURE.md`, `docs/PROTOCOL.md` |
| i18n | ✅ FR · EN · தமிழ் · සිංහල (ta/si : relecture native bienvenue) |
| Multijoueur dans l'app (salon + table en ligne) | ✅ écrit, à valider par la CI |
| Kit de mise en ligne (Cloud Run, Pages, stores) | ✅ voir `docs/MISE_EN_LIGNE.md` |
| Voice chat | ⏳ roadmap |

Le détail des règles : [`docs/RULES.md`](docs/RULES.md).

## Lancer

**Prototype web** (le plus rapide pour jouer / vérifier les règles) : ouvrir `prototype/304.html` dans un navigateur (marche aussi sur mobile).

**App Flutter** :
```bash
flutter pub get
flutter test          # valide le moteur (invariants + Partner Close Caps)
flutter run           # Android / iOS / desktop
flutter run -d chrome # web
```
Prérequis : Flutter ≥ 3.22.

## Structure

```
lib/
  engine/engine.dart   # moteur de règles (Dart pur) + sérialisation/vue réseau — le cœur
  ai/bots.dart         # IA des bots
  net/client.dart      # client réseau (WebSocket) + modèle de vue
  ui/game_screen.dart  # UI de jeu (baseline phase 1)
  main.dart            # point d'entrée + accueil
  l10n/                # traductions (en, fr complets ; ta, si à compléter)
bin/server.dart        # serveur multijoueur autoritatif (réutilise le moteur)
test/engine_test.dart  # tests (miroir des simulations validées)
prototype/304.html     # prototype web validé — référence jouable + spec visuelle
assets/                # identité : icon.svg, logo.svg, card_back_royal.svg
docs/                  # RULES · ARCHITECTURE · PROTOCOL · DEPLOY
.github/workflows/     # CI : flutter analyze + test à chaque push
```

## Roadmap

- **Phase 0 — Moteur** ✅ règles officielles + Partner Close Caps, validé.
- **Phase 1 — UI** 🟡 design « table royale » validé (web) et **porté en Flutter** (`lib/ui/game_screen.dart`) ; à confirmer par la CI, puis polissage (animations).
- **Phase 2 — i18n** brancher `AppLocalizations`, compléter tamoul & singhalais (relecture native).
- **Phase 3 — Multijoueur** ✅ archi décidée (serveur autoritatif Dart réutilisant le moteur), protocole + sérialisation + squelette serveur faits ; reste : client réseau Flutter, salles/codes en prod, reconnexion, déploiement Cloud Run.
- **Phase 4 — Confort** tutoriel « Apprendre le 304 », voice chat (WebRTC via signaling serveur), cosmétiques, bonus quotidiens.
- **Phase 5 — Publication** Play Store, App Store, déploiement web (Firebase Hosting).

## Serveur multijoueur (dev)

```bash
dart pub get
dart run bin/server.dart        # ws://localhost:8080/ws
```
Autoritatif : il fait tourner le moteur, remplit les sièges vides de bots, et n'envoie à chaque client que sa vue rédigée. Voir `docs/ARCHITECTURE.md` et `docs/PROTOCOL.md`.

## Ce dont j'ai besoin de toi (pour la mise en prod)

Je peux écrire tout le code, mais ces éléments demandent **tes comptes / décisions** :
- **Compte GCP** (tu en as déjà l'expérience) pour déployer le serveur sur **Cloud Run**.
- **Firebase** (projet) si on veut auth + hébergement web + profils/cosmétiques persistants.
- **Apple Developer** (99 $/an) et **Google Play Console** (25 $ une fois) pour publier sur les stores.
- Relecture **tamoul / singhalais** des traductions (idéalement par un proche natif).
- Direction artistique : logo, icône, dos de cartes (je peux générer des maquettes).

## Contribuer à la traduction

`lib/l10n/app_en.arb` est le modèle. `app_fr.arb` est complet. `app_ta.arb` (tamoul) et `app_si.arb` (singhalais) ne contiennent que quelques clés : les manquantes retombent automatiquement sur l'anglais. Compléter en s'appuyant sur le modèle ; relecture par un locuteur natif recommandée.

## Licence

MIT — voir [`LICENSE`](LICENSE).
