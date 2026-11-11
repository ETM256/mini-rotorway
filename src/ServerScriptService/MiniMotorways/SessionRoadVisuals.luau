--[[
	SessionRoadVisuals.luau
	Rendu des routes de Session : un seul renderer (RoadRenderer) piloté par
	RoadGeometry. Ajoute ses méthodes à Session ; appelé une seule fois depuis
	Session.luau.

	Rendu incrémental : un changement marque la case et ses quatre voisines
	(RoadGeometry.affectedCells) dans self.roadDirty ; flushRoadRender redessine
	chacune une seule fois, et seulement si sa forme a vraiment changé. Le réseau
	entier n'est jamais redessiné.

	État : self.roadParts[key] = parts de la case, self.roadSignatures[key] =
	forme rendue, self.roadDirty = cases à redessiner, self.roadReveal[key] =
	délai d'apparition d'une case neuve, self.roadBuildingsSeen = bâtiments déjà
	pris en compte (leurs côtés donnent les raccords).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Grid = require(Shared.Grid)
local RoadGeometry = require(Shared.RoadGeometry)
local RoadRenderer = require(script.Parent.RoadRenderer)
local SessionUtil = require(script.Parent.SessionUtil)

return function(Session)
	local function destroyParts(parts)
		for _, part in ipairs(parts) do
			SessionUtil.stopRoadPartReveal(part)
			part:Destroy()
		end
	end

	-- Marque à redessiner chaque case de `keys` et ses quatre voisines ; reveals
	-- (clé -> délai) désigne les cases neuves qui apparaissent en animation.
	function Session:markRoadsDirty(keys, reveals)
		for _, key in ipairs(keys) do
			for _, affected in ipairs(RoadGeometry.affectedCells(key)) do
				self.roadDirty[affected] = true
			end
		end
		if reveals then
			for key, delay in pairs(reveals) do
				self.roadReveal[key] = delay
			end
		end
	end

	-- Détruit les parts d'une case, et seulement les siennes.
	function Session:removeRoadVisual(key)
		local parts = self.roadParts[key]
		if parts then
			destroyParts(parts)
			self.roadParts[key] = nil
		end
		self.roadSignatures[key] = nil
	end

	-- Redessine une case sans condition : ses anciennes parts disparaissent.
	function Session:renderRoadCell(key, reveal)
		self:removeRoadVisual(key)
		if not self.world or not self.roads[key] then
			return
		end
		self.roadParts[key] = RoadRenderer.buildCell(self, key, reveal)
		self.roadSignatures[key] = RoadRenderer.signature(self, key)
	end

	-- Les bâtiments apparus depuis le dernier rendu : leurs côtés donnent de
	-- nouveaux raccords aux routes voisines (une maison peut naître au bord
	-- d'une route). Les bâtiments ne bougent ni ne disparaissent en cours de
	-- partie, un simple compteur suffit.
	local function syncBuildings(self)
		local list = self.buildingList
		if #list == self.roadBuildingsSeen then
			return
		end
		local cells = {}
		for index = self.roadBuildingsSeen + 1, #list do
			cells[#cells + 1] = list[index].key
		end
		self.roadBuildingsSeen = #list
		self:markRoadsDirty(cells)
	end

	-- Point d'entrée unique du rendu : appelé à la fin de chaque lot de routes
	-- et à chaque frame par Session:update. Sans changement, il ne fait rien.
	function Session:flushRoadRender()
		if not self.world then
			return
		end
		syncBuildings(self)
		if next(self.roadDirty) == nil then
			return
		end

		local dirty, reveals = self.roadDirty, self.roadReveal
		self.roadDirty, self.roadReveal = {}, {}
		for key in pairs(dirty) do
			if self.roads[key] then
				local reveal = reveals[key]
				if reveal or self.roadSignatures[key] ~= RoadRenderer.signature(self, key) then
					self:renderRoadCell(key, reveal)
				end
			end
		end
	end

	-- Détruit toutes les parts de route ; le prochain rendu repart de zéro.
	function Session:clearRoadVisuals()
		for _, parts in pairs(self.roadParts) do
			destroyParts(parts)
		end
		self.roadParts = {}
		self.roadSignatures = {}
	end

	-- Noms historiques des points d'entrée du rendu.
	function Session:rebuildRoadRibbons()
		self:flushRoadRender()
	end

	function Session:clearRoadRibbons()
		self:clearRoadVisuals()
	end

	-- cells : cases { x, y } (le format d'un tracé), toutes marquées à redessiner.
	function Session:addRoadRibbons(cells)
		local keys = {}
		for _, cell in ipairs(cells) do
			if type(cell) == "table" and type(cell[1]) == "number" and type(cell[2]) == "number" then
				keys[#keys + 1] = Grid.key(math.floor(cell[1]), math.floor(cell[2]))
			end
		end
		self:markRoadsDirty(keys)
		self:flushRoadRender()
	end

	-- Visuel d'une case de route, tout de suite. isBridge est ignoré : le pont
	-- est lu dans self.bridges, comme le fait le rendu à chaque redessin.
	function Session:createRoadVisual(key, _isBridge, delay, animate)
		self:renderRoadCell(key, if animate ~= false then delay or 0 else nil)
	end

	function Session:refreshRoadVisual(key)
		self:renderRoadCell(key, nil)
	end

	function Session:createRoundaboutVisual(key)
		if self.roundaboutParts[key] then
			self.roundaboutParts[key]:Destroy()
		end
		self.roundaboutParts[key] = RoadRenderer.buildRoundabout(self, key)
	end
end
