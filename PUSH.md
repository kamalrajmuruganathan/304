# Mettre ce projet sur GitHub

Ton dépôt existe déjà : **github.com/kamalrajmuruganathan/304**
(l'appli GitHub mobile gère mal l'upload de code — fais-le depuis un ordinateur.)

## Depuis un ordinateur

1. Télécharge et décompresse `game304.zip`.
2. Dans un terminal, place-toi dans le dossier `game304` :

```bash
cd game304
git init
git add .
git commit -m "304: moteur Dart (règles officielles + Partner Close Caps), prototype web, i18n, tests"
git branch -M main
git remote add origin https://github.com/kamalrajmuruganathan/304.git
git push -u origin main
```

Si le dépôt contient déjà des fichiers (README créé sur GitHub, etc.) :

```bash
git pull origin main --allow-unrelated-histories   # fusionne l'existant
# règle les conflits éventuels, puis :
git push -u origin main
```

## Vérifier avant de pousser (recommandé)

Avec Flutter installé (≥ 3.22) :

```bash
flutter pub get
flutter test        # doit passer : invariants + Partner Close Caps
flutter run -d chrome
```

## Astuce authentification

Si `git push` demande un mot de passe : GitHub n'accepte plus le mot de passe du
compte. Crée un **Personal Access Token** (Settings → Developer settings →
Personal access tokens) et utilise-le comme mot de passe, ou configure une clé SSH.
