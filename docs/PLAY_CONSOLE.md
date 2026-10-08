# Publier sur Google Play — pas à pas (Play Console)

Guide pour la première publication de **304**. Les intitulés de la Play Console changent
parfois : si un écran ne correspond pas exactement, chercher le même mot-clé dans le menu.
Textes et visuels : `docs/STORE_LISTING.md` et `docs/store/`.

## 0. Avant de commencer (une seule fois)

| Quoi | Où | Statut |
|---|---|---|
| Clé d'upload + 4 secrets GitHub | `docs/MISE_EN_LIGNE.md` §4 | ⬜ à faire par Kamal |
| `.aab` signé | release GitHub `android-N` (fichier `304.aab`), produite à chaque fusion sur `main` une fois la clé configurée | ⬜ après la clé |
| Adresse e-mail de contact (publique) | adresse dédiée conseillée, ex. `jeu304.contact@gmail.com` | ⬜ à créer |
| Serveur en ligne sur `main` | Render → service `three04` → Settings → Branch = `main` | ⬜ à faire |

## 1. Compte développeur
1. https://play.google.com/console → **Créer un compte** → type **Personnel** (ou Organisation
   si tu as un numéro D-U-N-S ; l'organisation évite le test fermé obligatoire).
2. Payer les **25 $** (une fois), vérifier l'identité (pièce d'identité) et le téléphone.
3. Compte personnel récent : Google impose un **test fermé avec au moins 12 testeurs pendant
   14 jours d'affilée** avant de pouvoir demander l'accès à la production (étape 7).

## 2. Créer l'application
**Créer une application** :
- Nom : celui choisi dans `STORE_LISTING.md` (jamais « Thuru »).
- Langue par défaut : **Français (France) – fr-FR**.
- Application ou jeu : **Jeu** ; Gratuite ou payante : **Gratuite**.
- Cocher les déclarations (règles du programme, lois export US).

## 3. Signature
**Configuration → Intégrité de l'application → Signature d'application** : accepter
**Play App Signing** (Google garde la clé finale ; ta clé d'upload sert seulement à envoyer les
`.aab`, elle peut être réinitialisée par le support si elle est perdue).

## 4. Contenu de l'application (menu « Contenu de l'appli » / « Règles »)

| Rubrique | Réponse |
|---|---|
| Règles de confidentialité | `https://kamalrajmuruganathan.github.io/304/privacy.html` |
| Accès à l'application | **Toutes les fonctionnalités sont accessibles sans restriction** (aucun compte). Préciser : « Le mode en ligne utilise un serveur gratuit qui peut mettre 30 à 60 s à se réveiller. » |
| Annonces | **Non, mon application ne contient pas d'annonces** |
| Classification du contenu (IARC) | catégorie **Jeu** (« Jeux de cartes / plateau / casse-tête » selon l'écran) ; violence, sexe, langage, drogues : **Non** ; **jeux d'argent simulés : Non** (jeu de plis, les jetons sont un score, aucune mise) ; **les utilisateurs peuvent-ils interagir ou échanger du contenu : Oui** (chat texte des tables privées) ; partage de position : Non ; achats numériques : Non |
| Public cible | **13 ans et plus** (13–15, 16–17, 18+). Ne pas cocher les tranches d'âge enfants (le chat les exclut des règles « Familles ») |
| Application d'actualités | Non |
| Applications gouvernementales / finance / santé | Non |
| Sécurité des données | voir §5 |

## 5. Sécurité des données (déclaration prudente)

L'app n'a ni compte, ni publicité, ni analyse. Deux informations transitent par le serveur en
ligne et y restent **seulement en mémoire** le temps de la table : le **pseudonyme** saisi et
les **messages du chat**. Déclaration recommandée (prudente, cohérente avec `privacy.html`) :

- **Votre application collecte-t-elle ou partage-t-elle des données ?** Oui.
- **Toutes les données sont-elles chiffrées en transit ?** Oui (WebSocket `wss://`).
- **Moyen de demander la suppression ?** Les données ne sont pas conservées (supprimées à la
  fin de la table) — répondre selon l'option proposée, sinon indiquer l'URL des issues GitHub.
- Types de données :

| Type | Collecté | Partagé | Éphémère | Obligatoire | Finalité |
|---|---|---|---|---|---|
| Infos personnelles → **Nom** (pseudonyme libre, peut être inventé) | Oui | Non | Oui | Non (facultatif : un nom par défaut est proposé) | Fonctionnalité de l'application |
| Messages → **Autres messages dans l'application** (chat de table) | Oui | Non | Oui | Non | Fonctionnalité de l'application |

Tout le reste : **non collecté** (préférences et statistiques restent sur l'appareil).

## 6. Fiche du Play Store (« Présence sur le Play Store → Fiche principale »)

| Champ | Contenu |
|---|---|
| Nom | ≤ 30 caractères (voir `STORE_LISTING.md`) |
| Description courte | `STORE_LISTING.md` (FR ; ajouter EN/TA/SI via **Traductions → Ajouter**) |
| Description longue | `STORE_LISTING.md` (FR, EN, TA, SI) |
| Icône 512×512 | `docs/store/icon-512.png` |
| Image de présentation 1024×500 | `docs/store/feature-1024x500.png` |
| Captures téléphone (2 à 8) | `docs/store/screenshots/fr/1-home.png` … `4-result.png` (et `en/`, `ta/`, `si/` pour chaque traduction) |
| Captures tablette 7 pouces | `docs/store/screenshots/tablet7/fr/` (et `en/`) |
| Captures tablette 10 pouces | `docs/store/screenshots/tablet10/fr/` (et `en/`) |
| Catégorie | **Jeux → Cartes** |
| Coordonnées | e-mail de contact (obligatoire, public) ; site web facultatif : `https://kamalrajmuruganathan.github.io/304/` |

## 7. Test fermé (obligatoire pour un compte personnel récent)
1. **Tester → Tests fermés → Créer un canal** (ou utiliser « Alpha »).
2. **Testeurs** : créer une liste d'e-mails (comptes Google) avec **au moins 12 personnes**.
3. **Créer une release** → téléverser `304.aab` (télécharger depuis la dernière release
   GitHub) → notes de version (ex. « Première version de test ») → **Examiner** → **Lancer**.
4. Envoyer aux testeurs le **lien d'inscription** affiché par la console ; chacun doit
   **accepter** puis installer l'app depuis le Play Store et la garder **14 jours**.
5. Chaque nouvelle version : fusion sur `main` → nouvelle release GitHub → nouveau `.aab`
   (le `versionCode` augmente tout seul) → nouvelle release dans le même canal.
6. Après 14 jours : **Tableau de bord → Demander l'accès à la production** (questionnaire
   sur le test : nombre de testeurs, retours reçus, changements faits).

## 8. Production
**Production → Créer une release** → même `.aab` (ou plus récent) → pays : tous, ou commencer
par Sri Lanka, Inde, France, Royaume-Uni, Canada, Suisse → **Envoyer pour examen**
(quelques heures à quelques jours).

## Pièges connus
- Ne jamais réutiliser « Thuru » (marque concurrente) dans le nom, la description ou les visuels.
- Toujours écrire « **sans argent réel** » : un jeu de cartes avec jetons peut être pris pour
  un jeu d'argent.
- Le `.aab` doit être signé avec **la même clé d'upload** à chaque fois : la sauvegarder.
- Les textes tamoul et cingalais sont des traductions automatiques vérifiées techniquement :
  une **relecture par un locuteur natif** est recommandée avant la production.
