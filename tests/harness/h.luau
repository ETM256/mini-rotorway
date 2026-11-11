--!nocheck
--[[
	h.luau  (harnais de test)
	Façade `H` donnée à chaque test : monde Roblox simulé, chargement des
	modules de src/ avec leur propre `script` / `require`, horloge virtuelle,
	journal des RemoteEvents et aides pour lancer une partie sans Roblox.
	Voir tests/README.md.
]]

local I = require("./instance")
local D = require("./datatypes")
local Scheduler = require("./scheduler")
local Api = require("./api")
local W = require("./classes")

local H = {}

local realPrint = print
-- loadstring est fourni par le CLI Luau ; on le lit via l'environnement pour
-- que l'analyseur (sans définitions du CLI) ne le signale pas.
local loadstring = (getfenv() :: any).loadstring
local typeOf = I.typeOf

-- ---------------------------------------------------------- globales mock --

local baseEnv = {}
setmetatable(baseEnv, { __index = _G })

H.logs = {}
H.warnings = {}
H.handlerErrors = {}
H.verbose = false

local function joinArgs(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

local taskLib = {
	spawn = Scheduler.spawn,
	defer = Scheduler.defer,
	delay = Scheduler.delay,
	wait = Scheduler.wait,
	cancel = Scheduler.cancel,
}

baseEnv.Vector3 = D.Vector3
baseEnv.Vector2 = D.Vector2
baseEnv.Color3 = D.Color3
baseEnv.UDim = D.UDim
baseEnv.UDim2 = D.UDim2
baseEnv.CFrame = D.CFrame
baseEnv.TweenInfo = D.TweenInfo
baseEnv.NumberRange = D.NumberRange
baseEnv.NumberSequence = D.NumberSequence
baseEnv.NumberSequenceKeypoint = D.NumberSequenceKeypoint
baseEnv.ColorSequence = D.ColorSequence
baseEnv.ColorSequenceKeypoint = D.ColorSequenceKeypoint
baseEnv.Rect = D.Rect
baseEnv.Font = D.Font
baseEnv.Random = D.Random
baseEnv.Ray = D.Ray
baseEnv.Enum = D.Enum
baseEnv.Instance = I.Instance
baseEnv.typeof = typeOf
baseEnv.task = taskLib
baseEnv.wait = Scheduler.wait
baseEnv.delay = Scheduler.delay
baseEnv.spawn = Scheduler.spawn
baseEnv.tick = function()
	return 1700000000 + Scheduler.now
end
baseEnv.time = function()
	return Scheduler.now
end
-- os.clock est virtualisé (horloge du harnais) : les anti-double-clic de Theme
-- et Lobby deviennent déterministes, sans attente réelle. Le temps CPU réel
-- reste disponible par H.cpuClock (tests de performance).
H.cpuClock = os.clock
baseEnv.os = setmetatable({
	clock = function()
		return 1000 + Scheduler.now
	end,
}, { __index = os })
baseEnv.elapsedTime = baseEnv.time
baseEnv.warn = function(...)
	table.insert(H.warnings, joinArgs(...))
	if H.verbose then
		realPrint("[warn] " .. joinArgs(...))
	end
end
baseEnv.print = function(...)
	table.insert(H.logs, joinArgs(...))
	if H.verbose then
		realPrint(joinArgs(...))
	end
end
H.G = baseEnv

-- Les tests lisent les mêmes noms que le code de src/ (Vector3, CFrame...) ;
-- ils sont aussi exposés ici pour les cas où un nom est nécessaire en dehors.
for _, name in ipairs({ "Vector3", "Vector2", "Color3", "UDim", "UDim2", "CFrame", "TweenInfo", "Enum", "Instance", "Rect", "Font", "Ray" }) do
	H[name] = baseEnv[name]
end
H.typeOf = typeOf

Scheduler.onError = function(message, traceback)
	table.insert(H.handlerErrors, { message = tostring(message), traceback = tostring(traceback) })
end

-- ------------------------------------------------------------------ monde --

local moduleList = nil
local game = I.create("DataModel", { internal = true })
game.Name = "Game"
baseEnv.game = game
H.game = game

local SERVICES = {
	"Workspace",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"Players",
	"Lighting",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"RunService",
	"TweenService",
	"UserInputService",
	"TextService",
	"DataStoreService",
	"SoundService",
	"Debris",
	"CollectionService",
}

local function loadModuleList()
	if moduleList == nil then
		local ok, result = pcall(require, "./_modules.generated")
		if not ok then
			error("tests/harness/_modules.generated.luau is missing or broken: run `bash tests/run.sh` (it regenerates it). " .. tostring(result), 0)
		end
		moduleList = result
	end
	return moduleList
end

local compiled = {} -- source -> fonction compilée (partagée entre les resets)
local moduleInstances = {} -- liste des instances de modules du monde courant

local function childNamed(parent, name)
	return parent:FindFirstChild(name)
end

local function buildTree()
	moduleInstances = {}
	for _, name in ipairs(SERVICES) do
		local service = I.create(name, { internal = true })
		service.Name = name
		I.setParent(service, game)
	end
	local starterPlayer = game.StarterPlayer
	for _, name in ipairs({ "StarterPlayerScripts", "StarterCharacterScripts" }) do
		local folder = I.create(name, { internal = true })
		folder.Name = name
		I.setParent(folder, starterPlayer)
	end

	for _, entry in ipairs(loadModuleList()) do
		local cur = game
		local tree = entry.tree
		for i = 1, #tree - 1 do
			local nextNode = childNamed(cur, tree[i])
			if not nextNode then
				nextNode = I.create("Folder", { internal = true })
				nextNode.Name = tree[i]
				I.setParent(nextNode, cur)
			end
			cur = nextNode
		end
		local inst = I.create(entry.class, { internal = true })
		inst.Name = tree[#tree]
		I.getState(inst).moduleInfo = { file = entry.file, source = entry.source, class = entry.class }
		I.setParent(inst, cur)
		table.insert(moduleInstances, inst)
	end
end

function H.seed(n)
	math.randomseed(n or 12345)
end

function H.reset()
	Scheduler.reset()
	I.resetStats()
	W.reset()
	H.logs = {}
	H.warnings = {}
	H.handlerErrors = {}
	H.handlerErrorsAllowed = false
	H.sessionCounter = 0
	H.localPlayer = nil
	I.clearChildrenRaw(game)
	buildTree()
	baseEnv.workspace = game.Workspace
	H.workspace = game.Workspace
	H.seed(12345)
end

-- Autorise les erreurs de gestionnaires d'événements pour le test courant.
function H.allowHandlerErrors()
	H.handlerErrorsAllowed = true
end

-- -------------------------------------------------------------- chargement --

local loading = {}

local function compile(entry)
	local source = entry.source
	local fn = compiled[source]
	if fn == nil then
		local err
		fn, err = loadstring(source, "=" .. entry.file)
		if not fn then
			error("syntax error in " .. entry.file .. ": " .. tostring(err), 0)
		end
		compiled[source] = fn
	end
	return fn
end

local function makeEnv(inst, extra)
	local env = {
		script = inst,
		require = function(target)
			return H.require(target)
		end,
	}
	if extra then
		for k, v in pairs(extra) do
			env[k] = v
		end
	end
	return setmetatable(env, { __index = baseEnv })
end

function H.require(target)
	if typeOf(target) ~= "Instance" then
		error("Attempted to call require with invalid argument(s). (got " .. typeOf(target) .. ")", 2)
	end
	local st = I.getState(target)
	local info = st.moduleInfo
	if not info or st.class ~= "ModuleScript" then
		error("Attempted to call require with a non-ModuleScript instance (" .. I.fullName(target) .. ")", 2)
	end
	if st.loaded then
		return st.result
	end
	if loading[target] then
		error("Cyclic require detected while loading " .. info.file, 2)
	end
	loading[target] = true
	local fn = compile(info)
	setfenv(fn, makeEnv(target))
	local results = table.pack(pcall(fn))
	loading[target] = nil
	if not results[1] then
		error(results[2], 0)
	end
	if results.n ~= 2 then
		error("Module code did not return exactly one value: " .. info.file, 0)
	end
	st.loaded = true
	st.result = results[2]
	return st.result
end

-- Cherche un module par nom ("Config"), chemin ("UI/HUD", "UI.HUD") ou nom
-- complet de l'arbre ("ReplicatedStorage.Shared.Config").
function H.findModule(spec)
	local dotted = string.gsub(string.gsub(spec, "^src/", ""), "[/\\]", ".")
	dotted = string.gsub(dotted, "%.luau$", "")
	local matches = {}
	for _, inst in ipairs(moduleInstances) do
		local full = I.fullName(inst)
		local file = I.getState(inst).moduleInfo.file
		local baseName = string.gsub(string.gsub(string.match(file, "([^/]+)$"), "%.luau$", ""), "%.(%a+)$", "")
		if full == dotted or string.sub(full, -(#dotted + 1)) == "." .. dotted or baseName == dotted or file == spec then
			table.insert(matches, inst)
		end
	end
	if #matches == 0 then
		error("H.load: no module matching '" .. spec .. "'", 3)
	elseif #matches > 1 then
		local names = {}
		for _, inst in ipairs(matches) do
			table.insert(names, I.fullName(inst))
		end
		error("H.load: ambiguous module '" .. spec .. "': " .. table.concat(names, ", "), 3)
	end
	return matches[1]
end

-- H.load("Session") : require le module et retourne sa valeur.
function H.load(spec)
	return H.require(H.findModule(spec))
end

-- H.runScript("Bootstrap") : exécute le corps d'un Script / LocalScript.
function H.runScript(spec)
	local inst = H.findModule(spec)
	local st = I.getState(inst)
	if st.class == "ModuleScript" then
		error("H.runScript: " .. spec .. " is a ModuleScript; use H.load", 2)
	end
	local info = st.moduleInfo
	-- Fonction neuve à chaque exécution : l'environnement n'est jamais partagé.
	local fn, err = loadstring(info.source, "=" .. info.file)
	if not fn then
		error("syntax error in " .. info.file .. ": " .. tostring(err), 2)
	end
	setfenv(fn, makeEnv(inst))
	return fn()
end

-- Sources de tous les modules du monde : liste de { file, class, source, name }.
-- Sert aux tests statiques (références croisées, méthodes appelées, etc.).
function H.sources()
	local list = {}
	for _, inst in ipairs(moduleInstances) do
		local info = I.getState(inst).moduleInfo
		table.insert(list, { file = info.file, class = info.class, source = info.source, name = inst.Name })
	end
	return list
end

-- Source sans les commentaires `--` ni `--[[ ]]` (les chaînes sont conservées).
function H.stripComments(source)
	source = string.gsub(source, "%-%-%[(=*)%[.-%]%1%]", "")
	return (string.gsub(source, "%-%-[^\n]*", ""))
end

-- Environnement donné aux fichiers de test (mêmes globales que src/ + T, H).
function H.testEnv(extra)
	local env = {}
	for k, v in pairs(extra or {}) do
		env[k] = v
	end
	env.print = realPrint
	env.script = nil
	return setmetatable(env, { __index = baseEnv })
end

-- ------------------------------------------------------------- temps / frames --

local function fireFrame(dt)
	local runService = game.RunService
	I.fire(I.getSignal(runService, "Stepped"), Scheduler.now, dt)
	I.fire(I.getSignal(runService, "RenderStepped"), dt)
	local names = {}
	for name in pairs(W.renderSteps) do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		local pa, pb = W.renderSteps[a].priority, W.renderSteps[b].priority
		if pa ~= pb then
			return pa < pb
		end
		return a < b
	end)
	for _, name in ipairs(names) do
		local binding = W.renderSteps[name]
		if binding then
			Scheduler.spawn(binding.fn, dt)
		end
	end
	I.fire(I.getSignal(runService, "Heartbeat"), dt)
end

-- Avance le temps virtuel : exécute task.delay / tweens dus et, par défaut,
-- tire Stepped / RenderStepped / Heartbeat à chaque pas (1/30 s).
function H.advance(seconds, opts)
	local step = opts and opts.step or 1 / 30
	local frames = not (opts and opts.frames == false)
	local remaining = seconds
	while remaining > 1e-9 do
		local dt = math.min(step, remaining)
		Scheduler.advance(dt)
		if frames then
			fireFrame(dt)
		end
		remaining -= dt
	end
end

-- Une frame complète : scheduler + Stepped / RenderStepped / Heartbeat(dt).
function H.fireHeartbeat(dt)
	dt = dt or 1 / 60
	H.advance(dt, { step = dt })
end

-- Exécute uniquement les tâches planifiées (pas d'événements de frame).
function H.flush(seconds)
	Scheduler.advance(seconds or 5)
end

function H.now()
	return Scheduler.now
end

-- ---------------------------------------------------------- joueurs / entrées --

function H.newPlayer(name, userId)
	local player = I.create("Player", { internal = true })
	player.Name = name or "Tester"
	I.setRawProp(player, "UserId", userId or 1001)
	I.setRawProp(player, "DisplayName", name or "Tester")
	I.setParent(player, game.Players)
	return player
end

-- Active le côté client : un LocalPlayer existe et les FireClient lui sont
-- livrés (OnClientEvent). Retourne le joueur.
function H.asClient(name)
	if not H.localPlayer then
		H.localPlayer = H.newPlayer(name or "Tester", 1001)
	end
	W.localPlayer = H.localPlayer
	W.isServer = false
	return H.localPlayer
end

function H.playerGui()
	return H.asClient().PlayerGui
end

function H.setViewport(width, height)
	W.viewport = D.Vector2.new(width, height)
	local function notify(inst)
		local st = I.getState(inst)
		if st.info.props.AbsoluteSize then
			I.fireChanged(inst, "AbsoluteSize")
		end
	end
	if H.localPlayer then
		for _, d in ipairs(I.descendants(H.localPlayer.PlayerGui)) do
			notify(d)
		end
		for _, d in ipairs(H.localPlayer.PlayerGui:GetChildren()) do
			notify(d)
		end
	end
	local camera = game.Workspace.CurrentCamera
	I.fireChanged(camera, "ViewportSize")
end

local function newInput(inputType, state, position, keyCode, delta)
	return {
		UserInputType = inputType,
		UserInputState = state,
		KeyCode = keyCode or D.Enum.KeyCode.Unknown,
		Position = position or D.Vector3.new(W.mouse.X, W.mouse.Y, 0),
		Delta = delta or D.Vector3.zero,
	}
end

H.input = {}
local function uis()
	return game.UserInputService
end
function H.input.mouseMove(x, y)
	local old = W.mouse
	W.mouse = D.Vector2.new(x, y)
	local input = newInput(D.Enum.UserInputType.MouseMovement, D.Enum.UserInputState.Change, D.Vector3.new(x, y, 0), nil, D.Vector3.new(x - old.X, y - old.Y, 0))
	I.fire(I.getSignal(uis(), "InputChanged"), input, false)
end
function H.input.mouseDown(x, y, button)
	if x then
		W.mouse = D.Vector2.new(x, y)
	end
	local inputType = button == 2 and D.Enum.UserInputType.MouseButton2 or button == 3 and D.Enum.UserInputType.MouseButton3 or D.Enum.UserInputType.MouseButton1
	W.buttonsDown[inputType.Name] = true
	I.fire(I.getSignal(uis(), "InputBegan"), newInput(inputType, D.Enum.UserInputState.Begin), false)
end
function H.input.mouseUp(x, y, button)
	if x then
		W.mouse = D.Vector2.new(x, y)
	end
	local inputType = button == 2 and D.Enum.UserInputType.MouseButton2 or button == 3 and D.Enum.UserInputType.MouseButton3 or D.Enum.UserInputType.MouseButton1
	W.buttonsDown[inputType.Name] = nil
	I.fire(I.getSignal(uis(), "InputEnded"), newInput(inputType, D.Enum.UserInputState.End), false)
end
function H.input.wheel(direction)
	local input = newInput(D.Enum.UserInputType.MouseWheel, D.Enum.UserInputState.Change, D.Vector3.new(0, 0, direction))
	I.fire(I.getSignal(uis(), "InputChanged"), input, false)
end
function H.input.key(keyCodeName, down)
	local keyCode = D.Enum.KeyCode[keyCodeName]
	W.keysDown[keyCodeName] = down and true or nil
	local state = down and D.Enum.UserInputState.Begin or D.Enum.UserInputState.End
	local signal = down and "InputBegan" or "InputEnded"
	I.fire(I.getSignal(uis(), signal), newInput(D.Enum.UserInputType.Keyboard, state, nil, keyCode), false)
end

-- Écran tactile : un même objet d'entrée par doigt, du début à la fin (comme
-- Roblox ; InputController le retrouve par identité). `id` identifie le doigt.
local function fingerDown(id)
	local input = W.fingers[id]
	if not input then
		error("H.input: finger " .. tostring(id) .. " is not down", 3)
	end
	return input
end
function H.input.touchBegin(id, x, y)
	assert(W.fingers[id] == nil, "H.input.touchBegin: finger " .. tostring(id) .. " is already down")
	local input = newInput(D.Enum.UserInputType.Touch, D.Enum.UserInputState.Begin, D.Vector3.new(x, y, 0))
	W.fingers[id] = input
	I.fire(I.getSignal(uis(), "InputBegan"), input, false)
end
function H.input.touchMove(id, x, y)
	local input = fingerDown(id)
	local old = input.Position
	input.Position = D.Vector3.new(x, y, 0)
	input.Delta = D.Vector3.new(x - old.X, y - old.Y, 0)
	input.UserInputState = D.Enum.UserInputState.Change
	I.fire(I.getSignal(uis(), "InputChanged"), input, false)
end
function H.input.touchEnd(id, x, y)
	local input = fingerDown(id)
	if x then
		input.Position = D.Vector3.new(x, y, 0)
	end
	input.UserInputState = D.Enum.UserInputState.End
	W.fingers[id] = nil
	I.fire(I.getSignal(uis(), "InputEnded"), input, false)
end

-- ---------------------------------------------------------------- remotes --

-- Messages envoyés : H.sent("State") -> liste de { args... } (serveur -> client).
function H.sent(remoteName, direction)
	local list = {}
	for _, entry in ipairs(W.remoteLog) do
		if entry.remote == remoteName and entry.dir == (direction or "toClient") then
			table.insert(list, entry.args)
		end
	end
	return list
end

-- Premier argument du dernier message envoyé sur ce remote (le payload).
function H.lastSent(remoteName, direction)
	local list = H.sent(remoteName, direction)
	local last = list[#list]
	return last and last[1], last
end

function H.remoteLog()
	return W.remoteLog
end

function H.clearRemoteLog()
	W.remoteLog = {}
end

function H.setupRemotes()
	H.load("Remotes").setup()
end

-- Simule le client : FireServer(name, ...) depuis le LocalPlayer.
function H.fireServer(remoteName, ...)
	H.asClient()
	H.load("Remotes").get(remoteName):FireServer(...)
end

-- ----------------------------------------------------------- aides de partie --

-- Crée un joueur + une Session démarrée sur la carte `mapId` ("los_angeles" par
-- défaut). Retourne session, player. Les remotes sont prêts ; les messages du
-- serveur sont lisibles via H.sent / H.lastSent.
function H.newSession(mapId, opts)
	H.setupRemotes()
	local Session = H.load("Session")
	H.sessionCounter = (H.sessionCounter or 0) + 1
	local player = opts and opts.player or H.localPlayer or H.newPlayer("Tester", 1001)
	local session = Session.new(player, mapId or "los_angeles", H.sessionCounter)
	session:start()
	return session, player
end

-- Avance une session de `seconds` secondes simulées par pas de dt (0,1 s) en
-- exécutant aussi les tâches virtuelles (tweens). Coupe si la partie se termine.
-- Chaque fin de semaine ouvre un choix de récompense : il est résolu
-- automatiquement (première option) sauf si opts.autoChoose == false, auquel
-- cas la boucle s'arrête dès que le choix est ouvert.
-- Usage : H.runSession(session, 120) / H.runSession(session, 120, 0.2, { autoChoose = false })
function H.runSession(session, seconds, dt, opts)
	if type(dt) == "table" then
		opts, dt = dt, nil
	end
	dt = dt or 0.1
	local autoChoose = not (opts and opts.autoChoose == false)
	local elapsed = 0
	while elapsed < seconds - 1e-9 do
		local step = math.min(dt, seconds - elapsed)
		session:update(step)
		Scheduler.advance(step)
		elapsed += step
		if session.awaitingChoice then
			if not autoChoose then
				break
			end
			session:chooseReward(session.choice.options[1].id)
		end
		if session.over then
			break
		end
	end
	return elapsed
end

local function isBuildableCell(session, x, y)
	local Grid = H.load("Grid")
	local Maps = H.load("Maps")
	if not Grid.inBounds(x, y) then
		return false
	end
	local key = Grid.key(x, y)
	if session.buildings[key] or session.roads[key] then
		return false
	end
	return not Maps.isWater(session.map, x, y)
end

-- Cellules {x, y} d'un tracé horizontal puis vertical de a vers b, `a` inclus.
function H.drawRoadBetween(session, a, b, opts)
	local RoadNetwork = H.load("RoadNetwork")
	local ax, ay = a[1] or a.x, a[2] or a.y
	local bx, by = b[1] or b.x, b[2] or b.y
	local cells = { { ax, ay } }
	for _, cell in ipairs(RoadNetwork.manhattanPath(ax, ay, bx, by, opts and opts.axis)) do
		table.insert(cells, cell)
	end
	session:drawRoad(cells)
	return cells
end

-- Plus court chemin (BFS) de cases libres reliant un côté de `from` à un côté de
-- `to` (deux bâtiments). Retourne une liste de {x, y} ou nil.
function H.pathCells(session, from, to)
	local Grid = H.load("Grid")
	local function sides(building)
		local cells = {}
		for _, n in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local x, y = building.x + n[1], building.y + n[2]
			if isBuildableCell(session, x, y) then
				table.insert(cells, { x, y })
			end
		end
		return cells
	end
	local goal = {}
	for _, c in ipairs(sides(to)) do
		goal[Grid.key(c[1], c[2])] = true
	end
	local queue, cameFrom, head = {}, {}, 1
	for _, c in ipairs(sides(from)) do
		local key = Grid.key(c[1], c[2])
		cameFrom[key] = false
		table.insert(queue, c)
	end
	while head <= #queue do
		local cur = queue[head]
		head += 1
		local curKey = Grid.key(cur[1], cur[2])
		if goal[curKey] then
			local path, key = {}, curKey
			while key do
				local x, y = Grid.parse(key)
				table.insert(path, 1, { x, y })
				key = cameFrom[key] or nil
			end
			return path
		end
		for _, n in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local x, y = cur[1] + n[1], cur[2] + n[2]
			local key = Grid.key(x, y)
			if cameFrom[key] == nil and isBuildableCell(session, x, y) then
				cameFrom[key] = curKey
				table.insert(queue, { x, y })
			end
		end
	end
	return nil
end

-- Relie deux bâtiments par une route (budget étendu si nécessaire). Retourne les cellules.
function H.connect(session, from, to)
	local cells = H.pathCells(session, from, to)
	if not cells then
		return nil
	end
	if session.budget < #cells then
		session.budget = #cells
	end
	session:drawRoad(cells)
	return cells
end

-- Première maison et un magasin de la même couleur. Retourne house, store.
function H.houseAndStore(session)
	for _, house in ipairs(session.houses) do
		for _, store in ipairs(session.destinations) do
			if store.colorIndex == house.colorIndex then
				return house, store
			end
		end
	end
	return nil, nil
end

-- --------------------------------------------------------------- inspection --

-- Nombre de descendants de `inst` (de la classe `className` si fournie, IsA).
function H.count(inst, className)
	local n = 0
	for _, d in ipairs(I.descendants(inst)) do
		if className == nil or I.getState(d).info.isA[className] then
			n += 1
		end
	end
	return n
end

-- Vrai si la position de cet élément d'interface dépend d'une mise en page
-- automatique (UIListLayout/UIGridLayout/... chez son parent), non simulée.
function H.isLayoutManaged(gui)
	local parent = gui.Parent
	if not parent then
		return false
	end
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("UIGridStyleLayout") or child:IsA("UITableLayout") or child:IsA("UIFlexItem") then
			return true
		end
	end
	return false
end

-- Simule un clic sur un bouton : Activated puis MouseButton1Click.
function H.click(button)
	local st = I.getState(button)
	if st.info.events.MouseButton1Down then
		I.fire(I.getSignal(button, "MouseButton1Down"), 0, 0)
	end
	if st.info.events.Activated then
		I.fire(I.getSignal(button, "Activated"), { UserInputType = D.Enum.UserInputType.MouseButton1 }, 1)
	end
	if st.info.events.MouseButton1Click then
		I.fire(I.getSignal(button, "MouseButton1Click"))
	end
	if st.info.events.MouseButton1Up then
		I.fire(I.getSignal(button, "MouseButton1Up"), 0, 0)
	end
end

-- Descendants (Instance) de `root` dont le nom, la classe ou le texte correspondent.
-- H.find(gui, { class = "TextButton", text = "Jouer", name = "Play" })
function H.find(root, spec)
	local found = {}
	for _, d in ipairs(I.descendants(root)) do
		local st = I.getState(d)
		local ok = true
		if spec.class and not st.info.isA[spec.class] then
			ok = false
		end
		if ok and spec.name and d.Name ~= spec.name then
			ok = false
		end
		if ok and spec.text then
			local text = st.info.props.Text and d.Text or nil
			if text == nil or not string.find(text, spec.text, 1, true) then
				ok = false
			end
		end
		if ok then
			table.insert(found, d)
		end
	end
	return found
end

-- Connexions d'événements encore actives créées depuis le dernier reset.
function H.connectionCount()
	return I.stats.connections
end

function H.instanceCount()
	return I.stats.instances
end

H.Api = Api
H.I = I
H.W = W
H.Scheduler = Scheduler

return H
