--[[
	SessionBuildings.luau
	Bâtiments de Session : placement, modèles de maisons/magasins, connexions aux routes.
	Ajoute ses méthodes à Session ; appelé une seule fois depuis Session.luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Grid = require(Shared.Grid)
local RoadConfig = require(Shared.RoadConfig)
local RoadNetwork = require(Shared.RoadNetwork)
local StoreConfig = require(Shared.StoreConfig)
local COLORS = Config.HouseColors
local SessionUtil = require(script.Parent.SessionUtil)
local CARD_CYLINDER_ROTATION = SessionUtil.CARD_CYLINDER_ROTATION
local makePart = SessionUtil.makePart
local addRoundedCard = SessionUtil.addRoundedCard
local animateModelScale = SessionUtil.animateModelScale

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
		return self:buildableNeighborCount(x, y) >= 2
	end

	function Session:findBuildingSpot(exclude, minDistance)
		for _ = 1, 500 do
			local x = math.random(1, self.size - 2)
			local y = math.random(1, self.size - 2)
			if self:isFreeCell(x, y) and self:hasBuildableNeighbor(x, y) then
				local ok = true
				if exclude then
					local distance = math.abs(x - exclude[1]) + math.abs(y - exclude[2])
					if distance < (minDistance or 0) then
						ok = false
					end
				end
				if ok then
					for _, other in ipairs(self.buildingList) do
						if math.abs(x - other.x) + math.abs(y - other.y) < 2 then
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

	function Session:buildBuildingModel(kind, id, x, y, colorIndex, storeType, skipSpawnAnimation)
		local palette = COLORS[colorIndex] or COLORS[1]
		local color = palette.color
		local baseColor = palette.base or color:Lerp(Config.Colors.Ink, 0.22)
		local ink = Config.Colors.Ink
		local white = Config.Colors.White
		local isHouse = kind == "house"
		local isStore = kind == "store"
		local isLarge = isStore and storeType == "large"

		local model = Instance.new("Model")
		model.Name = kind .. "_" .. tostring(id)
			.. (isStore and ("_" .. tostring(storeType or "small")) or "")

		-- Les icônes sont volontairement plus larges que la case occupée, comme
		-- dans la référence : elles débordent un peu sur la grille et sur la
		-- route, mais la validation reste sur une seule case.
		local width, depth
		if isHouse then
			width, depth = 5.2, 4.8
		elseif isLarge then
			width = StoreConfig.Visual.LargeSize
			depth = StoreConfig.Visual.LargeSize
		else
			width = StoreConfig.Visual.SmallSize
			depth = StoreConfig.Visual.SmallSize
		end
		-- Rayon 0.17 = carte carrée à coins arrondis ; rayon 0.5 = cercle parfait.
		local cardRadius = isLarge and 0.5 or 0.17
		-- Les couches sont des cartes très fines, empilées avec un pas de 0.05
		-- stud pour rester au-dessus des routes sans créer de faces coplanaires.
		local cardH = 0.05
		local baseY = 0.49
		local center = CFrame.new(Grid.center(self.origin, x, y, 0))

		-- Ombre douce décalée vers le bas-droite, en deux couches pour éviter
		-- un contour trop dur.
		addRoundedCard(model, "ShadowSoft", center, width + 1.00, depth + 1.00, cardH, baseY - 0.150, Config.Colors.BuildingShadow, {
			transparency = 0.82,
			offset = Vector3.new(0.52, 0, 0.52),
			radius = cardRadius,
		})
		addRoundedCard(model, "Shadow", center, width + 0.50, depth + 0.50, cardH, baseY - 0.100, Config.Colors.BuildingShadow, {
			transparency = 0.68,
			offset = Vector3.new(0.34, 0, 0.34),
			radius = cardRadius,
		})

		-- Petit chemin blanc arrondi qui dépasse de la maison, comme les
		-- allées dessinées autour des icônes de Mini Motorways.
		local directions = {
			{ angle = 0, dx = 0, dy = 1 },
			{ angle = math.pi, dx = 0, dy = -1 },
			{ angle = math.pi * 0.5, dx = 1, dy = 0 },
			{ angle = -math.pi * 0.5, dx = -1, dy = 0 },
		}
		local driveAngle = 0
		local driveIndex = id % 4
		for step = 0, 3 do
			local direction = directions[(driveIndex + step) % 4 + 1]
			local nx, ny = x + direction.dx, y + direction.dy
			if Grid.inBounds(nx, ny) and not Maps.isWater(self.map, nx, ny) then
				driveAngle = direction.angle
				break
			end
		end
		local driveWidth = width * 0.46
		local driveLength = width * 1.45
		addRoundedCard(model, "Driveway", center, driveWidth, driveLength, cardH, baseY - 0.050, white, {
			angle = driveAngle,
			offset = Vector3.new(0, 0, width * 0.52),
			radius = 0.5,
		})

		-- Liseré blanc extérieur puis décalage coloré sombre : le contour de
		-- l'icône reste net sur le sol crème.
		addRoundedCard(model, "Outline", center, width + 0.38, depth + 0.38, cardH, baseY, white, {
			radius = cardRadius,
		})
		addRoundedCard(model, "Offset", center, width + 0.10, depth + 0.10, cardH, baseY + 0.050, baseColor:Lerp(ink, 0.30), {
			offset = Vector3.new(0.18, 0, 0.18),
			radius = cardRadius,
		})

		local body
		if isHouse then
			body = addRoundedCard(model, "Body", center, width, depth, cardH, baseY + 0.100, baseColor, {
				radius = cardRadius,
			})
		else
			body = addRoundedCard(model, "Body", center, width, depth, cardH, baseY + 0.100, color, {
				radius = cardRadius,
			})
		end
		model.PrimaryPart = body

		if isHouse then
			-- Toit jaune/clair posé sur le socle corail, avec un petit décalage
			-- sombre pour retrouver l'empilement de la référence.
			local roofOffset = Vector3.new(0, 0, -depth * 0.10)
			addRoundedCard(model, "RoofOffset", center, width * 0.88, depth * 0.76, cardH, baseY + 0.150, baseColor:Lerp(ink, 0.32), {
				offset = roofOffset,
				radius = 0.17,
			})
			addRoundedCard(model, "Roof", center, width * 0.82, depth * 0.70, cardH, baseY + 0.200, color, {
				offset = roofOffset,
				radius = 0.17,
			})

			-- Trois petites cheminées carrées sur le bord supérieur du toit.
			local chimneyZ = center.Z - depth * 0.10 - depth * 0.30
			for i = -1, 1 do
				local cx = center.X + i * width * 0.14
				makePart({
					Name = "ChimneyShadow",
					Parent = model,
					Size = Vector3.new(width * 0.10 + 0.10, cardH, width * 0.12 + 0.10),
					CFrame = CFrame.new(cx, baseY + 0.250, chimneyZ),
					Color = baseColor:Lerp(ink, 0.32),
					CastShadow = false,
				})
				makePart({
					Name = "Chimney",
					Parent = model,
					Size = Vector3.new(width * 0.10, 0.06, width * 0.12),
					CFrame = CFrame.new(cx, baseY + 0.260, chimneyZ),
					Color = color,
					CastShadow = false,
				})
			end
		else
			-- Magasin minimaliste : toit plat, logo central, entrée sombre
			-- tournée vers l'allée. Le grand magasin est un disque avec un
			-- anneau blanc ; le petit est un carré à coins arrondis.
			if isLarge then
				addRoundedCard(model, "RoofRing", center, width * 0.78, depth * 0.78, cardH, baseY + 0.155, white, {
					radius = 0.5,
				})
				addRoundedCard(model, "Roof", center, width * 0.66, depth * 0.66, cardH, baseY + 0.180, color, {
					radius = 0.5,
				})
			else
				addRoundedCard(model, "RoofRing", center, width * 0.64, depth * 0.64, cardH, baseY + 0.155, white, {
					radius = 0.24,
				})
				addRoundedCard(model, "Roof", center, width * 0.54, depth * 0.54, cardH, baseY + 0.180, color, {
					radius = 0.24,
				})
			end

			-- Petit logo blanc, visible de loin sans masquer la couleur.
			makePart({
				Name = "Logo",
				Parent = model,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.06, 1.10, 1.10),
				CFrame = CFrame.new(center.X, baseY + 0.215, center.Z) * CARD_CYLINDER_ROTATION,
				Color = white,
				CastShadow = false,
			})

			-- Entrée / accès routier : une barre sombre sur le côté de l'allée.
			addRoundedCard(model, "Entrance", center, width * 0.30, 0.95, cardH + 0.006, baseY + 0.190, ink, {
				angle = driveAngle,
				offset = Vector3.new(0, 0, width * 0.40),
				radius = 0.28,
			})
		end

		model.Parent = self.world.Buildings
		model.WorldPivot = CFrame.new(center.Position)
		model:SetAttribute("BuildingKind", kind)
		model:SetAttribute("BuildingId", id)
		model:SetAttribute("ColorIndex", colorIndex)

		if isStore then
			model:SetAttribute("StoreType", storeType or "small")
			if not skipSpawnAnimation then
				animateModelScale(model, 0.65, 1, StoreConfig.Visual.SpawnAnimationDuration)
			end
		end

		return model
	end

	function Session:createBuilding(kind, x, y, colorIndex, storeType)
		local id = self.nextBuildingId
		self.nextBuildingId += 1

		local model = self:buildBuildingModel(kind, id, x, y, colorIndex, storeType, false)
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

	function Session:replaceStoreModel(store)
		if not store or not self.world then
			return
		end

		local oldModel = store.model
		if oldModel then
			for _, descendant in ipairs(oldModel:GetDescendants()) do
				if descendant:IsA("BasePart") then
					TweenService:Create(
						descendant,
						TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Transparency = 1 }
					):Play()
				end
			end
			task.delay(0.24, function()
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
			true
		)
		store.model = newModel
		animateModelScale(
			newModel,
			StoreConfig.Visual.EvolutionStartScale,
			1,
			StoreConfig.Visual.EvolutionDuration
		)
		self:destinationPulse(store)
	end

	function Session:findDestinationForHouse(house, requireAvailable)
		if self.storeSystem then
			return self.storeSystem:findDestination(house, requireAvailable)
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

	-- Une route touchant le côté d'une maison ou d'un magasin inscrit la
	-- connexion dans le graphe. Cette passe est appelée uniquement après une
	-- modification du réseau, jamais à chaque frame.
	function Session:updateBuildingConnections()
		for _, building in ipairs(self.buildingList) do
			building.connections = self:connectorCells(building)
			building.connected = #building.connections > 0
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
