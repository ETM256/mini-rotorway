# Rendu des routes : géométrie partagée

Ce document décrit `src/ReplicatedStorage/MiniMotorways/RoadGeometry.luau`,
le module qui décrit la surface des routes, puis le renderer serveur
(`RoadRenderer.luau`) qui les transforme en parts. Le module de géométrie ne
crée aucune instance : il renvoie des formes.

## Conventions

- **Repère de la case** : 0 à 1 sur chaque axe, origine en haut à gauche,
  `+x` vers la droite, `+y` vers le bas. Le centre est `(0.5, 0.5)`.
- **Directions** : `N` = `y-1`, `E` = `x+1`, `S` = `y+1`, `W` = `x-1`, comme `Grid`.
  Bits : `N = 1`, `E = 2`, `S = 4`, `W = 8` (`RoadGeometry.Dir`).
- **Clés** : format `Grid` (`"x:y"`). Un raccord à un bâtiment est une marque
  `"x:y>dir"` (`RoadGeometry.connectorKey`) posée sur la route qui touche le
  bâtiment. Ici `dir` est une lettre (`"N"`, `"E"`, `"S"`, `"W"`), et non le bit
  de `RoadGeometry.Dir`.
- **Monde** : la case `(x, y)` a pour coin `origin + (x * tile, 0, y * tile)`
  (cf. `Grid.center`). Un point local `(cx, cy)` se place donc en
  `X = origin.X + (x + cx) * tile`, `Z = origin.Z + (y + cy) * tile`.
- **Largeurs** : fractions de case, lues dans `RoadConfig.Visual`
  (`RoadWidth`, `EdgeWidth`, `CornerRadius` en fraction de `RoadWidth`).

## API

| Fonction | Rôle |
|----------|------|
| `RoadGeometry.cellPieces(roads, bridges, connectors, x, y, options?)` | pièces de la case, ou `{}` si ce n'est pas une route |
| `RoadGeometry.neighborMask(roads, x, y, bridges?, connectors?)` | bits N/E/S/W des bras (routes voisines et raccords) |
| `RoadGeometry.classify(mask)` | `kind` (`isolated`, `end`, `straight`, `corner`, `tee`, `cross`) et `orientation` |
| `RoadGeometry.affectedCells(key)` | la case et ses 4 voisins : les seules dont les pièces changent |
| `RoadGeometry.connectorKey(x, y, dir)` | clé d'un raccord |

## Pièces

Chaque pièce est une table :

```
{ kind, layer, cx, cy, w, h, r, rotation }
```

- `kind` : `"rect"` (`w` le long de `x` local, `h` le long de `y` local) ou
  `"disk"` (rayon `r`, `w = h = 2r`).
- `layer` : `"edge"` (liseré), `"body"` (surface graphite), `"bridge"`
  (surface d'un pont, à la place de `body`).
- `rotation` : `0`, `90`, `180` ou `270`. Les pièces produites valent `0`.

Une couche a une seule hauteur et une seule couleur : deux pièces d'une même
couche qui se chevauchent sont donc invisibles. C'est ce qui supprime les
coutures, les triangles et les pointes.

Formes, pour une demi-largeur `h` et un rayon d'angle `r` :

| Cas | Pièces (par couche) |
|-----|---------------------|
| isolée | 1 disque de rayon `h` (bloc rond) |
| cul-de-sac | 1 bras du bord au centre + 1 disque de rayon `h` (capuchon) |
| droite | 1 rectangle plein |
| virage | 2 rectangles + 1 disque de rayon `r` dans le coin extérieur |
| T | 2 rectangles (bande pleine + bras) |
| croix | 2 rectangles pleins |

Au plus 3 pièces par couche (un virage), donc 6 au total avec le liseré. Un bras relié à un
bâtiment s'arrête exactement au bord de la case.

Le liseré (`edge`) utilise la même géométrie avec la largeur `EdgeWidth`, et un
rayon d'angle augmenté de `(EdgeWidth - RoadWidth) / 2`. Ses arcs sont donc
concentriques à ceux de la surface : le contour a une épaisseur uniforme.

## Rendu : RoadRenderer

`src/ServerScriptService/MiniMotorways/RoadRenderer.luau` transforme les pièces
de `RoadGeometry` en `Part`. Il n'a aucune logique de partie. Le suivi des cases
à redessiner est dans `SessionRoadVisuals.luau`, qui ajoute ses méthodes à
`Session`.

### Parts et couches

Chaque pièce devient une part ancrée, sans collision, sans requête (`CanQuery`
faux) et sans ombre portée (`SessionUtil.makePart`). `rect` donne un bloc de
taille `(w * tile, épaisseur, h * tile)`. `disk` donne un `Cylinder` : l'axe d'un
cylindre est son axe X, la part est donc tournée de
`CFrame.Angles(0, 0, math.rad(90))` et sa taille est
`(épaisseur, diamètre, diamètre)` (épaisseur sur X, diamètres sur Y et Z). Le
disque est alors plat, dans le plan XZ.

Les hauteurs viennent de `RoadConfig.Layers` (studs au-dessus du plateau,
`Top` = dessus, `Thickness` = épaisseur). Une couche a une seule hauteur et une
seule couleur ; deux couches ne sont jamais coplanaires (écart d'au moins
0.01 stud entre deux couleurs différentes).

| Part | Couche | Dessus | Couleur |
|------|--------|--------|---------|
| `RoadEdge` | `Edge` | 0.29 | `Config.Colors.RoadEdge` (liseré) |
| `RoadBody` | `Body` | 0.31 | `Config.Colors.Road` (graphite) |
| `RoadBridgeEdge` | `BridgeEdge` | 0.37 | `Config.Colors.BridgeEdge` |
| `RoadBridge` | `Bridge` | 0.40 | `Config.Colors.Bridge` |
| `RoundaboutEdge` | `RoundaboutEdge` | 0.325 | `Config.Colors.RoadEdge` |
| `RoundaboutBody` | `RoundaboutBody` | 0.335 | `Config.Colors.Road` |
| `RoundaboutIsland` | `RoundaboutIsland` | 0.355 | `Config.Colors.White` |

Le décor (`WorldBuilder`) reste dessous : herbe 0.015, grille 0.035 à 0.045,
arbres 0.075, côte et eau 0.10 à 0.12, parcs secs 0.16 à 0.18. Les bâtiments
(`BuildingModels`) sont posés au-dessus des routes (ombre à partir de 0.38) et
les voitures (`CarModel`) au-dessus des bâtiments. L'ombre d'une voiture est
posée au-dessus de l'anneau des ronds-points (0.335) pour rester visible ;
elle disparaît sous le tablier d'un pont.

### Cycle de rendu

1. `Session:markRoadsDirty(keys, reveals?)` : marque chaque case de `keys` et
   ses quatre voisines (`RoadGeometry.affectedCells`) dans `self.roadDirty`.
   `reveals` (clé -> délai) désigne les cases neuves qui apparaissent en
   animation (`self.roadReveal`).
2. `Session:flushRoadRender()` : point d'entrée unique. Appelé à la fin de
   chaque lot de routes (`drawRoad`, `finishRoadErase`) et à chaque frame par
   `Session:update`. Sans case marquée, il ne fait rien (aucune allocation).
   Sinon, chaque case marquée est redessinée une seule fois, et seulement si sa
   signature (`RoadRenderer.signature` : masque des bras, raccords compris, et
   état de pont) a changé ou si elle est neuve. Le réseau entier n'est jamais
   redessiné.
3. `Session:renderRoadCell(key, reveal)` : détruit les parts de la case
   (`removeRoadVisual`), puis appelle `RoadRenderer.buildCell`, qui crée les
   parts sous `world.Roads`. L'état est `self.roadParts[key]` (parts) et
   `self.roadSignatures[key]` (forme rendue).

### Raccords aux bâtiments

`RoadRenderer.connectorsAround` marque, pour chaque côté orthogonal d'une case
occupé par un bâtiment, un raccord `RoadGeometry.connectorKey(x, y, dir)` : le
bras s'arrête alors au bord de la case. Les bâtiments naissent en cours de
partie : `syncBuildings` compare `#self.buildingList` à
`self.roadBuildingsSeen` et marque les cases des bâtiments neufs, ce qui
redessine les routes voisines.

### Apparition animée

`drawRoad` donne un délai échelonné à chaque case neuve
(`RoadConfig.Construction.RevealStagger`, plafonné par `RevealStaggerMax`).
`SessionUtil.animateRoadPart` fait grandir la pièce (52 % -> 100 %) et la rend
opaque (0.45 -> 0) en 0.18 s. Un tween serveur réplique la propriété à chaque
frame pour chaque pièce : une case coûte de 2 pièces (droite) à 6 (virage), et
un lot de 40 cases fait au plus 250 pièces tweenées en même temps. Au-delà de
`RoadConfig.Construction.MaxAnimatedCells` (40) cases neuves dans un lot, les
cases apparaissent sans animation. Seules les cases neuves sont animées ; les
voisines redessinées apparaissent d'un coup.

Les tweens sont suivis dans `session.tweens` (annulés à la fin de partie par
`SessionUtil.cancelTweens`). Quand une case est détruite pendant son
apparition, `SessionUtil.stopRoadPartReveal` annule le tween de chaque pièce
avant `Destroy` : aucun tween ne tourne sur une cible détruite.

### Ronds-points

`RoadRenderer.buildRoundabout` pose un `Model` `Roundabout` sous `world.FX` :
disque à liseré blanc (`RoundaboutEdge`), anneau graphite (`RoundaboutBody`) et
île centrale blanche (`RoundaboutIsland`), tous des cylindres de 0.03 à 0.05
stud, posés sur la case. `Session:createRoundaboutVisual(key)` remplace
l'ancien modèle de la case ; `removeRoadCell` le détruit avec la route.

### Points d'entrée historiques

Les noms suivants restent comme fines enveloppes (un autre code les appelle) :
`createRoadVisual(key, isBridge, delay, animate)` et `refreshRoadVisual(key)`
(redessin immédiat d'une case), `addRoadRibbons(cells)` (marque puis vide),
`rebuildRoadRibbons()` (équivaut à `flushRoadRender`), `clearRoadRibbons()`
(équivaut à `clearRoadVisuals`). `SessionRibbons.luau` est supprimé :
le ruban lissé est remplacé par `RoadRenderer`.

### Coûts

- Création : 2 à 6 parts par case, créées puis rangées sous `world.Roads`
  (le parent est posé en dernier par `makePart`).
- Effacement de tout le réseau : un `Destroy` par part, en une seule passe de
  rendu, puis une seule reconstruction du réseau (`commitRoadChange`).
- Aucun travail par frame sans changement : `flushRoadRender` sort dès que
  `roadDirty` est vide.

## Limites connues

- Le coin intérieur d'un virage reste vif (angle rentrant). L'arrondir demande
  une soustraction de formes, que le jeu de pièces ne permet pas.
- Les pièces de type `quarter` ne sont pas produites : le coin arrondi est un
  disque dont les trois autres quarts tombent dans la surface.
- `RoadConfig.Visual.ContourWidth` n'est pas utilisé. Un anneau intermédiaire
  serait une couche de plus, générée par la même fonction.
- Le module charge `RoadConfig`, donc `Config`, qui utilise `Color3.fromHex` :
  il ne tourne pas tel quel hors Roblox (il tourne dans le harnais de test).

## Tests

Le rendu serveur est couvert par `tests/sim/roadrender_*.test.luau` et
`tests/sim/server_visuals.test.luau` (orientation des disques, hauteurs des
couches, limite d'animation, tweens annulés).

`tests/unit/roadgeometry_pieces.test.luau` rastérise les pièces sur une grille
de 20 x 20 points et vérifie, pour les 16 masques, les cas avec raccords et
ponts, et des réseaux aléatoires à graine fixe : couverture des axes, largeur
de chaque bras, absence de fuite, arrondi des virages, capuchons, bords
continus entre cases voisines, rotation de la case et du réseau.

```bash
bash tests/run.sh roadgeometry
bash tests/run.sh sim/roadrender
bash tests/run.sh sim/server_visuals
```
