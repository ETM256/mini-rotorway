--[[
	Bootstrap.server.luau
	Point d'entrée serveur : prépare le monde, les remotes, les profils,
	puis fait tourner une Session par joueur.

	Chaque donnée venant d'un client est non fiable : débit limité par joueur
	et par remote, forme du payload vérifiée avant la Session, et aucune erreur
	d'une partie ne doit arrêter le serveur ni les autres parties.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Remotes = require(Shared.Remotes)
local SharedRoadConfig = require(Shared.RoadConfig)

local Session = require(script.Parent.Session)
local Profile = require(script.Parent.Profile)

local MAX_CELLS = SharedRoadConfig.Input.MaxCellsPerRequest

-- Limites d'entrée. Chaque remote a un seau à jetons par joueur : `burst`
-- actions d'un coup, puis `perSecond` actions par seconde en régime établi.
local NET = {
	MaxIdLength = 64,
	MaxKeyLength = 16,
	Limits = {
		StartGame = { burst = 3, perSecond = 0.5 },
		DrawRoad = { burst = 20, perSecond = 8 },
		EraseRoad = { burst = 30, perSecond = 15 },
		EraseRoads = { burst = 10, perSecond = 4 },
		PlaceRoundabout = { burst = 10, perSecond = 3 },
		SetSpeed = { burst = 10, perSecond = 4 },
		SetPaused = { burst = 10, perSecond = 4 },
		ChooseReward = { burst = 5, perSecond = 1 },
		RequestProfile = { burst = 5, perSecond = 1 },
		ResetRecords = { burst = 2, perSecond = 0.2 },
	},
}

-- Éclairage plat et pastel : ombres douces ou absentes, ambiance légère.
local LIGHTING = {
	Brightness = 0.8,
	ClockTime = 12,
	GeographicLatitude = 0,
	Ambient = Color3.fromHex("D8D2C5"),
	OutdoorAmbient = Color3.fromHex("E0D8C9"),
	GlobalShadows = false,
	ShadowSoftness = 0,
	EnvironmentDiffuseScale = 0.45,
	EnvironmentSpecularScale = 0,
	ExposureCompensation = -0.35,
}

-- Effets qui délavent, colorent ou floutent l'image : retirés s'ils existent.
local POST_EFFECT_CLASSES = {
	"BloomEffect",
	"BlurEffect",
	"ColorCorrectionEffect",
	"ColorGradingEffect",
	"DepthOfFieldEffect",
	"SunRaysEffect",
	"Atmosphere",
}

Players.CharacterAutoLoads = false

-- Une propriété refusée par le moteur ne doit pas arrêter tout le serveur :
-- le réglage est journalisé et le reste s'applique.
for property, value in pairs(LIGHTING) do
	local ok, err = pcall(function()
		Lighting[property] = value
	end)
	if not ok then
		warn("[MiniMotorways] Lighting." .. property .. " refusé : " .. tostring(err))
	end
end
for _, child in ipairs(Lighting:GetChildren()) do
	for _, className in ipairs(POST_EFFECT_CLASSES) do
		if child:IsA(className) then
			child:Destroy()
			break
		end
	end
end

local oldWorlds = Workspace:FindFirstChild("MMWorlds")
if oldWorlds then
	oldWorlds:Destroy()
end
local worlds = Instance.new("Folder")
worlds.Name = "MMWorlds"
worlds.Parent = Workspace

Remotes.setup()

local sessions = {} -- [player] = Session en cours
-- Joueurs en cours de sortie. Une lecture de profil encore en vol ne doit pas
-- lancer une partie pour eux : pendant la sortie, Player.Parent est encore
-- défini. Clés faibles : rien à nettoyer.
local departing = setmetatable({}, { __mode = "k" })
local buckets = {} -- [player] = { [remote] = { tokens, stamp } }
local warned = {} -- erreurs déjà journalisées (une fois par type)

-- Journalise une erreur une seule fois par type : les numéros de ligne ne
-- comptent pas, sinon chaque erreur paraîtrait nouvelle.
local function reportOnce(kind, err)
	local text = tostring(err)
	local signature = kind .. "|" .. (string.gsub(text, ":%d+:", ":"))
	if warned[signature] then
		return
	end
	warned[signature] = true
	warn("[MiniMotorways] " .. kind .. " : " .. text)
end

-- Exécute fn sans jamais propager l'erreur au moteur.
local function guard(kind, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		reportOnce(kind, err)
	end
	return ok
end

-- Seau à jetons : retourne false si le joueur a épuisé le débit de ce remote.
local function takeToken(player, name)
	local limit = NET.Limits[name]
	if not limit then
		return true
	end
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = tick()
	local bucket = perPlayer[name]
	if not bucket then
		bucket = { tokens = limit.burst, stamp = now }
		perPlayer[name] = bucket
	end
	-- tick() suit l'horloge murale : un recalage en arrière ne doit pas
	-- retirer de jetons.
	bucket.tokens = math.min(limit.burst, bucket.tokens + math.max(0, now - bucket.stamp) * limit.perSecond)
	bucket.stamp = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function isId(value)
	return type(value) == "string" and #value <= NET.MaxIdLength
end

local function isCellKey(value)
	return type(value) == "string" and #value <= NET.MaxKeyLength
end

local function isCell(cell)
	return type(cell) == "table" and #cell == 2 and isFiniteNumber(cell[1]) and isFiniteNumber(cell[2])
end

-- Liste bornée en nombre d'entrées, sans trou ni clé autre qu'un indice
-- entier. Le parcours s'arrête dès le premier dépassement : une table hostile
-- ne coûte jamais plus de maxCount + 1 tours.
local function isBoundedList(list, maxCount, check)
	if type(list) ~= "table" then
		return false
	end
	local count = 0
	for key, entry in pairs(list) do
		count += 1
		if count > maxCount or type(key) ~= "number" or not check(entry) then
			return false
		end
	end
	return #list == count
end

-- Emplacement de chaque joueur, qui fixe l'origine de sa ville. Un joueur
-- garde le sien tant qu'il est sur le serveur ; il est recyclé à sa sortie.
-- Ainsi une partie relancée retrouve son origine et les coordonnées ne
-- s'éloignent plus à chaque relance.
local slotOwners = {} -- [index] = player
local playerSlots = {} -- [player] = index

local function slotFor(player)
	local index = playerSlots[player]
	if index then
		return index
	end
	index = 1
	while slotOwners[index] do
		index += 1
	end
	slotOwners[index] = player
	playerSlots[player] = index
	return index
end

local function releaseSlot(player)
	local index = playerSlots[player]
	if index then
		slotOwners[index] = nil
		playerSlots[player] = nil
	end
end

local function activeSession(player)
	local session = sessions[player]
	if session and not session.destroyed then
		return session
	end
	return nil
end

local function destroySession(player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	guard("destroy", session.destroy, session)
end

-- Une Session en erreur est arrêtée seule ; le joueur en est prévenu par Toast.
local function abortSession(player, err)
	reportOnce("session", err)
	destroySession(player)
	if player.Parent then
		Remotes.get("Toast"):FireClient(player, "La partie a été interrompue. Relancez-la depuis le menu.")
	end
end

-- Lit le profil. Si le joueur est parti pendant la lecture, l'entrée qui vient
-- d'être mise en cache n'aurait plus personne pour la libérer : on la rend ici
-- (Profile.forget garde seulement ce qui reste à écrire).
local function loadProfile(player)
	local records = Profile.load(player)
	if departing[player] then
		Profile.forget(player)
	end
	return records
end

local function sendProfile(player)
	local records = loadProfile(player)
	if player.Parent and not departing[player] then
		Remotes.get("Profile"):FireClient(player, records)
	end
end

local function startGame(player, mapId)
	-- Carte inconnue ou invalide : première carte, comme avant.
	local map = nil
	if isId(mapId) then
		map = Maps.getById(mapId)
	end
	map = map or Maps.all()[1]

	-- Le profil doit être en cache avant la partie : la fin de partie y
	-- enregistre le score sans attendre le DataStore (Heartbeat).
	loadProfile(player)
	if not player.Parent or departing[player] then
		return
	end

	-- Partie précédente détruite après le yield, sinon elle resterait active.
	destroySession(player)
	local created, session = pcall(Session.new, player, map.id, slotFor(player))
	if not created then
		abortSession(player, session)
		return
	end
	sessions[player] = session
	local started, err = pcall(session.start, session)
	if not started then
		abortSession(player, err)
	end
end

local function withSession(action)
	return function(player, ...)
		local session = activeSession(player)
		if session then
			action(session, ...)
		end
	end
end

-- Relie un RemoteEvent : débit, puis forme du payload, puis action. Toute
-- erreur est journalisée une fois et ne remonte jamais au moteur.
local function runBound(validate, action, player, ...)
	if validate and not validate(...) then
		return
	end
	action(player, ...)
end

local function bind(name, validate, action)
	Remotes.get(name).OnServerEvent:Connect(function(player, ...)
		if not takeToken(player, name) then
			return
		end
		guard(name, runBound, validate, action, player, ...)
	end)
end

bind("StartGame", nil, startGame)

bind("DrawRoad", function(cells)
	return isBoundedList(cells, MAX_CELLS, isCell)
end, withSession(function(session, cells)
	session:drawRoad(cells)
end))

bind("EraseRoad", isCellKey, withSession(function(session, key)
	session:eraseRoad(key)
end))

bind("EraseRoads", function(keys)
	return isBoundedList(keys, MAX_CELLS, isCellKey)
end, withSession(function(session, keys)
	session:eraseRoads(keys)
end))

bind("SetPaused", function(paused)
	return type(paused) == "boolean"
end, withSession(function(session, paused)
	session:setPaused(paused)
end))

bind("SetSpeed", isFiniteNumber, withSession(function(session, speed)
	session:setSpeed(speed)
end))

bind("PlaceRoundabout", function(x, y)
	return isFiniteNumber(x) and isFiniteNumber(y)
end, withSession(function(session, x, y)
	session:placeRoundabout(x, y)
end))

bind("ChooseReward", isId, withSession(function(session, optionId)
	session:chooseReward(optionId)
end))

bind("ReturnToLobby", nil, function(player)
	destroySession(player)
end)

bind("RequestProfile", nil, function(player)
	sendProfile(player)
end)

bind("ResetRecords", nil, function(player)
	Profile.reset(player)
	sendProfile(player)
end)

local function onPlayerAdded(player)
	task.spawn(guard, "profile", sendProfile, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

-- Sortie : la partie est détruite, le profil écrit une seule fois (il est
-- propre ensuite), puis le cache libéré si rien n'attend d'être écrit.
Players.PlayerRemoving:Connect(function(player)
	departing[player] = true
	destroySession(player)
	guard("save", Profile.save, player)
	Profile.forget(player)
	buckets[player] = nil
	releaseSlot(player)
end)

-- Une partie qui échoue est arrêtée seule : les autres continuent. Les
-- erreurs sont collectées pendant le parcours et traitées après, pour ne
-- jamais modifier `sessions` pendant qu'on le parcourt.
RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, Config.Time.MaxFrameDt)
	local failed = nil
	for player, session in pairs(sessions) do
		local ok, err = pcall(session.update, session, dt)
		if not ok then
			failed = failed or {}
			table.insert(failed, { player = player, err = err })
		end
	end
	if failed then
		for _, item in ipairs(failed) do
			abortSession(item.player, item.err)
		end
	end
end)

-- Sauvegarde périodique : les scores modifiés ne restent pas seulement en mémoire.
task.spawn(function()
	while true do
		task.wait(Profile.AUTOSAVE_SECONDS)
		guard("autosave", Profile.flushAll)
	end
end)

game:BindToClose(function()
	guard("shutdown", Profile.flushAll)
end)

warn("[MiniMotorways] Server ready — " .. Config.GameName .. " v" .. Config.Version)
