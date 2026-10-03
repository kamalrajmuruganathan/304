# Architecture multijoueur (ADR)

## Décision

**Serveur autoritatif en Dart qui réutilise `lib/engine/engine.dart`.**
Les clients (Flutter) n'envoient que des **actions** (« j'enchéris 180 », « je joue le V♠ »). Le serveur valide et applique l'action via le moteur, puis renvoie à chaque joueur **sa vue rédigée** (`engine.viewFor(seat)`).

### Pourquoi
- **Un seul jeu de règles.** Le moteur validé tourne côté serveur ; aucun risque de désync entre client et serveur, pas de logique dupliquée.
- **Anti-triche par construction.** Le client ne connaît jamais les cartes adverses ni l'atout caché : le serveur ne les lui envoie pas (`snapshot` masque). C'est le « never cheats » du concurrent, garanti.
- **Client léger.** L'UI ne fait qu'afficher un état et émettre des actions.
- **Réutilise tes compétences GCP.** Déploiement simple sur **Cloud Run** (conteneur, scale-to-zero, pas cher).

### Alternative écartée
Firebase seul (Firestore + règles côté client) : impose de réécrire les règles en Cloud Functions (duplication) ou d'exposer trop d'état. On garde Firebase **optionnel** pour l'auth et la persistance des profils/cosmétiques plus tard, pas pour la logique de jeu.

## Composants

```
Flutter (Android/iOS/Web)  ──WebSocket JSON──►  Serveur Dart (Cloud Run)
   lib/net/ (client)                              bin/server.dart
   affiche viewFor(seat)                          Engine (autorité) + bots
   émet des actions                               1 Room par partie
```

## Salles (rooms) & codes
- **Créer** une table → le serveur génère un **code à 4 caractères** et une Room (une instance `Engine`).
- **Rejoindre** avec le code → le joueur prend un siège libre.
- Au **démarrage**, les sièges vides sont **remplis par des bots** (le serveur appelle `botBid`, `botPlay`, … du même package). La partie démarre toujours.
- Le serveur **fait avancer les bots** et les transitions automatiques (redeal, distribution) ; il **attend une action** uniquement quand `engine.seatToAct` est un siège humain.

## Reconnexion
- À l'entrée, le serveur donne un **token** (siège + secret). En cas de coupure réseau, le client renvoie `reconnect{token}` et récupère sa place + l'état courant. Pendant l'absence, un **bot joue à sa place** (option) pour ne pas bloquer la table.

## Sécurité / équité
- Le serveur **rejette** toute action qui ne vient pas du siège censé jouer (`seatToAct`) ou qui n'est pas légale (`legalBids`, `playableCards`).
- Les vues sont rédigées **par siège** — impossible d'inspecter la main d'un autre via le réseau.

## Déploiement (cible)
- **Serveur** : conteneur Dart → Cloud Run (région proche EU). Redis/Memorystore plus tard si on veut des Rooms partagées entre instances ; au départ, une instance suffit.
- **Client web** : build `flutter build web` → Firebase Hosting ou tout hébergeur statique.
- **Mobile** : Play Store + App Store (comptes développeur requis).

## Voice chat (phase 4)
WebRTC pair-à-pair avec le **serveur comme signaling** (échange d'offres/ICE via le même WebSocket). À traiter après le multijoueur de base.
