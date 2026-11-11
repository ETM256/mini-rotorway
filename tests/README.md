# Tests Luau (Roblox simulé)

Un harnais qui exécute le vrai code de `src/` dans le CLI `luau`, sans Roblox :
un faux monde (Instance, services, RemoteEvent, tweens, caméra, entrées) permet
de lancer le serveur (`Bootstrap` + `Session`) et le client (`Main`, HUD, lobby,
caméra) ensemble et de vérifier le jeu de bout en bout. Environ 230 tests,
~6 s.

```bash
bash tests/run.sh                  # tout ; n'affiche que les échecs + la ligne finale
                                   #   TESTS: N passed, M failed, K skipped
bash tests/run.sh sim/roads        # fichiers dont le chemin contient « sim/roads »
bash tests/run.sh sim::budget      # ... et dont le nom de test contient « budget »
bash tests/run.sh --verbose        # liste chaque test (ok / SKIP / TODO / FAIL)
bash tests/run.sh --list           # tests découverts, sans exécution
```

Code de sortie : 0 si aucun échec, 1 sinon (échec, crash, délai dépassé, filtre
sans résultat). Variables : `LUAU=/chemin/luau`, `TEST_TIMEOUT=120` (secondes).
Installer Luau : `brew install luau` (ou les releases GitHub de `luau-lang/luau`).

Contrôles complémentaires (hors harnais) :

```bash
node tools/check-roblox-api.js     # Enum.X.Y, Instance.new("X"), GetService("X") valides
```

## Ajouter un test

Déposer `tests/<zone>/<nom>.test.luau` ; il est découvert tout seul.

```lua
return function(T, H)
	T.test("une route coûte une pièce", function()
		local session = H.newSession("los_angeles")
		local before = session.budget
		H.connect(session, H.houseAndStore(session))
		T.lt(session.budget, before)
	end)
end
```

Chaque test s'exécute dans un monde neuf (`H.reset()` automatique : arbre
d'instances, horloge virtuelle, caches de modules, graine aléatoire 12345).
Les fichiers de test voient les mêmes globales que `src/` (`Vector3`, `Enum`,
`Instance`, `workspace`, `task`, `typeof`...). Pas de `require` : on charge le
code testé avec `H.load("Nom")`.

Un fichier qui ne compile pas ou dont le module de `src/` est cassé fait
échouer **ses** tests, jamais toute l'exécution. Une erreur levée dans un
gestionnaire d'événement ou une tâche (`task.spawn`, `Connect`) fait échouer le
test courant (sauf `H.allowHandlerErrors()`).

## Assertions `T`

`T.test(nom, fn)`, `T.todo(nom, fn)`, `T.skipTest(nom, raison)`, `T.skip(raison)`,
`T.skipIf(cond, raison)`, `T.eq`, `T.ne`, `T.ok`, `T.falsy`, `T.near(a, b, eps)`,
`T.lt/le/gt/ge`, `T.deepEq`, `T.isType(v, "Vector3")`, `T.contains(chaîne|table, x)`,
`T.throws(fn, motif)`, `T.noThrow(fn)`, `T.fail(msg)`. Le dernier argument est un
message optionnel.

`T.todo` documente un défaut connu : s'il échoue, le test est « skipped » ; dès
qu'il passe, il **échoue** pour demander de le convertir en `T.test`.
`bash tests/run.sh --verbose | grep TODO` liste les défauts connus.

## `H` : aides

| Aide | Rôle |
|------|------|
| `H.load("Config")` | `require` d'un module de `src/` par nom, `"UI/HUD"` ou nom complet ; mis en cache jusqu'au prochain reset |
| `H.runScript("Bootstrap")`, `H.runScript("Main")` | exécute un `Script` / `LocalScript` |
| `H.newSession(mapId?)` | joueur + `Session` démarrée (`"los_angeles"` par défaut) → `session, player` |
| `H.runSession(session, secondes, dt?, opts?)` | avance la simulation (pas 0,1 s) ; résout seul les choix de fin de semaine (`{ autoChoose = false }` pour s'arrêter) ; s'arrête à la fin de partie |
| `H.houseAndStore(session)` | première maison et un magasin de la même couleur |
| `H.connect(session, a, b)` | relie deux bâtiments par un plus court chemin de cases libres (étend le budget si besoin) → cases |
| `H.drawRoadBetween(session, {x,y}, {x,y}, {axis="x"})` | trace horizontal puis vertical, départ inclus, via `Session:drawRoad` |
| `H.pathCells(session, a, b)` | le chemin de `H.connect` sans construire |
| `H.sent("State")`, `H.lastSent("State")` | messages serveur → client (`H.sent(nom, "toServer")` pour l'inverse) ; `lastSent` rend le payload |
| `H.remoteLog()`, `H.clearRemoteLog()` | journal complet des RemoteEvents |
| `H.fireServer("DrawRoad", cells)` | simule le client (crée le `LocalPlayer`) |
| `H.asClient()` | active le côté client : `Players.LocalPlayer`, les `FireClient` lui sont livrés |
| `H.advance(s, {step=1/30, frames=true})` | temps virtuel : `task.delay`, tweens, `Stepped/RenderStepped/Heartbeat` |
| `H.fireHeartbeat(dt)` | une frame complète de durée `dt` |
| `H.flush(s)` | tâches planifiées seulement, sans événements de frame |
| `H.input.mouseMove/mouseDown/mouseUp(x, y, bouton)`, `.wheel(±1)`, `.key("P", true)` | entrées utilisateur (coordonnées d'écran) |
| `H.setViewport(w, h)` | résolution (déclenche `AbsoluteSize` / `ViewportSize`) |
| `H.click(bouton)` | `Activated` puis `MouseButton1Click` |
| `H.find(racine, {class=, name=, text=})` | recherche de descendants |
| `H.count(inst, "BasePart")` | nombre de descendants (IsA) |
| `H.sources()`, `H.stripComments(src)` | sources embarquées, pour les tests statiques |
| `H.connectionCount()`, `H.instanceCount()` | fuites de connexions / instances |
| `H.warnings`, `H.logs`, `H.handlerErrors` | `warn`, `print` et erreurs capturés |
| `H.seed(n)` | graine de `math.random` |

## Fonctionnement

- `tests/run.sh` **génère** avant chaque exécution (écriture atomique
  `mktemp` + `mv`, sûre en parallèle ; ignorés par git, ne pas éditer) :
  `tests/harness/_modules.generated.luau` (chaque `src/**/*.luau` avec sa place
  dans l'arbre, d'après `default.project.json` ; `.server` = `Script`,
  `.client` = `LocalScript`) et `tests/_tests.generated.luau` (chaque
  `*.test.luau`). Les sources sont embarquées en chaînes longues : chaque module
  est compilé avec `loadstring` et son propre environnement (`script`,
  `require`), sans rien modifier dans `src/`.
- `harness/api_data.luau` (généré par `node tools/gen-roblox-api.js
  <globalTypes.d.luau>`, versionné) donne toutes les énumérations et les
  propriétés / méthodes / événements des classes Roblox : une propriété
  inconnue, un mauvais type (`part.Material = "Plastic"`) ou un `Enum` inexistant
  lève la même erreur que Roblox.
- Les `RemoteEvent` sont journalisés ; les charges sont copiées (fonctions
  refusées) comme à travers le réseau.
- `TweenService` applique l'objectif à la fin du délai (virtuel) et déclenche
  `Completed`, sans interpolation intermédiaire.

## Limites connues

- Pas de rendu, de physique ni de mise en page automatique : `UIListLayout`
  et consorts ne placent rien (`AbsolutePosition` est indicative sous un layout :
  voir `H.isLayoutManaged`).
- Pas d'inset de barre supérieure : `ScreenPointToRay` == `ViewportPointToRay`.
- `Workspace:Raycast`, `UserInputService` tactile et autres API non utilisées
  par le jeu ne sont pas implémentées : appel = erreur explicite
  « valid Roblox method but is not implemented by the harness ». Les ajouter
  dans `tests/harness/classes.luau` (`I.implement(classe, { methods, getters,
  setters, defaults })`).
- `task.wait` appelé directement dans un test avance l'horloge virtuelle ;
  `Signal:Wait()` / `WaitForChild` sans enfant exigent une tâche (`task.spawn`),
  sinon erreur « would block ».
- Le temps réel (`os.clock`) n'est pas virtualisé ; `tick()` et `time()` le sont.
