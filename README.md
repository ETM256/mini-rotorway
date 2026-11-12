# Mini Rotorway

> **Prototype Roblox de gestion de trafic**, inspiré de *Mini Motorways*.
> Projet public, jouable et open source, pour jouer, tester et faire évoluer le jeu à deux.

![Statut](https://img.shields.io/badge/statut-prototype-orange)
![Version](https://img.shields.io/badge/version-1.5.0-blue)
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
- [Système de magasins](#système-de-magasins)
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
| Version | 1.5.0 |
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
| Dessiner une route | Clic gauche + glisser, relâcher pour valider | — | Glisser |
| Annuler le tracé en cours | `Échap` | `Échap` | — |
| Effacer une route | Clic droit + glisser (quel que soit l'outil), ou outil « Effacer » (`2`) | `2` | Outil « Effacer » |
| Poser un rond-point | Outil « Rond-point » | `3` | Bouton du HUD |
| Déplacer la caméra | Clic milieu + glisser, ou outil « Main » (`4`) | `4` | Deux doigts, ou outil « Main » |
| Changer d'outil | Colonne d'outils à droite | `1` / `2` / `3` / `4` | Colonne d'outils |
| Zoomer / dézoomer | Molette | — | Pincement |
| Ouvrir les contrôles de temps | Cliquer sur l'horloge | — | Toucher l'horloge |
| Menu pause | Bouton de pause du HUD | `P` (la touche le referme aussi) | Bouton de pause |
| Changer la vitesse | Boutons `×1` / `×2` / `×3` de l'horloge | — | Boutons de l'horloge |

Le **menu pause** (`P`) propose Reprendre, Rejouer, Paramètres (grille visible en permanence, astuces à l'écran) et Quitter vers le menu principal. Pendant qu'il est ouvert, le temps est figé et les commandes de la carte sont coupées. L'écran de fin affiche le score, le record et, quand le serveur les fournit, la durée, les statistiques et la cause de la défaite, avec les boutons Rejouer et Menu. Le choix de semaine reste bloquant.

---

## Règles du jeu

- **Objectif** : livrer un maximum de trajets. Chaque livraison rapporte **1 point**.
- **Couleurs** : une maison doit être reliée par un chemin continu au **magasin de la même couleur**. Une maison ne peut pas desservir un magasin d'une autre couleur.
- **Magasins** : un magasin apparaît avec quelques maisons de sa couleur. De nouveaux magasins et de nouvelles couleurs arrivent progressivement ; la carte se remplit au fil de la partie.
- **Demandes** : chaque magasin génère des **pastilles de demande** au-dessus de lui. Un petit magasin en stocke **6**, un grand magasin **8**. Une voiture réserve une demande, part de sa maison, la consomme à l'arrivée, puis revient.
- **Évolution** : après un délai minimal et plusieurs livraisons, un petit magasin carré peut devenir un grand magasin circulaire. Il garde sa couleur, gagne de la capacité et génère ses demandes plus vite.
- **Surcharge** : quand un magasin est plein, une alerte et un compte à rebours apparaissent. S'il reste saturé trop longtemps, il devient **critique** et draine la jauge de circulation. Une livraison le remet en état.
- **Routes** : une route coûte **1 route** par case. Une case d'eau coûte **1 pont**. Le réseau est **orthogonal** : les segments sont horizontaux ou verticaux, les virages sont arrondis et les intersections en T ou en croix sont détectées automatiquement.
- **Connexions** : une route qui touche le côté d'une maison ou d'un magasin inscrit le bâtiment dans le graphe. Le serveur recalcule les connexions et les trajets uniquement quand le réseau change.
- **Ronds-points** : ils peuvent être posés sur une route existante comme repère de carrefour et sont récupérés si la route est effacée.
- **Semaines** : une semaine dure **60 secondes**. À la fin de chaque semaine, la partie se met en pause et propose **deux améliorations**. Le joueur en choisit une, puis la semaine suivante commence.
- **Améliorations** : chaque semaine, deux propositions. Les deux donnent des routes : **+20 routes** avec un outil spécial, ou **+30 / +40 routes** sans outil. Une seule proposition contient un **pont** ou un **rond-point**, comme dans Mini Motorways.
- **Circulation** : si des voitures restent bloquées trop longtemps ou si un magasin critique n'est pas livré, la jauge de circulation baisse. À **0 %**, la partie est terminée.
- **Budget de départ** : 20 routes, 1 pont, 0 rond-point, **1 magasin et 3 maisons de sa couleur**.
- **Records** : le meilleur score de chaque carte est affiché dans le lobby et sauvegardé si les DataStores sont disponibles.

---

## Système de magasins

Le système reprend le rythme de Mini Motorways : la partie commence avec **un seul magasin** et **trois maisons** de sa couleur, puis de nouveaux magasins apparaissent progressivement. Les intervalles sont calculés en **temps simulé** : accélérer la partie accélère aussi l'apparition, sans changer le rythme global.

| Phase (temps simulé) | Intervalle entre deux magasins |
| --- | --- |
| 0–180 s | 100–120 s |
| 180–360 s | 75–100 s |
| 360–600 s | 55–75 s |
| 600–900 s | 35–55 s |
| 900–1200 s | 25–40 s |
| 1200 s et + | 15–30 s |

Avec `MaxStores = 8` et 8 couleurs uniques, les derniers paliers servent surtout si tu augmentes la limite de magasins. La difficulté de fin de partie vient aussi de l'accélération des demandes.

### Apparence et couleurs

- **Petit magasin** : carré à coins arrondis, toit plat, liseré blanc, logo central et entrée sombre côté allée. Taille visuelle **6,4 studs**.
- **Grand magasin** : disque circulaire, anneau blanc, logo central et entrée. Taille visuelle **8,4 studs**.
- Les deux utilisent la **même couleur** et le même langage graphique que les maisons : cartes plates, ombre douce, blanc cassé et palette pastel.
- Chaque magasin reçoit une **couleur unique** parmi les 8 couleurs de `Config.HouseColors`. Les maisons de cette couleur ne desservent que lui.
- La palette est centralisée : ajouter une couleur dans `Config.HouseColors` suffit pour le visuel, puis augmente `StoreConfig.Spawn.MaxStores` si tu veux plus de magasins uniques.

### Placement semi-aléatoire

Le serveur choisit une zone pondérée, puis vérifie que la case est :

- dans la carte et hors de l'eau ;
- libre de route, de bâtiment et de rond-point ;
- assez éloignée des autres magasins (`MinStoreDistance`) et bâtiments (`MinBuildingDistance`) ;
- entourée d'assez de cases constructibles pour tracer des routes (`MinBuildableNeighbors`).

En cas d'échec, il réessaie un nombre borné de fois, puis parcourt la grille pour trouver un emplacement de repli. Aucune boucle infinie.

### Demandes, réservations et surcharge

- Chaque demande a un **identifiant serveur unique** (`magasin-demande`). Une voiture réserve un identifiant précis ; deux voitures ne peuvent jamais servir la même demande.
- Le client reçoit la liste des identifiants et affiche un **pin coloré individuel** par demande. À l'arrivée, le pin exact est retiré avec une petite animation.
- Capacités : **6** pour un petit magasin, **8** pour un grand.
- Génération : environ **11,5 s** par demande pour un petit magasin, **7,5 s** pour un grand, avec une accélération progressive jusqu'à un facteur **0,70** après 10 minutes.
- À capacité, une alerte et un compte à rebours de **12 s** apparaissent. À zéro, le magasin devient critique et draine la jauge de circulation. Une livraison annule l'alerte et remet le compteur à zéro.

### Évolution

- Un petit magasin peut évoluer après **95 s**, au moins **3 livraisons** et avec **42 %** de chance à chaque vérification (toutes les ~14 s).
- Il conserve son identifiant, sa position et sa couleur. L'ancien modèle s'efface pendant que le nouveau cercle grandit : aucune duplication dans les listes de bâtiments.
- Maximum **6 grands magasins** par défaut, pour éviter que toute la carte devienne circulaire trop vite.
- Le grand magasin gagne **2 demandes de capacité** et génère plus vite.

### Fichiers du système

| Fichier | Rôle |
| --- | --- |
| `src/ReplicatedStorage/MiniMotorways/StoreConfig.luau` | Tous les réglages : palette, paliers, zones, capacités, demandes, surcharge, évolution, maisons, visuels. |
| `src/ServerScriptService/MiniMotorways/StoreSystem.luau` | Apparition, placement, couleurs, demandes, réservations, surcharge, évolution et synchronisation. |
| `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/StoreVisualController.luau` | Pins `BillboardGui`, animations, couleurs et compte à rebours côté client. |
| `Session.luau` | Intégration aux bâtiments, maisons, voitures, pathfinding, satisfaction et boucle de jeu. |
| `Remotes.luau` | Remote `StoreState` serveur → client. |

### Réglages principaux

| Paramètre | Valeur par défaut | Effet |
| --- | --- | --- |
| `StoreConfig.Spawn.MaxStores` | 8 | Nombre maximal de magasins. |
| `StoreConfig.Spawn.Tiers` | 100–120 → 15–30 s | Rythme d'apparition par phase. |
| `StoreConfig.Spawn.MinStoreDistance` | 4,4 cases | Distance minimale entre magasins. |
| `StoreConfig.Demand.SmallCapacity` | 6 | Demandes en attente d'un petit magasin. |
| `StoreConfig.Demand.LargeCapacity` | 8 | Demandes en attente d'un grand magasin. |
| `StoreConfig.Demand.SmallInterval` | 11,5 s | Génération d'un petit magasin. |
| `StoreConfig.Demand.LargeInterval` | 7,5 s | Génération d'un grand magasin. |
| `StoreConfig.Demand.OverloadGrace` | 12 s | Délai avant qu'un magasin plein devienne critique. |
| `StoreConfig.Evolution.MinAge` | 95 s | Âge minimal avant évolution. |
| `StoreConfig.Evolution.Chance` | 0,42 | Probabilité par vérification. |
| `StoreConfig.Houses.StartHouses` | 3 | Maisons créées avec le premier magasin. |
| `StoreConfig.Houses.HousesPerStore` | 2 | Maisons ajoutées avec chaque nouveau magasin. |

La checklist de test manuelle détaillée est dans [`docs/PLAN.md`](./docs/PLAN.md).

---

## Système de routes

Le système de routes prolonge la grille existante sans la remplacer :

- **Tracé orthogonal** : un geste en biais est converti en chemin horizontal puis vertical (ou l'inverse). Les diagonales restent disponibles avec `RoadConfig.AllowDiagonals = true` pour les anciens réseaux.
- **Aperçu local** : l'aperçu reprend la forme réelle de la route (même largeur, coins arrondis, bouts arrondis, calculés par `RoadGeometry`). Menthe si la case est constructible, corail si elle est refusée (bâtiment, route existante, eau sans pont, budget épuisé). Rien n'est envoyé au serveur avant le relâchement.
- **Rendu unique** : `RoadGeometry` (module pur, testé) décrit la surface de chaque case ; `RoadRenderer` en fait des parts (liseré, surface, pont). Largeur identique partout, virages et bouts arrondis, T et croix en une seule surface, raccords qui s'arrêtent au bord des bâtiments. Seules la case modifiée et ses quatre voisines sont redessinées. Détail : `docs/road-rendering.md`.
- **Validation autoritaire** : le serveur revérifie chaque case, consomme le budget et les ponts, puis renvoie l'état réel du réseau (`RoadState`) au client.
- **Annulation** : `Échap` vide l'aperçu et annule tout le tracé en cours, sans consommer de route.
- **Suppression** : clic droit + glisser ou outil « Effacer ». Les routes sont remboursées, les connexions et les trajets sont recalculés.
- **Intersections** : le nombre de voisins d'une case détermine une extrémité, un virage, un T ou une croix. Une voiture réserve une intersection pour éviter les collisions au centre.
- **Circulation** : A* sur le graphe routier, recalcul ciblé après modification, distance de sécurité, freinage progressif, orientation lissée et ralentissement dans les virages.
- **Compteur** : le HUD affiche le budget restant, les ponts, les ronds-points et le nombre de routes posées.

### Fichiers du système de routes

| Fichier | Rôle |
| --- | --- |
| `src/ReplicatedStorage/MiniMotorways/RoadConfig.luau` | Paramètres centralisés : diagonales, largeurs, aperçu, trafic, infrastructures. |
| `src/ReplicatedStorage/MiniMotorways/RoadNetwork.luau` | Voisinage orthogonal, intersections et résolution d'un geste en chemin H/V. |
| `src/ReplicatedStorage/MiniMotorways/Pathfinding.luau` | A* orthogonal par défaut, 8 directions en option historique. |
| `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/RoadPreview.luau` | Aperçu local des cases valides / invalides. |
| `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/InputController.luau` | Construction, annulation, effacement, caméra et raycast. |
| `src/ReplicatedStorage/MiniMotorways/RoadGeometry.luau` | Géométrie pure d'une case de route (pièces, raccords, classification). |
| `src/ServerScriptService/MiniMotorways/RoadRenderer.luau`, `SessionRoadVisuals.luau` | Rendu unique des routes et des ronds-points, mise à jour incrémentale. |
| `src/ServerScriptService/MiniMotorways/SessionRoads.luau` | Validation, budget, remboursements, ponts, ronds-points, effacement. |

### Réglages principaux des routes

| Paramètre | Valeur par défaut | Effet |
| --- | --- | --- |
| `RoadConfig.AllowDiagonals` | `false` | Réseau orthogonal ; passer à `true` pour les diagonales historiques. |
| `RoadConfig.BuildingConnection` | `"orthogonal"` | Une route doit toucher un côté du bâtiment. |
| `Config.Dimensions.Road.Width` | 0,54 case | Largeur unique de toutes les routes. |
| `RoadConfig.Layers` | hauteurs / épaisseurs | Empilement liseré, surface, pont, rond-point. |
| `RoadConfig.Visual.PreviewValidColor` | menthe | Couleur des cases constructibles. |
| `RoadConfig.Visual.PreviewInvalidColor` | corail | Couleur des cases refusées. |
| `RoadConfig.Input.MaxCellsPerRequest` | 512 | Taille maximale d'un lot de construction. |
| `Config.Traffic.CarSpeed` | 9 studs/s | Vitesse de base des voitures. |
| `RoadConfig.Traffic.TurnSpeedFactor` | 0,62 | Ralentissement visuel dans les virages. |
| `RoadConfig.Traffic.IntersectionReservation` | `true` | Une voiture à la fois dans une intersection. |
| `RoadConfig.Infrastructure.Highways.Enabled` | `false` | Emplacement réservé aux futures autoroutes. |

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
- [x] Tracé orthogonal à la souris et au doigt, virages arrondis, intersections T et croix
- [x] Aperçu local des cases valides / invalides et annulation par `Échap`
- [x] Routes anthracite de largeur uniforme, virages et bouts arrondis, intersections homogènes, raccords aux bâtiments (un seul renderer)
- [x] Ponts pour traverser l'eau
- [x] Ronds-points posables sur le réseau
- [x] Serveur autoritaire : validation des routes, budget et état de la partie
- [x] Pathfinding A* orthogonal sur la grille 18 × 18, recalcul ciblé après modification
- [x] Voitures qui partent, livrent, reviennent et recalculent leur chemin
- [x] Magasins progressifs : 1 magasin + 3 maisons au départ, puis de nouvelles couleurs et de nouveaux magasins selon le temps simulé
- [x] Petit magasin carré (capacité 6) et grand magasin circulaire (capacité 8), avec évolution animée et conservation de la couleur
- [x] Demandes individuelles avec identifiants serveur, pins colorés animés, réservations anti-double-service et suppression à l'arrivée
- [x] Placement semi-aléatoire validé : zones pondérées, distances minimales, routes/eau/bâtiments évités
- [x] Surcharge des magasins : alerte, compte à rebours, état critique et drainage de la jauge de circulation
- [x] Choix hebdomadaire fidèle au jeu : routes + outil spécial, ou lot de routes
- [x] Jauge de circulation et game over
- [x] Records par carte avec DataStore et fallback en mémoire
- [x] Interface claire : barre supérieure, colonne d'outils, compteurs homogènes, menu pause, paramètres, écran de fin ; adaptée de 1920×1080 aux téléphones, panneaux qui n'envoient plus leurs clics au monde
- [x] Caméra : vue aérienne, zoom fluide avec limites, déplacement au clic milieu ou à deux doigts, marges d'interface
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
| 09/11/2026 | Système de magasins progressif : couleurs uniques, demandes, pins, surcharge et évolution petit → grand |

### 1. Fondations techniques

- Mise en place de la structure **Rojo** (`default.project.json`) et du build `MiniMotorwaysRBX.rbxlx`.
- Création de `Config.luau` : grille 18 × 18, cases de 4 studs, budgets, semaines, trafic, récompenses et palette.
- Création de `Maps.luau` avec **6 cartes** : Dubaï, Los Angeles, Pékin, Tokyo, Dar es Salaam et Londres.
- Création de `Grid.luau` : conversions case ↔ position 3D et voisinage orthogonal + diagonal.
- Création de `Pathfinding.luau` : **A\*** sur les routes en 8 directions.
- Création de `Remotes.luau` : RemoteEvents partagés entre serveur et client.

### 2. Serveur de jeu

- `Bootstrap.server.luau` : remotes, profils, boucle de jeu et gestion des sessions.
- `Session.luau` : routes, ponts, ronds-points, bâtiments, maisons, magasins, voitures, semaines, score et jauge de circulation.
- `StoreSystem.luau` : apparition, demandes, réservations, surcharge, évolution et synchronisation des magasins.
- `WorldBuilder.luau` : sol crème, eau menthe, parcs, grille, étiquettes et dossiers 3D.
- `Profile.luau` : meilleurs scores via DataStore `MiniMotorwaysV1`, avec fallback en mémoire.
- **Serveur autoritaire** : il valide les routes, le budget, les ponts, les ronds-points et les demandes.
- Une **ville isolée par joueur** dans `Workspace.MMWorlds`.
- Les voitures partent de la maison, livrent la destination, reviennent, et recalculent leur chemin si une route est supprimée.
- Choix hebdomadaire : pause serveur, deux améliorations proposées, validation puis reprise.
- Budget de départ : **20 routes, 1 pont, 0 rond-point, 1 magasin et 3 maisons de sa couleur**.

### 3. Client, caméra et interface

- `Main.client.luau` : câblage du lobby, du HUD, de la caméra et des entrées.
- `CameraController.luau` : caméra de dessus quasi orthographique (FOV 20), zoom à la molette et déplacement au clic milieu.
- `InputController.luau` : dessin à la souris et au doigt, gomme et outil rond-point. En construction, le gros carré de visée est masqué : la route apparaît directement sous le curseur.
- `StoreVisualController.luau` : pins de demande, animations et alertes de surcharge côté client.
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
- Bâtiments façon icônes : cartes plates à coins arrondis, liseré blanc, ombre douce, allée, toit à deux teintes et cheminées. Magasins à toit plat ou cercle, avec pins de demande côté client.
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
- Le build de référence avant le ruban était `5C571B3D...` ; le build de l'époque était `7DB81580...`.

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

- Version **1.5.0**, prototype jouable.
- **22 fichiers Luau**, 0 erreur de syntaxe.
- Build actuel : `1C84FB41C17AAA25E19A148946319FA24A754A34E6DE1F4513003FE5CCDD49BD`.
- 6 cartes, grille 18 × 18, routes noires orthogonales, virages et intersections, extrémités ovales, ponts, ronds-points, semaines, magasins et records.
- Choix hebdomadaires : **+1 pont/rond-point +20 routes**, ou **+30 / +40 routes**.
- Magasins : 8 couleurs uniques, apparition progressive, demandes 6/8, évolution petit → grand et surcharge.
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
- Build de l'époque reconstruit et vérifié : `7DB81580BA5D32007C86D20D670A5055C7AD19490CF9082626512384C35C6F8A`.

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

### 12. Système de magasins et de demandes

- **09/11/2026** : ajout du système complet de destinations inspiré de Mini Motorways.
- `StoreConfig.luau` centralise les paliers d'apparition, les zones pondérées, les capacités 6/8, les intervalles de demandes, la surcharge, l'évolution, les maisons et les réglages visuels.
- `StoreSystem.luau` gère le serveur : apparition, placement validé, couleurs uniques, demandes avec identifiants, réservations, surcharge, évolution et synchronisation `StoreState`.
- `StoreVisualController.luau` affiche les pins côté client avec `BillboardGui`, anime leur apparition/disparition et le compte à rebours de surcharge.
- `Session.luau` réutilise ses bâtiments, maisons, voitures et son pathfinding : un magasin est un bâtiment `kind = "store"`, les maisons gardent leur `colorIndex` et les voitures réservent une demande avant de partir.
- Le pin blanc historique des destinations a été remplacé par les pins de demande côté client, pour éviter deux représentations concurrentes.
- Les 8 couleurs de `Config.HouseColors` sont utilisées pour garantir une couleur unique par magasin ; `MaxStores = 8` par défaut.
- La carte commence avec un magasin et trois maisons, puis chaque nouveau magasin ajoute environ deux maisons.
- Le rythme dépend uniquement du temps simulé et non du nombre de bâtiments, pour éviter les explosions de difficulté.
- Test runtime Studio encore à faire : voir la checklist dédiée dans `docs/PLAN.md`.

---

## Architecture

```text
mini-rotorway/
├─ MiniMotorwaysRBX.rbxlx        ← place prête à ouvrir dans Studio
├─ default.project.json          ← mapping Rojo
├─ README.md
├─ docs/
│  ├─ PLAN.md                    ← checklist de développement et de test
│  └─ road-rendering.md          ← rendu des routes (RoadGeometry + RoadRenderer)
├─ tools/
│  ├─ build.ps1                  ← télécharge Rojo si besoin et construit le .rbxlx
│  ├─ build-rbxlx.js             ← reconstruit le .rbxlx depuis src/ sans Rojo
│  ├─ fix-source-tags.js         ← convertit les sources pour Studio
│  ├─ gen-roblox-api.js          ← génère les données d'API Roblox des tests
│  └─ check-roblox-api.js        ← valide Enum.X.Y et Instance.new("X") dans src/
├─ tests/                        ← harnais Luau headless + tests (voir tests/README.md)
└─ src/
   ├─ ReplicatedStorage/MiniMotorways/
   │  ├─ Config.luau             ← réglages (grille, budget, semaines, couleurs)
   │  ├─ StoreConfig.luau        ← tous les réglages des magasins et demandes
   │  ├─ RoadConfig.luau         ← réglages des routes : rendu, couches, aperçu, trafic
   │  ├─ Maps.luau               ← les 6 cartes + géographie/eau + aperçus
   │  ├─ Grid.luau               ← conversions case ↔ position 3D
   │  ├─ RoadNetwork.luau        ← voisinage, intersections, chemins H/V
   │  ├─ RoadGeometry.luau       ← surface d'une case de route (pur, testé)
   │  ├─ Pathfinding.luau        ← A* orthogonal (8 directions en option)
   │  └─ Remotes.luau            ← RemoteEvents partagés
   ├─ ServerScriptService/MiniMotorways/
   │  ├─ Bootstrap.server.luau   ← point d'entrée serveur
   │  ├─ Session.luau            ← simulation d'une ville (état, horloge, score)
   │  ├─ SessionBuildings.luau   ← placement et modèles des bâtiments, connexions
   │  ├─ SessionRoads.luau       ← validation et budget des routes, ronds-points
   │  ├─ SessionRoadVisuals.luau ← mise à jour incrémentale du rendu des routes
   │  ├─ RoadRenderer.luau       ← pièces de RoadGeometry → parts Roblox
   │  ├─ SessionTraffic.luau     ← voitures, trajets, réservations d'intersection
   │  ├─ SessionProgress.luau    ← satisfaction, choix hebdomadaires, récompenses
   │  ├─ SessionUtil.luau        ← helpers partagés (parts, cartes arrondies, animations)
   │  ├─ StoreSystem.luau        ← magasins, demandes, surcharge, évolution
   │  ├─ WorldBuilder.luau       ← sol, eau, grille, dossiers 3D
   │  └─ Profile.luau            ← DataStore / records
   └─ StarterPlayer/StarterPlayerScripts/MiniMotorways/
      ├─ Main.client.luau        ← câblage client
      ├─ CameraController.luau   ← vue aérienne, zoom fluide, limites, marges d'interface
      ├─ RoadPreview.luau        ← aperçu à la forme de la route
      ├─ InputController.luau    ← dessin, effacement, tactile, grille
      ├─ StoreVisualController.luau ← pins et alertes des magasins
      └─ UI/
         ├─ Theme.luau           ← jetons de style, survol, ombres, aides
         ├─ MapPreview.luau      ← aperçus circulaires des cartes
         ├─ Lobby.luau           ← menu, cartes, options, records
         └─ HUD*.luau            ← HUD : barre supérieure, outils, compteurs, menus, responsive
```

### Fonctionnement

- Le **serveur est autoritaire** : il valide les routes, gère le budget, les ponts, les ronds-points, les bâtiments, les voitures, les semaines, les choix d'amélioration, la jauge et les scores.
- Le **client ne fait que demander** : il envoie des lots de cases à dessiner, à effacer ou un rond-point à poser, et affiche l'état renvoyé par le serveur.
- Chaque joueur possède sa propre ville, placée très loin des autres dans `Workspace.MMWorlds`.
- Le pathfinding est un **A\*** sur la grille 18 × 18 (cases de 4 studs). Par défaut il est **orthogonal** (heuristique de Manhattan) ; `RoadConfig.AllowDiagonals` réactive les 8 directions historiques.
- Les **routes** sont rendues par un seul renderer : `RoadGeometry` (pur) décrit les pièces de chaque case, `RoadRenderer` les instancie. C'est purement visuel : la simulation, les voitures et le budget restent sur la grille.
- La construction est **locale jusqu'au relâchement** : `InputController` affiche les cases valides / invalides, puis envoie le lot au serveur. `Échap` annule sans consommer de ressources.
- Le choix hebdomadaire est un `RemoteEvent` serveur → client ; le serveur reste en pause tant qu'aucune des deux options n'a été validée.
- Les voitures partent de la maison, suivent le chemin, livrent la destination, puis reviennent. Si une route est supprimée, leur chemin est recalculé.
- `StoreSystem` est une extension de `Session`, pas un second monde : il crée les magasins comme bâtiments, utilise les maisons/voitures existantes et expose `StoreState` pour l'affichage.
- Les demandes sont des identifiants serveur réservés par les voitures. Le client ne décide jamais qu'une demande est servie : il affiche la liste reçue et retire le pin exact correspondant.
- L'évolution remplace uniquement le modèle visuel du magasin (même identifiant, même couleur, mêmes listes) et met à jour sa capacité dans `StoreSystem`.

---

## Développement

### Rebuild rapide (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File tools/build.ps1
```

Le script télécharge Rojo 7.7.1 dans `%TEMP%\mini-motorways-rbx-tools` s'il n'est pas déjà présent, construit `MiniMotorwaysRBX.rbxlx`, puis convertit les balises `Source` pour Roblox Studio. Node.js est utilisé pour cette dernière étape.

### Rebuild sans Rojo (macOS / Linux / Windows avec Node)

```bash
node tools/build-rbxlx.js
```

Régénère `MiniMotorwaysRBX.rbxlx` depuis `src/` (mêmes balises `ProtectedString` que le build Rojo) en conservant l'éclairage et les services statiques du fichier existant.

### Tests

```bash
bash tests/run.sh          # n'affiche que les échecs et la ligne finale « TESTS: N passed, ... »
node tools/check-roblox-api.js
```

Le harnais exécute le vrai code de `src/` dans le CLI `luau` (`brew install luau`) avec un Roblox simulé strict : une propriété, une méthode ou une énumération invalide fait échouer le test. Voir `tests/README.md`. Les tests ne remplacent pas un essai dans Studio : ils ne voient ni le rendu, ni la mise en page réelle de l'interface, ni les entrées réelles.

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
- `Config.Game` : durée d'une semaine, délai entre deux trajets d'une maison, score et satisfaction.
- `Config.Traffic` : vitesse des voitures, patience, régénération.
- `Config.Colors` / `Config.HouseColors` : palette de l'interface, des maisons et des magasins.

Les routes ont leur propre fichier, `src/ReplicatedStorage/MiniMotorways/RoadConfig.luau` :

- `AllowDiagonals` : réseau orthogonal (`false`) ou diagonales historiques (`true`).
- `BuildingConnection` : `"orthogonal"` ou `"all"`.
- `Visual` : largeurs, rayons, hauteur et couleurs de l'aperçu.
- `Input.MaxCellsPerRequest` : taille maximale d'un lot de construction.
- `Traffic` : ralentissement dans les virages, lissage de direction, freinage, réservations.
- `Infrastructure` : ponts et emplacement réservé aux futures autoroutes.

Les magasins ont leur propre fichier, `src/ReplicatedStorage/MiniMotorways/StoreConfig.luau` :

- `Spawn.Tiers` : intervalles d'apparition par phase de temps simulé.
- `Spawn.Zones` : zones pondérées de placement.
- `Spawn.MinStoreDistance` / `MinBuildingDistance` : distances minimales.
- `Demand.SmallCapacity` / `LargeCapacity` : capacités 6 / 8.
- `Demand.SmallInterval` / `LargeInterval` : vitesse de génération.
- `Demand.OverloadGrace` / `OverloadDrainPerSecond` : surcharge et critique.
- `Evolution.MinAge` / `Chance` / `MaxLargeStores` : évolution.
- `Houses.StartHouses` / `HousesPerStore` / `MaxHouses` : maisons.
- `Visual` : tailles, hauteurs de pins et durées d'animation.

Les cartes sont dans `Maps.luau` : nom, description, couleurs, fonction `isWater` et petit tracé `previewRoads` pour l'aperçu du menu.

Les routes se règlent dans `Config.Dimensions.Road`, `RoadConfig.Visual` (`CornerRadius`) et `RoadConfig.Layers` (hauteurs). Les couleurs restent celles du jeu : `Config.Colors.Road`, `RoadEdge`, `Bridge` et `BridgeEdge`. Le détail du rendu est dans `docs/road-rendering.md`.

---

## État du prototype

- **Version** : 1.5.0
- **Build actuel** : `1C84FB41C17AAA25E19A148946319FA24A754A34E6DE1F4513003FE5CCDD49BD`
- **Sources** : 22 fichiers Luau, 0 erreur de syntaxe
- **Test runtime** : à refaire dans Roblox Studio après chaque grosse modification, notamment pour les routes, les intersections et les embouteillages

### Limites connues

- Le coin intérieur des virages reste vif : seul le coin extérieur est arrondi (la surface est une union de rectangles et de disques).
- Les voitures utilisent un évitement simple et une réservation d'intersection : les embouteillages en boucle fermée restent possibles. C'est volontaire pour le prototype, mais des feux/priorités avancés seraient la prochaine amélioration.
- Menu pause : Échap ouvre aussi le menu de Roblox (non désactivable par script) ; à vérifier dans Studio. Les boutons de temps (32×28 px) sont sous la taille tactile conseillée.
- Les records sont locaux au serveur/DataStore ; il n'y a pas encore de classement global.
- Le nom et l'identité visuelle doivent être remplacés avant une publication publique.
- Les tests automatiques (`bash tests/run.sh`) utilisent un Roblox simulé : ils ne remplacent pas un essai dans Studio.
- Les magasins sont limités à **8 couleurs uniques** par défaut. Au-delà de 8, `StoreSystem` réutilise une couleur et les maisons choisissent le magasin de même couleur le plus proche.
- Les pins sont affichés côté client à partir de `StoreState`. Le serveur renvoie un snapshot toutes les **1,5 s** même sans changement, ce qui sert de resynchronisation si un message est manqué.
- Le rythme et l'équilibrage des magasins (intervalles, surcharge, évolution) sont des valeurs de départ à valider en jouant.

---

## Roadmap

1. Tester le parcours complet : lobby → carte → routes → livraisons → semaine → game over → rejouer.
2. Valider en jeu le rythme des magasins, les capacités 6/8, l'évolution et la surcharge, puis ajuster `StoreConfig`.
3. Ajouter des sons discrets (clic, livraison, fin de semaine, alerte de magasin).
4. Ajouter un tutoriel intégré au premier lancement.
5. Améliorer la circulation : priorités, feux, évitement plus propre.
6. Ajouter des modes (sans ponts, chrono) et un classement global.
7. Ajouter des captures d'écran et un GIF de gameplay au README.
8. Remplacer le nom provisoire et les références à la marque.

---

## Avertissement

**Mini Motorways** est une marque de **Dinosaur Polo Club**. Ce projet est un prototype personnel inspiré du jeu, sans lien avec l'éditeur. Avant toute publication publique sur Roblox, remplace le nom affiché (`Config.GameName`), le titre de la place et l'identité visuelle par ceux de **Mini Rotorway**.

---

## Pour jouer à deux

- **Toi (ETM256)** : garde le dossier local `mini-motorways-rbx/` pour modifier le jeu, puis pousse le build et le README sur ce dépôt.
- **Ton pote** : récupère `MiniMotorwaysRBX.rbxlx` depuis la page GitHub publique, ouvre-le dans Studio et appuie sur Play. Pour jouer ensemble sur Roblox, publie la place et invite-le.
- **Pour contribuer** : clone le dépôt ou fais un fork, ouvre-le avec Rojo, modifie `src/`, puis rebuild.

Bon jeu et bons tests !
