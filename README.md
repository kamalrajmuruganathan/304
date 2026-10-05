# 304 — three-nought-four

> **Jouer tout de suite : https://kamalrajmuruganathan.github.io/304/app/** · Publier : [`docs/MISE_EN_LIGNE.md`](docs/MISE_EN_LIGNE.md)

Implémentation **cross-platform** (Android · iOS · Web) et **multilingue** du 304, le jeu de plis par équipes populaire au Sri Lanka et dans le sud de l'Inde.

> Jeu de pure stratégie, sans argent réel. 4 joueurs, 2 équipes, paquet de 32 cartes, enchères + atout caché.

## Pourquoi ce projet

Le 304 a déjà des joueurs (diaspora sri-lankaise / sud-indienne), mais l'offre existante est limitée. Ce projet vise trois différenciateurs clairs :

- **Cross-platform** : Android **+** iOS **+** Web depuis un seul codebase Flutter (les apps existantes sont souvent iOS-only alors qu'une grande partie du public est sur Android).
- **Multilingue** : tamoul, singhalais, français, anglais (l'i18n est prévue dès la fondation).
- **Web instantané** : une version jouable dans le navigateur, sans passer par un store.

## Jouer

| | Adresse |
|---|---|
| **App web** (solo + tables privées en ligne) | https://kamalrajmuruganathan.github.io/304/app/ |
| **APK Android de test** (signé debug, hors Play Store) | https://github.com/kamalrajmuruganathan/304/releases/latest/download/304.apk |
| Prototype web (référence des règles) | https://kamalrajmuruganathan.github.io/304/ |
| Serveur multijoueur (Render, offre gratuite) | `wss://three04-bivu.onrender.com/ws` — s'endort après 15 min sans joueur, réveil ≈ 50 s |

## État actuel

| Brique | État |
|---|---|
| Moteur de règles Dart (`lib/engine`) | ✅ **identique au prototype coup par coup** (test différentiel, 1 074 donnes) |
| IA v3 (`lib/ai`) | ✅ portée, même trace que le prototype |
| App Flutter solo | ✅ table royale, Conseil, Dernier pli, lignes d'aide, vitesse des bots, tutoriel |
| Tables privées en ligne | ✅ créer/rejoindre par code, partenaire = 2ᵉ joueur, bots sur les sièges vides, résultat de chaque donne, relance |
| Serveur autoritatif (`bin/server.dart`) | ✅ valide chaque coup, codes d'erreur traduits, tables abandonnées supprimées ; image Docker 16 Mo |
| 4 langues | ✅ FR · EN · தமிழ் · සිංහල (ta/si : relecture native bienvenue, voir `docs/TRANSLATIONS.md`) |
| Tests | ✅ `flutter test` : moteur, différentiel, serveur WebSocket, interface solo/en ligne, i18n ; CI GitHub |
| Android / iOS | 🟡 APK de test construit par la CI ; stores : à faire (voir `docs/MISE_EN_LIGNE.md`) |
| Voice chat, sons, cosmétiques | ⏳ roadmap |

Le détail des règles : [`docs/RULES.md`](docs/RULES.md). Le contexte complet du projet : [`CLAUDE.md`](CLAUDE.md).

## Développer

```bash
flutter pub get
flutter analyze && flutter test   # tout doit passer
flutter run -d chrome             # web (solo)
dart run bin/server.dart          # serveur local ws://localhost:8080/ws
flutter run -d chrome --dart-define=SERVER_URL=ws://localhost:8080/ws   # app + serveur local
```

Après toute modification des règles ou de l'IA : modifier **le prototype et le moteur Dart**, puis
`node tools/diff-test/trace.js` et `flutter test` (le test différentiel compare les deux).

## Structure

```
lib/engine/engine.dart   moteur de règles (Dart pur) + vue réseau rédigée par joueur
lib/ai/bots.dart         IA v3
lib/net/client.dart      client WebSocket
lib/ui/                  écrans : jeu solo, en ligne, tutoriel
lib/l10n/                traductions (ARB, 4 langues)
bin/server.dart          serveur multijoueur autoritatif
test/                    tests (moteur, différentiel, serveur, interface, i18n)
prototype/304.html       prototype web validé (référence)
tools/                   test différentiel (diff-test) et test d'interface du prototype (ui-test)
.github/workflows/       CI, publication GitHub Pages, APK Android
```

## Contribuer à la traduction

`lib/l10n/app_en.arb` est le modèle ; les 4 fichiers ont les mêmes clés (vérifié par `test/i18n_test.dart`).
Les textes tamouls et cingalais à faire relire en priorité sont listés dans `docs/TRANSLATIONS.md`.

## Licence

MIT — voir [`LICENSE`](LICENSE).
