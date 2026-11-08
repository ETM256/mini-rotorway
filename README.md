# Mini Rotorway

> **Prototype Roblox de gestion de trafic**, inspiré de *Mini Motorways*.
> Projet public, jouable et open source, pour jouer, tester et faire évoluer le jeu à deux.

![Statut](https://img.shields.io/badge/statut-prototype-orange)
![Version](https://img.shields.io/badge/version-1.3.0-blue)
![Roblox](https://img.shields.io/badge/Roblox-Studio-red)
![Luau](https://img.shields.io/badge/Luau-0%20erreur-brightgreen)
![Rojo](https://img.shields.io/badge/Rojo-7.7.1-purple)

**Mini Rotorway** est un jeu de gestion de trafic jouable dans Roblox. Tu dessines des routes, tu relies les maisons aux bâtiments de la même couleur, tu livres les trajets et tu tentes de tenir le plus longtemps possible sans que la circulation s'effondre.

Le projet contient **6 cartes** : Dubaï, Los Angeles, Pékin, Tokyo, Dar es Salaam et Londres. Tous les décors et l'interface sont générés en code avec des primitives Roblox : aucune image, police ou asset externe n'est nécessaire.

---

## Sommaire

- [En bref](#en-bref)
- [Télécharger et lancer](#télécharger-et-lancer)
- [Jouer à deux](#jouer-à-deux)
- [Commandes](#commandes)
- [Règles du jeu](#règles-du-jeu)
- [Les 6 cartes](#les-6-cartes)
- [Fonctionnalités](#fonctionnalités)
- [Historique du projet](#historique-du-projet)
- [Architecture](#architecture)
- [Développement](#développement)
- [État du prototype](#état-du-prototype)
- [Roadmap](#roadmap)
- [Avertissement](#avertissement)

---

## En bref

| Élément | Détail |
| --- | --- |
| Type | Gestion de trafic / puzzle |
| Plateforme | Roblox Studio |
| Joueurs | 1 joueur par ville, plusieurs villes en parallèle |
| Vue | Caméra de dessus, zoom et déplacement |
| Grille | 18 × 18 cases de 4 studs |
| Cartes | 6 |
| Durée d'une semaine | 60 secondes |
| Version | 1.3.0 |
| Statut | Prototype jouable |

---

## Télécharger et lancer

### Pour jouer tout de suite

1. Télécharge le build : **[MiniMotorwaysRBX.rbxlx](./MiniMotorwaysRBX.rbxlx)**
2. Ouvre **Roblox Studio**.
3. Va dans `File` → `Open from File…`.
4. Sélectionne `MiniMotorwaysRBX.rbxlx`.
5. Appuie sur **Play** (F5).
6. Dans le lobby : clique sur **Jouer**, choisis une carte, puis dessine tes routes.

> Le fichier de build s'appelle encore `MiniMotorwaysRBX.rbxlx` pour rester compatible avec les outils du projet. Le nom public du jeu est **Mini Rotorway**.

### Activer les meilleurs scores persistants

Le jeu utilise un `DataStore` nommé `MiniMotorwaysV1`.

- En local, sans API Services, les scores restent en mémoire pendant la session.
- Pour la persistance : `Game Settings` → `Security` → active **Enable Studio Access to API Services**, puis publie la place.
- La clé utilisée est `player_<UserId>`.

---

## Jouer à deux

### En local

Chacun ouvre le fichier dans Roblox Studio et joue sa propre ville. Pratique pour tester, comparer les scores et signaler les bugs.

### Sur Roblox

1. Publie la place depuis Roblox Studio.
2. Invite ton pote dans la place publiée.
3. Chaque joueur reçoit sa propre ville dans `Workspace.MMWorlds`.
4. Active les DataStores pour conserver les records.

> Avant une publication publique, change le nom affiché dans `Config.GameName` et remplace l'identité visuelle provisoire. Voir la section [Avertissement](#avertissement).

---

## Commandes

| Action | Souris | Clavier | Tactile |
| --- | --- | --- | --- |
| Dessiner une route | Clic gauche + glisser | — | Glisser |
| Effacer une route | Clic droit | — | Outil « Effacer » |
| Poser un rond-point | Outil « Rond-point » | `3` | Bouton du HUD |
| Changer d'outil | Boutons du HUD | `1` / `2` / `3` | Boutons du HUD |
| Zoomer / dézoomer | Molette | — | — |
| Déplacer la vue | Clic milieu + glisser | — | — |
| Ouvrir les contrôles de temps | Cliquer sur l'horloge | — | Toucher l'horloge |
| Pause | Bouton `II` | `P` | Bouton `II` |
| Reprendre | Bouton `▶` | — | Bouton `▶` |
| Changer la vitesse | Bouton `▶▶` | — | Bouton `▶▶` |
| Rejouer / menu | Boutons de l'écran de fin | — | Boutons de l'écran de fin |

La pause manuelle fige le temps mais **laisse la construction active** : on peut continuer à tracer ou effacer des routes et poser un rond-point. Aucun écran de pause ne s'affiche ; le bouton `▶` relance la simulation. La pause automatique du choix de semaine reste, elle, bloquante.

---

## Règles du jeu

- **Objectif** : livrer un maximum de trajets. Chaque livraison rapporte **1 point**.
- **Couleurs** : une maison doit être reliée par un chemin continu à une destination de la **même couleur**.
- **Routes** : une route coûte **1 route** par case. Une case d'eau coûte **1 pont**.
- **Ronds-points** : ils peuvent être posés sur une route existante comme repère de carrefour et sont récupérés si la route est effacée.
- **Semaines** : une semaine dure **60 secondes**. À la fin de chaque semaine, la partie se met en pause et propose **deux améliorations**. Le joueur en choisit une, puis la semaine suivante commence.
- **Améliorations** : chaque semaine, deux propositions. Les deux donnent des routes : **+20 routes** avec un outil spécial, ou **+30 / +40 routes** sans outil. Une seule proposition contient un **pont** ou un **rond-point**, comme dans Mini Motorways.
- **Circulation** : si des voitures restent bloquées trop longtemps, la jauge de circulation baisse. À **0 %**, la partie est terminée.
- **Budget de départ** : 20 routes, 1 pont, 0 rond-point, 3 paires maison/destination.
- **Records** : le meilleur score de chaque carte est affiché dans le lobby et sauvegardé si les DataStores sont disponibles.

---

## Les 6 cartes

| Carte | Ambiance | Défi principal |
| --- | --- | --- |
| **Dubaï** | Marina, eau au sud, quartiers dorés | Relier les quartiers et traverser la marina |
| **Los Angeles** | Côte ouest en goutte d'eau, grande baie, presqu'île | Gérer le quadrillage d'autoroutes de la métropole |
| **Pékin** | Grande ville dense, quartiers traditionnels | Faire arriver les habitants au travail à l'heure |
| **Tokyo** | Métropole tentaculaire, quartiers serrés | Relier les quartiers de la plus grande métropole du monde |
| **Dar es Salaam** | Croissance rapide, relief et eau | Suivre l'extension rapide de la ville |
| **Londres** | Tamise, rues historiques | Traverser le fleuve et redessiner les rues |

Chaque carte possède son aperçu circulaire dans le lobby, avec un tracé de routes, des bâtiments et une géographie d'eau partagée entre l'aperçu et la scène 3D.

---

## Fonctionnalités

- [x] Lobby animé avec route courbe, maison, destination et voitures qui circulent
- [x] 6 cartes avec aperçus circulaires et records locaux
- [x] Tracé de routes à la souris et au doigt, lignes droites, diagonales et virages arrondis
- [x] Ruban noir lissé au-dessus des cases : les routes suivent les diagonales et les courbes comme dans la vidéo de référence
- [x] Ponts pour traverser l'eau
- [x] Ronds-points posables sur le réseau
- [x] Serveur autoritaire : validation des routes, budget et état de la partie
- [x] Pathfinding A* en 8 directions sur la grille 18 × 18
- [x] Voitures qui partent, livrent, reviennent et recalculent leur chemin
- [x] Choix hebdomadaire fidèle au jeu : routes + outil spécial, ou lot de routes
- [x] Jauge de circulation et game over
- [x] Records par carte avec DataStore et fallback en mémoire
- [x] Interface adaptative portrait/paysage
- [x] Caméra avec zoom et déplacement
- [x] Pause, reprise et accélération du temps
- [x] Tout le décor et l'UI sont générés en code, sans asset externe

---

## Historique du projet

### Chronologie rapide

| Période | Étape |
| --- | --- |
| Fin octobre 2026 | Fondations Rojo, grille 18 × 18, pathfinding, serveur, client, refonte visuelle claire et française |
| 04/11/2026 | Sauvegarde d'un état issu d'une refonte plus lourde, finalement écartée |
| 07/11/2026 | Retour au prototype stable 1.3.0, page GitHub complète, routes diagonales lissées, dépôt public |
| 08/11/2026 | Extrémités de route plates, suppression des disques ronds aux fins de route |
| 08/11/2026 | Choix hebdomadaires fidèles à Mini Motorways : routes + outil spécial, ou lot de routes |
| 08/11/2026 | Extrémités de route ovales et suppression du gros carré bleu pendant la construction |

### 1. Fondations techniques

- Mise en place de la structure **Rojo** (`default.project.json`) et du build `MiniMotorwaysRBX.rbxlx`.
- Création de `Config.luau` : grille 18 × 18, cases de 4 studs, budgets, semaines, trafic, récompenses et palette.
- Création de `Maps.luau` avec **6 cartes** : Dubaï, Los Angeles, Pékin, Tokyo, Dar es Salaam et Londres.
- Création de `Grid.luau` : conversions case ↔ position 3D et voisinage orthogonal + diagonal.
- Création de `Pathfinding.luau` : **A\*** sur les routes en 8 directions.
- Création de `Remotes.luau` : RemoteEvents partagés entre serveur et client.

### 2. Serveur de jeu

- `Bootstrap.server.luau` : remotes, profils, boucle de jeu et gestion des sessions.
- `Session.luau` : routes, ponts, ronds-points, bâtiments, maisons, destinations, voitures, semaines, score et jauge de circulation.
- `WorldBuilder.luau` : sol crème, eau menthe, parcs, grille, étiquettes et dossiers 3D.
- `Profile.luau` : meilleurs scores via DataStore `MiniMotorwaysV1`, avec fallback en mémoire.
- **Serveur autoritaire** : il valide les routes, le budget, les ponts et les ronds-points.
- Une **ville isolée par joueur** dans `Workspace.MMWorlds`.
- Les voitures partent de la maison, livrent la destination, reviennent, et recalculent leur chemin si une route est supprimée.
- Choix hebdomadaire : pause serveur, deux améliorations proposées, validation puis reprise.
- Budget de départ : **20 routes, 1 pont, 0 rond-point, 3 paires maison/destination**.

### 3. Client, caméra et interface

- `Main.client.luau` : câblage du lobby, du HUD, de la caméra et des entrées.
- `CameraController.luau` : caméra de dessus quasi orthographique (FOV 20), zoom à la molette et déplacement au clic milieu.
- `InputController.luau` : dessin à la souris et au doigt, gomme et outil rond-point. En construction, le gros carré de visée est masqué : la route apparaît directement sous le curseur.
- `UI/Theme.luau` : palette claire et composants réutilisables.
- `UI/MapPreview.luau` : aperçus circulaires des cartes avec eau, parcs et tracé de route.
- `UI/Lobby.luau` : menu, 6 cartes, garage, statistiques et records.
- `UI/HUD.luau` : score, jour, horloge, vitesse, outils, compteurs, pause et écran de fin.
- Interface adaptative **portrait / paysage**, textes redimensionnés et interface entièrement en **français**.

### 4. Refonte visuelle claire

- Palette de Los Angeles : fond pêche, sol crème, eau menthe, eau profonde, parcs jaune-vert, liseré de côte blanc et ombre beige.
- Eau 3D lissée avec plusieurs couches et formes arrondies (rectangles, ellipses tournées, capsules).
- Correction des ellipses d'eau avec un `SpecialMesh` sphère pour éviter les formes aplaties invisibles.
- Presqu'îles sèches et côtes retravaillées, avec raccord terre net.
- Lumière adoucie : `Brightness = 0.8`, ambiance beige plus sombre et exposition réduite.
- Bordure beige hachurée avec étiquettes verticales turquoise.
- Routes **graphite `#262B2C`** avec fin liseré blanc, virages en arc et extrémités ovales.
- Bâtiments façon icônes : cartes plates à coins arrondis, liseré blanc, ombre douce, allée, toit à deux teintes, cheminées et épingles de destination.
- Petits arbres vectoriels dans les parcs.
- Voitures avec contour et toit clair pour rester lisibles sur les routes sombres.

### 5. Corrections et stabilisation

- `Enum.ScrollDirection` remplacé par `Enum.ScrollingDirection`.
- Boutons du lobby et du HUD fiabilisés avec `Active`, `Selectable` et fallback `MouseButton1Click`.
- Constructeurs `Vector3(...)` corrigés en `Vector3.new(...)`.
- Horloge corrigée : aiguilles centrées et aiguille des heures progressive.
- Contrôles de temps masqués par défaut, affichés au clic sur l'horloge.
- Pause manuelle : le temps s'arrête mais les routes restent modifiables.
- Diagonales corrigées : le client n'improvise plus un escalier de cases, le pathfinding utilise les 8 voisins et les voitures conservent leur vitesse réelle sur les segments diagonaux plus longs.
- Routes voisines rafraîchies dans les 8 directions pour éviter les raccords manquants.
- Apparition animée des routes : croissance et fondu à chaque case posée.

### 6. Routes diagonales et ruban lissé

- Analyse des **deux vidéos de référence** (65 s et 33 s, 1280 × 720, 30 fps) avec extraction d'images.
- Les vidéos montrent une route blanche libre, avec courbes, diagonales et extrémités arrondies.
- Décision de garder les **routes noires du jeu**, tout en reprenant la forme et le lissé.
- Ajout dans `Session.luau` d'un **ruban noir continu** tracé avec une spline de **Catmull-Rom** passant par les centres des cases.
- Le ruban ajoute :
  - un liseré blanc ;
  - des virages arrondis ;
  - des jonctions en disque ;
  - des **extrémités ovales**, avec un capuchon elliptique plus large que long, sans gros disque rond ;
  - des couleurs spécifiques pour les ponts.
- La simulation reste sur la grille : pathfinding, voitures, budget et règles ne changent pas.
- L'effacement reconstruit le ruban. Les reconstructions sont regroupées à la frame suivante (`roadRibbonsDirty`) pour éviter les ralentissements lors d'un effacement rapide.
- Le build de référence avant le ruban était `5C571B3D...` ; le build actuel est `7DB81580...`.

### 7. Retour à la base stable

- Une refonte plus ambitieuse a été tentée après la première version jouable.
- Elle a été sauvegardée puis volontairement mise de côté pour repartir du prototype **18 × 18 / version 1.3.0**, plus stable et plus proche de la version validée.
- Sauvegardes conservées :
  - `mini-motorways-rbx-backup-20261104-183146` ;
  - `mini-motorways-rbx-E7AB-backup-20261107-221824`.
- Le retour à la base stable a été fait avant d'ajouter le ruban lissé, pour ne pas mélanger les changements.

### 8. Page GitHub et publication

- Dépôt créé : **`ETM256/mini-rotorway`**.
- Ajout du build jouable, des sources, de la configuration Rojo, des outils et de `docs/PLAN.md`.
- README complet en français : pitch, téléchargement, commandes, règles, cartes, architecture, développement, état, roadmap et avertissement de marque.
- Ajout de `OUVRIR-ICI.txt` pour lancer le jeu rapidement.
- Ajout de `.gitignore` pour les fichiers temporaires Roblox / Windows.
- Le dépôt était privé, avec le pote ajouté comme collaborateur.
- Le **07/11/2026**, le dépôt est passé **public** : le pote peut maintenant télécharger le build sans être collaborateur.
- Pour contribuer au code, il faut toujours soit être collaborateur, soit passer par un fork + pull request.
- Commits principaux :
  - `5c515f9` : page GitHub et prototype jouable ;
  - `7479921` : ruban de route lissé ;
  - `484c867` : reconstruction différée et robustesse ;
  - `1b74f25` : page GitHub publique ;
  - `e898c12` : historique complet du projet ;
  - `c5b2ffe` : extrémités de route plates, sans ronds ;
  - `f74b7f9` : suppression des disques de jonction aux extrémités ;
  - `0519f67` : détails des extrémités plates dans le README ;
  - `90ff98c` : choix hebdomadaires fidèles à Mini Motorways ;
  - `3325d42` : extrémités ovales et suppression du gros carré de construction.

### 9. État actuel

- Version **1.3.0**, prototype jouable.
- **16 fichiers Luau**, 0 erreur de syntaxe.
- Build actuel : `7DB81580BA5D32007C86D20D670A5055C7AD19490CF9082626512384C35C6F8A`.
- 6 cartes, grille 18 × 18, routes noires, diagonales lissées, extrémités ovales, ponts, ronds-points, semaines et records.
- Choix hebdomadaires : **+1 pont/rond-point +20 routes**, ou **+30 / +40 routes**.
- Le dépôt est public : **https://github.com/ETM256/mini-rotorway**.
- Le test runtime complet dans Roblox Studio reste à refaire manuellement après les dernières modifications.

### 10. Extrémités ovales et curseur de construction

- Les **gros disques ronds** aux fins de route restent supprimés.
- Les extensions plates vont jusqu'au bord de la case pour assurer la continuité.
- Un **capuchon ovale** est ajouté par-dessus, sur le ruban et sur la case :
  - grand axe **perpendiculaire** à la route ;
  - petit axe **le long** de la route, environ **0,62 × la largeur** ;
  - résultat : une fin arrondie en ellipse, sans effet « grosse bille ».
- Les **disques de jonction** restent réservés aux virages et aux raccords intermédiaires ; ils ne sont pas recréés aux extrémités.
- En mode construction, le **gros carré bleu de sélection** est masqué : la route apparaît directement sous le curseur, comme dans la vidéo.
- Le carré reste disponible pour la **gomme** et le **rond-point**, où il sert de repère de placement.
- Build reconstruit et vérifié : `7DB81580BA5D32007C86D20D670A5055C7AD19490CF9082626512384C35C6F8A`.

### 11. Choix hebdomadaires fidèles à Mini Motorways

- Recherche sur le fonctionnement réel des **budget increases** de Mini Motorways (Wikipedia et wiki Fandom).
- Règle appliquée : chaque semaine propose **deux choix**, et **les deux donnent des routes**.
  - Une proposition contient un **outil spécial + 20 routes** (pont ou rond-point).
  - L'autre proposition est un **lot de routes seul** : **+30 routes**, parfois **+40 routes**.
- Une seule proposition contient un outil spécial, comme dans le jeu original.
- Les outils déjà au maximum ne sont plus proposés.
- Si tous les outils sont au maximum, les deux propositions deviennent des lots de routes.
- Le serveur reste en pause tant que le joueur n'a pas choisi.
- Outils réels du jeu original : **Bridge, Motorway, Road Tiles, Roundabout, Traffic Light, Tunnel**.
- Le prototype implémente **Bridge, Roundabout et Road Tiles**. **Motorway**, **Traffic Light** et **Tunnel** ne sont pas encore disponibles : ils ne sont donc pas proposés pour éviter des choix inutiles.
- Sources :
  - [Mini Motorways — Wikipedia](https://en.wikipedia.org/wiki/Mini_Motorways)
  - [Upgrades — Mini Motorways Wiki](https://mini-motorways.fandom.com/wiki/Upgrades)

---

## Architecture

```text
mini-rotorway/
├─ MiniMotorwaysRBX.rbxlx        ← place prête à ouvrir dans Studio
├─ default.project.json          ← mapping Rojo
├─ README.md
├─ docs/
│  └─ PLAN.md                    ← checklist de développement et de test
├─ tools/
│  ├─ build.ps1                  ← télécharge Rojo si besoin et construit le .rbxlx
│  └─ fix-source-tags.js         ← convertit les sources pour Studio
└─ src/
   ├─ ReplicatedStorage/MiniMotorways/
   │  ├─ Config.luau             ← réglages (grille, budget, semaines, couleurs)
   │  ├─ Maps.luau               ← les 6 cartes + géographie/eau + aperçus
   │  ├─ Grid.luau               ← conversions case ↔ position 3D
   │  ├─ Pathfinding.luau        ← A* sur le réseau de routes
   │  └─ Remotes.luau            ← RemoteEvents partagés
   ├─ ServerScriptService/MiniMotorways/
   │  ├─ Bootstrap.server.luau   ← point d'entrée serveur
   │  ├─ Session.luau            ← simulation d'une ville
   │  ├─ WorldBuilder.luau       ← sol, eau, grille, dossiers 3D
   │  └─ Profile.luau            ← DataStore / records
   └─ StarterPlayer/StarterPlayerScripts/MiniMotorways/
      ├─ Main.client.luau        ← câblage client
      ├─ CameraController.luau   ← caméra responsive au-dessus de la ville
      ├─ InputController.luau    ← dessin des routes + curseur
      └─ UI/
         ├─ Theme.luau           ← palette et constructeurs d'UI
         ├─ MapPreview.luau      ← aperçus circulaires des cartes
         ├─ Lobby.luau           ← menu, cartes, options, records
         └─ HUD.luau             ← score, semaine, outils, pause, game over
```

### Fonctionnement

- Le **serveur est autoritaire** : il valide les routes, gère le budget, les ponts, les ronds-points, les bâtiments, les voitures, les semaines, les choix d'amélioration, la jauge et les scores.
- Le **client ne fait que demander** : il envoie des lots de cases à dessiner, à effacer ou un rond-point à poser, et affiche l'état renvoyé par le serveur.
- Chaque joueur possède sa propre ville, placée très loin des autres dans `Workspace.MMWorlds`.
- Le pathfinding est un **A\*** en 8 directions sur la grille 18 × 18 (cases de 4 studs), diagonales comprises.
- Le **ruban de route** ajouté dans `Session.luau` est une spline de Catmull-Rom qui passe par les centres des cases. Il est purement visuel : il recouvre les cases pour donner les courbes et les diagonales continues de la vidéo, tandis que la simulation, les voitures et le budget restent sur la grille.
- Le choix hebdomadaire est un `RemoteEvent` serveur → client ; le serveur reste en pause tant qu'aucune des deux options n'a été validée.
- Les voitures partent de la maison, suivent le chemin, livrent la destination, puis reviennent. Si une route est supprimée, leur chemin est recalculé.

---

## Développement

### Rebuild rapide (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File tools/build.ps1
```

Le script télécharge Rojo 7.7.1 dans `%TEMP%\mini-motorways-rbx-tools` s'il n'est pas déjà présent, construit `MiniMotorwaysRBX.rbxlx`, puis convertit les balises `Source` pour Roblox Studio. Node.js est utilisé pour cette dernière étape.

### Rojo serve + plugin

```powershell
rojo serve default.project.json
```

Puis, dans Studio, ouvre le plugin **Rojo** et connecte-toi au serveur local. Les modifications de `.luau` sont alors synchronisées sans rebuild.

### Vérifier la syntaxe

Avec l'outil `luau-compile` :

```powershell
$files = Get-ChildItem -Recurse -Filter *.luau src |
    ForEach-Object { $_.FullName.Substring((Get-Location).Path.Length + 1) }
& "$env:TEMP\luau-tools\luau-compile.exe" --only-parse @files
```

### Personnalisation rapide

Tout est centralisé dans `src/ReplicatedStorage/MiniMotorways/Config.luau` :

- `Config.GameName` : nom affiché (à changer avant publication).
- `Config.Tagline` : sous-titre du menu.
- `Config.Grid` : taille de la grille et taille d'une case.
- `Config.Roads` : budget de départ, ponts, ronds-points et limites.
- `Config.Rewards` : les deux propositions d'amélioration hebdomadaires.
- `Config.Game` : durée d'une semaine, nombre de paires, délais.
- `Config.Traffic` : vitesse des voitures, patience, régénération.
- `Config.Colors` / `Config.HouseColors` : palette de l'interface et des bâtiments.

Les cartes sont dans `Maps.luau` : nom, description, couleurs, fonction `isWater` et petit tracé `previewRoads` pour l'aperçu du menu.

Le ruban lissé se règle dans `src/ServerScriptService/MiniMotorways/Session.luau` : `edgeWidth` / `topWidth` pour la largeur, `samplesPerSegment` pour la finesse des courbes, `edgeY` / `topY` pour les hauteurs de couche. Les couleurs restent celles du jeu : `Config.Colors.Road`, `RoadEdge`, `Bridge` et `BridgeEdge`.

---

## État du prototype

- **Version** : 1.3.0
- **Build actuel** : `7DB81580BA5D32007C86D20D670A5055C7AD19490CF9082626512384C35C6F8A`
- **Sources** : 16 fichiers Luau, 0 erreur de syntaxe
- **Test runtime** : à refaire dans Roblox Studio après chaque grosse modification

### Limites connues

- Le ruban lissé est **visuel** : les voitures suivent toujours les centres des cases de la grille. La courbe peut donc légèrement dépasser le centre du trajet, mais elle reste dans la largeur de la route.
- Les voitures utilisent un évitement simple : elles peuvent se bloquer dans des situations de trafic complexes. C'est volontaire pour le prototype, mais un système de priorités/feux serait la prochaine amélioration.
- Le zoom et le déplacement de caméra sont disponibles à la souris (molette et clic milieu) ; les gestes tactiles à deux doigts ne sont pas encore gérés.
- Les records sont locaux au serveur/DataStore ; il n'y a pas encore de classement global.
- Le nom et l'identité visuelle doivent être remplacés avant une publication publique.
- Il n'y a pas de test automatisé du runtime Roblox dans ce dépôt.

---

## Roadmap

1. Tester le parcours complet : lobby → carte → routes → livraisons → semaine → game over → rejouer.
2. Ajouter des sons discrets (clic, livraison, fin de semaine).
3. Ajouter un tutoriel intégré au premier lancement.
4. Améliorer la circulation : priorités, feux, évitement plus propre.
5. Ajouter des modes (sans ponts, chrono) et un classement global.
6. Ajouter des captures d'écran et un GIF de gameplay au README.
7. Remplacer le nom provisoire et les références à la marque.

---

## Avertissement

**Mini Motorways** est une marque de **Dinosaur Polo Club**. Ce projet est un prototype personnel inspiré du jeu, sans lien avec l'éditeur. Avant toute publication publique sur Roblox, remplace le nom affiché (`Config.GameName`), le titre de la place et l'identité visuelle par ceux de **Mini Rotorway**.

---

## Pour jouer à deux

- **Toi (ETM256)** : garde le dossier local `mini-motorways-rbx/` pour modifier le jeu, puis pousse le build et le README sur ce dépôt.
- **Ton pote** : récupère `MiniMotorwaysRBX.rbxlx` depuis la page GitHub publique, ouvre-le dans Studio et appuie sur Play. Pour jouer ensemble sur Roblox, publie la place et invite-le.
- **Pour contribuer** : clone le dépôt ou fais un fork, ouvre-le avec Rojo, modifie `src/`, puis rebuild.

Bon jeu et bons tests !
