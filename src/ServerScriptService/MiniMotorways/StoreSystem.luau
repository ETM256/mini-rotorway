--[[
	StoreSystem.luau
	Gestion serveur des magasins / destinations :
	  - apparition progressive selon le temps simulé
	  - placement semi-aléatoire validé (zones pondérées)
	  - génération et réservation des demandes (pins)
	  - évolution petit magasin -> grand magasin
	  - surcharge et compte à rebours
	  - synchronisation de l'état vers le client (StoreState)

	Session reste propriétaire des bâtiments, des routes et des voitures.
	StoreSystem réutilise Session:createBuilding et ne crée pas de second
	système parallèle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local StoreConfig = require(Shared.StoreConfig)

local StoreSystem = {}
StoreSystem.__index = StoreSystem

local COLORS = Config.HouseColors

local function randomRange(minValue, maxValue)
	return minValue + math.random() * (maxValue - minValue)
end

local function distanceSquared(ax, ay, bx, by)
	local dx = ax - bx
	local dy = ay - by
	return dx * dx + dy * dy
end

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

function StoreSystem.new(session)
	local self = setmetatable({}, StoreSystem)
	self.session = session
	-- Alias volontaire : Session.destinations est la liste officielle des
	-- magasins utilisée par les maisons, les voitures et l'état du jeu.
	self.stores = session.destinations
	self.elapsed = 0
	self.spawnClock = 0
	self.houseClock = StoreConfig.Houses.FirstSpawnDelay
	self.largeCount = 0
	self.colorBag = {}
	self.dirty = false
	self.broadcastClock = 0
	return self
end

function StoreSystem:seed()
	local spawned = self:spawnStore(true)
	self.spawnClock = spawned and self:nextSpawnInterval() or 1
	self.houseClock = StoreConfig.Houses.FirstSpawnDelay
	self.dirty = true
end

function StoreSystem:nextSpawnInterval()
	for _, tier in ipairs(StoreConfig.Spawn.Tiers) do
		if self.elapsed < tier.untilTime then
			return randomRange(tier.minInterval, tier.maxInterval)
		end
	end
	local last = StoreConfig.Spawn.Tiers[#StoreConfig.Spawn.Tiers]
	return randomRange(last.minInterval, last.maxInterval)
end

function StoreSystem:refillColorBag()
	local used = {}
	for _, store in ipairs(self.stores) do
		used[store.colorIndex] = true
	end

	local bag = {}
	for index = 1, #COLORS do
		if not used[index] then
			table.insert(bag, index)
		end
	end
	shuffle(bag)
	self.colorBag = bag
end

function StoreSystem:pickColor()
	if #self.colorBag == 0 then
		self:refillColorBag()
	end
	if #self.colorBag == 0 then
		-- La palette est épuisée. On réutilise une couleur : les maisons
		-- choisiront alors le magasin de même couleur le plus proche.
		return math.random(1, #COLORS)
	end
	return table.remove(self.colorBag, math.random(1, #self.colorBag))
end

function StoreSystem:pickZone()
	local total = 0
	for _, zone in ipairs(StoreConfig.Spawn.Zones) do
		total += zone.weight
	end

	local pick = math.random() * total
	for _, zone in ipairs(StoreConfig.Spawn.Zones) do
		pick -= zone.weight
		if pick <= 0 then
			return zone
		end
	end
	return StoreConfig.Spawn.Zones[#StoreConfig.Spawn.Zones]
end

function StoreSystem:isStoreSpotValid(x, y, minStoreDistance)
	if not self.session:isFreeCell(x, y) then
		return false
	end
	if self.session:buildableNeighborCount(x, y) < StoreConfig.Spawn.MinBuildableNeighbors then
		return false
	end

	local limit = (minStoreDistance or StoreConfig.Spawn.MinStoreDistance) ^ 2
	for _, store in ipairs(self.stores) do
		if distanceSquared(x, y, store.x, store.y) < limit then
			return false
		end
	end

	local buildingLimit = StoreConfig.Spawn.MinBuildingDistance ^ 2
	for _, building in ipairs(self.session.buildingList) do
		if distanceSquared(x, y, building.x, building.y) < buildingLimit then
			return false
		end
	end
	return true
end

function StoreSystem:findStoreSpot()
	local size = self.session.size
	local center = (size - 1) * 0.5
	local half = size * 0.5

	for _ = 1, StoreConfig.Spawn.MaxAttempts do
		local zone = self:pickZone()
		local radius = randomRange(zone.minRadius, zone.maxRadius) * half
		local angle = math.random() * math.pi * 2
		local x = math.floor(center + math.cos(angle) * radius + 0.5)
		local y = math.floor(center + math.sin(angle) * radius + 0.5)
		if x >= 1 and y >= 1 and x <= size - 2 and y <= size - 2
			and self:isStoreSpotValid(x, y)
		then
			return x, y
		end
	end

	-- Repli déterministe : on parcourt la grille et on choisit un emplacement
	-- encore assez éloigné des autres magasins. Cela évite les boucles
	-- infinies quand les zones pondérées sont toutes occupées.
	local candidates = {}
	for x = 1, size - 2 do
		for y = 1, size - 2 do
			if self:isStoreSpotValid(x, y) then
				table.insert(candidates, { x, y })
			end
		end
	end
	if #candidates > 0 then
		local pick = candidates[math.random(1, #candidates)]
		return pick[1], pick[2]
	end
	return nil
end

function StoreSystem:isHouseSpotValid(x, y)
	if not self.session:isFreeCell(x, y) then
		return false
	end
	if self.session:buildableNeighborCount(x, y) < StoreConfig.Houses.MinBuildableNeighbors then
		return false
	end

	local limit = StoreConfig.Houses.MinDistanceFromBuilding ^ 2
	for _, building in ipairs(self.session.buildingList) do
		if distanceSquared(x, y, building.x, building.y) < limit then
			return false
		end
	end
	return true
end

function StoreSystem:findHouseSpot(store)
	local size = self.session.size
	for _ = 1, 500 do
		local angle = math.random() * math.pi * 2
		local radius = randomRange(
			StoreConfig.Houses.MinDistanceFromStore,
			StoreConfig.Houses.MaxDistanceFromStore
		)
		local x = math.floor(store.x + math.cos(angle) * radius + 0.5)
		local y = math.floor(store.y + math.sin(angle) * radius + 0.5)
		if x >= 1 and y >= 1 and x <= size - 2 and y <= size - 2
			and self:isHouseSpotValid(x, y)
		then
			return x, y
		end
	end

	return self.session:findBuildingSpot(
		{ store.x, store.y },
		StoreConfig.Houses.MinDistanceFromStore
	)
end

function StoreSystem:createHouse(store, x, y)
	local house = self.session:createBuilding("house", x, y, store.colorIndex)
	house.dest = store
	house.homeStore = store
	house.timer = Config.Game.FirstSpawnDelay + math.random() * 4
	return house
end

function StoreSystem:spawnHousesForStore(store, count)
	for _ = 1, count do
		if #self.session.houses >= StoreConfig.Houses.MaxHouses then
			break
		end
		local x, y = self:findHouseSpot(store)
		if not x then
			break
		end
		self:createHouse(store, x, y)
	end
end

function StoreSystem:countHousesForStore(store)
	local count = 0
	for _, house in ipairs(self.session.houses) do
		if house.homeStore == store or (not house.homeStore and house.colorIndex == store.colorIndex) then
			count += 1
		end
	end
	return count
end

function StoreSystem:spawnHouse()
	if #self.stores == 0 or #self.session.houses >= StoreConfig.Houses.MaxHouses then
		return false
	end

	local candidates = {}
	for _, store in ipairs(self.stores) do
		if self:countHousesForStore(store) < StoreConfig.Houses.MaxHousesPerStore then
			table.insert(candidates, store)
		end
	end
	if #candidates == 0 then
		return false
	end

	local store = candidates[math.random(1, #candidates)]
	local x, y = self:findHouseSpot(store)
	if not x then
		return false
	end
	self:createHouse(store, x, y)
	return true
end

function StoreSystem:markOverload(store)
	if not store.overloaded then
		store.overloaded = true
		store.overloadClock = StoreConfig.Demand.OverloadGrace
		self.dirty = true
	end
end

function StoreSystem:clearOverload(store)
	if store.overloaded or store.critical then
		store.overloaded = false
		store.critical = false
		store.overloadClock = StoreConfig.Demand.OverloadGrace
		self.dirty = true
	end
end

function StoreSystem:addDemand(store)
	local demandIds = store.demandIds
	if #demandIds >= store.capacity then
		self:markOverload(store)
		return false
	end

	store.demandSeq += 1
	local demandId = tostring(store.id) .. "-" .. tostring(store.demandSeq)
	table.insert(demandIds, demandId)
	store.demands = #demandIds
	if store.demands >= store.capacity then
		self:markOverload(store)
	end
	self.dirty = true
	return true
end

function StoreSystem:claimDemand(store)
	if not store then
		return nil
	end
	for _, demandId in ipairs(store.demandIds) do
		if not store.reservedIds[demandId] then
			store.reservedIds[demandId] = true
			store.reserved = (store.reserved or 0) + 1
			return demandId
		end
	end
	return nil
end

function StoreSystem:releaseClaim(store, demandId)
	if not store then
		return false
	end
	if demandId and store.reservedIds[demandId] then
		store.reservedIds[demandId] = nil
		store.reserved = math.max(0, (store.reserved or 0) - 1)
		self.dirty = true
		return true
	end
	return false
end

function StoreSystem:consumeDemand(store, demandId)
	if not store or not demandId then
		return false
	end

	local index = table.find(store.demandIds, demandId)
	if not index then
		-- La demande a déjà été servie : on libère seulement la réservation.
		self:releaseClaim(store, demandId)
		return false
	end

	table.remove(store.demandIds, index)
	if store.reservedIds[demandId] then
		store.reservedIds[demandId] = nil
		store.reserved = math.max(0, (store.reserved or 0) - 1)
	end
	store.demands = #store.demandIds
	store.delivered = (store.delivered or 0) + 1
	if store.demands < store.capacity then
		self:clearOverload(store)
	end
	self.dirty = true
	return true
end

function StoreSystem:findDestination(house, requireAvailable)
	local best = nil
	local bestDistance = math.huge
	for _, store in ipairs(self.stores) do
		if store.colorIndex == house.colorIndex then
			local available = (store.demands or 0) - (store.reserved or 0)
			if not requireAvailable or available > 0 then
				local distance = math.abs(store.x - house.x) + math.abs(store.y - house.y)
				if distance < bestDistance then
					best = store
					bestDistance = distance
				end
			end
		end
	end
	return best
end

function StoreSystem:demandInterval(store)
	local base = store.storeType == "large"
		and StoreConfig.Demand.LargeInterval
		or StoreConfig.Demand.SmallInterval
	local ramp = math.clamp(self.elapsed / StoreConfig.Demand.RampDuration, 0, 1)
	local factor = 1 - ramp * (1 - StoreConfig.Demand.RampMinMultiplier)
	return math.max(
		StoreConfig.Demand.MinInterval,
		base * factor * randomRange(0.90, 1.10)
	)
end

function StoreSystem:beginEvolution(store)
	if store.evolving then
		return
	end
	store.evolving = true
	store.evolveTimer = StoreConfig.Evolution.AnimationDuration
	self.dirty = true
	self.session:replaceStoreModel(store)
end

function StoreSystem:finishEvolution(store)
	store.evolving = false
	store.storeType = "large"
	store.capacity = StoreConfig.Demand.LargeCapacity
	if (store.demands or 0) < store.capacity then
		self:clearOverload(store)
	end
	self.largeCount += 1
	self.dirty = true
end

function StoreSystem:updateStore(store, dt)
	store.age = (store.age or 0) + dt

	if store.evolving then
		store.evolveTimer -= dt
		if store.evolveTimer <= 0 then
			self:finishEvolution(store)
		end
		return
	end

	store.demandClock -= dt
	if store.demandClock <= 0 then
		store.demandClock = self:demandInterval(store)
		if (store.demands or 0) < store.capacity then
			self:addDemand(store)
		else
			self:markOverload(store)
		end
	end

	if store.overloaded then
		store.overloadClock -= dt
		if store.overloadClock <= 0 and not store.critical then
			store.critical = true
		end
		-- Le compte à rebours doit être visible et se rafraîchir côté client.
		self.dirty = true
	end

	if store.storeType == "small" then
		store.evolveClock -= dt
		if store.evolveClock <= 0 then
			local canEvolve = self.largeCount < StoreConfig.Evolution.MaxLargeStores
				and store.age >= StoreConfig.Evolution.MinAge
				and (store.delivered or 0) >= StoreConfig.Evolution.MinDeliveries
			if canEvolve and math.random() < StoreConfig.Evolution.Chance then
				self:beginEvolution(store)
			else
				store.evolveClock = randomRange(
					StoreConfig.Evolution.CheckInterval * 0.7,
					StoreConfig.Evolution.CheckInterval * 1.3
				)
			end
		end
	end
end

function StoreSystem:spawnStore(initial)
	if #self.stores >= StoreConfig.Spawn.MaxStores then
		return false
	end

	local x, y = self:findStoreSpot()
	if not x then
		return false
	end
	local colorIndex = self:pickColor()

	local store = self.session:createBuilding("store", x, y, colorIndex, "small")
	store.storeType = "small"
	store.capacity = StoreConfig.Demand.SmallCapacity
	store.demandIds = {}
	store.reservedIds = {}
	store.demandSeq = 0
	store.demands = 0
	store.reserved = 0
	store.delivered = 0
	store.age = 0
	store.demandClock = randomRange(
		StoreConfig.Demand.FirstDelayMin,
		StoreConfig.Demand.FirstDelayMax
	)
	store.overloaded = false
	store.critical = false
	store.overloadClock = StoreConfig.Demand.OverloadGrace
	store.evolving = false
	store.evolveTimer = 0
	store.evolveClock = StoreConfig.Evolution.MinAge
		+ randomRange(0, StoreConfig.Evolution.CheckInterval)

	self:spawnHousesForStore(
		store,
		initial and StoreConfig.Houses.StartHouses or StoreConfig.Houses.HousesPerStore
	)

	self.dirty = true
	return true
end

function StoreSystem:getOverloadDrain()
	local drain = 0
	for _, store in ipairs(self.stores) do
		if store.critical then
			drain += StoreConfig.Demand.OverloadDrainPerSecond
		end
	end
	return drain
end

function StoreSystem:snapshot()
	local stores = {}
	for _, store in ipairs(self.stores) do
		local demandIds = {}
		for index, demandId in ipairs(store.demandIds) do
			demandIds[index] = demandId
		end
		table.insert(stores, {
			id = store.id,
			x = store.x,
			y = store.y,
			colorIndex = store.colorIndex,
			storeType = store.storeType or "small",
			demands = #demandIds,
			demandIds = demandIds,
			capacity = store.capacity or StoreConfig.Demand.SmallCapacity,
			overloaded = store.overloaded == true,
			critical = store.critical == true,
			evolving = store.evolving == true,
			overloadClock = math.max(0, store.overloadClock or 0),
		})
	end
	return { stores = stores }
end

function StoreSystem:broadcast()
	if not self.session.player then
		return
	end
	Remotes.get("StoreState"):FireClient(self.session.player, self:snapshot())
end

function StoreSystem:update(dt)
	if self.session.over then
		return
	end

	self.elapsed += dt

	self.spawnClock -= dt
	if self.spawnClock <= 0 then
		if #self.stores < StoreConfig.Spawn.MaxStores and self:spawnStore(false) then
			self.spawnClock = self:nextSpawnInterval()
		else
			self.spawnClock = StoreConfig.Spawn.RetryDelay
		end
	end

	self.houseClock -= dt
	if self.houseClock <= 0 then
		if #self.session.houses < StoreConfig.Houses.MaxHouses then
			self:spawnHouse()
		end
		self.houseClock = StoreConfig.Houses.SpawnInterval
	end

	for _, store in ipairs(self.stores) do
		self:updateStore(store, dt)
	end

	self.broadcastClock += dt
	if (self.dirty and self.broadcastClock >= 0.2) or self.broadcastClock >= 1.5 then
		self.dirty = false
		self.broadcastClock = 0
		self:broadcast()
	end
end

function StoreSystem:destroy()
	self.stores = {}
	self.colorBag = {}
	self.dirty = false
end

return StoreSystem
