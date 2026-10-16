# Règles du 304 (référence du moteur)

Version Jaffna (référence [pagat.com](https://www.pagat.com/jass/304.html)), telle qu'implémentée dans `lib/engine/engine.dart`.

## Base
- **4 joueurs, 2 équipes** de 2, partenaires face à face. Jeu **anti-horaire**.
- **Paquet de 32 cartes** : 7, 8, 9, 10, V(J), D(Q), R(K), As par couleur.
- **Hiérarchie (fort → faible)** : **J, 9, A, 10, K, Q, 8, 7**.
- **Valeurs** : J=30, 9=20, A=11, 10=10, K=3, Q=2, 8=0, 7=0 → **total 304**.

## Déroulé d'une donne
1. **1er temps** : 4 cartes chacune.
2. **Redistribution** : le joueur à droite du donneur peut l'exiger si ses 4 cartes valent **< 15 pts**.
3. **1er tour d'enchères** (sur 4 cartes) : minimum **160**, multiples de 10. Un joueur qui reparle, ou dont le partenaire mène, doit annoncer **≥ 200**. Fin après 3 passes consécutives.
4. Le preneur **pose une carte face cachée** : sa couleur devient l'**atout** (caché).
5. **2e temps** : 4 cartes de plus (→ 8 ; le preneur garde 7 en main + l'atout posé).
6. **2e tour d'enchères** (sur 8 cartes) : à partir du gagnant du 1er tour, un tour de table. Bids **≥ 250** et supérieurs au 1er tour. Annoncer fait de soi le nouveau preneur (il récupère et repose un atout). On ne peut pas surenchérir sur son partenaire.
   - **Partner Close Caps** : l'enchère max. Le preneur joue **seul** contre les 2 adversaires (partenaire écarté), mène le 1er pli, doit gagner les 8 plis.
7. **Jeu ouvert / fermé** au choix du preneur.
8. **8 plis** — voir ci-dessous.

## Jeu des plis (atout fermé)
- On doit **suivre la couleur** demandée si possible (carte face visible).
- Sinon, on joue une carte **face cachée** (tentative de coupe en devinant l'atout).
- En fin de pli, le preneur inspecte les cartes cachées : si l'une est l'atout, **révélation** — l'atout devient ouvert pour le reste de la donne.
- **Enchère ≥ 250 (et Partner Close Caps)** : l'atout est **révélé après le 1er pli**.

## Score (jetons, transfert entre équipes, 11 chacun au départ)
| Enchère | Réussie | Ratée |
|---|---|---|
| < 200 | +1 | −2 |
| 200–249 | +2 | −3 |
| ≥ 250 | +3 | −4 |
| Partner Close Caps | +4 | −5 |

- **Caps** (les 8 plis, règle de pagat.com) : dès qu'un joueur **doit savoir**, avec les cartes qu'il
  a vues, que son équipe gagnera **tous** les plis restants, il doit **annoncer « Caps »** avant
  d'entamer. Annonce juste à la **1re occasion**, au plus tard à l'entame du **7e pli** : **+1** jeton.
  **Wrong Caps** — annonce trop tôt (pas encore certaine), trop tard (occasion déjà passée), oubliée, ou
  suivie d'un pli perdu : **−2 jetons** pour l'équipe fautive (Pagat ne chiffre pas la pénalité ; 2 est
  la valeur la plus citée). Les 8 plis sans annonce ni occasion certaine ne rapportent pas de bonus.
  Pas de Caps en Partner Close Caps (déjà une enchère « 8 plis »).
- **Mise en œuvre** : l'occasion est évaluée pour le joueur qui entame (plis 1 à 7), son équipe ayant
  gagné tous les plis joués ; « certain » = il connaît l'atout et, en menant ses atouts du plus fort
  puis ses autres cartes, chacune gagne quelle que soit la répartition des cartes qu'il n'a pas vues
  (un atout posé chez un autre joueur ne tombe pas sur une entame atout). Les bots annoncent dès que
  c'est certain (vérifié : 1 277 annonces sur 188 325 donnes simulées, toutes réussies).
- Une équipe gagne la **partie** quand l'adversaire tombe à **0 jeton**.

## Sous-règles (statut)
- ~~Wrong Caps~~ → implémenté (16/10/2026), voir Score.
- Half-Court (variante à 4 cartes).
