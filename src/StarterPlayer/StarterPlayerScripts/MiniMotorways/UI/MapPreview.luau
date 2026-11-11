--[[
	MapPreview.luau
	Dessine l'aperçu circulaire d'une carte dans le menu, avec les formes de
	Maps.luau et le même ordre de superposition que WorldBuilder : parcs, liseré
	de côte, eau, puis presqu'îles (liseré, terre sèche). Viennent ensuite le
	réseau et les maisons. Aucune image, aucun libellé.

	Roblox n'a pas d'ellipse native. Une forme elliptique est donc un seul Frame
	dont les coins ont un rayon de 50 % : un disque si rx = ry, sinon une capsule
	de même encombrement que l'ellipse. Le grand axe suit rx, comme dans
	Maps.isWaterAt. Les bouts arrondis des ellipses allongées sont plus pleins
	qu'une vraie ellipse ; les maisons, elles, ne sont jamais posées sur l'eau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)

local Theme = require(script.Parent.Theme)

local C = Config.Colors

local MapPreview = {}

-- Réglages, en fractions du diamètre sauf indication contraire (px).
local RING_PADDING = 4 -- px entre le disque et son halo
local HALO_TRANSPARENCY = 0.55 -- halo très doux, pas de liseré dur
-- Liseré de côte : la même épaisseur relative qu'en 3D (Terrain.Shoreline sur
-- le côté du plateau), avec un minimum pour rester visible sur un petit aperçu.
local BOARD_EXTENT = Config.Grid.Size * Config.Grid.TileSize
local SHORE_RATIO = Config.Terrain.Shoreline / BOARD_EXTENT
local SHORE_MIN = 1.8 -- px
local ROAD_THICKNESS = 0.03
local HOUSE_RATIO = 0.075
local HOUSE_MIN = 12 -- px
local DEFAULT_BAR_THICKNESS = 0.04
local MIN_SIZE = 0.5 -- px : une forme plus petite n'est pas dessinée

-- Cadre centré en (x, y), sans bordure. Le zIndex range la forme dans l'ordre
-- de superposition ; rotation est en degrés, sens horaire comme Roblox.
local function addFrame(parent, x, y, width, height, color, zIndex, rotation)
	return Theme.new("Frame", {
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, height),
		Rotation = rotation or 0,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	})
end

-- Coins à 50 % : le cadre devient un disque (carré) ou une capsule (rectangle).
local function roundEnds(frame)
	Theme.corner(frame, UDim.new(0.5, 0))
end

-- Disque centré en (x, y).
local function addDisc(parent, x, y, size, color, zIndex)
	local disc = addFrame(parent, x, y, size, size, color, zIndex)
	roundEnds(disc)
	return disc
end

-- Ellipse : un seul Frame tourné. Le grand axe suit rx dans le repère de la
-- forme (même règle que Maps.isWaterAt), donc tourné de 90 degrés si ry est le
-- plus grand. Un liseré (grow) élargit l'ellipse de chaque côté.
local function drawEllipse(parent, shape, diameter, color, grow, zIndex)
	local rxNorm = shape.rx or shape.r or 0.05
	local ryNorm = shape.ry or shape.r or rxNorm
	local rx = rxNorm * diameter + grow
	local ry = ryNorm * diameter + grow
	local minor = math.min(rx, ry)
	local major = math.max(rx, ry)
	if minor < MIN_SIZE then
		return
	end

	local rotation = shape.rotation or 0
	if ry > rx then
		rotation += 90
	end
	local blob = addFrame(
		parent,
		shape.x * diameter,
		shape.y * diameter,
		major * 2,
		minor * 2,
		color,
		zIndex,
		rotation
	)
	roundEnds(blob)
end

-- Segment épais de (x1, y1) à (x2, y2). Par défaut les deux bouts sont ronds
-- (une seule capsule). Avec flatStart, le bout x1 est une coupe nette côté
-- terre et seul le bout x2 reçoit un capuchon rond, comme en 3D.
local function drawBar(parent, shape, diameter, color, grow, zIndex)
	local x1 = shape.x1 * diameter
	local y1 = shape.y1 * diameter
	local x2 = shape.x2 * diameter
	local y2 = shape.y2 * diameter
	local dx = x2 - x1
	local dy = y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)
	if length <= 0 then
		return
	end
	local thickness = (shape.thickness or DEFAULT_BAR_THICKNESS) * diameter + grow * 2
	local angle = math.deg(math.atan2(dy, dx))
	local centerX = (x1 + x2) * 0.5
	local centerY = (y1 + y2) * 0.5

	if shape.flatStart then
		addFrame(parent, centerX, centerY, length, thickness, color, zIndex, angle)
		addDisc(parent, x2, y2, thickness, color, zIndex)
		return
	end

	-- Capsule : chaque bout rond dépasse du rayon, d'où length + thickness.
	local capsule = addFrame(parent, centerX, centerY, length + thickness, thickness, color, zIndex, angle)
	roundEnds(capsule)
end

-- Rectangle de Maps (rect) : un cadre, avec un arrondi seulement si la forme
-- en demande un. grow élargit le rectangle de chaque côté.
local function drawRect(parent, shape, diameter, color, grow, zIndex)
	local frame = Theme.new("Frame", {
		Parent = parent,
		Position = UDim2.fromOffset(shape.x * diameter - grow, shape.y * diameter - grow),
		Size = UDim2.fromOffset(shape.w * diameter + grow * 2, shape.h * diameter + grow * 2),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	})
	local radius = (shape.radius or 0) * diameter + grow
	if radius > 0 then
		Theme.corner(frame, radius)
	end
end

-- Dessine une forme de Maps.luau (rect, ellipse, circle, bar). grow élargit la
-- forme de chaque côté : c'est ainsi que le liseré de côte est tracé.
local function drawShape(parent, shape, diameter, color, grow, zIndex)
	local kind = shape.type
	if kind == "rect" then
		drawRect(parent, shape, diameter, color, grow, zIndex)
	elseif kind == "circle" or kind == "ellipse" then
		drawEllipse(parent, shape, diameter, color, grow, zIndex)
	elseif kind == "bar" then
		drawBar(parent, shape, diameter, color, grow, zIndex)
	end
end

function MapPreview.create(parent, map, diameter, position, anchorPoint)
	local id = tostring(map.id or "map")
	local land = map.land or C.Land
	local water = map.water or C.Water
	local grass = map.grass or C.Park
	local coast = C.Coast
	local outline = math.max(SHORE_MIN, diameter * SHORE_RATIO)

	local grassShapes = map.grassShapes or {}
	local waterShapes = map.waterShapes or {}
	local dryShapes = map.dryShapes or {}
	-- Même règle d'eau que la construction (Maps.isWaterAt) : une presqu'île
	-- retire de l'eau, tout le reste est de l'eau si une forme d'eau le couvre.
	local terrain = { waterShapes = waterShapes, dryShapes = dryShapes }

	local wrapperSize = diameter + RING_PADDING * 2
	local wrapper = Theme.new("Frame", {
		Name = "PreviewFrame_" .. id,
		Parent = parent,
		Position = position or UDim2.fromScale(0.5, 0),
		AnchorPoint = anchorPoint or Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(wrapperSize, wrapperSize),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
	})
	-- Halo doux, sans liseré : le cercle se détache par la couleur, pas par un trait.
	Theme.circle(wrapper, wrapperSize, C.RingShadow, {
		Name = "Halo",
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = HALO_TRANSPARENCY,
		ZIndex = 1,
	})

	-- CanvasGroup : il découpe réellement ses enfants selon le cercle, donc l'eau
	-- ne déborde jamais dans les angles.
	local circle = Theme.new("CanvasGroup", {
		Name = "Preview_" .. id,
		Parent = wrapper,
		Position = UDim2.fromOffset(RING_PADDING, RING_PADDING),
		Size = UDim2.fromOffset(diameter, diameter),
		BackgroundColor3 = land,
		BorderSizePixel = 0,
		ZIndex = 2,
	})
	Theme.corner(circle, diameter / 2)

	-- Ordre identique à WorldBuilder : parcs, liseré puis eau, presqu'îles.
	for _, shape in ipairs(grassShapes) do
		drawShape(circle, shape, diameter, grass, 0, 1)
	end
	for _, shape in ipairs(waterShapes) do
		drawShape(circle, shape, diameter, coast, outline, 2)
	end
	for _, shape in ipairs(waterShapes) do
		drawShape(circle, shape, diameter, water, 0, 3)
	end
	for _, shape in ipairs(dryShapes) do
		drawShape(circle, shape, diameter, coast, outline, 4)
	end
	for _, shape in ipairs(dryShapes) do
		drawShape(circle, shape, diameter, land, 0, 5)
	end

	-- Réseau : routes anthracite de largeur uniforme, comme en jeu.
	local roads = map.previewRoads or {}
	for _, road in ipairs(roads) do
		if road[1] and road[2] and road[3] and road[4] then
			drawBar(circle, {
				x1 = road[1],
				y1 = road[2],
				x2 = road[3],
				y2 = road[4],
				thickness = ROAD_THICKNESS,
			}, diameter, C.Road, 0, 7)
		end
	end

	-- Maisons : extrémités des routes, hors des bords et hors de l'eau. Chacune a
	-- une ombre décalée, sans contour.
	local houses = Config.HouseColors
	local houseSize = math.max(HOUSE_MIN, diameter * HOUSE_RATIO)
	local seen = {}
	for index, road in ipairs(roads) do
		local points = { { road[1], road[2] }, { road[3], road[4] } }
		for pointIndex, point in ipairs(points) do
			local nx = point[1]
			local ny = point[2]
			if type(nx) == "number" and type(ny) == "number" then
				-- Clé entière au millième : deux extrémités identiques ne tracent qu'une maison.
				local key = math.floor(nx * 1000 + 0.5) * 1000 + math.floor(ny * 1000 + 0.5)
				local inside = nx > 0.02 and nx < 0.98 and ny > 0.02 and ny < 0.98
				if not seen[key] and inside and not Maps.isWaterAt(terrain, nx, ny) then
					seen[key] = true
					local color = C.Teal
					if #houses > 0 then
						color = houses[(index + pointIndex - 1) % #houses + 1].color
					end
					local x = nx * diameter
					local y = ny * diameter
					local shadow = addFrame(circle, x, y + Theme.Shadow.Offset, houseSize, houseSize, C.CardShadow, 8)
					shadow.Name = "HouseShadow"
					shadow.BackgroundTransparency = Theme.Shadow.Transparency
					Theme.corner(shadow, Theme.Radius.Small)
					local house = addFrame(circle, x, y, houseSize, houseSize, color, 9)
					house.Name = "House"
					Theme.corner(house, Theme.Radius.Small)
				end
			end
		end
	end

	return circle
end

return MapPreview
