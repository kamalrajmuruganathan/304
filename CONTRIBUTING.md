# Contribuer

## Mettre en place
```bash
flutter pub get
flutter test        # doit passer (moteur + Partner Close Caps)
flutter analyze
```

## Où vit quoi
- **Règles** : `lib/engine/engine.dart` — toute la logique de jeu. Toute modif doit
  garder les tests verts (`test/engine_test.dart`) et, idéalement, être vérifiée aussi
  dans le prototype de référence `prototype/304.html`.
- **IA** : `lib/ai/bots.dart`.
- **Réseau** : `lib/net/client.dart` (client) et `bin/server.dart` (serveur autoritatif).
- **UI** : `lib/ui/`.
- **Traductions** : `lib/l10n/*.arb` (modèle : `app_en.arb`).

## Règles d'or
1. Le **serveur est l'autorité** : ne jamais dupliquer/déplacer la logique de règles
   dans le client ou l'UI.
2. Ne jamais envoyer au client des infos cachées : passer par `engine.viewFor(seat)`.
3. La CI (`.github/workflows/ci.yml`) lance analyze + test à chaque push.
