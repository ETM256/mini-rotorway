# Plan de développement — Mini Motorways (prototype Roblox)

## 1. Fondations

- [x] Structure Rojo (`default.project.json`)
- [x] `Config.luau` : grille, budgets, semaines, trafic, palette claire, récompenses
- [x] `Maps.luau` : Dubaï, Los Angeles, Pékin, Tokyo, Dar es Salaam, Londres
- [x] `Grid.luau` : conversions case ↔ monde, voisins orthogonaux et diagonaux
- [x] `Pathfinding.luau` : A\* sur les routes en 8 directions
- [x] `Remotes.luau` : RemoteEvents partagés

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
- [x] `InputController.luau` : dessin souris/tactile + curseur + outil rond-point
- [x] `StoreVisualController.luau` : pins `BillboardGui`, animations d'apparition/disparition, couleurs et compte à rebours de surcharge
- [x] Tracé en diagonale : le geste avance simultanément sur X et Y et dessine
  des segments à 45° au lieu de fabriquer un escalier de cases. La carte garde
  sa grille 18 × 18, mais la détection est agrandie et favorise les diagonales
  près des coins. En construction, le gros carré de visée est masqué : la route
  apparaît directement sous le curseur, sans pad de choix.
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
- [x] Vérification des classes : 1 `Script`, 1 `LocalScript`, 17 `ModuleScript`
- [x] Parse Luau de tous les fichiers
- [ ] Test manuel dans Studio (à faire par l'utilisateur)

## 5. Test manuel recommandé

1. Ouvrir `MiniMotorwaysRBX.rbxlx` dans Studio.
2. Vérifier le lobby clair, le titre, les boutons, le décor routier et les 6 cartes.
3. Lancer Los Angeles.
4. Vérifier la vue de dessus, le papier crème, l'eau menthe avec son liseré
   de côte blanc, les parcs jaune-vert, les routes graphite et les bâtiments
   colorés.
5. Dessiner une route entre une maison et un bâtiment de la même couleur :
   vérifier le trait blanc de chaque côté, les bords droits, les jonctions
   arrondies et l'extrémité **ovale** de la route. En construction, aucun gros
   carré bleu ne doit suivre la souris : la route apparaît directement. Le
   carré de repère reste visible pour la gomme et le rond-point.
6. Glisser à 45° : la route doit se prolonger en diagonale, rester aussi lisse
   qu'une ligne droite, garder des jonctions ovales sans triangle et être
   empruntée par une voiture.
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
13. Tester la molette (zoom) et le clic milieu (déplacement).
14. Laisser la jauge tomber à 0 et vérifier l'écran de fin + record.
15. Rejouer, changer de carte, revenir au menu.
16. Tester en portrait (mobile) et en paysage.

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
