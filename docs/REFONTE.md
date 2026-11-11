# Refonte qualité de Mini Rotorway (11/11/2026)

Rapport de fin de travail, au format demandé par le cahier des charges de la refonte (partie 19, non versionné).
Méthode : analyse du code existant, découpage en lots de fichiers distincts, puis
plusieurs vagues d'agents (implémentation, relecture indépendante, audit des pièges
du moteur Roblox), chacune validée par la syntaxe (`luau-compile`), le lint
(`luau-analyze`), la vérification des API (`tools/check-roblox-api.js`) et la suite de
tests. Rien n'a été vérifié dans Roblox Studio (non disponible).

## 1. Fichiers créés

Code du jeu :
- `src/ReplicatedStorage/MiniMotorways/RoadGeometry.luau`
- `src/ServerScriptService/MiniMotorways/BuildingModels.luau`
- `src/ServerScriptService/MiniMotorways/BuildingShapes.luau`
- `src/ServerScriptService/MiniMotorways/CarModel.luau`
- `src/ServerScriptService/MiniMotorways/RoadRenderer.luau`
- `src/ServerScriptService/MiniMotorways/SessionBuildings.luau`
- `src/ServerScriptService/MiniMotorways/SessionProgress.luau`
- `src/ServerScriptService/MiniMotorways/SessionRoadVisuals.luau`
- `src/ServerScriptService/MiniMotorways/SessionRoads.luau`
- `src/ServerScriptService/MiniMotorways/SessionTraffic.luau`
- `src/ServerScriptService/MiniMotorways/SessionUtil.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/UI/HUDCounters.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/UI/HUDIcons.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/UI/HUDOverlays.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/UI/HUDResponsive.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/UI/HUDToolbar.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/UI/HUDTopBar.luau`

Outils :
- `tools/build-rbxlx.js`
- `tools/check-roblox-api.js`
- `tools/gen-roblox-api.js`

Documentation :
- `docs/road-rendering.md`

Tests : 108 fichiers `*.test.luau` dans `tests/unit`, `tests/sim` et `tests/client`, plus le harnais :
- `tests/.gitignore`
- `tests/README.md`
- `tests/harness/api.luau`
- `tests/harness/api_data.luau`
- `tests/harness/classes.luau`
- `tests/harness/datatypes.luau`
- `tests/harness/framework.luau`
- `tests/harness/h.luau`
- `tests/harness/instance.luau`
- `tests/harness/scheduler.luau`
- `tests/run.sh`
- `tests/run_all.luau`

## 2. Fichiers modifiés

- `OUVRIR-ICI.txt`
- `README.md`
- `docs/PLAN.md`
- `src/ReplicatedStorage/MiniMotorways/Config.luau`
- `src/ReplicatedStorage/MiniMotorways/Grid.luau`
- `src/ReplicatedStorage/MiniMotorways/Maps.luau`
- `src/ReplicatedStorage/MiniMotorways/Pathfinding.luau`
- `src/ReplicatedStorage/MiniMotorways/Remotes.luau`
- `src/ReplicatedStorage/MiniMotorways/RoadConfig.luau`
- `src/ReplicatedStorage/MiniMotorways/RoadNetwork.luau`
- `src/ReplicatedStorage/MiniMotorways/StoreConfig.luau`
- `src/ServerScriptService/MiniMotorways/Bootstrap.server.luau`
- `src/ServerScriptService/MiniMotorways/Profile.luau`
- `src/ServerScriptService/MiniMotorways/Session.luau`
- `src/ServerScriptService/MiniMotorways/StoreSystem.luau`
- `src/ServerScriptService/MiniMotorways/WorldBuilder.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/CameraController.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/InputController.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/Main.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/RoadPreview.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/StoreVisualController.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/UI/HUD.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/UI/Lobby.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/UI/MapPreview.luau`
- `src/StarterPlayer/StarterPlayerScripts/MiniMotorways/UI/Theme.luau`

`Session.luau` (2 581 lignes au départ) a été découpé : sa logique vit maintenant dans
`SessionBuildings`, `SessionRoads`, `SessionRoadVisuals`, `SessionTraffic`,
`SessionProgress` et `SessionUtil`. Le HUD (1 368 lignes) est découpé en `HUD*.luau`.
`MiniMotorwaysRBX.rbxlx` a été régénéré depuis `src/` avec `tools/build-rbxlx.js`.

## 3. Fonctionnalités terminées (vérifiées par des tests headless)

- **Terrain et cartes** (parties 6, 7) : eau dérivée des formes (ce qui est dessiné est
  ce qui est interdit), rivières sinueuses qui séparent la terre et exigent un pont,
  lacs, parcs et arbres vus du dessus, grille très discrète qui se renforce pendant la
  construction. Bordure hachurée, bandes turquoise latérales et textes latéraux supprimés.
- **Routes** (partie 3) : un seul renderer (`RoadGeometry` + `RoadRenderer`) ; largeur
  unique de 0,54 case partout ; virages et bouts arrondis ; T et croix en une surface ;
  raccords qui s'arrêtent au bord des bâtiments ; mise à jour limitée à la case modifiée
  et ses voisines ; aperçu à la forme réelle ; validation et budget côté serveur,
  remboursements, ponts, ronds-points.
- **Bâtiments** (parties 4, 5) : maisons vues du dessus avec variantes par couleur et
  entrée, petits magasins carrés et grands magasins ronds, ombres douces, groupes de
  maisons irrégulières avec espacement, pastilles de demande petites et espacées,
  animations courtes, tailles centralisées.
- **Circulation** (partie 8) : voitures arrondies avec vitre, voies à droite, arcs de virage,
  accélération et freinage progressifs, arrêt avant l'intersection, réservation par
  séquences de cases sans interblocage, chemins mis en cache, A* à tas binaire.
- **Interface** (partie 9) : barre supérieure (jour, mois, score), colonne d'outils,
  compteurs homogènes, menu pause (Reprendre, Rejouer, Paramètres, Quitter), écran de fin
  (score, record, durée, statistiques, cause, Rejouer), choix de récompense, adaptation de
  1920×1080 aux téléphones, panneaux qui n'envoient plus leurs clics au monde.
- **Caméra** (partie 10) : vue aérienne, zoom fluide avec limites, déplacement au clic
  milieu / deux doigts, marges d'interface, interface Roblox par défaut masquée.
- **Temps, ressources, score** (parties 11 à 13) : une seule horloge (pause, ×1, ×2, ×3),
  jours et mois, récompenses équilibrées dont une amélioration de circulation, score,
  surcharge et difficulté progressives, statistiques de fin de partie.
- **Palette et style** (parties 2, 14, 15) : jetons centralisés (`Config.Colors`,
  `Config.Dimensions`, `Config.Style`, `Theme`), couleurs pastel, 8 couleurs de maisons
  distinctes (écart mesuré par un test).
- **Qualité** (partie 16) : validation et limites de débit des remotes, DataStore robuste,
  tweens suivis et annulés, connexions nettoyées, rendu incrémental.
- **Audit moteur Roblox** : décalage des clics d'une hauteur de barre supérieure corrigé,
  ellipses rendues en dômes corrigées, voitures enfoncées dans les ponts corrigées,
  lectures DataStore en double, tweens orphelins, glyphes risqués remplacés.

## 4. Fonctionnalités non terminées

- Aucune vérification visuelle dans Roblox Studio.
- Coin intérieur des virages non arrondi (surface en rectangles et disques).
- Outil « Autoroute » et feux de circulation (hors périmètre de la demande, déjà notés).
- Voies partagées pour le trafic traversant : sur une rue bordée de maisons, deux voitures
  de sens opposé s'attendent.
- Sons, tutoriel, classement global.
- Pékin et Londres gardent des rivières à plus de 10 formes (budget d'aperçu respecté).

## 5. Tests réellement effectués

- `luau-compile` sur les 39 fichiers de `src/` : 0 erreur.
- `luau-analyze` (Roblox filtré) : 0 avertissement.
- `node tools/check-roblox-api.js` : toutes les `Enum.X.Y` et `Instance.new("X")` valides.
- `bash tests/run.sh` : **980 tests passés, 0 échec** (environ 50 s), répétés plusieurs fois
  sans instabilité. Ils couvrent : modules purs (grille, A*, géométrie des routes, cartes,
  palette), simulation serveur complète (routes, budget, bâtiments, voitures, demandes,
  surcharge, récompenses, fin de partie, équilibrage sur plusieurs graines), et client
  (caméra, entrées souris et tactiles, aperçu, pastilles, HUD, lobby, menus) avec un Roblox
  simulé strict. Des mutations volontaires du code ont été utilisées pour vérifier que
  les tests détectent bien les régressions.

## 6. Problèmes encore présents ou à vérifier dans Studio

- Rendu réel : largeurs, hauteurs de couches, ombres, ellipses (cylindres aplatis),
  coins arrondis du lobby (`ClipsDescendants` sur `UICorner`), `CanvasGroup` du
  `MapPreview`, pastilles `BillboardGui`.
- Mise en page réelle de l'interface (pas de moteur de mise en page dans le harnais) :
  la colonne d'outils, les compteurs et la barre supérieure aux 6 résolutions ont été
  vérifiées par calcul, pas à l'écran. Boutons de temps de 32×28 px sous le minimum tactile.
- Échap ouvre aussi le menu de Roblox en plus du menu pause du jeu.
- Marges d'encoche (`ScreenInsets`) des téléphones non prises en compte.
- Animations côté serveur (routes, évolution des magasins, position des voitures) : coût de
  réplication à surveiller avec beaucoup de joueurs.
- L'équilibrage vient de simulations automatiques : une vraie partie de 15 minutes reste à jouer.
- `Lighting.Technology = Future` est conservé dans la place (non modifiable par script) ; une
  technologie plus légère conviendrait à ce style plat.
