# Plan de développement — Mini Motorways (prototype Roblox)

## 1. Fondations

- [x] Structure Rojo (`default.project.json`)
- [x] `Config.luau` : grille, budgets, semaines, trafic, palette claire, récompenses
- [x] `Maps.luau` : Dubaï, Los Angeles, Pékin, Tokyo, Dar es Salaam, Londres
- [x] `Grid.luau` : conversions case ↔ monde, voisins orthogonaux et diagonaux
- [x] `RoadConfig.luau` : réglages centralisés des routes, de l'aperçu et du trafic
- [x] `RoadNetwork.luau` : voisinage, intersections et résolution des gestes en chemins H/V
- [x] `Pathfinding.luau` : A\* orthogonal par défaut, 8 directions en option
- [x] `Remotes.luau` : RemoteEvents partagés, dont `RoadState` et `EraseRoads`

## 2. Serveur

- [x] `Bootstrap.server.luau` : remotes, profils, boucle de jeu
- [x] `Session.luau` : routes, ponts, ronds-points, bâtiments, voitures, semaines, score
- [x] `WorldBuilder.luau` : sol crème, eau menthe, parcs, grille, étiquettes verticales
- [x] Choix hebdomadaire serveur : pause, deux options, validation, reprise
- [x] `Profile.luau` : meilleurs scores + fallback mémoire
- [x] Une ville isolée par joueur
- [x] Validation serveur des routes et du budget
- [x] Livraisons, retour des voitures, recalcul de chemin
- [x] `StoreSystem.luau` : magasins progressifs, placement validé, couleurs uniques, demandes avec identifiants, surcharge et évolution
- [x] Jauge de circulation et game over

## 3. Client

- [x] `Main.client.luau` : câblage lobby/HUD/caméra/input
- [x] `CameraController.luau` : caméra responsive, zoom molette, déplacement clic milieu
- [x] `InputController.luau` : dessin souris/tactile, aperçu local, annulation `Échap`, gomme et outil caméra
- [x] `RoadPreview.luau` : cases valides en menthe, cases refusées en corail
- [x] `StoreVisualController.luau` : pins `BillboardGui`, animations d'apparition/disparition, couleurs et compte à rebours de surcharge
- [x] Tracé orthogonal : un geste en biais est résolu en chemin horizontal puis
  vertical (ou l'inverse), avec hystérésis pour éviter les zigzags. La
  construction est validée au relâchement ; `Échap` annule le tracé local sans
  consommer de route.
- [x] `UI/Theme.luau` : palette claire et composants
- [x] `UI/MapPreview.luau` : aperçus circulaires clairs, eau et parcs
- [x] `UI/Lobby.luau` : menu clair, 6 cartes, garage, stats, records
- [x] `UI/HUD.luau` : score, jour, horloge, vitesse, outils, compteurs, pause, fin
- [x] Modale de choix hebdomadaire avec deux cartes d'amélioration
- [x] Adaptation portrait/paysage
- [x] Textes et panneaux redimensionnés (`TextScaled`, `UISizeConstraint`, `UIScale`)

## 4. Build et validation

- [x] Build Rojo (`MiniMotorwaysRBX.rbxlx`)
- [x] Conversion des `Source` en `ProtectedString`
- [x] Vérification des classes : 1 `Script`, 1 `LocalScript`, 20 `ModuleScript`
- [x] Parse Luau de tous les 22 fichiers
- [x] Test logique autonome de `RoadNetwork` et `Pathfinding` : 136 vérifications, 0 échec
- [ ] Test manuel dans Studio (à faire par l'utilisateur)

## 5. Test manuel recommandé

1. Ouvrir `MiniMotorwaysRBX.rbxlx` dans Studio.
2. Vérifier le lobby clair, le titre, les boutons, le décor routier et les 6 cartes.
3. Lancer Los Angeles.
4. Vérifier la vue de dessus, le papier crème, l'eau menthe avec son liseré
   de côte blanc, les parcs jaune-vert, les routes graphite et les bâtiments
   colorés.
5. Dessiner une route entre une maison et un bâtiment de la même couleur :
   vérifier le trait blanc de chaque côté, les bords droits, les virages
   arrondis et l'extrémité **ovale** de la route. Pendant le glissement,
   l'aperçu doit être menthe sur les cases libres et corail sur les cases
   refusées. Relâcher pour valider.
6. Glisser en biais : la route doit être un chemin **horizontal puis vertical**
   (ou l'inverse), sans diagonale. Vérifier qu'une voiture l'emprunte et que
   les jonctions restent propres.
7. Vérifier qu'une voiture part, livre, revient, et que le score monte.
8. Utiliser l'outil gomme et vérifier le recalcul des voitures.
9. Attendre une fin de semaine : la partie se met en pause et deux
   améliorations sont proposées. Vérifier le modèle réel : une proposition
   contient un pont/rond-point + 20 routes, l'autre un lot de 30/40 routes.
10. Vérifier que le compteur correspondant augmente et que la semaine reprend.
11. Choisir un rond-point, le poser sur une route, puis effacer la route pour
    vérifier le remboursement du rond-point.
12. Tester la vitesse x1 / x2 / x3, la pause (`P`) et la reprise. Vérifier
    que les contrôles de temps n'apparaissent qu'après un clic sur l'horloge,
    qu'aucun écran de pause ne s'affiche et que les routes restent modifiables
    pendant la pause. Vérifier aussi que les aiguilles tournent autour du
    centre de l'horloge et que l'aiguille des heures avance progressivement.
13. Tester la molette (zoom), le clic milieu et l'outil **Caméra** (`4`).
14. Tracer une route puis appuyer sur `Échap` avant de relâcher : aucune route
    ne doit être construite et le budget doit rester intact.
15. Laisser la jauge tomber à 0 et vérifier l'écran de fin + record.
16. Rejouer, changer de carte, revenir au menu.
17. Tester en portrait (mobile) et en paysage.

### 5.1 Test manuel des magasins

1. Lancer une partie : **un seul magasin** doit apparaître, avec **trois maisons** de sa couleur.
2. Vérifier le petit magasin : carré à coins arrondis, toit plat, liseré blanc, logo et entrée sombre côté allée.
3. Attendre 5 à 9 secondes : une première **pastille de demande** colorée apparaît au-dessus du magasin.
4. Relier une maison de la même couleur au magasin : la voiture part, le pin disparaît à l'arrivée et le score augmente.
5. Vérifier qu'une deuxième voiture ne peut pas consommer le même pin pendant qu'il est réservé.
6. Laisser les demandes s'accumuler : le petit magasin doit plafonner à **6 pins**.
7. À capacité, vérifier l'**alerte** et le compte à rebours de 12 secondes au-dessus du magasin.
8. Laisser le compte à rebours atteindre zéro : le magasin devient critique et la jauge de circulation baisse.
9. Livrer une demande : l'alerte doit disparaître et le compteur repartir à 12 s si le magasin se remplit à nouveau.
10. Attendre l'évolution d'un petit magasin (âge minimal 95 s, au moins 3 livraisons) : transition fluide carré → cercle, même couleur, même position.
11. Vérifier que le grand magasin accepte **8 pins** et génère plus vite.
12. Attendre le magasin suivant (100–120 s au début) : nouvelle couleur unique, environ deux nouvelles maisons.
13. Vérifier qu'aucun magasin n'apparaît sur une route, dans l'eau, sur un bâtiment, collé à un autre magasin ou hors carte.
14. Passer en vitesse ×3 : les magasins et les demandes doivent progresser plus vite en temps réel, sans changer le rythme en temps simulé.
15. Mettre en pause et attendre un choix de semaine : le rythme des magasins doit être figé.
16. Rejouer : les anciens pins doivent disparaître, une nouvelle partie doit repartir avec un seul magasin.
17. Laisser tourner jusqu'à 8 magasins / 16 maisons et vérifier que le jeu reste fluide.

### 5.2 Test manuel des routes

1. Tracer un segment droit : une seule case par clic, budget −1, compteur « POSÉES » +1.
2. Tracer un virage : la route doit tourner à 90° avec un raccord arrondi, sans diagonale.
3. Tracer un T : la branche doit se raccorder automatiquement et le carrefour doit être franchissable.
4. Tracer une croix : quatre branches, aucun trou au centre, voitures des deux axes.
5. Relier une maison et un magasin de même couleur : la connexion doit se faire dès que la route touche un côté.
6. Construire deux réseaux séparés puis les relier : les voitures doivent recalculer leur trajet.
7. Tenter de traverser un bâtiment : la case doit être corail et le serveur doit refuser.
8. Tenter de construire sur l'eau sans pont : case corail, aucune ressource consommée.
9. Épuiser le budget : les cases suivantes doivent être corail et refusées.
10. Effacer une route au clic droit et en glisser plusieurs : remboursement, compteur et trajets mis à jour.
11. Effacer une route au milieu d'un axe : les voitures déjà engagées doivent recalculer ou s'arrêter proprement.
12. Créer une intersection très fréquentée : vérifier qu'une seule voiture s'engage à la fois et qu'aucune ne se traverse.
13. Créer un embouteillage : les voitures doivent ralentir, s'arrêter à distance et redémarrer progressivement.
14. Tracer une route de 30+ cases : l'aperçu doit rester fluide et le ruban ne doit pas clignoter.
15. Vérifier les branches multiples : chaque extrémité doit avoir un capuchon et aucun segment ne doit flotter.
16. `Échap` pendant un tracé : aucune route, aucun budget consommé.
17. Rejouer : réseau, aperçu, réservations et compteurs doivent repartir à zéro.

## 6. Correctifs UI récents

- [x] `Enum.ScrollDirection` remplacé par `Enum.ScrollingDirection` : l'ancienne
  valeur n'existe pas et interrompait `Lobby.new` pendant `buildMapPage`, ce qui
  laissait le menu visible mais sans `lobby` fonctionnel.
- [x] Boutons du lobby, cartes et outils du HUD : `Active = true`,
  `Selectable = true` et fallback `MouseButton1Click` avec anti-double-clic.
- [x] Route décorative du menu reconstruite uniquement avec des segments
  horizontaux et verticaux (aucune rotation).
- [x] Aperçus des cartes lissés : l'eau n'est plus dessinée avec une grille
  de gros pixels, mais avec des formes arrondies (côtes, lacs, rivières).
- [x] Constructeurs `Vector3(...)` corrigés en `Vector3.new(...)` côté serveur,
  caméra et grille : l'erreur `attempt to call a table value` empêchait le
  lancement d'une partie.
- [x] Voitures animées sur la route décorative du menu : elles suivent le
  trajet en T, changent d'orientation au carrefour et disparaissent sous la
  carte puis sous le petit bâtiment.
- [x] Horloge corrigée : les aiguilles tournent autour d'un pivot au centre
  (la rotation Roblox part du centre du GuiObject), l'aiguille des heures
  avance progressivement avec la semaine, et l'horloge reste dans le panneau
  en portrait.
- [x] Contrôles de temps masqués par défaut : un clic sur l'horloge affiche
  ou cache pause, lecture, avance rapide et le libellé de vitesse.
- [x] Diagonales corrigées : le client ne fabrique plus un escalier de cases,
  le pathfinding utilise les 8 voisins et les voitures conservent leur vitesse
  réelle sur les segments diagonaux plus longs. Les routes voisines sont
  rafraîchies dans les 8 directions pour éviter les raccords manquants.

## 7. Refonte visuelle claire et française

- [x] Palette de l'aperçu de Los Angeles : fond pêche `#FFDD94`, sol crème
  `#FFF8DC`, eau menthe `#A5DAC6`, eau profonde `#7FB7A5`, parcs
  `#EFEC8C`, liseré de côte `#FFFFF7`, anneau `#88B5A7` et ombre beige
  `#D3CDB8`.
- [x] Eau 3D lissée : les formes `waterShapes` servent à l'aperçu du menu et
  au rendu 3D ; rectangles, ellipses tournées et capsules se superposent.
  Trois couches donnent une ombre d'eau, un liseré de côte blanc puis le
  remplissage menthe, afin que l'eau reste visible en jeu.
- [x] Correction de l'eau invisible : les ellipses utilisent un `SpecialMesh`
  sphère au lieu d'une `Part` `Ball`, qui restait ronde et devenait un point
  minuscule dès que la forme était aplatie.
- [x] Parcs 3D jaune-vert dessinés sous la grille et sous l'eau.
- [x] Aperçu de Los Angeles retravaillé d'après la référence : côte ouest en
  goutte d'eau inclinée, grande baie arrondie au sud, chenal vertical fin,
  presqu'île crème centrale, parcs tournés en haut à droite, sur la côte ouest
  et sur la presqu'île.
- [x] Presqu'îles sèches (`dryShapes`) dessinées après l'eau dans l'aperçu et
  en 3D, avec liseré de côte et raccord terre ; `Maps.isWater` les traite
  comme de la terre.
- [x] Côtes de Los Angeles complétées par des capsules le long de la côte
  ouest et du bord de la baie : la silhouette est moins ovale et se rapproche
  des segments presque droits de la référence.
- [x] Lumière du plateau adoucie (`Brightness = 0.8`, ambiante beige plus
  sombre, exposition `-0.35`) pour éviter que le sol crème et le papier virent
  au blanc. Le plateau est volontairement moins lumineux qu'avant.
- [x] Bordure beige hachurée avec étiquettes verticales turquoise
  (`LOS ANGELES`, `SANTA MONICA`, etc.).
- [x] Routes graphite `#262B2C` avec un fin liseré blanc de chaque côté.
  Le rendu orthogonal historique est conservé : cases droites, virages en arc
  et extrémités arrondies. Les liaisons diagonales sont dessinées comme des
  segments fins sous ces formes centrales, qui masquent les raccords et
  gardent des courbes ovales sans triangles visibles.
- [x] Diagonales droites lissées : une case alignée entre deux diagonales
  opposées ne reçoit ni tuile centrale plus large ni capuchon superflu. Le
  ruban garde la même largeur que l'horizontal ; les formes arrondies ne
  restent qu'aux virages, extrémités et jonctions.
- [x] Visée des routes agrandie : la carte reste en 18 × 18 cases de 4 studs,
  mais la détection accentue les diagonales près des coins. En construction,
  le carré de survol est masqué ; il ne reste visible que pour la gomme et le
  rond-point. Aucun pad ni case de choix n'entoure le curseur.
- [x] Presqu'île de Los Angeles recoupée à ras du littoral : le raccord au
  continent est net, sans gros capuchon rond, et seul le bout côté eau reste
  arrondi.
- [x] Routes diagonales à 45° : le client interpole les cases en diagonale,
  le serveur accepte ces cases, les voitures suivent les segments et le rendu
  hybride reste continu aux jonctions.
- [x] Apparition animée des routes : croissance et fondu à chaque case posée.
- [x] Bâtiments colorés, magasins carrés/circulaires, pins de demande et effets d'apparition.
- [x] Icônes de bâtiments façon Mini Motorways : cartes plates à coins
  arrondis, liseré blanc, ombre douce décalée, allée blanche, toit à deux
  teintes et cheminées pour les maisons. Magasins carrés à toit plat ou
  circulaires, avec pins de demande colorés côté client.
- [x] Petits arbres vectoriels dans les parcs : deux disques verts superposés
  par bosquet, comme les taches de végétation de la référence.
- [x] Voitures avec contour et toit clair, lisibles sur les routes sombres.
- [x] Caméra quasi orthographique (FOV 20) avec zoom et déplacement.
- [x] Éclairage plat et légèrement assombri : ombres globales désactivées,
  ambiance beige douce et exposition réduite pour un plateau moins lumineux.
- [x] HUD clair : flèche retour, score, jour, horloge (qui ouvre les contrôles
  de temps), outils à droite, compteurs rond-point / routes / ponts en bas.
- [x] Lobby clair : cartes pastel, rail garage / stats / records, décor routier
  animé et accès aux options en bas à droite.
- [x] Interface entièrement en français.

## 8. Améliorations futures

- Sons et musique discrète.
- Tutoriel au premier lancement.
- Meilleure gestion des intersections et priorités.
- Ajouter les outils **Motorway**, **Traffic Light** et **Tunnel** pour compléter les six améliorations de Mini Motorways.
- Modes de jeu supplémentaires.
- Classement global et statistiques.
- Nom/identité originale avant publication publique.

## 9. Système de magasins (09/11/2026)

### Fichiers

- **Créés** :
  - `src/ReplicatedStorage/MiniMotorways/StoreConfig.luau`
  - `src/ServerScriptService/MiniMotorways/StoreSystem.luau`
  - `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/StoreVisualController.luau`
- **Modifiés** :
  - `src/ReplicatedStorage/MiniMotorways/Config.luau` : version 1.4.0, 8ᵉ couleur Orange, nettoyage des anciens réglages de paires.
  - `src/ReplicatedStorage/MiniMotorways/Remotes.luau` : remote `StoreState`.
  - `src/ServerScriptService/MiniMotorways/Session.luau` : intégration magasins/maisons/voitures, réservations, pins, évolution, surcharge et satisfaction.
  - `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/Main.client.luau` : câblage de `StoreVisualController` et du remote `StoreState`.
  - `README.md` et `docs/PLAN.md` : documentation, paramètres et checklist.

### Fonctionnalités terminées

- [x] Premier magasin immédiat + trois maisons de sa couleur.
- [x] Apparition progressive selon le temps simulé, avec paliers 100–120 → 15–30 s.
- [x] Placement semi-aléatoire validé (zones pondérées, eau/routes/bâtiments, distances minimales, espace constructible).
- [x] Couleurs uniques centralisées ; 8 couleurs, 8 magasins maximum par défaut.
- [x] Petit magasin carré et grand magasin circulaire, style minimaliste.
- [x] Animation d'apparition, d'évolution et de demande.
- [x] Capacités 6 / 8 configurables.
- [x] Demande individuelle avec identifiant serveur et réservation anti-double-service.
- [x] Suppression du pin exact à l'arrivée de la voiture.
- [x] Alerte de capacité, compte à rebours, état critique et drainage de la satisfaction.
- [x] Évolution après âge minimal, livraisons minimales et probabilité configurable.
- [x] Ajout progressif de maisons par magasin.
- [x] Synchronisation serveur → client via `StoreState` (0,2 s en cas de changement, 1,5 s de resynchronisation).
- [x] Compilation des 19 fichiers Luau et build Rojo réussis.
- [x] Build : `1980DEBB3E02DCB68B5EC319276A214AAA9ACCD858B8BB89CAAA59C0F704C014`.

### Paramètres à ajuster en priorité

| Paramètre | Valeur actuelle | Effet |
| --- | --- | --- |
| `StoreConfig.Spawn.Tiers` | 100–120 → 15–30 s | Vitesse d'apparition des magasins. |
| `StoreConfig.Spawn.MaxStores` | 8 | Nombre de magasins. |
| `StoreConfig.Spawn.MinStoreDistance` | 4,4 | Espacement des magasins. |
| `StoreConfig.Demand.SmallInterval` | 11,5 s | Fréquence des demandes d'un petit magasin. |
| `StoreConfig.Demand.LargeInterval` | 7,5 s | Fréquence des demandes d'un grand magasin. |
| `StoreConfig.Demand.OverloadGrace` | 12 s | Tolérance avant l'état critique. |
| `StoreConfig.Evolution.MinAge` | 95 s | Délai minimal avant évolution. |
| `StoreConfig.Evolution.Chance` | 0,42 | Probabilité d'évolution. |
| `StoreConfig.Houses.StartHouses` | 3 | Maisons du premier magasin. |
| `StoreConfig.Houses.HousesPerStore` | 2 | Maisons par nouveau magasin. |

### Points restants

- [ ] Validation runtime complète dans Roblox Studio (checklist 5.1).
- [ ] Ajuster les intervalles et la surcharge après une vraie partie de 10–15 minutes.
- [ ] Vérifier visuellement la taille des pins et du compte à rebours sur mobile.
- [ ] Tester le passage à 8 magasins et l'évolution de plusieurs grands magasins.
- [ ] Décider si les couleurs doivent être réutilisées au-delà de 8 magasins ou si `MaxStores` doit rester strictement égal au nombre de couleurs.

## 10. Système de routes (10/11/2026)

### Fichiers

- **Créés** :
  - `src/ReplicatedStorage/MiniMotorways/RoadConfig.luau`
  - `src/ReplicatedStorage/MiniMotorways/RoadNetwork.luau`
  - `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/RoadPreview.luau`
- **Modifiés** :
  - `Config.luau` : version 1.5.0.
  - `Pathfinding.luau` : A* orthogonal par défaut, heuristique de Manhattan, 8 directions en option.
  - `Remotes.luau` : `RoadState` et `EraseRoads`.
  - `Bootstrap.server.luau` : limite de lot centralisée, suppression par lot.
  - `Session.luau` : connexions orthogonales aux bâtiments, topologie d'intersections, réservations, freinage lissé, orientation lissée, recalcul ciblé, état réseau, compteur de routes.
  - `InputController.luau` : aperçu local, chemins H/V, annulation `Échap`, validation au relâchement, outil caméra.
  - `Main.client.luau` : câblage `RoadState`, `EraseRoads`, caméra et `mapId`.
  - `UI/HUD.luau` : outil caméra, compteur « POSÉES », aide mise à jour.
  - `README.md` et `docs/PLAN.md` : documentation, paramètres et checklist.

### Fonctionnalités terminées

- [x] Réseau orthogonal par défaut, virages arrondis et intersections T / croix automatiques.
- [x] Aperçu local des cases valides / invalides, sans consommation avant validation.
- [x] Construction au clic maintenu, validation au relâchement et annulation `Échap`.
- [x] Résolution des gestes en biais en chemin horizontal / vertical avec hystérésis.
- [x] Connexions automatiques aux côtés des maisons et magasins.
- [x] Refus des bâtiments, routes existantes, eau sans pont et budget épuisé.
- [x] Suppression au clic / glisser, remboursement et recalcul des connexions et trajets.
- [x] A* orthogonal et recalcul ciblé après modification du réseau.
- [x] Réservation d'intersection, distance de sécurité, freinage et redémarrage progressifs.
- [x] Orientation des voitures lissée et ralentissement dans les virages.
- [x] `RoadState` serveur → client et compteur de routes posées dans le HUD.
- [x] Architecture prête pour les ponts et les futures autoroutes via `RoadConfig.Infrastructure`.
- [x] Compilation des 22 fichiers Luau et build Rojo réussis.
- [x] Test logique autonome : 136 vérifications, 0 échec.
- [x] Build : `1C84FB41C17AAA25E19A148946319FA24A754A34E6DE1F4513003FE5CCDD49BD`.

### Paramètres à ajuster en priorité

| Paramètre | Valeur actuelle | Effet |
| --- | --- | --- |
| `RoadConfig.AllowDiagonals` | `false` | Réseau orthogonal ou diagonales historiques. |
| `RoadConfig.BuildingConnection` | `"orthogonal"` | Connexion par les côtés ou aussi en diagonale. |
| `RoadConfig.Input.MaxCellsPerRequest` | 512 | Taille maximale d'un lot. |
| `RoadConfig.Traffic.TurnSpeedFactor` | 0,62 | Ralentissement dans les virages. |
| `RoadConfig.Traffic.HeadingLerp` | 9 | Vitesse de rotation visuelle. |
| `RoadConfig.Traffic.Acceleration` | 2,2 | Redémarrage après un arrêt. |
| `RoadConfig.Traffic.Braking` | 6 | Freinage. |
| `RoadConfig.Traffic.IntersectionReservation` | `true` | Une voiture à la fois dans une intersection. |
| `Config.Roads.StartBudget` | 20 | Routes disponibles au départ. |
| `Config.Traffic.CarSpacing` | 3,6 | Distance de sécurité entre voitures. |
| `Config.Traffic.CarSpeed` | 9 | Vitesse de base en studs/s. |

### Points restants

- [ ] Validation runtime complète dans Roblox Studio (checklist 5.2).
- [ ] Vérifier la fluidité avec 300+ cases de route et 16 voitures.
- [ ] Valider visuellement les raccords de ruban aux T et aux croix.
- [ ] Tester les embouteillages en boucle fermée et confirmer l'absence de blocage permanent.
- [ ] Tester la construction et l'effacement au doigt sur mobile.
- [ ] Décider du moment où les autoroutes dédiées seront branchées.
