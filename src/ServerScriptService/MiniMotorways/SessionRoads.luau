--[[
	SessionRoads.luau
	Routes de Session : validation, construction, rond-points, effacement.
	Ajoute ses méthodes à Session ; appelé une seule fois depuis Session.luau.

	Le client envoie des cases brutes : chaque coordonnée est revalidée ici.
	Un lot modifie le réseau une seule fois (topologie, connexions des
	bâtiments, trajets des voitures, envoi au client).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Grid = require(Shared.Grid)
local RoadConfig = require(Shared.RoadConfig)

-- Raisons de refus liées aux ressources : le toast les affiche, l'aperçu
-- client utilise les mêmes règles.
local REASON_NO_BUDGET = "Plus de routes disponibles"
local REASON_NO_BRIDGE = "Plus de ponts disponibles"

local MAX_CELLS = RoadConfig.Input.MaxCellsPerRequest

-- Lit une case envoyée par un client. Renvoie nil si une coordonnée n'est pas
-- un nombre fini, ou si la case est hors carte. Le -0 est ramené à 0 : sans
-- cela, "-0:3" serait une clé distincte de "0:3" et casserait le réseau.
local function readCell(x, y)
	if type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	if x ~= x or y ~= y or math.abs(x) == math.huge or math.abs(y) == math.huge then
		return nil
	end
	x = math.floor(x) + 0
	y = math.floor(y) + 0
	if not Grid.inBounds(x, y) then
		return nil
	end
	return x, y
end

return function(Session)
	-- Une case de route coûte une pièce de route, plus un pont sur l'eau.
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
			return false, REASON_NO_BRIDGE
		end
		if self.budget < 1 then
			return false, REASON_NO_BUDGET
		end
		return true, water and "bridge" or "road"
	end

	-- La pause manuelle fige la simulation, pas l'édition des routes. En revanche,
	-- toute édition est bloquée pendant le choix de semaine.
	function Session:canEditRoads()
		return self.running and not self.over and not self.awaitingChoice
	end

	-- Une seule reconstruction par lot : topologie, connexions des bâtiments,
	-- trajets des voitures, puis état envoyé au client.
	function Session:commitRoadChange(count, statName)
		self.roadVersion += 1
		self:rebuildRoadTopology()
		self:updateBuildingConnections()
		self:refreshCarPaths()
		self:sendState()
		self:sendRoadState()
	end

	function Session:drawRoad(cells)
		if not self:canEditRoads() or type(cells) ~= "table" then
			return
		end
		-- Un lot trop grand est refusé en entier, comme le fait Bootstrap.
		if #cells > MAX_CELLS then
			return
		end

		local placed = 0
		local limit = nil
		local newRoads = {}
		for _, cell in ipairs(cells) do
			local x, y = nil, nil
			if type(cell) == "table" then
				x, y = readCell(cell[1], cell[2])
			end
			if x then
				local key = Grid.key(x, y)
				local ok, detail = self:canDraw(x, y)
				if ok then
					local isBridge = detail == "bridge"
					self.roads[key] = true
					if isBridge then
						self.bridges[key] = true
						self.bridgesLeft -= 1
					end
					self.budget -= 1
					table.insert(newRoads, { key = key, isBridge = isBridge })
					placed += 1
				elseif detail == REASON_NO_BUDGET or detail == REASON_NO_BRIDGE then
					limit = limit or detail
				end
			end
		end

		-- Le tracé s'arrête proprement quand les ressources manquent : les cases
		-- restantes sont refusées sans être facturées.
		if limit then
			self:toast(limit)
		end
		if placed == 0 then
			return
		end

		-- Toutes les cases sont posées avant le rendu : les extrémités et les
		-- virages connaissent déjà leurs voisins. Une seule passe dessine les
		-- cases neuves (en animation) et redessine leurs voisines si leur forme
		-- change (une ancienne extrémité peut devenir un virage).
		-- Un très long tracé n'est pas animé : chaque pièce animée réplique sa
		-- taille et sa transparence à chaque frame, ce qui coûte trop pour des
		-- centaines de pièces.
		local stagger = RoadConfig.Construction
		local animate = #newRoads <= stagger.MaxAnimatedCells
		local reveals = animate and {} or nil
		local placedKeys = {}
		for index, road in ipairs(newRoads) do
			if reveals then
				reveals[road.key] = math.min((index - 1) * stagger.RevealStagger, stagger.RevealStaggerMax)
			end
			placedKeys[index] = road.key
		end
		self:markRoadsDirty(placedKeys, reveals)
		self:flushRoadRender()

		self:commitRoadChange(placed, "roadsBuilt")
	end

	function Session:placeRoundabout(x, y)
		if not self:canEditRoads() then
			return
		end
		if type(x) ~= "number" or type(y) ~= "number" then
			return
		end
		x, y = readCell(x, y)
		if not x then
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

		-- Le rond-point ne change pas le réseau : pas de version ni de trajets.
		self.roundaboutsLeft -= 1
		self:createRoundaboutVisual(key)
		self:sendState()
		self:toast("Rond-point placé.")
	end

	-- Retire une case de route et rend exactement ce qu'elle avait coûté (pièce,
	-- pont, rond-point). Ne reconstruit pas le réseau : c'est le rôle du lot.
	function Session:removeRoadCell(key)
		if type(key) ~= "string" or not self.roads[key] then
			return false
		end
		if not Grid.parse(key) then
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

		-- Les parts de la case partent tout de suite ; ses voisines changent de
		-- forme (une route peut redevenir une extrémité) et sont redessinées une
		-- seule fois par le rendu, même si le lot touche plusieurs cases.
		self:removeRoadVisual(key)
		self:markRoadsDirty({ key })
		return true
	end

	-- Finalise un effacement : rendu des voisines (une fois par case), puis une
	-- seule mise à jour du réseau pour tout le lot.
	function Session:finishRoadErase(removed)
		self:flushRoadRender()
		self:commitRoadChange(removed, "roadsErased")
	end

	function Session:eraseRoad(key)
		if not self:canEditRoads() then
			return false
		end
		if not self:removeRoadCell(key) then
			return false
		end
		self:finishRoadErase(1)
		return true
	end

	function Session:eraseRoads(keys)
		if not self:canEditRoads() or type(keys) ~= "table" or #keys > MAX_CELLS then
			return
		end
		local removed = 0
		for _, key in ipairs(keys) do
			if self:removeRoadCell(key) then
				removed += 1
			end
		end
		if removed > 0 then
			self:finishRoadErase(removed)
		end
	end
end
