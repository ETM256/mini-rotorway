--[[
	SessionRoads.luau
	Routes de Session : validation, construction, rond-points, effacement.
	Ajoute ses méthodes à Session ; appelé une seule fois depuis Session.luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Grid = require(Shared.Grid)
local RoadConfig = require(Shared.RoadConfig)
local RoadNetwork = require(Shared.RoadNetwork)

return function(Session)
	function Session:canDraw(x, y)
		if not Grid.inBounds(x, y) then
			return false, "Hors de la carte"
		end
		local key = Grid.key(x, y)
		if self.buildings[key] then
			return false, "Bâtiment"
		end
		if self.roads[key] then
			return false, "Route déjà construite"
		end
		local water = Maps.isWater(self.map, x, y)
		if water and self.bridgesLeft <= 0 then
			return false, "Plus de ponts disponibles"
		end
		if self.budget < 1 then
			return false, "Plus de routes disponibles"
		end
		return true, water and "bridge" or "road"
	end

	function Session:drawRoad(cells)
		-- La pause manuelle fige la simulation, pas l'édition des routes.
		-- En revanche, on bloque toute édition pendant le choix de semaine.
		if not self.running or self.over or self.awaitingChoice then
			return
		end
		if type(cells) ~= "table" then
			return
		end

		local placed = 0
		local newRoads = {}
		local newRoadSet = {}
		for _, cell in ipairs(cells) do
			if type(cell) == "table" then
				local x = tonumber(cell[1])
				local y = tonumber(cell[2])
				if x and y then
					x = math.floor(x)
					y = math.floor(y)
					local ok, kind = self:canDraw(x, y)
					if ok then
						local key = Grid.key(x, y)
						self.roads[key] = true
						if kind == "bridge" then
							self.bridges[key] = true
							self.bridgesLeft -= 1
						end
						self.budget -= 1
						table.insert(newRoads, { key = key, isBridge = kind == "bridge" })
						newRoadSet[key] = true
						placed += 1
					end
				end
			end
		end

		if placed > 0 then
			-- Toutes les cases sont posées avant de créer les visuels : les
			-- extrémités et les virages connaissent ainsi déjà leurs voisins.
			for index, road in ipairs(newRoads) do
				local delay = math.min((index - 1) * 0.022, 0.28)
				self:createRoadVisual(road.key, road.isBridge, delay, true)
			end

			-- Les routes déjà présentes autour du tracé doivent mettre à jour
			-- leurs capuchons (une ancienne extrémité peut devenir un virage).
			local refreshed = {}
			for _, road in ipairs(newRoads) do
				local x, y = Grid.parse(road.key)
				if x then
					for _, neighbor in ipairs(Grid.neighbors8(x, y)) do
						local neighborKey = Grid.key(neighbor[1], neighbor[2])
						if self.roads[neighborKey] and not newRoadSet[neighborKey] and not refreshed[neighborKey] then
							refreshed[neighborKey] = true
							self:refreshRoadVisual(neighborKey)
						end
					end
				end
			end

			-- Le ruban lissé est purement visuel : il recouvre les cases pour
			-- donner les courbes et les diagonales continues de la vidéo, tandis
			-- que la simulation continue de suivre la grille.
			self:addRoadRibbons(cells)

			self.roadVersion += 1
			self:rebuildRoadTopology()
			self:updateBuildingConnections()
			self:refreshCarPaths()
			self:sendState()
			self:sendRoadState()
		end
	end

	function Session:placeRoundabout(x, y)
		if not self.running or self.over or self.awaitingChoice then
			return
		end
		x = tonumber(x)
		y = tonumber(y)
		if not x or not y then
			return
		end
		x = math.floor(x)
		y = math.floor(y)
		if not Grid.inBounds(x, y) then
			self:toast("Placez le rond-point sur la carte.")
			return
		end
		if self.roundaboutsLeft <= 0 then
			self:toast("Plus de ronds-points disponibles.")
			return
		end
		local key = Grid.key(x, y)
		if not self.roads[key] then
			self:toast("Placez le rond-point sur une route.")
			return
		end
		if self.roundaboutParts[key] then
			self:toast("Il y a déjà un rond-point ici.")
			return
		end
		if self.bridges[key] then
			self:toast("Un rond-point ne peut pas être posé sur un pont.")
			return
		end

		self.roundaboutsLeft -= 1
		self:createRoundaboutVisual(key)
		self:sendState()
		self:toast("Rond-point placé.")
	end

	function Session:eraseRoad(key, deferState)
		if not self.running or self.over or self.awaitingChoice then
			return false
		end
		if type(key) ~= "string" or not self.roads[key] then
			return false
		end

		local x, y = Grid.parse(key)
		if not x then
			return false
		end

		local roundabout = self.roundaboutParts[key]
		if roundabout then
			roundabout:Destroy()
			self.roundaboutParts[key] = nil
			self.roundaboutsLeft = math.min(Config.Roads.MaxRoundabouts, self.roundaboutsLeft + 1)
		end

		self.roads[key] = nil
		self.intersectionReservations[key] = nil
		if self.bridges[key] then
			self.bridges[key] = nil
			self.bridgesLeft = math.min(Config.Roads.MaxBridges, self.bridgesLeft + 1)
		end
		self.budget = math.min(Config.Roads.MaxBudget, self.budget + 1)

		local parts = self.roadParts[key]
		if parts then
			for _, part in pairs(parts) do
				if part then
					part:Destroy()
				end
			end
			self.roadParts[key] = nil
		end

		-- Une route voisine peut redevenir une extrémité : on lui redonne
		-- immédiatement son capuchon arrondi.
		for _, neighbor in ipairs(RoadNetwork.neighbors(x, y, RoadConfig.AllowDiagonals)) do
			local neighborKey = Grid.key(neighbor[1], neighbor[2])
			if self.roads[neighborKey] then
				self:refreshRoadVisual(neighborKey)
			end
		end

		-- On regroupe les reconstructions de rubans : un effacement au clic
		-- droit peut envoyer plusieurs cases d'affilée. Le ruban est reconstruit
		-- une seule fois à la prochaine frame.
		self.roadRibbonsDirty = true

		self.roadVersion += 1
		if not deferState then
			self:rebuildRoadTopology()
			self:updateBuildingConnections()
			self:refreshCarPaths()
			self:sendState()
			self:sendRoadState()
		end
		return true
	end

	function Session:eraseRoads(keys)
		if type(keys) ~= "table" then
			return
		end
		local removed = 0
		for _, key in ipairs(keys) do
			if type(key) == "string" and self:eraseRoad(key, true) then
				removed += 1
			end
		end
		if removed > 0 then
			self:rebuildRoadTopology()
			self:updateBuildingConnections()
			self:refreshCarPaths()
			self:sendState()
			self:sendRoadState()
		end
	end
end
