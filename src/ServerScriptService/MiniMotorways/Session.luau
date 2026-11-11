--[[
	Session.luau
	Une partie = une ville. Tout est simulé côté serveur :
	  - génération des maisons / destinations
	  - routes et ponts (budget)
	  - trajets des voitures (A*)
	  - horloge de jeu (jours, mois, vitesse), score, statistiques
	Le client ne fait qu'envoyer des demandes de routes et afficher l'état.

	Horloge unique : Session.elapsed (secondes simulées) avance d'un même pas
	pour tous les systèmes. Le jour, la semaine et le mois en sont déduits.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Remotes = require(Shared.Remotes)
local RoadConfig = require(Shared.RoadConfig)
local WorldBuilder = require(script.Parent.WorldBuilder)
local Profile = require(script.Parent.Profile)
local StoreSystem = require(script.Parent.StoreSystem)
local SessionUtil = require(script.Parent.SessionUtil)
local clamp = SessionUtil.clamp

local Session = {}
Session.__index = Session

-- Les méthodes sont réparties par responsabilité dans des modules voisins.
require(script.Parent.SessionBuildings)(Session)
require(script.Parent.SessionRoads)(Session)
require(script.Parent.SessionRoadVisuals)(Session)
require(script.Parent.SessionTraffic)(Session)
require(script.Parent.SessionProgress)(Session)

local Time = Config.Time
local WEEK_DURATION = Config.Game.WeekDuration
local DAY_DURATION = WEEK_DURATION / Time.DaysPerWeek

-- Tolérance flottante : sur les bornes de jour et de semaine (60 / (60 / 7)
-- n'est pas exactement 7) et sur le reste d'un découpage de frame, qui sans
-- elle ajouterait un pas de simulation quasi nul.
local FLOAT_EPSILON = 1e-9

-- Compteurs présents à zéro dans le payload de fin, même s'ils n'ont pas
-- encore été incrémentés. recordStat accepte aussi des noms supplémentaires.
local STAT_NAMES = {
	"deliveries",
	"carsSpawned",
	"roadsBuilt",
	"roadsErased",
	"storesSpawned",
	"housesSpawned",
	"demandsCreated",
	"demandsServed",
	"weeksCompleted",
	"rewardsChosen",
	"stuckSeconds",
}

local function unitIndex(seconds, unit)
	return math.floor(seconds / unit + FLOAT_EPSILON)
end

-- Un index de monde invalide (nil, NaN, infini) ne doit pas placer la ville
-- à une origine absurde : on retombe sur le premier emplacement.
local function sanitizeWorldIndex(value)
	local index = tonumber(value)
	if not index or index ~= index or math.abs(index) == math.huge then
		return 1
	end
	return math.max(0, math.floor(index))
end

local function sameFields(a, b)
	for key, value in pairs(b) do
		if a[key] ~= value then
			return false
		end
	end
	for key in pairs(a) do
		if b[key] == nil then
			return false
		end
	end
	return true
end

local function copyTable(source)
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

local function initStats()
	local stats = {}
	for _, name in ipairs(STAT_NAMES) do
		stats[name] = 0
	end
	return stats
end

-- Remet à zéro toute la partie en cours. Appelé à la création et à chaque
-- start() : rien ne doit survivre d'une partie précédente.
local function resetGameState(self)
	self.roads = {}
	self.bridges = {}
	self.roadParts = {}
	self.roadSignatures = {}
	self.roadDirty = {}
	self.roadReveal = {}
	self.roadBuildingsSeen = 0
	self.roundaboutParts = {}
	self.intersections = {}
	self.intersectionReservations = {}
	self.buildings = {}
	self.buildingList = {}
	self.houses = {}
	self.destinations = {}
	self.cars = {}
	self.servedStores = {}
	self.criticalTimes = {}
	self.upgrades = {}
	self.gameOverReason = nil
	self.routeCache = {}
	self.routeCacheVersion = nil
	-- Cache des cases tenues par les bâtiments (SessionTraffic). Un cache d'une
	-- partie précédente ne doit jamais servir à la suivante : la version de
	-- route repart de zéro, il faut donc aussi le vider ici.
	self.holdCells = {}
	self.holdCellVersion = nil
	self.holdCellCount = nil

	self.score = 0
	self.elapsed = 0
	self.week = 1
	self.weekTime = 0
	self.satisfaction = Config.Traffic.SatisfactionStart
	self.budget = Config.Roads.StartBudget
	self.bridgesLeft = Config.Roads.StartBridges
	self.roundaboutsLeft = Config.Roads.StartRoundabouts
	self.speed = Time.MinSpeed
	self.stats = initStats()

	self.roadVersion = 0
	self.running = false
	self.paused = false
	self.over = false
	self.awaitingChoice = false
	self.choice = nil

	self.stateClock = 0
	self.nextBuildingId = 1
	self.lastState = nil
	self:updateClock()
end

-- Détruit le monde visuel et les stores de la partie courante, et arrête les
-- tweens. Ne touche pas aux tables de jeu : resetGameState s'en charge.
local function teardownGame(self)
	SessionUtil.cancelTweens(self.tweens)
	if self.storeSystem then
		self.storeSystem:destroy()
		self.storeSystem = nil
	end
	if self.world and self.world.folder then
		self.world.folder:Destroy()
	end
	self.world = nil
end

local function buildGame(self)
	self.world = WorldBuilder.build(self)
	-- StoreSystem réutilise les bâtiments, les maisons et les voitures de
	-- Session : un seul système, pas de doublon.
	self.storeSystem = StoreSystem.new(self)
	self.storeSystem:seed()
end

function Session.new(player, mapId, worldIndex)
	local map = Maps.getById(mapId) or Maps.all()[1]
	local index = sanitizeWorldIndex(worldIndex)

	local self = setmetatable({}, Session)
	self.player = player
	self.mapId = map.id
	self.map = map
	self.worldIndex = index
	self.origin = Vector3.new(index * Config.World.OriginSpacing, Config.World.BaseY, 0)
	self.size = Config.Grid.Size
	self.tile = Config.Grid.TileSize
	self.tweens = {}
	self.destroyed = false
	self.world = nil
	self.storeSystem = nil

	-- Le monde n'est construit qu'au start() : une session créée mais non
	-- démarrée n'occupe aucun Instance dans Workspace.
	resetGameState(self)
	return self
end

-- Horloge dérivée de self.elapsed : semaine, jour de la semaine, mois.
-- Un mois = WeeksPerMonth semaines ; les noms de mois bouclent sur l'année.
function Session:updateClock()
	local completedWeeks = unitIndex(self.elapsed, WEEK_DURATION)
	self.week = completedWeeks + 1
	self.weekTime = math.max(0, self.elapsed - completedWeeks * WEEK_DURATION)

	local dayIndex = unitIndex(self.elapsed, DAY_DURATION)
	self.day = dayIndex + 1
	self.dayOfWeek = dayIndex % Time.DaysPerWeek + 1
	self.dayProgress = clamp((self.elapsed - dayIndex * DAY_DURATION) / DAY_DURATION, 0, 1)

	local monthIndex = math.floor((self.week - 1) / Time.WeeksPerMonth)
	self.month = monthIndex + 1
	self.monthName = Time.MonthNames[monthIndex % #Time.MonthNames + 1]
	self.monthWeek = (self.week - 1) % Time.WeeksPerMonth + 1
	self.monthProgress = clamp(
		((self.monthWeek - 1) + self.weekTime / WEEK_DURATION) / Time.WeeksPerMonth,
		0,
		1
	)
end

-- Statistiques : un nom inconnu est accepté (un module peut en ajouter un),
-- un montant non numérique est ignoré.
function Session:recordStat(name, amount)
	if type(name) ~= "string" or type(amount) ~= "number" or amount ~= amount then
		return
	end
	self.stats[name] = (self.stats[name] or 0) + amount
end

-- Point d'entrée unique du score d'une livraison (appelé par le trafic quand
-- une voiture arrive). Une livraison vaut DeliveryScore, plus un bonus à la
-- première livraison vers chaque magasin et un bonus pour un trajet long.
function Session:onDelivery(house, destination)
	if self.over or type(destination) ~= "table" then
		return 0
	end

	local points = Config.Game.DeliveryScore
	local storeId = destination.id
	if storeId ~= nil and not self.servedStores[storeId] then
		self.servedStores[storeId] = true
		points += Config.Game.NewStoreBonus
	end
	if type(house) == "table" and house.x and house.y and destination.x and destination.y then
		local distance = math.abs(house.x - destination.x) + math.abs(house.y - destination.y)
		if distance >= Config.Game.LongTripCells then
			points += Config.Game.LongTripBonus
		end
	end

	self.score += points
	self.satisfaction = math.min(
		Config.Traffic.SatisfactionMax,
		self.satisfaction + Config.Game.DeliverySatisfaction
	)
	self:recordStat("deliveries", 1)
	return points
end

function Session:sendRoadState()
	if not self.player then
		return
	end
	local roadCells = {}
	for key in pairs(self.roads) do
		roadCells[#roadCells + 1] = key
	end
	local bridgeCells = {}
	for key in pairs(self.bridges) do
		bridgeCells[#bridgeCells + 1] = key
	end
	local buildingCells = {}
	for _, building in ipairs(self.buildingList) do
		buildingCells[#buildingCells + 1] = building.key
	end
	Remotes.get("RoadState"):FireClient(self.player, {
		roads = roadCells,
		bridges = bridgeCells,
		buildings = buildingCells,
		budget = self.budget,
		bridgesLeft = self.bridgesLeft,
		count = #roadCells,
		allowDiagonals = RoadConfig.AllowDiagonals,
		roadVersion = self.roadVersion,
	})
end

-- État envoyé au client (remote State). Champs : score, week, weekProgress,
-- day, dayOfWeek, dayProgress, month, monthName, monthWeek, monthProgress,
-- budget, bridges, roundabouts, satisfaction, speed, paused, awaitingChoice,
-- choice, over, houses, destinations, largeStores, cars, roadsBuilt.
-- Un envoi identique au précédent est ignoré : les appels nombreux (routes,
-- achats, voitures) ne génèrent pas de trafic inutile. update() l'envoie au
-- plus toutes les Time.StateInterval secondes réelles, plus à chaque changement
-- d'état (vitesse, pause, choix, fin de partie).
function Session:sendState()
	if not self.player then
		return
	end
	local roadCount = 0
	for _ in pairs(self.roads) do
		roadCount += 1
	end
	local payload = {
		score = self.score,
		week = self.week,
		weekProgress = clamp(self.weekTime / WEEK_DURATION, 0, 1),
		day = self.day,
		dayOfWeek = self.dayOfWeek,
		dayProgress = self.dayProgress,
		month = self.month,
		monthName = self.monthName,
		monthWeek = self.monthWeek,
		monthProgress = self.monthProgress,
		budget = self.budget,
		bridges = self.bridgesLeft,
		roundabouts = self.roundaboutsLeft,
		satisfaction = self.satisfaction,
		speed = self.speed,
		paused = self.paused,
		awaitingChoice = self.awaitingChoice,
		choice = self.choice,
		over = self.over,
		houses = #self.houses,
		destinations = #self.destinations,
		largeStores = self.storeSystem and self.storeSystem.largeCount or 0,
		cars = #self.cars,
		roadsBuilt = roadCount,
	}

	local last = self.lastState
	if last and sameFields(last, payload) then
		return
	end
	self.lastState = payload
	Remotes.get("State"):FireClient(self.player, payload)
end

-- Un pas de simulation : toutes les parties du jeu reçoivent le même dt.
-- Le choix de semaine est traité en fin de pas, une fois la semaine close.
function Session:simulateStep(step)
	local previousWeek = self.week
	self.elapsed += step
	self:updateClock()

	-- Magasins, demandes, surcharge et évolutions (StoreSystem).
	if self.storeSystem then
		self.storeSystem:update(step)
	end

	for _, house in ipairs(self.houses) do
		if not house.car then
			house.timer -= step
			if house.timer <= 0 then
				house.timer = 0
				self:trySpawnCar(house)
			end
		end
	end

	-- stuckSeconds est compté par le trafic, au moment où une voiture est
	-- réellement bloquée. Le compter aussi ici doublerait la statistique.
	for i = #self.cars, 1, -1 do
		local car = self.cars[i]
		if self:updateCar(car, step) then
			table.remove(self.cars, i)
			self:retireCar(car)
		end
	end

	self:updateSatisfaction(step)

	if self.week > previousWeek and not self.over then
		self:offerWeekChoice()
	end
end

function Session:start()
	if self.destroyed then
		return
	end

	-- Chaque start() repart d'une partie neuve : monde, stores, compteurs.
	teardownGame(self)
	resetGameState(self)
	buildGame(self)
	self.running = true

	Remotes.get("GameStarted"):FireClient(self.player, {
		mapId = self.mapId,
		origin = self.origin,
		size = self.size,
		tile = self.tile,
		weekDuration = WEEK_DURATION,
	})

	self:rebuildRoadTopology()
	self:updateBuildingConnections()
	self:sendState()
	self:sendRoadState()
	self.storeSystem:broadcast()
	self:toast("Reliez les maisons aux magasins de la même couleur. Les pastilles au-dessus d'un magasin sont ses demandes.")
end

function Session:update(dt)
	if self.destroyed then
		return
	end

	-- Même en pause, on peut effacer des routes : le rendu doit se mettre à
	-- jour sans attendre la reprise de la simulation. Sans changement (ni route
	-- ni bâtiment neuf), le flush ne fait rien.
	self:flushRoadRender()

	if not self.running or self.paused or self.over or self.awaitingChoice then
		return
	end
	if type(dt) ~= "number" or not (dt > 0) then
		return
	end

	-- Le temps simulé = temps réel × vitesse. Une grosse frame est découpée
	-- en pas de MaxSimStep pour que le trafic reste stable à vitesse 3.
	local remaining = dt * self.speed
	while remaining > FLOAT_EPSILON do
		local step = math.min(remaining, Time.MaxSimStep)
		remaining -= step
		self:simulateStep(step)
		if self.over or self.paused or self.awaitingChoice then
			break
		end
	end

	-- La cadence d'envoi se mesure en temps réel, pas en temps simulé : à
	-- vitesse 3 l'interface reste à 5 Hz.
	self.stateClock += dt
	if self.stateClock >= Time.StateInterval then
		self.stateClock = 0
		self:sendState()
	end
end

-- Vitesse de simulation : seulement 1, 2 ou 3 (entiers). Toute autre valeur
-- envoyée par le client est ignorée.
function Session:setSpeed(value: any)
	-- Forme positive : seul un nombre entier dans l'intervalle est accepté.
	if
		not self.over
		and type(value) == "number"
		and value == math.floor(value)
		and value >= Time.MinSpeed
		and value <= Time.MaxSpeed
		and value ~= self.speed
	then
		self.speed = value
		self:sendState()
	end
end

function Session:setPaused(value)
	if type(value) ~= "boolean" or self.destroyed then
		return
	end
	if self.over or self.awaitingChoice then
		return
	end
	if value == self.paused then
		return
	end
	self.paused = value
	self:sendState()
end

function Session:toast(text)
	if not self.player then
		return
	end
	Remotes.get("Toast"):FireClient(self.player, text)
end

-- Fin de partie, exactement une fois : le client reçoit le bilan complet.
-- Charge GameOver : mapId, score, best, week, durationSeconds (entier), day,
-- dayOfWeek, month, monthName, stats (copie : compteurs de STAT_NAMES et
-- autres), reason ("overload" : un magasin critique, "traffic" : voitures
-- bloquées, "satisfaction" : repli si aucune cause n'est enregistrée), et
-- overload, toujours présent en données simples : criticalCount, pressure,
-- seconds, storeId, colorIndex, colorName (nil si aucun magasin critique).
function Session:gameOver()
	if self.over then
		return
	end
	self.over = true
	self.running = false
	self.paused = false
	self.awaitingChoice = false
	self.choice = nil

	local best = self.score
	if self.player then
		best = Profile.submit(self.player, self.mapId, self.score)
	end

	local overload = nil
	if self.getOverloadSummary then
		overload = self:getOverloadSummary()
	end
	local reason = self.gameOverReason and self.gameOverReason.kind or "satisfaction"

	if self.player then
		Remotes.get("GameOver"):FireClient(self.player, {
			mapId = self.mapId,
			score = self.score,
			best = best,
			week = self.week,
			durationSeconds = math.floor(self.elapsed),
			day = self.day,
			dayOfWeek = self.dayOfWeek,
			month = self.month,
			monthName = self.monthName,
			stats = copyTable(self.stats),
			reason = reason,
			overload = overload,
		})
	end
	self:sendState()
end

-- Arrêt définitif (retour au lobby, joueur parti, nouvelle partie). Idempotent :
-- le monde, les stores et les tweens disparaissent, toutes les tables sont vidées.
function Session:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	teardownGame(self)
	resetGameState(self)
	self.running = false
	self.over = true
end

return Session
