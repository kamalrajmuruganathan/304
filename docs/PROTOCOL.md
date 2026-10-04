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
| `play` | `{card}` ou `{indicator:true}` | `playCard()` / `playIndicatorToCut()` |

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
  "legalBids": [], "canPCC": false
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
