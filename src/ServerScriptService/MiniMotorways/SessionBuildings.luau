--[[
	SessionBuildings.luau
	Bâtiments de Session : placement, connexions aux routes, topologie.
	La construction visuelle des Models est déléguée à BuildingModels.
	Ajoute ses méthodes à Session ; appelé une seule fois depuis Session.luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Grid = require(Shared.Grid)
local RoadConfig = require(Shared.RoadConfig)
local RoadNetwork = require(Shared.RoadNetwork)
local StoreConfig = require(Shared.StoreConfig)
local COLORS = Config.HouseColors
local SessionUtil = require(script.Parent.SessionUtil)
local BuildingModels = require(script.Parent.BuildingModels)
local animateModelScale = SessionUtil.animateModelScale

-- Deux cases d'écart au minimum entre bâtiments (en distance de Manhattan, donc
-- les cases en diagonale sont acceptées).
local MIN_MANHATTAN_SPACING = 2

-- Un magasin qui apparaît part légèrement plus petit et grandit en fondu.
local SPAWN_FROM_SCALE = 0.65

-- Un magasin qui évolue : l'ancien modèle s'efface, puis il est détruit après
-- la fin du fondu (délai de sécurité compris).
local REPLACE_FADE_DURATION = 0.2
local REPLACE_CLEANUP_DELAY = 0.24

-- Directions d'entrée, dans l'ordre des quatre côtés. L'angle est celui de
-- BuildingModels : 0 pointe vers +Z (écran bas), pi/2 vers +X.
local ENTRANCE_DIRECTIONS = {
	{ angle = 0, dx = 0, dy = 1 },
	{ angle = math.pi, dx = 0, dy = -1 },
	{ angle = math.pi * 0.5, dx = 1, dy = 0 },
	{ angle = -math.pi * 0.5, dx = -1, dy = 0 },
}

return function(Session)
	function Session:isFreeCell(x, y)
		if not Grid.inBounds(x, y) then
			return false
		end
		local key = Grid.key(x, y)
		return not self.buildings[key] and not self.roads[key] and not Maps.isWater(self.map, x, y)
	end

	function Session:buildableNeighborCount(x, y)
		local count = 0
		for _, neighbor in ipairs(Grid.neighbors8(x, y)) do
			local nx, ny = neighbor[1], neighbor[2]
			if Grid.inBounds(nx, ny) then
				local key = Grid.key(nx, ny)
				if not self.buildings[key] and not Maps.isWater(self.map, nx, ny) then
					count += 1
				end
			end
		end
		return count
	end

	function Session:hasBuildableNeighbor(x, y)
		return self:buildableNeighborCount(x, y) >= StoreConfig.Houses.MinBuildableNeighbors
	end

	-- Règles de terrain (arbres décoratifs, marge du bord) partagées avec les
	-- magasins quand StoreSystem est présent. Sans lui, seules les règles de Session.
	function Session:passesStoreRules(x, y)
		local store = self.storeSystem
		if not store or not store.isBuildableSpot then
			return true
		end
		return store:isBuildableSpot(x, y, StoreConfig.Houses.MinBuildableNeighbors)
	end

	-- Tirage aléatoire borné. Le bord de la carte (une case) reste libre, comme
	-- pour l'emplacement des magasins dans StoreSystem.
	function Session:findBuildingSpot(exclude, minDistance)
		for _ = 1, 500 do
			local x = math.random(1, self.size - 2)
			local y = math.random(1, self.size - 2)
			if self:isFreeCell(x, y) and self:hasBuildableNeighbor(x, y) and self:passesStoreRules(x, y) then
				local ok = true
				if exclude then
					local distance = math.abs(x - exclude[1]) + math.abs(y - exclude[2])
					if distance < (minDistance or 0) then
						ok = false
					end
				end
				if ok then
					for _, other in ipairs(self.buildingList) do
						if math.abs(x - other.x) + math.abs(y - other.y) < MIN_MANHATTAN_SPACING then
							ok = false
							break
						end
					end
				end
				if ok then
					return x, y
				end
			end
		end
		return nil
	end

	-- Face d'entrée : le côté tourné vers une route voisine si elle existe,
	-- sinon le premier côté libre, choisi de façon déterministe par l'identifiant.
	function Session:entranceAngle(x, y, id)
		for _, direction in ipairs(ENTRANCE_DIRECTIONS) do
			local nx, ny = x + direction.dx, y + direction.dy
			if Grid.inBounds(nx, ny) and self.roads[Grid.key(nx, ny)] then
				return direction.angle
			end
		end

		local count = #ENTRANCE_DIRECTIONS
		local start = id % count
		for step = 0, count - 1 do
			local direction = ENTRANCE_DIRECTIONS[(start + step) % count + 1]
			local nx, ny = x + direction.dx, y + direction.dy
			if Grid.inBounds(nx, ny) and not Maps.isWater(self.map, nx, ny) then
				return direction.angle
			end
		end
		return 0
	end

	-- Crée le Model d'un bâtiment sur la case (x, y) et range le Model dans le
	-- monde. Un magasin grandit en fondu ; une maison, plus petite, se contente
	-- du fondu. L'entrée est celle du bâtiment s'il en a déjà une, pour qu'elle
	-- ne change pas à l'évolution.
	function Session:buildBuildingModel(kind, id, x, y, colorIndex, storeType, skipSpawnAnimation, entranceAngle)
		local model = BuildingModels.build(kind, id, Grid.center(self.origin, x, y, 0), colorIndex, storeType, {
			parent = self.world.Buildings,
			entranceAngle = entranceAngle or self:entranceAngle(x, y, id),
		})
		if not skipSpawnAnimation then
			local duration = StoreConfig.Visual.SpawnAnimationDuration
			if kind == "store" then
				animateModelScale(model, SPAWN_FROM_SCALE, 1, duration, self.tweens)
			end
			BuildingModels.fadeIn(model, duration, self.tweens)
		end
		return model
	end

	function Session:createBuilding(kind, x, y, colorIndex, storeType)
		local id = self.nextBuildingId
		self.nextBuildingId += 1

		local entranceAngle = self:entranceAngle(x, y, id)
		local model = self:buildBuildingModel(kind, id, x, y, colorIndex, storeType, false, entranceAngle)
		local palette = COLORS[colorIndex] or COLORS[1]
		local building = {
			id = id,
			kind = kind,
			x = x,
			y = y,
			key = Grid.key(x, y),
			colorIndex = colorIndex,
			color = palette.color,
			model = model,
			entranceAngle = entranceAngle,
		}
		if kind == "store" then
			building.storeType = storeType or "small"
		end

		self.buildings[building.key] = building
		table.insert(self.buildingList, building)
		if kind == "house" then
			table.insert(self.houses, building)
		else
			table.insert(self.destinations, building)
		end

		-- Le client a besoin de connaître les nouvelles cases occupées pour
		-- refuser immédiatement une route qui traverserait un bâtiment.
		self:rebuildRoadTopology()
		self:updateBuildingConnections()
		self:sendRoadState()
		return building
	end

	-- Évolution petit -> grand magasin : même case, même couleur. L'ancien
	-- modèle s'efface pendant que le nouveau grandit en fondu.
	function Session:replaceStoreModel(store)
		if not store or not self.world then
			return
		end

		local oldModel = store.model
		if oldModel then
			BuildingModels.fadeOut(oldModel, REPLACE_FADE_DURATION, self.tweens)
			task.delay(REPLACE_CLEANUP_DELAY, function()
				if oldModel.Parent then
					oldModel:Destroy()
				end
			end)
		end

		local newModel = self:buildBuildingModel(
			"store",
			store.id,
			store.x,
			store.y,
			store.colorIndex,
			"large",
			true,
			store.entranceAngle
		)
		store.model = newModel
		local duration = StoreConfig.Visual.EvolutionDuration
		BuildingModels.fadeIn(newModel, duration, self.tweens)
		animateModelScale(newModel, StoreConfig.Visual.EvolutionStartScale, 1, duration, self.tweens)
		self:destinationPulse(store)
	end

	-- isReachable(store) (optionnel) : fourni par le trafic, il écarte les
	-- magasins sans trajet quand un autre candidat existe.
	function Session:findDestinationForHouse(house, requireAvailable, isReachable)
		if self.storeSystem then
			return self.storeSystem:findDestination(house, requireAvailable, isReachable)
		end

		local best = nil
		local bestDistance = math.huge
		for _, destination in ipairs(self.destinations) do
			if destination.colorIndex == house.colorIndex then
				local distance = math.abs(destination.x - house.x) + math.abs(destination.y - house.y)
				if distance < bestDistance then
					best = destination
					bestDistance = distance
				end
			end
		end
		return best
	end

	function Session:connectorCells(building)
		local cells = {}
		local allowDiagonals = RoadConfig.BuildingConnection == "all"
		for _, neighbor in ipairs(RoadNetwork.neighbors(building.x, building.y, allowDiagonals)) do
			local nx, ny = neighbor[1], neighbor[2]
			if Grid.inBounds(nx, ny) then
				local key = Grid.key(nx, ny)
				if self.roads[key] then
					table.insert(cells, key)
				end
			end
		end
		return cells
	end

	-- Deux listes de connexions identiques, dans le même ordre (connectorCells est
	-- déterministe pour un même réseau).
	local function sameCells(a, b)
		if not a or #a ~= #b then
			return false
		end
		for index = 1, #a do
			if a[index] ~= b[index] then
				return false
			end
		end
		return true
	end

	-- Une route touchant le côté d'une maison ou d'un magasin inscrit la
	-- connexion dans le graphe. Cette passe est appelée uniquement après une
	-- modification du réseau, jamais à chaque frame. Les bâtiments dont les
	-- connexions changent voient leur entrée recalculée.
	function Session:updateBuildingConnections()
		for _, building in ipairs(self.buildingList) do
			local connections = self:connectorCells(building)
			if not sameCells(building.connections, connections) then
				building.aimPending = true
			end
			building.connections = connections
			building.connected = #connections > 0
		end
		self:refreshBuildingEntrances()
	end

	-- Remet l'entrée des bâtiments dont le réseau a changé vers le côté route.
	-- Seule la dalle est refaite, et seulement si le côté change. Un magasin
	-- évolué garde son entrée : store.entranceAngle sert à son nouveau modèle.
	function Session:refreshBuildingEntrances()
		for _, building in ipairs(self.buildingList) do
			if building.aimPending then
				building.aimPending = false
				local angle = self:entranceAngle(building.x, building.y, building.id)
				if angle ~= building.entranceAngle and building.model then
					building.entranceAngle = angle
					BuildingModels.aimEntrance(
						building.model,
						Grid.center(self.origin, building.x, building.y, 0),
						building.kind,
						building.id,
						building.storeType,
						angle
					)
				end
			end
		end
	end

	function Session:rebuildRoadTopology()
		self.intersections = {}
		for key in pairs(self.roads) do
			if RoadNetwork.isIntersectionKey(self.roads, key, RoadConfig.AllowDiagonals) then
				self.intersections[key] = true
			end
		end

		-- Une réservation dont la route a disparu ou dont la voiture n'existe
		-- plus est libérée immédiatement.
		for key, car in pairs(self.intersectionReservations) do
			if not self.roads[key] or not car.path then
				self.intersectionReservations[key] = nil
			end
		end
	end
end
