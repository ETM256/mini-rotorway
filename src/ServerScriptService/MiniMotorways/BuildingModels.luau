--[[
	BuildingModels.luau
	Construction visuelle pure des maisons et des magasins. Aucune logique de
	partie : SessionBuildings décide où et quand un bâtiment existe, ce module
	fabrique son Model.

	Tout reste dans la case : une maison occupe au plus 0.62 de la case, un
	magasin au plus 0.9, ombre comprise. Une route posée dans la case voisine
	touche la limite de la case sans jamais traverser le bâtiment.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BuildingShapes = require(script.Parent.BuildingShapes)
local SessionUtil = require(script.Parent.SessionUtil)

local BuildingModels = {}

local PALETTE = Config.HouseColors
local CELL = Config.Grid.TileSize
local HALF_CELL = CELL * 0.5
local WHITE = Config.Colors.White
local SHADOW_COLOR = Config.Colors.BuildingShadow

-- Tailles en fraction de la case, rayon des coins et ombre : tout vient de
-- Config, pour que les pins et les voitures lisent les mêmes valeurs.
local SIZE = Config.Dimensions.Building
local CORNER_RATIO = Config.Style.BuildingCornerRatio
local SHADOW = Config.Style.Shadow

-- Hauteurs (bas de chaque couche). Les routes montent jusqu'à 0.40 (tablier
-- d'un pont, RoadConfig.Layers) : tous les bâtiments sont posés au-dessus, sans
-- faces coplanaires entre couches.
local LAYER = {
	Shadow = { bottom = 0.38, height = 0.04 },
	Halo = { bottom = 0.40, height = 0.10 },
	Body = { bottom = 0.42, height = 0.14 },
	Pad = { bottom = 0.42, height = 0.08 },
	Detail = { bottom = 0.56, height = 0.05 },
}

local ENTRANCE_PAD_WIDTH = 0.5
local ENTRANCE_PAD_MIN_DEPTH = 0.2
local HALO_WIDTH = 0.06
local LARGE_LOGO_RATIO = 0.36
local SMALL_LOGO_RATIO = 0.28
local DOT_DIAMETER = 0.36
local RIDGE_LENGTH_RATIO = 0.56
local RIDGE_THICKNESS = 0.2

-- Quatre variantes discrètes par couleur : proportions du socle (fraction de
-- la taille de base) et petit détail de toit. Le détail garde la couleur du
-- groupe. L'orientation est choisie à part, par quart de tour.
local HOUSE_VARIANTS = {
	{ width = 1.00, depth = 0.90, detail = nil },
	{ width = 0.90, depth = 1.00, detail = "Chimney" },
	{ width = 0.94, depth = 0.84, detail = "Garden" },
	{ width = 1.00, depth = 0.96, detail = "Chimney" },
}

local function paletteFor(colorIndex)
	local palette = PALETTE[colorIndex] or PALETTE[1]
	local color = palette.color
	local base = palette.base or color:Lerp(Config.Colors.Ink, 0.22)
	return color, base
end

-- Point situé dans le repère local d'un bâtiment tourné de `angle`, ramené
-- au monde. Sert à placer le toit, le détail et l'entrée.
local function pointAt(center, angle, localX, localZ)
	local frame = CFrame.new(center) * CFrame.Angles(0, angle, 0)
	return frame:PointToWorldSpace(Vector3.new(localX, 0, localZ))
end

local function shadowCenter(center)
	return center + Vector3.new(SHADOW.Offset, 0, SHADOW.Offset)
end

-- Entrée : une petite dalle blanche qui relie le bord du bâtiment à la limite
-- de la case, du côté de la route. `extent` est la demi-taille du bâtiment
-- dans la direction de l'entrée.
local function addEntrance(model, center, entranceAngle, extent)
	local depth = math.max(ENTRANCE_PAD_MIN_DEPTH, HALF_CELL - extent - 0.02)
	local normal = Vector3.new(math.sin(entranceAngle), 0, math.cos(entranceAngle))
	BuildingShapes.rect(
		model,
		"Entrance",
		center + normal * (extent + depth * 0.5),
		ENTRANCE_PAD_WIDTH,
		depth,
		LAYER.Pad.bottom,
		LAYER.Pad.height,
		WHITE,
		entranceAngle
	)
end

-- Variante, orientation et dimensions d'une maison, déduites de son identifiant :
-- le même résultat sert à la construction et au recalcul de l'entrée.
local function houseFootprint(id)
	local variant = HOUSE_VARIANTS[id % #HOUSE_VARIANTS + 1]
	local turn = (math.floor(id / #HOUSE_VARIANTS) % 4) * math.pi * 0.5
	local side = SIZE.House * CELL
	return variant, turn, side * variant.width, side * variant.depth
end

-- Demi-taille du bâtiment dans la direction de l'entrée : la dalle part du bord
-- réel, que l'orientation soit horizontale ou verticale.
local function entranceExtent(kind, id, storeType, entranceAngle)
	if kind ~= "house" then
		local size = (storeType == "large" and SIZE.LargeStore or SIZE.SmallStore) * CELL
		return size * 0.5
	end
	local _, turn, width, depth = houseFootprint(id)
	local facesDepth = math.abs(math.cos(entranceAngle - turn)) > 0.5
	return facesDepth and depth * 0.5 or width * 0.5
end

local function buildHouse(model, center, id, color, base, entranceAngle)
	local variant, turn, width, depth = houseFootprint(id)
	local radius = math.min(width, depth) * CORNER_RATIO

	BuildingShapes.ellipse(
		model,
		"Shadow",
		shadowCenter(center),
		width + SHADOW.Grow,
		depth + SHADOW.Grow,
		LAYER.Shadow.bottom,
		LAYER.Shadow.height,
		SHADOW_COLOR,
		turn,
		SHADOW.Transparency
	)
	local body = BuildingShapes.roundedRect(
		model,
		"Body",
		center,
		width,
		depth,
		radius,
		LAYER.Body.bottom,
		LAYER.Body.height,
		color,
		turn
	)

	-- Toit bi-ton : une arête plus foncée posée sur la moitié arrière.
	BuildingShapes.rect(
		model,
		"Ridge",
		pointAt(center, turn, 0, -depth * 0.12),
		width * RIDGE_LENGTH_RATIO,
		RIDGE_THICKNESS,
		LAYER.Detail.bottom,
		LAYER.Detail.height,
		base,
		turn
	)

	if variant.detail == "Chimney" then
		BuildingShapes.circle(
			model,
			"Chimney",
			pointAt(center, turn, -width * 0.26, depth * 0.24),
			DOT_DIAMETER,
			LAYER.Detail.bottom,
			LAYER.Detail.height,
			base
		)
	elseif variant.detail == "Garden" then
		BuildingShapes.circle(
			model,
			"Garden",
			pointAt(center, turn, width * 0.26, depth * 0.24),
			DOT_DIAMETER,
			LAYER.Detail.bottom,
			LAYER.Detail.height,
			base
		)
	end

	addEntrance(model, center, entranceAngle, entranceExtent("house", id, nil, entranceAngle))
	return body
end

local function buildSmallStore(model, center, color, entranceAngle)
	local side = SIZE.SmallStore * CELL
	local radius = side * CORNER_RATIO

	local body = BuildingShapes.roundedRect(
		model,
		"Body",
		center,
		side,
		side,
		radius,
		LAYER.Body.bottom,
		LAYER.Body.height,
		color,
		0
	)
	BuildingShapes.roundedRect(
		model,
		"Shadow",
		shadowCenter(center),
		side + SHADOW.Grow,
		side + SHADOW.Grow,
		radius + SHADOW.Grow * 0.5,
		LAYER.Shadow.bottom,
		LAYER.Shadow.height,
		SHADOW_COLOR,
		0,
		SHADOW.Transparency
	)
	BuildingShapes.circle(
		model,
		"Logo",
		center,
		side * SMALL_LOGO_RATIO,
		LAYER.Detail.bottom,
		LAYER.Detail.height,
		WHITE
	)
	addEntrance(model, center, entranceAngle, side * 0.5)
	return body
end

local function buildLargeStore(model, center, color, entranceAngle)
	local diameter = SIZE.LargeStore * CELL

	BuildingShapes.circle(
		model,
		"Shadow",
		shadowCenter(center),
		diameter + SHADOW.Grow,
		LAYER.Shadow.bottom,
		LAYER.Shadow.height,
		SHADOW_COLOR,
		SHADOW.Transparency
	)
	-- Liseré blanc fin : sépare le disque du sol sans contour noir.
	BuildingShapes.circle(
		model,
		"Halo",
		center,
		diameter + HALO_WIDTH * 2,
		LAYER.Halo.bottom,
		LAYER.Halo.height,
		WHITE
	)
	local body = BuildingShapes.circle(
		model,
		"Body",
		center,
		diameter,
		LAYER.Body.bottom,
		LAYER.Body.height,
		color
	)
	BuildingShapes.circle(
		model,
		"Logo",
		center,
		diameter * LARGE_LOGO_RATIO,
		LAYER.Detail.bottom,
		LAYER.Detail.height,
		WHITE
	)
	addEntrance(model, center, entranceAngle, diameter * 0.5)
	return body
end

-- Construit le Model d'une maison ou d'un magasin, posé sur la case dont le
-- centre au sol est `cellCenter`. options :
--   parent         dossier où ranger le Model (optionnel)
--   entranceAngle  angle de lacet de l'entrée (0, pi/2, pi ou -pi/2 ; défaut 0)
-- Renvoie le Model ; la partie logique (taille de la case, animations) reste
-- au Session appelant.
function BuildingModels.build(kind, id, cellCenter, colorIndex, storeType, options)
	options = options or {}
	local isStore = kind == "store"
	local isLarge = isStore and storeType == "large"
	local color, base = paletteFor(colorIndex)
	local center = Vector3.new(cellCenter.X, 0, cellCenter.Z)
	local entranceAngle = options.entranceAngle or 0

	local model = Instance.new("Model")
	model.Name = kind .. "_" .. tostring(id) .. (isStore and ("_" .. (storeType or "small")) or "")

	local body
	if not isStore then
		body = buildHouse(model, center, id, color, base, entranceAngle)
	elseif isLarge then
		body = buildLargeStore(model, center, color, entranceAngle)
	else
		body = buildSmallStore(model, center, color, entranceAngle)
	end
	model.PrimaryPart = body

	model:SetAttribute("BuildingKind", kind)
	model:SetAttribute("BuildingId", id)
	model:SetAttribute("ColorIndex", colorIndex)
	if isStore then
		model:SetAttribute("StoreType", storeType or "small")
	end
	if options.parent then
		model.Parent = options.parent
	end
	return model
end

local function forEachPart(model, callback)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			callback(descendant)
		end
	end
end

-- Remet l'entrée d'un bâtiment déjà construit vers un autre côté. Seule la
-- dalle est refaite (une part) : le reste du Model ne bouge pas.
function BuildingModels.aimEntrance(model, cellCenter, kind, id, storeType, entranceAngle)
	local old = model:FindFirstChild("Entrance")
	if old then
		old:Destroy()
	end
	local center = Vector3.new(cellCenter.X, 0, cellCenter.Z)
	addEntrance(model, center, entranceAngle, entranceExtent(kind, id, storeType, entranceAngle))
end

-- Fondu sortant : toutes les parts deviennent transparentes. Le Model doit
-- être détruit par l'appelant après la durée. `tweens` (table de Session)
-- permet d'arrêter les tweens à la fin de la partie.
function BuildingModels.fadeOut(model, duration, tweens)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	forEachPart(model, function(part)
		SessionUtil.trackTween(tweens, TweenService:Create(part, info, { Transparency = 1 })):Play()
	end)
end

-- Fondu entrant : chaque part repart de l'opacité nulle puis rejoint sa
-- transparence de construction (l'ombre reste discrète).
function BuildingModels.fadeIn(model, duration, tweens)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	forEachPart(model, function(part)
		local target = part.Transparency
		part.Transparency = 1
		SessionUtil.trackTween(tweens, TweenService:Create(part, info, { Transparency = target })):Play()
	end)
end

return BuildingModels
