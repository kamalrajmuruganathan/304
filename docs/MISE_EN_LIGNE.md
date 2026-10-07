# Mise en ligne — le guide pas à pas

> **État au 05/10/2026** — étapes 1 et 2 faites (dépôt, CI, GitHub Pages : prototype sur `/304/`, app Flutter
> sur `/304/app/`). Étape 3 faite **sans carte bancaire** : serveur sur **Render** (offre gratuite) au lieu de
> Cloud Run — service Docker relié au dépôt, URL `https://three04-bivu.onrender.com` (WebSocket `wss://…/ws`).
> L'adresse du serveur utilisée par l'app web et l'APK se change sans toucher au code :
> **Settings → Secrets and variables → Actions → Variables → `SERVER_URL`**.
> Un APK Android de test est publié à chaque mise à jour de `main` :
> https://github.com/kamalrajmuruganathan/304/releases/latest/download/304.apk
> La section Cloud Run ci-dessous reste valable si un jour une carte bancaire est utilisée.

Tout le code et les scripts sont prêts. Ce qui reste demande **tes comptes** et **un ordinateur**.
Les étapes sont dans l'ordre ; chacune débloque la suivante.

| # | Étape | Coût | Temps |
|---|---|---|---|
| 1 | Préparer le projet + pousser sur GitHub | gratuit | 15 min |
| 2 | Jeu web public (GitHub Pages) | gratuit | 2 min |
| 3 | Serveur multijoueur (Google Cloud Run) | quasi gratuit* | 10 min |
| 4 | Android (Google Play) | 25 $ une fois | 1 h + 14 jours de test |
| 5 | iPhone (App Store) | 99 $ / an | 2 h + revue Apple |

\* Cloud Run : facturé à l'usage, instance à zéro quand personne ne joue. Pour quelques tables entre amis, quelques euros par mois au plus.

---

## 1. Préparer le projet (PC, une seule fois)

Prérequis : [Flutter](https://docs.flutter.dev/get-started/install) ≥ 3.22 et Git.

```bash
cd game304
# Génère les dossiers android/, ios/, web/ (absents du zip). Ne touche pas à lib/.
flutter create --platforms=android,ios,web --org com.kjtech --project-name game304 .
# ⚠️ flutter create ajoute un test d'exemple incompatible : le supprimer, sinon la CI échoue.
rm -f test/widget_test.dart
flutter pub get
flutter test          # doit passer
flutter run -d chrome # essai local (partie solo)
```

Puis pousser sur GitHub : voir `PUSH.md`. La CI se lance toute seule
(analyse Dart, tests du moteur, parties jouées automatiquement dans le prototype).
**Si elle est rouge, copie-moi le message d'erreur.**

## 2. Jeu web public — GitHub Pages (gratuit, sans autre compte)

Sur GitHub : **Settings → Pages → Source : GitHub Actions**. C'est tout.
À chaque push, le jeu est publié à l'adresse :

`https://kamalrajmuruganathan.github.io/304/`

(la version jouable solo contre les bots, dans les 4 langues ; la politique de
confidentialité est servie sur `/privacy.html` — utile pour les stores).

## 3. Serveur multijoueur — Google Cloud Run

Prérequis : [gcloud CLI](https://cloud.google.com/sdk/docs/install), un projet GCP avec facturation activée.

```bash
gcloud auth login
./deploy/server.sh <ID_DE_TON_PROJET_GCP>
```

Le script affiche à la fin l'adresse à utiliser dans l'app, du type
`wss://game304-server-xxxxx.a.run.app/ws`. Test : `curl https://…/health` doit répondre `ok`.

Choix de configuration (déjà dans le script) : **une seule instance** (les tables vivent
en mémoire), affinité de session pour les WebSockets, connexions d'1 h max.

### Essayer le multijoueur tout de suite
```bash
flutter run -d chrome --dart-define=SERVER_URL=wss://game304-server-xxxxx.a.run.app/ws
```
Accueil → **Table privée entre amis** → *Créer une table* → partager le code à 4 lettres.
Le 2ᵉ joueur devient ton partenaire ; les sièges vides sont tenus par des bots.

Optionnel : publier la version Flutter web (avec multijoueur) sur Firebase Hosting :
`./deploy/web.sh <ID_PROJET_FIREBASE> wss://…/ws` (nécessite `npm i -g firebase-tools` et `firebase login`).

## 4. Android — Google Play

1. Créer un compte [Google Play Console](https://play.google.com/console) (**25 $**, une fois).
   - ⚠️ **Compte personnel créé récemment** : Google exige un **test fermé avec au moins
     12 testeurs pendant 14 jours** avant de pouvoir publier. Prévois ta famille/tes amis.
   - Un compte **organisation** (ex. au nom de ta micro-entreprise, numéro D-U-N-S requis)
     n'a pas cette contrainte.
2. Créer la **clé d'upload** (une fois, sur PC avec Java installé ; **à sauvegarder précieusement**,
   par ex. dans un gestionnaire de mots de passe) :
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   base64 -w0 upload-keystore.jks > upload-keystore.b64     # Windows : certutil -encode upload-keystore.jks upload-keystore.b64
   ```
   Puis sur GitHub : **Settings → Secrets and variables → Actions → New repository secret**, créer :
   | Secret | Valeur |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | contenu de `upload-keystore.b64` (une seule ligne ; avec certutil, retirer les lignes BEGIN/END) |
   | `ANDROID_KEYSTORE_PASSWORD` | mot de passe du keystore |
   | `ANDROID_KEY_ALIAS` | `upload` |
   | `ANDROID_KEY_PASSWORD` | mot de passe de la clé (souvent le même) |

   Le fichier `.jks` et les mots de passe ne doivent **jamais** être commités (`*.keystore`,
   `*.jks` et `key.properties` sont ignorés par Git). Avec **Play App Signing** (par défaut),
   Google garde la clé finale : une clé d'upload perdue peut être réinitialisée via le support.
3. Construire : à chaque fusion sur `main`, le workflow **APK Android** produit aussi
   `304.aab` (signé avec la clé d'upload) et le joint à la release GitHub. Le téléverser dans la
   Play Console (Test fermé → Créer une release). Le `versionCode` = numéro d'exécution du
   workflow (toujours croissant). En local : `android/key.properties` (voir
   [la doc Flutter](https://docs.flutter.dev/deployment/android#sign-the-app)) puis
   `flutter build appbundle`.
4. Remplir la fiche avec `docs/STORE_LISTING.md` et l'URL de confidentialité (étape 2).

## 5. iPhone — App Store

1. Compte [Apple Developer](https://developer.apple.com/programs/) : **99 $ / an**.
2. **Un Mac avec Xcode est obligatoire** pour construire et envoyer l'app.
3. Sur le Mac : `./deploy/mobile.sh wss://…/ws` puis envoi via Transporter ou Xcode.
4. Dans App Store Connect : fiche (`docs/STORE_LISTING.md`), confidentialité, classification.
   Revue Apple : généralement 1 à 3 jours.

---

## Points d'attention pour la validation des stores

- **Nom** : ne pas utiliser « Thuru » (marque de l'app concurrente). Voir les propositions
  dans `docs/STORE_LISTING.md`.
- **Argent réel** : le jeu n'en utilise pas — le dire clairement (déjà dans la fiche et la
  politique de confidentialité) évite d'être classé « jeu d'argent ».
- **Confidentialité** : aucun compte, préférences stockées sur l'appareil, pseudonyme
  multijoueur non conservé. Remplacer `[EMAIL DE CONTACT]` et `[DATE]` dans `docs/privacy.html`.
- **Icône** : générer les tailles à partir de `assets/icon.svg`
  (par ex. avec le paquet `flutter_launcher_icons`).
