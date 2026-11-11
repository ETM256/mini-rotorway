--[[
	StoreSystem.luau
	Gestion serveur des magasins / destinations :
	  - apparition progressive selon le temps simulé, difficulté lissée
	  - placement semi-aléatoire validé (zones pondérées, espacement, arbres)
	  - maisons en petits groupes autour de leur magasin
	  - génération et réservation des demandes (pins)
	  - évolution petit magasin -> grand magasin
	  - surcharge et compte à rebours
	  - synchronisation de l'état vers le client (StoreState)

	Session reste propriétaire des bâtiments, des routes et des voitures.
	StoreSystem réutilise Session:createBuilding et ne crée pas de second
	système parallèle.

	Aléa : self.rng reprend session.random s'il existe (même interface que
	math.random), ce qui rend les tests reproductibles sans toucher au code.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local StoreConfig = require(Shared.StoreConfig)

local StoreSystem = {}
StoreSystem.__index = StoreSystem

local COLORS = Config.HouseColors
-- Un magasin reçoit une couleur unique : il ne peut pas y en avoir plus que
-- de couleurs dans la palette.
local MAX_STORES = math.min(StoreConfig.Spawn.MaxStores, #COLORS)

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function distanceSquared(ax, ay, bx, by)
	local dx = ax - bx
	local dy = ay - by
	return dx * dx + dy * dy
end

-- Vrai si (x, y) est à au moins minDistance de chaque élément de la liste.
local function isFarEnough(list, x, y, minDistance)
	local limit = minDistance * minDistance
	for _, item in ipairs(list) do
		if distanceSquared(x, y, item.x, item.y) < limit then
			return false
		end
	end
	return true
end

-- Une maison reste dans l'anneau autour de son magasin : assez loin pour ne
-- pas le toucher, assez près pour que le trajet reste court.
local function isInHouseRing(store, x, y)
	local squared = distanceSquared(x, y, store.x, store.y)
	return squared >= StoreConfig.Houses.MinDistanceFromStore ^ 2
		and squared <= StoreConfig.Houses.MaxDistanceFromStore ^ 2
end

-- Vrai si (x, y) tombe sur la droite passant par deux maisons du même magasin :
-- une rangée droite ne ressemble pas à un petit groupe irrégulier.
local function alignsWithHouses(houses, x, y)
	for i = 1, #houses do
		for j = i + 1, #houses do
			local a, b = houses[i], houses[j]
			if (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x) == 0 then
				return true
			end
		end
	end
	return false
end

-- Intervalle (min, max) des magasins suivants à l'instant `elapsed`.
-- Fonction pure et continue : aucun saut au passage d'un palier. Entre
-- deux paliers, chaque borne glisse linéairement vers celle du palier suivant.
function StoreSystem.spawnIntervalRange(elapsed)
	local tiers = StoreConfig.Spawn.Tiers
	local start = 0
	for index, tier in ipairs(tiers) do
		if index == #tiers or elapsed < tier.untilTime then
			local nextTier = tiers[index + 1] or tier
			local alpha = 0
			if index < #tiers then
				alpha = math.clamp((elapsed - start) / (tier.untilTime - start), 0, 1)
			end
			return lerp(tier.minInterval, nextTier.minInterval, alpha),
				lerp(tier.maxInterval, nextTier.maxInterval, alpha)
		end
		start = tier.untilTime
	end
	local last = tiers[#tiers]
	return last.minInterval, last.maxInterval
end

-- Facteur appliqué aux intervalles de demandes : 1 au début, puis une baisse
-- linéaire jusqu'à RampMinMultiplier en RampDuration secondes simulées.
function StoreSystem.demandRampFactor(elapsed)
	local ramp = math.clamp(elapsed / StoreConfig.Demand.RampDuration, 0, 1)
	return 1 - ramp * (1 - StoreConfig.Demand.RampMinMultiplier)
end

function StoreSystem.new(session)
	local self = setmetatable({}, StoreSystem)
	self.session = session
	-- Alias volontaire : Session.destinations est la liste officielle des
	-- magasins utilisée par les maisons, les voitures et l'état du jeu.
	self.stores = session.destinations
	self.rng = session.random or math
	self.spawnClock = 0
	self.houseClock = StoreConfig.Houses.FirstSpawnDelay
	-- largeCount compte les grands magasins finis ; evolvingCount ceux en
	-- cours d'évolution. Les deux comptent pour la limite de grands magasins.
	self.largeCount = 0
	self.evolvingCount = 0
	self.dirty = false
	self.broadcastClock = 0
	return self
end

function StoreSystem:randomRange(minValue, maxValue)
	return minValue + self.rng.random() * (maxValue - minValue)
end

-- Statistiques de partie : ignorées tant que Session ne les enregistre pas.
function StoreSystem:recordStat(name, amount)
	if self.session.recordStat then
		self.session:recordStat(name, amount)
	end
end

function StoreSystem:seed()
	local spawned = 0
	for _ = 1, StoreConfig.Spawn.StartStores do
		if not self:spawnStore(true) then
			break
		end
		spawned += 1
	end
	self.spawnClock = spawned > 0 and self:nextSpawnInterval() or StoreConfig.Spawn.RetryDelay
	self.houseClock = StoreConfig.Houses.FirstSpawnDelay
	self.dirty = true
end

-- Horloge unique : le temps simulé appartient à Session (session.elapsed).
-- Une session sans horloge (fausse session de test) compte pour 0.
local function simulatedTime(session)
	return session.elapsed or 0
end

function StoreSystem:nextSpawnInterval()
	local minInterval, maxInterval = StoreSystem.spawnIntervalRange(simulatedTime(self.session))
	return self:randomRange(minInterval, maxInterval)
end

-- Couleur libre tirée au hasard : chaque magasin garde une couleur unique.
function StoreSystem:pickColor()
	local used = {}
	for _, store in ipairs(self.stores) do
		used[store.colorIndex] = true
	end

	local free = {}
	for index = 1, #COLORS do
		if not used[index] then
			table.insert(free, index)
		end
	end
	if #free == 0 then
		return nil
	end
	return free[self.rng.random(1, #free)]
end

function StoreSystem:pickZone()
	local zones = StoreConfig.Spawn.Zones
	local total = 0
	for _, zone in ipairs(zones) do
		total += zone.weight
	end

	local pick = self.rng.random() * total
	for _, zone in ipairs(zones) do
		pick -= zone.weight
		if pick <= 0 then
			return zone
		end
	end
	return zones[#zones]
end

-- Vrai si un arbre occupe la case ou l'une de ses voisines. Un bâtiment
-- déborde de sa case (1,3 à 1,6 case de large) : il ne doit pas recouvrir
-- un arbre posé dans une case voisine.
function StoreSystem:isNearTree(x, y)
	local treeCells = self.session.world and self.session.world.treeCells
	if not treeCells then
		return false
	end
	for dx = -1, 1 do
		for dy = -1, 1 do
			if treeCells[(x + dx) .. ":" .. (y + dy)] then
				return true
			end
		end
	end
	return false
end

-- Règles communes aux magasins et aux maisons : case libre (ni eau, ni route,
-- ni bâtiment), à une case du bord de la carte au moins, hors arbres, et
-- entourée d'assez de cases constructibles.
function StoreSystem:isBuildableSpot(x, y, minBuildableNeighbors)
	local size = self.session.size
	if x < 1 or y < 1 or x > size - 2 or y > size - 2 then
		return false
	end
	if not self.session:isFreeCell(x, y) or self:isNearTree(x, y) then
		return false
	end
	return self.session:buildableNeighborCount(x, y) >= minBuildableNeighbors
end

function StoreSystem:isStoreSpotValid(x, y)
	if not self:isBuildableSpot(x, y, StoreConfig.Spawn.MinBuildableNeighbors) then
		return false
	end
	return isFarEnough(self.stores, x, y, StoreConfig.Spawn.MinStoreDistance)
		and isFarEnough(self.session.buildingList, x, y, StoreConfig.Spawn.MinBuildingDistance)
end

-- Repli déterministe : on tire au hasard parmi toutes les cases valides de la
-- zone. Utilisé seulement quand l'échantillonnage aléatoire n'a rien trouvé.
function StoreSystem:pickValidCell(isValid, minX, minY, maxX, maxY)
	local candidates = {}
	for x = math.max(1, minX), maxX do
		for y = math.max(1, minY), maxY do
			if isValid(x, y) then
				table.insert(candidates, { x, y })
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	local pick = candidates[self.rng.random(1, #candidates)]
	return pick[1], pick[2]
end

function StoreSystem:findStoreSpot()
	local size = self.session.size
	local center = (size - 1) * 0.5
	local half = size * 0.5

	for _ = 1, StoreConfig.Spawn.MaxAttempts do
		local zone = self:pickZone()
		local radius = self:randomRange(zone.minRadius, zone.maxRadius) * half
		local angle = self.rng.random() * math.pi * 2
		local x = math.floor(center + math.cos(angle) * radius + 0.5)
		local y = math.floor(center + math.sin(angle) * radius + 0.5)
		if self:isStoreSpotValid(x, y) then
			return x, y
		end
	end

	-- Les zones pondérées sont peut-être toutes occupées : on cherche partout.
	return self:pickValidCell(function(x, y)
		return self:isStoreSpotValid(x, y)
	end, 1, 1, size - 2, size - 2)
end

function StoreSystem:isHouseSpotValid(x, y)
	return self:isBuildableSpot(x, y, StoreConfig.Houses.MinBuildableNeighbors)
		and isFarEnough(self.session.buildingList, x, y, StoreConfig.Houses.MinDistanceFromBuilding)
end

-- Une maison se pose autour du magasin, ou près d'une maison déjà présente
-- (groupe). L'espacement et l'anneau sont toujours imposés : pas de maisons
-- collées, et la disposition reste irrégulière.
function StoreSystem:findHouseSpot(store)
	local houses = store.houses
	local config = StoreConfig.Houses
	local function isValid(x, y)
		return isInHouseRing(store, x, y)
			and not alignsWithHouses(houses, x, y)
			and self:isHouseSpotValid(x, y)
	end

	for _ = 1, config.MaxAttempts do
		local anchorX, anchorY = store.x, store.y
		local minRadius, maxRadius = config.MinDistanceFromStore, config.MaxDistanceFromStore
		if #houses > 0 and self.rng.random() < config.ClusterChance then
			local anchor = houses[self.rng.random(1, #houses)]
			anchorX, anchorY = anchor.x, anchor.y
			minRadius, maxRadius = config.ClusterMinDistance, config.ClusterMaxDistance
		end
		local angle = self.rng.random() * math.pi * 2
		local radius = self:randomRange(minRadius, maxRadius)
		local x = math.floor(anchorX + math.cos(angle) * radius + 0.5)
		local y = math.floor(anchorY + math.sin(angle) * radius + 0.5)
		if isValid(x, y) then
			return x, y
		end
	end

	local reach = math.ceil(config.MaxDistanceFromStore)
	return self:pickValidCell(isValid, store.x - reach, store.y - reach, store.x + reach, store.y + reach)
end

function StoreSystem:createHouse(store, x, y)
	local house = self.session:createBuilding("house", x, y, store.colorIndex)
	house.dest = store
	house.homeStore = store
	house.timer = Config.Game.FirstSpawnDelay + self.rng.random() * StoreConfig.Houses.FirstTripJitter
	table.insert(store.houses, house)
	self:recordStat("housesSpawned", 1)
	return house
end

function StoreSystem:spawnHousesForStore(store, count)
	for _ = 1, count do
		if #self.session.houses >= StoreConfig.Houses.MaxHouses
			or #store.houses >= StoreConfig.Houses.MaxHousesPerStore
		then
			break
		end
		local x, y = self:findHouseSpot(store)
		if not x then
			break
		end
		self:createHouse(store, x, y)
	end
end

-- Ajoute une maison à un magasin qui a encore de la place. Si l'emplacement
-- manque près d'un magasin, on essaie les autres dans un ordre aléatoire.
function StoreSystem:spawnHouse()
	if #self.session.houses >= StoreConfig.Houses.MaxHouses then
		return false
	end

	local candidates = {}
	for _, store in ipairs(self.stores) do
		if #store.houses < StoreConfig.Houses.MaxHousesPerStore then
			table.insert(candidates, store)
		end
	end

	while #candidates > 0 do
		local store = table.remove(candidates, self.rng.random(1, #candidates))
		local x, y = self:findHouseSpot(store)
		if x then
			self:createHouse(store, x, y)
			return true
		end
	end
	return false
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

-- Ajoute une demande. Les demandes réservées par une voiture comptent aussi
-- dans la capacité : elles restent affichées jusqu'à la livraison.
function StoreSystem:addDemand(store)
	local demandIds = store.demandIds
	if #demandIds >= store.capacity then
		self:markOverload(store)
		return false
	end

	store.demandSeq += 1
	table.insert(demandIds, tostring(store.id) .. "-" .. tostring(store.demandSeq))
	store.demands = #demandIds
	if store.demands >= store.capacity then
		self:markOverload(store)
	end
	self.dirty = true
	self:recordStat("demandsCreated", 1)
	return true
end

function StoreSystem:claimDemand(store)
	if not store then
		return nil
	end
	for _, demandId in ipairs(store.demandIds) do
		if not store.reservedIds[demandId] then
			store.reservedIds[demandId] = true
			store.reserved += 1
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
		store.reserved = math.max(0, store.reserved - 1)
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
		store.reserved = math.max(0, store.reserved - 1)
	end
	store.demands = #store.demandIds
	store.delivered += 1
	-- Toute livraison libère la place : le compte à rebours repart de zéro.
	if store.demands < store.capacity then
		self:clearOverload(store)
	end
	self.dirty = true
	self:recordStat("demandsServed", 1)
	return true
end

-- Magasin le plus proche de même couleur. isReachable(store) (optionnel) écarte
-- les magasins sans trajet tant qu'un autre candidat reste ; sans candidat
-- atteignable, on garde le plus proche pour que la voiture réessaie.
function StoreSystem:findDestination(house, requireAvailable, isReachable)
	local best, bestDistance = nil, math.huge
	local fallback, fallbackDistance = nil, math.huge
	for _, store in ipairs(self.stores) do
		if store.colorIndex == house.colorIndex then
			local available = store.demands - store.reserved
			if not requireAvailable or available > 0 then
				local distance = math.abs(store.x - house.x) + math.abs(store.y - house.y)
				if distance < fallbackDistance then
					fallback = store
					fallbackDistance = distance
				end
				if distance < bestDistance and (not isReachable or isReachable(store)) then
					best = store
					bestDistance = distance
				end
			end
		end
	end
	return best or fallback
end

function StoreSystem:demandInterval(store)
	local base = store.storeType == "large"
		and StoreConfig.Demand.LargeInterval
		or StoreConfig.Demand.SmallInterval
	local jitter = StoreConfig.Demand.Jitter
	return math.max(
		StoreConfig.Demand.MinInterval,
		base * StoreSystem.demandRampFactor(simulatedTime(self.session)) * self:randomRange(1 - jitter, 1 + jitter)
	)
end

-- Un petit magasin peut devenir grand tant que la limite n'est pas atteinte,
-- en comptant aussi les évolutions déjà lancées.
function StoreSystem:canEvolve(store)
	return store.storeType == "small"
		and not store.evolving
		and store.age >= StoreConfig.Evolution.MinAge
		and store.delivered >= StoreConfig.Evolution.MinDeliveries
		and self.largeCount + self.evolvingCount < StoreConfig.Evolution.MaxLargeStores
end

function StoreSystem:beginEvolution(store)
	if store.evolving then
		return
	end
	store.evolving = true
	store.evolveTimer = StoreConfig.Evolution.AnimationDuration
	self.evolvingCount += 1
	self.dirty = true
	self.session:replaceStoreModel(store)
end

function StoreSystem:finishEvolution(store)
	store.evolving = false
	store.storeType = "large"
	store.capacity = StoreConfig.Demand.LargeCapacity
	self.evolvingCount -= 1
	self.largeCount += 1
	if store.demands < store.capacity then
		self:clearOverload(store)
	end
	self.dirty = true
end

function StoreSystem:updateStore(store, dt)
	store.age += dt

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
		-- addDemand signale lui-même la surcharge quand le magasin est plein.
		self:addDemand(store)
	end

	if store.overloaded then
		local wasCritical = store.critical
		store.overloadClock -= dt
		if store.overloadClock <= 0 then
			store.critical = true
		end
		-- Le compte à rebours doit se rafraîchir côté client jusqu'à la
		-- criticité (le passage en critique est lui-même envoyé) : ensuite
		-- l'horloge reste figée à 0 dans le payload, inutile de le réémettre
		-- cinq fois par seconde.
		if not wasCritical then
			self.dirty = true
		end
	end

	if store.storeType == "small" then
		store.evolveClock -= dt
		if store.evolveClock <= 0 then
			if self:canEvolve(store) and self.rng.random() < StoreConfig.Evolution.Chance then
				self:beginEvolution(store)
			else
				local checkInterval = StoreConfig.Evolution.CheckInterval
				local jitter = StoreConfig.Evolution.CheckJitter
				store.evolveClock = self:randomRange(
					checkInterval * (1 - jitter),
					checkInterval * (1 + jitter)
				)
			end
		end
	end
end

function StoreSystem:spawnStore(initial)
	if #self.stores >= MAX_STORES then
		return false
	end
	local colorIndex = self:pickColor()
	if not colorIndex then
		return false
	end
	local x, y = self:findStoreSpot()
	if not x then
		return false
	end

	local store = self.session:createBuilding("store", x, y, colorIndex, "small")
	store.storeType = "small"
	store.capacity = StoreConfig.Demand.SmallCapacity
	store.houses = {}
	store.demandIds = {}
	store.reservedIds = {}
	store.demandSeq = 0
	store.demands = 0
	store.reserved = 0
	store.delivered = 0
	store.age = 0
	store.demandClock = self:randomRange(
		StoreConfig.Demand.FirstDelayMin,
		StoreConfig.Demand.FirstDelayMax
	)
	store.overloaded = false
	store.critical = false
	store.overloadClock = StoreConfig.Demand.OverloadGrace
	store.evolving = false
	store.evolveTimer = 0
	store.evolveClock = StoreConfig.Evolution.MinAge
		+ self:randomRange(0, StoreConfig.Evolution.CheckInterval)

	self:spawnHousesForStore(
		store,
		initial and StoreConfig.Houses.StartHouses or StoreConfig.Houses.HousesPerStore
	)

	self:recordStat("storesSpawned", 1)
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
		for index, demandId in ipairs(store.demandIds or {}) do
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

	-- Quand le nombre maximal de magasins est atteint, l'horloge s'arrête :
	-- plus aucune tentative de placement inutile.
	if #self.stores < MAX_STORES then
		self.spawnClock -= dt
		if self.spawnClock <= 0 then
			if self:spawnStore(false) then
				self.spawnClock = self:nextSpawnInterval()
			else
				self.spawnClock = StoreConfig.Spawn.RetryDelay
			end
		end
	end

	self.houseClock -= dt
	if self.houseClock <= 0 then
		self:spawnHouse()
		self.houseClock = StoreConfig.Houses.SpawnInterval
	end

	for _, store in ipairs(self.stores) do
		self:updateStore(store, dt)
	end

	-- La cadence de diffusion se mesure en temps réel : dt est en temps simulé,
	-- donc on le ramène au temps réel avec la vitesse choisie (Session:update).
	self.broadcastClock += dt / math.max(1, self.session.speed or 1)
	if (self.dirty and self.broadcastClock >= StoreConfig.Sync.DirtyDelay)
		or self.broadcastClock >= StoreConfig.Sync.IdleDelay
	then
		self.dirty = false
		self.broadcastClock = 0
		self:broadcast()
	end
end

function StoreSystem:destroy()
	-- Une réservation ne survit pas à la partie : les voitures qui la
	-- portaient sont retirées par Session.
	for _, store in ipairs(self.stores) do
		store.reservedIds = {}
		store.reserved = 0
	end
	self.stores = {}
	self.dirty = false
end

return StoreSystem
