--[[
	Session.luau
	Une partie = une ville. Tout est simulé côté serveur :
	  - génération des maisons / destinations
	  - routes et ponts (budget)
	  - trajets des voitures (A*)
	  - jauges de score, semaine, patience
	Le client ne fait qu'envoyer des demandes de routes et afficher l'état.
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
require(script.Parent.SessionRibbons)(Session)
require(script.Parent.SessionTraffic)(Session)
require(script.Parent.SessionProgress)(Session)

function Session.new(player, mapId, worldIndex)
	local map = Maps.getById(mapId) or Maps.all()[1]

	local self = setmetatable({}, Session)
	self.player = player
	self.mapId = map.id
	self.map = map
	self.worldIndex = worldIndex
	self.origin = Vector3.new(worldIndex * Config.World.OriginSpacing, Config.World.BaseY, 0)
	self.size = Config.Grid.Size
	self.tile = Config.Grid.TileSize

	self.roads = {}
	self.bridges = {}
	self.roadParts = {}
	self.roadRibbons = {}
	self.roadRibbonPaths = {}
	self.ribbonEdges = {}
	self.lastRibbonCell = nil
	self.roadRibbonsDirty = false
	self.roundaboutParts = {}
	self.intersections = {}
	self.intersectionReservations = {}
	self.buildings = {}
	self.buildingList = {}
	self.houses = {}
	self.destinations = {}
	self.cars = {}

	self.score = 0
	self.week = 1
	self.weekTime = 0
	self.satisfaction = Config.Traffic.SatisfactionStart
	self.budget = Config.Roads.StartBudget
	self.bridgesLeft = Config.Roads.StartBridges
	self.roundaboutsLeft = Config.Roads.StartRoundabouts
	self.speed = 1

	self.roadVersion = 0
	self.running = false
	self.paused = false
	self.over = false
	self.awaitingChoice = false
	self.choice = nil

	self.stateClock = 0
	self.nextBuildingId = 1

	self.world = WorldBuilder.build(self)

	-- StoreSystem réutilise les bâtiments, les maisons et les voitures de
	-- Session : un seul système, pas de doublon.
	self.storeSystem = StoreSystem.new(self)
	self.storeSystem:seed()

	return self
end

function Session:setSpeed(value)
	value = tonumber(value) or 1
	self.speed = clamp(math.floor(value), 1, 3)
	self:sendState()
end

function Session:update(dt)
	-- Même en pause, on peut effacer des routes : le ruban visuel doit se
	-- mettre à jour sans attendre la reprise de la simulation.
	if self.roadRibbonsDirty then
		self.roadRibbonsDirty = false
		self:rebuildRoadRibbons()
	end

	if not self.running or self.paused or self.over or self.awaitingChoice then
		return
	end

	dt = dt * self.speed

	self.weekTime += dt
	if self.weekTime >= Config.Game.WeekDuration then
		self.weekTime -= Config.Game.WeekDuration
		self.week += 1
		self:offerWeekChoice()
		return
	end

	-- Apparition des magasins, génération des demandes, surcharge,
	-- évolution et ajout périodique de maisons. Le StoreSystem utilise le dt
	-- simulé, donc la vitesse de jeu accélère aussi son rythme.
	if self.storeSystem then
		self.storeSystem:update(dt)
	end

	for _, house in ipairs(self.houses) do
		if not house.car then
			house.timer -= dt
			if house.timer <= 0 then
				house.timer = 0
				self:trySpawnCar(house)
			end
		end
	end

	for i = #self.cars, 1, -1 do
		local car = self.cars[i]
		if self:updateCar(car, dt) then
			table.remove(self.cars, i)
			self:retireCar(car)
		end
	end

	self:updateSatisfaction(dt)

	self.stateClock += dt
	if self.stateClock >= 0.2 then
		self.stateClock = 0
		self:sendState()
	end
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

function Session:sendState()
	local roadCount = 0
	for _ in pairs(self.roads) do
		roadCount += 1
	end
	Remotes.get("State"):FireClient(self.player, {
		score = self.score,
		week = self.week,
		weekProgress = clamp(self.weekTime / Config.Game.WeekDuration, 0, 1),
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
	})
end

function Session:start()
	self.running = true
	self.paused = false
	self.over = false
	self.awaitingChoice = false
	self.choice = nil
	self.speed = 1

	Remotes.get("GameStarted"):FireClient(self.player, {
		mapId = self.mapId,
		origin = self.origin,
		size = self.size,
		tile = self.tile,
		weekDuration = Config.Game.WeekDuration,
	})

	self:rebuildRoadTopology()
	self:updateBuildingConnections()
	self:sendState()
	self:sendRoadState()
	if self.storeSystem then
		self.storeSystem:broadcast()
	end
	self:toast("Reliez les maisons aux magasins de la même couleur. Les pastilles au-dessus d'un magasin sont ses demandes.")
end

function Session:setPaused(value)
	if self.over or self.awaitingChoice then
		return
	end
	self.paused = value == true
	self:sendState()
end

function Session:toast(text)
	Remotes.get("Toast"):FireClient(self.player, text)
end

function Session:gameOver()
	if self.over then
		return
	end
	self.over = true
	self.running = false
	self.paused = false
	self.awaitingChoice = false
	self.choice = nil

	local best = Profile.submit(self.player, self.mapId, self.score)
	Remotes.get("GameOver"):FireClient(self.player, {
		mapId = self.mapId,
		score = self.score,
		best = best,
		week = self.week,
	})
	self:sendState()
end

function Session:destroy()
	self.running = false
	self.over = true
	self.paused = false
	if self.storeSystem then
		self.storeSystem:destroy()
		self.storeSystem = nil
	end
	if self.world and self.world.folder then
		self.world.folder:Destroy()
	end
	self.world = nil
	self.cars = {}
	self.houses = {}
	self.destinations = {}
	self.buildings = {}
	self.buildingList = {}
	self.roundaboutParts = {}
	self.intersections = {}
	self.intersectionReservations = {}
	self.roadRibbons = {}
	self.roadRibbonPaths = {}
	self.ribbonEdges = {}
	self.lastRibbonCell = nil
	self.choice = nil
end

return Session
