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
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Grid = require(Shared.Grid)
local Pathfinding = require(Shared.Pathfinding)
local Remotes = require(Shared.Remotes)

local WorldBuilder = require(script.Parent.WorldBuilder)
local Profile = require(script.Parent.Profile)

local Session = {}
Session.__index = Session

local COLORS = Config.HouseColors

local function clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	elseif value > maxValue then
		return maxValue
	end
	return value
end

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth

	local parent = nil
	for key, value in pairs(props) do
		if key == "Parent" then
			parent = value
		else
			p[key] = value
		end
	end
	if parent then
		p.Parent = parent
	end
	return p
end

-- Carte plate à coins arrondis, construite avec des primitives : deux
-- traverses qui se croisent et quatre petits disques aux coins. Cela donne
-- l'aspect « icône vectorielle » des maisons de la référence, sans mesh.
local CARD_CYLINDER_ROTATION = CFrame.Angles(0, 0, math.rad(90))

local function addRoundedCard(model, name, center, width, depth, height, y, color, options)
	options = options or {}
	local radius = math.min(width, depth) * (options.radius or 0.16)
	local position = center * CFrame.Angles(0, options.angle or 0, 0) * CFrame.new(0, y, 0)
	if options.offset then
		position = position * CFrame.new(options.offset.X, 0, options.offset.Z)
	end

	local transparency = options.transparency or 0
	local firstPart = nil
	local function add(props)
		props.Name = name
		props.Parent = model
		props.Color = color
		props.Transparency = transparency
		props.CastShadow = false
		local p = makePart(props)
		firstPart = firstPart or p
		return p
	end

	-- Les deux traverses se recouvrent au centre. On rend la verticale très
	-- légèrement plus haute pour éviter un clignotement de faces coplanaires.
	if width - radius * 2 > 0.02 then
		add({
			Size = Vector3.new(width - radius * 2, height, depth),
			CFrame = position,
		})
	end
	if depth - radius * 2 > 0.02 then
		add({
			Size = Vector3.new(width, height + 0.004, depth - radius * 2),
			CFrame = position,
		})
	end

	local xs = { 0 }
	local zs = { 0 }
	if width - radius * 2 > 0.02 then
		xs = { -(width * 0.5 - radius), width * 0.5 - radius }
	end
	if depth - radius * 2 > 0.02 then
		zs = { -(depth * 0.5 - radius), depth * 0.5 - radius }
	end
	for _, sx in ipairs(xs) do
		for _, sz in ipairs(zs) do
			add({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(height + 0.006, radius * 2, radius * 2),
				CFrame = position * CFrame.new(sx, 0, sz) * CARD_CYLINDER_ROTATION,
			})
		end
	end

	return firstPart
end

-- Petite apparition de la route : la pièce grandit et devient opaque.
-- Le délai permet de faire apparaître les cases l'une après l'autre quand
-- le joueur trace un trait continu.
local function animateRoadPart(part, finalSize, delay)
	local startSize = Vector3.new(
		math.max(0.04, finalSize.X * 0.52),
		math.max(0.04, finalSize.Y * 0.52),
		math.max(0.04, finalSize.Z * 0.52)
	)
	part.Size = startSize
	part.Transparency = 0.45

	TweenService:Create(part, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay), {
		Size = finalSize,
		Transparency = 0,
	}):Play()
end

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
	self.roundaboutParts = {}
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
	self.pairClock = Config.Game.FirstPairDelay
	self.pairCount = 0
	self.nextBuildingId = 1

	self.world = WorldBuilder.build(self)
	self:seedBuildings()

	return self
end

function Session:seedBuildings()
	for _ = 1, Config.Game.StartPairs do
		self:spawnPair(true)
	end
end

function Session:isFreeCell(x, y)
	if not Grid.inBounds(x, y) then
		return false
	end
	local key = Grid.key(x, y)
	return not self.buildings[key] and not self.roads[key] and not Maps.isWater(self.map, x, y)
end

function Session:hasBuildableNeighbor(x, y)
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
	return count >= 2
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

function Session:spawnPair(initial)
	if #self.houses >= Config.Game.MaxPairs then
		return
	end

	for _ = 1, 8 do
		local colorIndex = (self.pairCount % #COLORS) + 1
		local destX, destY = self:findBuildingSpot(nil, 0)
		if destX then
			local houseX, houseY = self:findBuildingSpot({ destX, destY }, 5)
			if houseX then
				local destination = self:createBuilding("destination", destX, destY, colorIndex)
				local house = self:createBuilding("house", houseX, houseY, colorIndex)
				house.dest = self:findDestinationForHouse(house) or destination
				house.timer = initial
						and (Config.Game.FirstSpawnDelay + math.random() * 4)
					or (2 + math.random() * 3)
				self.pairCount += 1
				return
			end
		end
	end
end

function Session:createBuilding(kind, x, y, colorIndex)
	local id = self.nextBuildingId
	self.nextBuildingId += 1

	local palette = COLORS[colorIndex] or COLORS[1]
	local color = palette.color
	local baseColor = palette.base or color:Lerp(Config.Colors.Ink, 0.22)
	local ink = Config.Colors.Ink
	local white = Config.Colors.White
	local isHouse = kind == "house"

	local model = Instance.new("Model")
	model.Name = kind .. "_" .. tostring(id)

	-- Les icônes sont volontairement plus larges que la case occupée, comme
	-- dans la référence : elles débordent un peu sur la grille et sur la
	-- route, mais la validation reste sur une seule case.
	local width = isHouse and 5.2 or 6.4
	local depth = isHouse and 4.8 or 6.4
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
	})
	addRoundedCard(model, "Shadow", center, width + 0.50, depth + 0.50, cardH, baseY - 0.100, Config.Colors.BuildingShadow, {
		transparency = 0.68,
		offset = Vector3.new(0.34, 0, 0.34),
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
		radius = 0.17,
	})
	addRoundedCard(model, "Offset", center, width + 0.10, depth + 0.10, cardH, baseY + 0.050, baseColor:Lerp(ink, 0.30), {
		offset = Vector3.new(0.18, 0, 0.18),
		radius = 0.17,
	})

	local body
	if isHouse then
		body = addRoundedCard(model, "Body", center, width, depth, cardH, baseY + 0.100, baseColor)
	else
		body = addRoundedCard(model, "Body", center, width, depth, cardH, baseY + 0.100, color)
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
		-- Épingle blanche à pointe, posée au centre de la carte.
		local pinY = baseY + 0.170
		local pinRotation = CFrame.Angles(0, 0, math.rad(90))
		makePart({
			Name = "PinTailShadow",
			Parent = model,
			Size = Vector3.new(0.92, cardH, 0.92),
			CFrame = CFrame.new(center.X, pinY - 0.004, center.Z + 0.46) * CFrame.Angles(0, math.rad(45), 0),
			Color = ink,
			CastShadow = false,
		})
		makePart({
			Name = "PinOutline",
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.06, 1.45, 1.45),
			CFrame = CFrame.new(center.X, pinY, center.Z) * pinRotation,
			Color = ink,
			CastShadow = false,
		})
		makePart({
			Name = "PinTail",
			Parent = model,
			Size = Vector3.new(0.70, cardH, 0.70),
			CFrame = CFrame.new(center.X, pinY + 0.006, center.Z + 0.42) * CFrame.Angles(0, math.rad(45), 0),
			Color = white,
			CastShadow = false,
		})
		makePart({
			Name = "Pin",
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.06, 1.15, 1.15),
			CFrame = CFrame.new(center.X, pinY + 0.012, center.Z) * pinRotation,
			Color = white,
			CastShadow = false,
		})
		makePart({
			Name = "PinDot",
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.06, 0.42, 0.42),
			CFrame = CFrame.new(center.X, pinY + 0.030, center.Z) * pinRotation,
			Color = ink,
			CastShadow = false,
		})
	end

	model.Parent = self.world.Buildings

	local building = {
		id = id,
		kind = kind,
		x = x,
		y = y,
		key = Grid.key(x, y),
		colorIndex = colorIndex,
		color = color,
		model = model,
	}

	self.buildings[building.key] = building
	table.insert(self.buildingList, building)
	if isHouse then
		table.insert(self.houses, building)
	else
		table.insert(self.destinations, building)
	end

	return building
end

function Session:findDestinationForHouse(house)
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
	for _, neighbor in ipairs(Grid.neighbors8(building.x, building.y)) do
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

		self.roadVersion += 1
		self:refreshCarPaths()
		self:sendState()
	end
end

function Session:createRoadVisual(key, isBridge, delay, animate)
	local x, y = Grid.parse(key)
	if not x then
		return
	end

	delay = delay or 0
	animate = animate ~= false
	local function reveal(part, size)
		if animate then
			animateRoadPart(part, size, delay)
		end
	end

	local tile = self.tile
	local color = isBridge and Config.Colors.Bridge or Config.Colors.Road
	local edgeColor = isBridge and Config.Colors.BridgeEdge or Config.Colors.RoadEdge
	local contourColor = Config.Colors.RoadContour
	local outlineHeight = isBridge and 0.32 or 0.28
	local outlineCenterY = isBridge and 0.21 or 0.15
	local contourHeight = isBridge and 0.28 or 0.24
	local contourCenterY = isBridge and 0.255 or 0.18
	local topHeight = isBridge and 0.20 or 0.18
	local topCenterY = isBridge and 0.30 or 0.22
	local jointRotation = CFrame.Angles(0, 0, math.rad(90))
	-- Le liseré blanc reste visible tout autour du ruban graphite : les
	-- couches sont légèrement décalées pour éviter toute couture.
	local layerLift = 0.01
	local diagonalLift = 0.008

	local parts = {}
	local function addBox(name, size, center, partColor)
		local part = makePart({
			Name = name,
			Parent = self.world.Roads,
			Size = size,
			CFrame = CFrame.new(center),
			Color = partColor,
		})
		reveal(part, size)
		table.insert(parts, part)
		return part
	end

	local function addCylinder(name, size, center, partColor)
		local part = makePart({
			Name = name,
			Parent = self.world.Roads,
			Shape = Enum.PartType.Cylinder,
			Size = size,
			CFrame = CFrame.new(center) * jointRotation,
			Color = partColor,
		})
		reveal(part, size)
		table.insert(parts, part)
		return part
	end

	-- Segment orienté librement, réservé aux liaisons diagonales. Il est
	-- volontairement placé très légèrement sous la forme arrondie centrale :
	-- la forme ovale recouvre le raccord et il ne reste aucun triangle.
	local function addRotatedBox(name, size, center, direction, partColor)
		local part = makePart({
			Name = name,
			Parent = self.world.Roads,
			Size = size,
			CFrame = CFrame.lookAt(center, center + direction),
			Color = partColor,
		})
		reveal(part, size)
		table.insert(parts, part)
		return part
	end

	local function addDiagonalSegment(name, width, height, centerY, partColor, dx, dz)
		local from = Grid.center(self.origin, x, y, 0)
		local to = Grid.center(self.origin, x + dx, y + dz, 0)
		local midpoint = (from + to) * 0.5
		local direction = (to - from).Unit
		local center = midpoint + Vector3.new(0, centerY, 0)
		addRotatedBox(
			name,
			Vector3.new(width, height, (to - from).Magnitude),
			center,
			direction,
			partColor
		)
	end

	-- Les directions orthogonales gardent exactement l'ancien rendu : cases
	-- droites, virages en arc et extrémités arrondies. Les directions
	-- diagonales sont collectées séparément et ajoutées sous ces formes.
	local neighborDirs = {}
	local diagonalDirs = {}
	for _, neighbor in ipairs(Grid.neighbors8(x, y)) do
		local nx, ny = neighbor[1], neighbor[2]
		if Grid.inBounds(nx, ny) and self.roads[Grid.key(nx, ny)] then
			local dx, dy = nx - x, ny - y
			if dx == 0 or dy == 0 then
				table.insert(neighborDirs, { dx, dy })
			else
				table.insert(diagonalDirs, { dx, dy, nx, ny })
			end
		end
	end

	-- Une diagonale droite ne doit pas avoir de tuile centrale plus large :
	-- sinon le ruban paraît bosselé à chaque case. On la laisse filer comme
	-- une route horizontale et on ne garde les formes centrales qu'aux
	-- virages, aux extrémités et aux jonctions.
	local isStraightDiagonal = false
	if #neighborDirs == 0 and #diagonalDirs == 2 then
		local a, b = diagonalDirs[1], diagonalDirs[2]
		if a[1] == -b[1] and a[2] == -b[2] then
			isStraightDiagonal = true
			local cellIsBridge = self.bridges[key] == true
			for _, diagonal in ipairs(diagonalDirs) do
				local neighborBridge = self.bridges[Grid.key(x + diagonal[1], y + diagonal[2])] == true
				if (cellIsBridge or neighborBridge) ~= cellIsBridge then
					isStraightDiagonal = false
					break
				end
			end
		end
	end

	-- Les lignes droites gardent des bords parfaitement droits. Un virage
	-- est un arc d'anneau : une suite de disques qui se chevauchent dessine
	-- l'extérieur et l'intérieur arrondis, avec une largeur constante.
	local isTurn = false
	local turnDirs = nil
	local rounded = nil
	if #neighborDirs == 0 then
		rounded = { NE = true, NW = true, SE = true, SW = true }
	elseif #neighborDirs == 2 then
		local a, b = neighborDirs[1], neighborDirs[2]
		if a[1] * b[1] + a[2] * b[2] == 0 then
			isTurn = true
			turnDirs = { a, b }
		end
	end

	local center = Grid.center(self.origin, x, y, 0)
	local function addLayer(name, width, height, centerY, radius, layerColor)
		local layerCenter = center + Vector3.new(0, centerY, 0)
		if not rounded then
			addBox(name, Vector3.new(width, height, width), layerCenter, layerColor)
			return
		end

		local r = math.min(radius, width * 0.5)
		local inner = width * 0.5 - r
		addBox(name .. "H", Vector3.new(width, height, width - 2 * r), layerCenter, layerColor)
		addBox(name .. "V", Vector3.new(width - 2 * r, height, width), layerCenter, layerColor)

		local corners = {
			{ key = "NE", sx = 1, sz = -1 },
			{ key = "NW", sx = -1, sz = -1 },
			{ key = "SE", sx = 1, sz = 1 },
			{ key = "SW", sx = -1, sz = 1 },
		}
		for _, corner in ipairs(corners) do
			if rounded[corner.key] then
				addCylinder(
					name .. corner.key,
					Vector3.new(height, 2 * r, 2 * r),
					layerCenter + Vector3.new(corner.sx * inner, 0, corner.sz * inner),
					layerColor
				)
			else
				addBox(
					name .. corner.key,
					Vector3.new(r, height, r),
					layerCenter + Vector3.new(corner.sx * (inner + r * 0.5), 0, corner.sz * (inner + r * 0.5)),
					layerColor
				)
			end
		end
	end

	local roadWidth = tile * 0.72
	local contourWidth = tile * 0.78
	local edgeWidth = tile * 0.84
	local cornerRadius = roadWidth * 0.42

	local function addArcLayer(name, width, height, centerY, layerColor, dirs)
		local d1, d2 = dirs[1], dirs[2]
		local outer = Vector3.new(-(d1[1] + d2[1]), 0, -(d1[2] + d2[2])).Unit
		local function perpTowardOuter(dir)
			local a = Vector3.new(dir[2], 0, -dir[1])
			local b = Vector3.new(-dir[2], 0, dir[1])
			if a:Dot(outer) >= b:Dot(outer) then
				return a
			end
			return b
		end

		local p1 = perpTowardOuter(d1)
		local p2 = perpTowardOuter(d2)
		local arcCenter = center
			+ Vector3.new((d1[1] + d2[1]) * tile * 0.5, centerY, (d1[2] + d2[2]) * tile * 0.5)
		local arcRadius = tile * 0.5
		local steps = 6
		for index = 0, steps do
			local t = index / steps
			local direction = (p1 * (1 - t) + p2 * t).Unit
			local circleCenter = arcCenter + direction * arcRadius
			addCylinder(
				name .. tostring(index),
				Vector3.new(height, width, width),
				circleCenter,
				layerColor
			)
		end
	end

	local function addTileLayer(name, width, height, centerY, layerColor)
		if isTurn then
			addArcLayer(name, width, height, centerY, layerColor, turnDirs)
			return
		end

		if #neighborDirs == 0 then
			-- Une diagonale droite est déjà couverte par le ruban et son
			-- disque de jonction. Une tuile plus large ferait une bosse.
			if not isStraightDiagonal then
				local offset = (width - roadWidth) * 0.5
				addLayer(name, width, height, centerY, cornerRadius + offset, layerColor)
			end
			return
		end

		local layerCenter = center + Vector3.new(0, centerY, 0)
		-- Une case qui a une seule route orthogonale et une diagonale n'est pas
		-- une extrémité : on ne dessine que la branche utile et le disque
		-- central, au lieu du grand capuchon historique qui créerait un ergot.
		if #neighborDirs == 1 and #diagonalDirs > 0 then
			local axis = neighborDirs[1]
			if axis[1] ~= 0 then
				addBox(
					name,
					Vector3.new(tile * 0.5, height, width),
					layerCenter + Vector3.new(axis[1] * tile * 0.25, 0, 0),
					layerColor
				)
			else
				addBox(
					name,
					Vector3.new(width, height, tile * 0.5),
					layerCenter + Vector3.new(0, 0, axis[2] * tile * 0.25),
					layerColor
				)
			end
			return
		end

		if #neighborDirs <= 2 then
			local axis = neighborDirs[1]
			if axis[1] ~= 0 then
				addBox(name, Vector3.new(tile, height, width), layerCenter, layerColor)
			else
				addBox(name, Vector3.new(width, height, tile), layerCenter, layerColor)
			end
			return
		end

		-- T et croisement : une branche par voisin, depuis le centre.
		for _, dir in ipairs(neighborDirs) do
			if dir[1] ~= 0 then
				addBox(
					name .. (dir[1] > 0 and "E" or "W"),
					Vector3.new(tile * 0.5, height, width),
					layerCenter + Vector3.new(dir[1] * tile * 0.25, 0, 0),
					layerColor
				)
			else
				addBox(
					name .. (dir[2] > 0 and "S" or "N"),
					Vector3.new(width, height, tile * 0.5),
					layerCenter + Vector3.new(0, 0, dir[2] * tile * 0.25),
					layerColor
				)
			end
		end
	end

	-- Les diagonales passent d'abord, sous les formes arrondies. On ne les
	-- dessine qu'une fois par arête (clé la plus petite) pour éviter les
	-- surfaces coplanaires qui clignotent.
	local diagonalLayers = {
		{
			name = "RoadOutline",
			width = edgeWidth,
			height = outlineHeight,
			centerY = outlineCenterY,
			color = edgeColor,
			bridgeHeight = 0.32,
			bridgeCenterY = 0.21,
			bridgeColor = Config.Colors.BridgeEdge,
		},
		{
			name = "RoadContour",
			width = contourWidth,
			height = contourHeight,
			centerY = contourCenterY,
			color = contourColor,
			bridgeHeight = 0.28,
			bridgeCenterY = 0.255,
			bridgeColor = contourColor,
		},
		{
			name = "Road",
			width = roadWidth,
			height = topHeight,
			centerY = topCenterY,
			color = color,
			bridgeHeight = 0.20,
			bridgeCenterY = 0.30,
			bridgeColor = Config.Colors.Bridge,
		},
	}
	for _, layer in ipairs(diagonalLayers) do
		for _, diagonal in ipairs(diagonalDirs) do
			local nx, ny = diagonal[1], diagonal[2]
			local neighborKey = Grid.key(nx, ny)
			if key < neighborKey then
				local edgeIsBridge = self.bridges[key] == true or self.bridges[neighborKey] == true
				addDiagonalSegment(
					layer.name .. "_" .. neighborKey,
					layer.width,
					edgeIsBridge and layer.bridgeHeight or layer.height,
					(edgeIsBridge and layer.bridgeCenterY or layer.centerY) - diagonalLift,
					edgeIsBridge and layer.bridgeColor or layer.color,
					diagonal[1],
					diagonal[2]
				)
			end
		end
	end

	-- Un disque central recouvre l'extrémité carrée de chaque segment diagonal.
	-- Il est placé entre les segments et les formes orthogonales : le raccord
	-- reste rond, sans coin ni triangle qui dépasse, même sur un T ou un
	-- croisement qui n'a pas de forme centrale arrondie.
	if #diagonalDirs > 0 and not isStraightDiagonal then
		for _, layer in ipairs(diagonalLayers) do
			local capHeight = isBridge and layer.bridgeHeight or layer.height
			local capCenterY = isBridge and layer.bridgeCenterY or layer.centerY
			addCylinder(
				layer.name .. "_Center",
				Vector3.new(capHeight, layer.width, layer.width),
				center + Vector3.new(0, capCenterY - diagonalLift * 0.5, 0),
				isBridge and layer.bridgeColor or layer.color
			)
		end
	end

	addTileLayer("RoadOutline", edgeWidth, outlineHeight, outlineCenterY, edgeColor)
	addTileLayer("RoadContour", contourWidth, contourHeight, contourCenterY, contourColor)
	addTileLayer("Road", roadWidth, topHeight, topCenterY, color)

	-- Extrémité : un demi-cercle net, dans le prolongement de la route.
	-- On le garde uniquement pour une vraie impasse orthogonale ; une case
	-- reliée aussi en diagonale est un virage, pas une extrémité.
	if #neighborDirs == 1 and #diagonalDirs == 0 then
		local dir = neighborDirs[1]
		local capCenter = Grid.center(self.origin, x - dir[1] * 0.5, y - dir[2] * 0.5, 0)
		addCylinder(
			"RoadOutlineCap",
			Vector3.new(outlineHeight - 0.02, edgeWidth, edgeWidth),
			capCenter + Vector3.new(0, outlineCenterY + layerLift, 0),
			edgeColor
		)
		addCylinder(
			"RoadContourCap",
			Vector3.new(contourHeight - 0.02, contourWidth, contourWidth),
			capCenter + Vector3.new(0, contourCenterY + layerLift, 0),
			contourColor
		)
		addCylinder(
			"RoadCap",
			Vector3.new(topHeight - 0.02, roadWidth, roadWidth),
			capCenter + Vector3.new(0, topCenterY + layerLift, 0),
			color
		)
	end

	self.roadParts[key] = parts
end

function Session:refreshRoadVisual(key)
	local parts = self.roadParts[key]
	if parts then
		for _, part in pairs(parts) do
			if part then
				part:Destroy()
			end
		end
		self.roadParts[key] = nil
	end
	if self.roads[key] then
		self:createRoadVisual(key, self.bridges[key] == true, 0, false)
	end
end

function Session:createRoundaboutVisual(key)
	local x, y = Grid.parse(key)
	if not x then
		return
	end
	local tile = self.tile
	local model = Instance.new("Model")
	model.Name = "Roundabout"

	local rotation = CFrame.Angles(0, 0, math.rad(90))
	-- Même liseré blanc fin que les routes, autour du rond-point graphite.
	makePart({
		Name = "RoundaboutContour",
		Parent = model,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.20, tile * 1.02, tile * 1.02),
		CFrame = CFrame.new(Grid.center(self.origin, x, y, 0.32)) * rotation,
		Color = Config.Colors.RoadContour,
	})
	makePart({
		Name = "RoundaboutOuter",
		Parent = model,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.18, tile * 0.92, tile * 0.92),
		CFrame = CFrame.new(Grid.center(self.origin, x, y, 0.34)) * rotation,
		Color = Config.Colors.Road,
	})
	makePart({
		Name = "RoundaboutInner",
		Parent = model,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.20, tile * 0.44, tile * 0.44),
		CFrame = CFrame.new(Grid.center(self.origin, x, y, 0.36)) * rotation,
		Color = Config.Colors.White,
	})
	makePart({
		Name = "RoundaboutDot",
		Parent = model,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.22, tile * 0.16, tile * 0.16),
		CFrame = CFrame.new(Grid.center(self.origin, x, y, 0.38)) * rotation,
		Color = Config.Colors.Ink,
	})

	model.Parent = self.world.FX
	self.roundaboutParts[key] = model
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

function Session:eraseRoad(key)
	if not self.running or self.over or self.awaitingChoice then
		return
	end
	if type(key) ~= "string" or not self.roads[key] then
		return
	end

	local x, y = Grid.parse(key)
	if not x then
		return
	end

	local roundabout = self.roundaboutParts[key]
	if roundabout then
		roundabout:Destroy()
		self.roundaboutParts[key] = nil
		self.roundaboutsLeft = math.min(Config.Roads.MaxRoundabouts, self.roundaboutsLeft + 1)
	end

	self.roads[key] = nil
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
	for _, neighbor in ipairs(Grid.neighbors8(x, y)) do
		local neighborKey = Grid.key(neighbor[1], neighbor[2])
		if self.roads[neighborKey] then
			self:refreshRoadVisual(neighborKey)
		end
	end

	self.roadVersion += 1
	self:refreshCarPaths()
	self:sendState()
end

function Session:refreshCarPaths()
	for _, car in ipairs(self.cars) do
		car.retry = 0
		car.roadVersion = -1
	end
end

function Session:parkingSpot(house)
	local base = Grid.center(self.origin, house.x, house.y, 0.5)
	for _, neighbor in ipairs(Grid.neighbors8(house.x, house.y)) do
		local nx, ny = neighbor[1], neighbor[2]
		if Grid.inBounds(nx, ny)
			and not self.buildings[Grid.key(nx, ny)]
			and not Maps.isWater(self.map, nx, ny)
		then
			local target = Grid.center(self.origin, nx, ny, 0.5)
			return base:Lerp(target, 0.42)
		end
	end
	return base + Vector3.new(1.1, 0, 0)
end

function Session:createCarVisual(house, spot)
	local palette = COLORS[house.colorIndex]
	local bodyCFrame = CFrame.new(spot)

	local model = Instance.new("Model")
	model.Name = "Car"

	-- Contour sombre sous la carrosserie.
	makePart({
		Name = "Outline",
		Parent = model,
		Size = Vector3.new(1.55, 0.28, 2.50),
		CFrame = bodyCFrame * CFrame.new(0, -0.10, 0),
		Color = Config.Colors.Ink,
	})

	local body = makePart({
		Name = "Body",
		Parent = model,
		Size = Vector3.new(1.35, 0.45, 2.30),
		CFrame = bodyCFrame,
		Color = palette.color,
	})
	model.PrimaryPart = body

	-- Toit clair, avec un liseré sombre.
	makePart({
		Name = "CabinOutline",
		Parent = model,
		Size = Vector3.new(1.02, 0.10, 1.18),
		CFrame = bodyCFrame * CFrame.new(0, 0.25, -0.15),
		Color = Config.Colors.Ink,
	})
	makePart({
		Name = "Cabin",
		Parent = model,
		Size = Vector3.new(0.84, 0.18, 0.98),
		CFrame = bodyCFrame * CFrame.new(0, 0.33, -0.15),
		Color = Config.Colors.White,
	})

	model:PivotTo(CFrame.new(spot))
	model.Parent = self.world.Cars
	return model
end

function Session:trySpawnCar(house)
	if house.car or self.over then
		return
	end

	local destination = house.dest
	if not destination then
		destination = self:findDestinationForHouse(house)
		house.dest = destination
	end
	if not destination then
		house.timer = 2
		return
	end

	local spot = self:parkingSpot(house)
	local car = {
		house = house,
		dest = destination,
		state = "out",
		path = nil,
		index = 2,
		t = 0,
		pos = spot,
		blocked = true,
		waitTime = 0,
		retry = 0,
		roadVersion = -1,
		part = self:createCarVisual(house, spot),
	}

	table.insert(self.cars, car)
	house.car = car

	local path = self:findPath(car)
	if path then
		self:setCarPath(car, path)
	end
end

function Session:findPath(car)
	local from = car.state == "out" and car.house or car.dest
	local to = car.state == "out" and car.dest or car.house

	local goalSet = {}
	for _, key in ipairs(self:connectorCells(to)) do
		goalSet[key] = true
	end
	if next(goalSet) == nil then
		return nil
	end

	local starts = self:connectorCells(from)
	if car.currentKey and self.roads[car.currentKey] then
		starts = { car.currentKey }
	end
	if #starts == 0 then
		return nil
	end

	local bestPath = nil
	for _, startKey in ipairs(starts) do
		local path = Pathfinding.find(self.roads, self.size, startKey, goalSet)
		if path and (not bestPath or #path < #bestPath) then
			bestPath = path
		end
	end
	return bestPath
end

function Session:setCarPath(car, path)
	if not path or #path == 0 then
		return
	end
	car.path = path
	car.index = 2
	car.t = 0
	car.currentKey = path[1]
	car.waitTime = 0
	car.retry = 0
	car.blocked = false
	car.roadVersion = self.roadVersion

	local x, y = Grid.parse(path[1])
	if x then
		car.pos = Grid.center(self.origin, x, y, 0.5)
		if car.part then
			car.part:PivotTo(CFrame.new(car.pos))
		end
	end
end

function Session:isBlockedAhead(car, direction)
	for _, other in ipairs(self.cars) do
		if other ~= car and other.pos then
			local delta = other.pos - car.pos
			local along = delta:Dot(direction)
			if along > 0 and along < Config.Traffic.CarSpacing then
				local lateral = (delta - direction * along).Magnitude
				if lateral < 0.9 then
					return true
				end
			end
		end
	end
	return false
end

function Session:completeLeg(car)
	if car.state == "out" then
		self.score += Config.Game.DeliveryScore
		self.satisfaction = math.min(
			Config.Traffic.SatisfactionMax,
			self.satisfaction + Config.Game.DeliverySatisfaction
		)
		car.state = "back"

		local reversed = {}
		for i = #car.path, 1, -1 do
			reversed[#reversed + 1] = car.path[i]
		end
		car.path = reversed
		car.index = 2
		car.t = 0
		car.currentKey = reversed[1]
		car.waitTime = 0
		car.retry = 0
		car.roadVersion = self.roadVersion

		self:destinationPulse(car.dest)
		return false
	end

	return true
end

function Session:updateCar(car, dt)
	if not car.path then
		car.retry -= dt
		if car.retry <= 0 then
			car.retry = Config.Traffic.RetryPathInterval
			local path = self:findPath(car)
			if path then
				self:setCarPath(car, path)
			end
		end
		car.blocked = true
		car.waitTime += dt
		return false
	end

	if car.index > #car.path then
		return self:completeLeg(car)
	end

	local fromKey = car.path[car.index - 1]
	local toKey = car.path[car.index]
	if not self.roads[toKey] then
		local path = self:findPath(car)
		if path then
			self:setCarPath(car, path)
		else
			car.path = nil
			car.retry = Config.Traffic.RetryPathInterval
		end
		return false
	end

	local fx, fy = Grid.parse(fromKey)
	local tx, ty = Grid.parse(toKey)
	if not fx or not tx then
		car.path = nil
		return false
	end

	local fromPos = Grid.center(self.origin, fx, fy, 0.5)
	local toPos = Grid.center(self.origin, tx, ty, 0.5)
	local direction = (toPos - fromPos).Unit
	-- La vitesse doit rester en studs/seconde réels : une diagonale est
	-- plus longue qu'une case orthogonale, donc on divise par la longueur
	-- du segment et non par la taille de la case.
	local segmentLength = math.max((toPos - fromPos).Magnitude, 0.001)

	local blocked = self:isBlockedAhead(car, direction)
	if blocked then
		car.blocked = true
		car.waitTime += dt
	else
		car.blocked = false
		car.waitTime = math.max(0, car.waitTime - dt * 2)
		car.t += (Config.Traffic.CarSpeed * dt) / segmentLength
	end

	if car.t >= 1 then
		car.t = 0
		car.index += 1
		car.currentKey = toKey
		car.pos = toPos
		if car.part then
			car.part:PivotTo(CFrame.new(toPos))
		end
		if car.index > #car.path then
			return self:completeLeg(car)
		end
		return false
	end

	car.pos = fromPos:Lerp(toPos, car.t) + Vector3.new(-direction.Z, 0, direction.X) * 0.55
	if car.part then
		car.part:PivotTo(CFrame.lookAt(car.pos, car.pos + direction))
	end
	return false
end

function Session:retireCar(car)
	if car.part then
		car.part:Destroy()
		car.part = nil
	end
	local house = car.house
	if house then
		house.car = nil
		house.timer = Config.Game.SpawnInterval
	end
end

function Session:destinationPulse(destination)
	if not destination or not self.world then
		return
	end

	local ring = Instance.new("Part")
	ring.Name = "Delivery"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = destination.color
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.1, 3.2, 3.2)
	ring.CFrame = CFrame.new(Grid.center(self.origin, destination.x, destination.y, 0.35))
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = self.world.FX

	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, 7.5, 7.5),
		Transparency = 1,
	}):Play()

	task.delay(0.6, function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

function Session:updateSatisfaction(dt)
	local drain = 0
	for _, car in ipairs(self.cars) do
		-- Une voiture sans trajet n'est pas encore "dans le trafic" :
		-- on ne pénalise que les voitures réellement bloquées sur un chemin.
		if car.path and car.waitTime >= Config.Traffic.StuckAfter then
			drain += Config.Traffic.DrainPerStuckCar
		end
	end

	if drain > 0 then
		self.satisfaction -= drain * dt
	else
		self.satisfaction = math.min(
			Config.Traffic.SatisfactionMax,
			self.satisfaction + Config.Traffic.RegenPerSecond * dt
		)
	end

	if self.satisfaction <= 0 then
		self.satisfaction = 0
		self:gameOver()
	end
end

function Session:pickWeekChoices()
	local roadReward = math.random() < 0.35 and Config.Rewards.RoadsSmall or Config.Rewards.Roads
	local secondReward = math.random() < 0.5 and Config.Rewards.Bridge or Config.Rewards.Roundabout
	local options = { roadReward, secondReward }
	if math.random() < 0.5 then
		options[1], options[2] = options[2], options[1]
	end
	return options
end

function Session:offerWeekChoice()
	self.awaitingChoice = true
	self.paused = true
	self.choice = {
		week = self.week,
		options = self:pickWeekChoices(),
	}
	Remotes.get("WeekChoice"):FireClient(self.player, self.choice)
	self:sendState()
end

function Session:chooseReward(optionId)
	if not self.awaitingChoice or not self.choice then
		return
	end
	local selected = nil
	for _, option in ipairs(self.choice.options or {}) do
		if option.id == optionId then
			selected = option
			break
		end
	end
	if not selected then
		return
	end

	if selected.kind == "roads" then
		self.budget = math.min(Config.Roads.MaxBudget, self.budget + selected.amount)
	elseif selected.kind == "bridges" then
		self.bridgesLeft = math.min(Config.Roads.MaxBridges, self.bridgesLeft + selected.amount)
	elseif selected.kind == "roundabouts" then
		self.roundaboutsLeft = math.min(Config.Roads.MaxRoundabouts, self.roundaboutsLeft + selected.amount)
	end

	self.awaitingChoice = false
	self.choice = nil
	self.paused = false
	self:sendState()
	self:toast("Amélioration choisie : " .. selected.title .. ".")
end

function Session:setSpeed(value)
	value = tonumber(value) or 1
	self.speed = clamp(math.floor(value), 1, 3)
	self:sendState()
end

function Session:update(dt)
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

	self.pairClock -= dt
	if self.pairClock <= 0 and #self.houses < Config.Game.MaxPairs then
		self.pairClock = Config.Game.PairInterval
		self:spawnPair(false)
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

function Session:sendState()
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
		cars = #self.cars,
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

	self:sendState()
	self:toast("Tracez des routes entre les maisons et les bâtiments de la même couleur.")
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
	self.choice = nil
end

return Session
