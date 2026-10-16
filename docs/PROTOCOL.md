# Protocole client ↔ serveur (WebSocket, JSON)

Chaque message est un objet JSON avec un champ `t` (type). Transport : WebSocket (`wss://…/ws`).

## Client → serveur

| `t` | Charge utile | Effet |
|---|---|---|
| `create` | `{name}` | Crée une table, renvoie `joined` (siège 0 + code). |
| `join` | `{code, name}` | Rejoint la table `code` sur un siège libre. |
| `reconnect` | `{token}` | Reprend sa place après coupure. |
| `start` | `{}` | Démarre la partie (sièges vides → bots). Hôte uniquement. |
| `action` | `{action}` | Joue un coup (voir ci-dessous). Rejeté si ce n'est pas ton tour ou si illégal. |
| `chat` | `{text}` | Message de table (option). |

### Objet `action`
| `type` | Champs | Correspond à |
|---|---|---|
| `redeal` | `{keep:bool}` | `redeal()` ou `startBidding1()` |
| `bid` | `{value:int\|null}` | `placeBid(value)` (null = passe) |
| `chooseTrump1` | `{card:{s,r}}` | `chooseTrump1(card)` |
| `bid2` | `{value:int\|"PCC"\|null}` | `placeBid2(value)` |
| `chooseTrump2` | `{card}` | `chooseTrump2(card)` |
| `chooseTrumpPCC` | `{card}` | `chooseTrumpPCC(card)` |
| `open` | `{open:bool}` | `startPlayOpen()` / `startPlayClosed()` |
| `play` | `{card}` ou `{indicator:true}` | `playCard()` / `playIndicatorToCut()` (refusé si `canCutWithIndicator` est faux ; la vue indique `canCut`) |

Une carte est toujours `{"s":"S|C|D|H","r":"7|8|9|10|J|Q|K|A"}`.

## Serveur → client

| `t` | Charge utile |
|---|---|
| `joined` | `{code, seat, token}` |
| `state` | `{you:seat, view:{…}}` — `view` = `engine.viewFor(seat)` (rédigé). Émis après chaque changement. |
| `trick` | `{winner, points, revealed}` — pour animer la fin de pli (option). |
| `handResult` | `{score:{…}, gameOver, gameWinner}` |
| `error` | `{msg}` |
| `chat` | `{seat, text}` |

## Forme de `view` (extrait de `snapshot`)
```json
{
  "phase": "play",
  "you": 0,
  "yourTurn": true,
  "turn": 0,
  "tokens": {"NS": 11, "EW": 11},
  "bid": 180, "trumpMaker": 0, "pcc": false,
  "trumpOpen": false, "trumpSuit": "S",      // trumpSuit null si caché pour ce joueur
  "trickWinsNS": 2, "trickWinsEW": 1,
  "hands": [ [{"s":"S","r":"J"}, …],          // TA main en clair
             {"count": 8}, {"count": 8}, {"count": 8} ],  // les autres = compte
  "currentTrick": [ {"seat":3,"faceDown":false,"card":{"s":"S","r":"9"}},
                    {"seat":0,"faceDown":true,"card":null} ],  // face cachée = card null
  "legalBids": [], "canPCC": false, "canCut": false
}
```

## Boucle serveur (pseudo)
```
on action(seat, a):
  if engine.seatToAct != seat: send error; return
  applyAction(engine, a)          // dispatch vers la méthode du moteur
  broadcastState()                // viewFor(seat) à chaque humain
  advanceUntilHuman()             // joue bots + transitions auto, en diffusant
```

## Ajouts (12/10/2026)
- Client → serveur `{"t":"leave"}` : le joueur quitte la table ; son siège redevient un bot (libre
  pour un nouvel arrivant) et son jeton n'est plus valable.
- Joueur déconnecté depuis `BOT_TAKEOVER_SECONDS` (20 s par défaut) : le serveur joue pour lui
  jusqu'à sa reconnexion ; la vue indique `players[i].away = true`.
- Aucun joueur connecté à la table : le serveur ne fait plus avancer la partie.
- Chat : un texte `:r:<clé>` (clés `wellPlayed`, `comeOn`, `oops`, `thanks`, `hurry`, `goodGame`)
  est une réaction rapide, affichée traduite par chaque client.

## Caps (16/10/2026)
- Action `{"type":"caps"}` : annonce « Caps » avant d'entamer ; acceptée si `canCaps` (sinon
  `invalidAction`) ; jugée par le moteur au décompte (bonus +1 ou Wrong Caps −2).
- Vue : `canCaps` (je peux annoncer), `capsBy` (siège qui a annoncé), `playable` (mes cartes jouables,
  calculées par le moteur), `lastScore.capsTeam` / `lastScore.wrongCaps` (équipe bonifiée / pénalisée).

## Chat vocal (13/10/2026)
L'audio passe **directement d'un appareil à l'autre** (WebRTC, maillage entre les humains de la
table) ; le serveur ne relaie que la signalisation et n'entend rien.
- `joined` contient `ice` : serveurs STUN/TURN à utiliser (`[{urls:[…]}, {urls, username, credential}]`),
  réglés côté serveur par `STUN_URLS` (défaut `stun:stun.l.google.com:19302`), `TURN_URLS`,
  `TURN_USERNAME`, `TURN_CREDENTIAL`.
- Client → serveur `{"t":"voice","on":true|false,"muted":true|false}` : rejoindre / quitter le vocal,
  micro coupé ou non ; la vue indique `players[i].voice` et `players[i].muted` (remis à `false` à la
  déconnexion : le client les renvoie après reconnexion).
- Client → serveur `{"t":"rtc","to":<siège>,"data":{…}}` → relayé au seul destinataire sous la forme
  `{"t":"rtc","from":<siège>,"data":{…}}`, si l'expéditeur et le destinataire sont dans le vocal
  (sinon ignoré ; 20 000 caractères max). `data` = `{type:"offer"|"answer", sdp}` ou
  `{ice:{candidate, sdpMid, sdpMLineIndex}}`.
- Dans chaque paire, seul le **plus petit siège** envoie l'offre (`callsFirst`, `lib/net/voice.dart`).

