--[[
	WorldBuilder.luau
	Construit le décor 3D d'une ville : sol, eau lissée, lignes de grille,
	puis les dossiers qui recevront routes, bâtiments et voitures.
	L'eau est dessinée avec les mêmes formes que l'aperçu du menu :
	rectangles, ellipses et capsules, avec une ombre d'eau et un liseré de
	côte blanc autour du remplissage menthe.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local WorldBuilder = {}

local function part(props)
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

-- Important : une Part de type Ball garde toujours un diamètre rond
-- (le minimum de ses trois axes). Pour obtenir une vraie ellipse d'eau
-- aplatie, on utilise un SpecialMesh sphère, qui suit les proportions
-- de la Part.
local function addSphereMesh(p)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = p
	return p
end

-- Dessine une forme d'eau normalisée (0..1) à l'échelle de la carte.
-- padding agrandit la forme pour créer l'ombre ou le liseré de côte.
local function drawWaterShape(parent, shape, origin, mapSize, color, height, centerY, padding)
	local kind = shape.type
	padding = padding or 0

	if kind == "rect" then
		local center = Vector3.new(
			origin.X + (shape.x + shape.w * 0.5) * mapSize,
			centerY,
			origin.Z + (shape.y + shape.h * 0.5) * mapSize
		)
		part({
			Name = "Water",
			Parent = parent,
			Size = Vector3.new(
				shape.w * mapSize + padding * 2,
				height,
				shape.h * mapSize + padding * 2
			),
			CFrame = CFrame.new(center),
			Color = color,
		})
		return
	end

	if kind == "circle" or kind == "ellipse" then
		local rx = shape.rx or shape.r or 0.05
		local ry = shape.ry or shape.r or rx
		local center = Vector3.new(
			origin.X + shape.x * mapSize,
			centerY,
			origin.Z + shape.y * mapSize
		)
		-- La rotation de l'aperçu est horaire à l'écran ; en 3D, l'axe Z
		-- descend et l'axe Y tourne dans le sens inverse.
		local rotation = CFrame.Angles(0, math.rad(-(shape.rotation or 0)), 0)
		local p = part({
			Name = "Water",
			Parent = parent,
			Size = Vector3.new(
				rx * 2 * mapSize + padding * 2,
				height,
				ry * 2 * mapSize + padding * 2
			),
			CFrame = CFrame.new(center) * rotation,
			Color = color,
		})
		addSphereMesh(p)
		return
	end

	if kind == "bar" then
		local thickness = (shape.thickness or 0.04) * mapSize
		local radius = thickness * 0.5 + padding
		local x1 = shape.x1 * mapSize
		local z1 = shape.y1 * mapSize
		local x2 = shape.x2 * mapSize
		local z2 = shape.y2 * mapSize
		local dx = x2 - x1
		local dz = z2 - z1
		local length = math.sqrt(dx * dx + dz * dz)
		if length <= 0 then
			return
		end

		if shape.flatStart then
			-- Presqu'île : le côté terre est coupé net, seul le côté eau
			-- garde un bout arrondi. Cela évite le gros capuchon blanc qui
			-- dépassait sur le continent.
			local from = Vector3.new(origin.X + x1, centerY, origin.Z + z1)
			local to = Vector3.new(origin.X + x2, centerY, origin.Z + z2)
			local direction = (to - from).Unit
			part({
				Name = "Water",
				Parent = parent,
				Size = Vector3.new(radius * 2, height, length),
				CFrame = CFrame.lookAt((from + to) * 0.5, (from + to) * 0.5 + direction),
				Color = color,
			})
			local cap = part({
				Name = "Water",
				Parent = parent,
				Size = Vector3.new(radius * 2, height, radius * 2),
				CFrame = CFrame.new(to),
				Color = color,
			})
			addSphereMesh(cap)
			return
		end

		local step = math.max(0.35, radius * 0.35)
		local count = math.max(1, math.ceil(length / step))
		for i = 0, count do
			local t = i / count
			local p = part({
				Name = "Water",
				Parent = parent,
				Size = Vector3.new(radius * 2, height, radius * 2),
				CFrame = CFrame.new(
					origin.X + x1 + dx * t,
					centerY,
					origin.Z + z1 + dz * t
				),
				Color = color,
			})
			addSphereMesh(p)
		end
	end
end

-- Cache l'eau qui dépasserait de la carte, pour garder un bord net.
local function addWaterMasks(parent, origin, mapSize, border)
	local y = 0.17
	local thickness = 0.06
	local outer = mapSize + border * 2

	part({
		Name = "WaterMaskTop",
		Parent = parent,
		Size = Vector3.new(outer, thickness, border),
		CFrame = CFrame.new(origin.X + mapSize * 0.5, y, origin.Z - border * 0.5),
		Color = Config.Colors.Paper,
	})
	part({
		Name = "WaterMaskBottom",
		Parent = parent,
		Size = Vector3.new(outer, thickness, border),
		CFrame = CFrame.new(origin.X + mapSize * 0.5, y, origin.Z + mapSize + border * 0.5),
		Color = Config.Colors.Paper,
	})
	part({
		Name = "WaterMaskLeft",
		Parent = parent,
		Size = Vector3.new(border, thickness, mapSize),
		CFrame = CFrame.new(origin.X - border * 0.5, y, origin.Z + mapSize * 0.5),
		Color = Config.Colors.Paper,
	})
	part({
		Name = "WaterMaskRight",
		Parent = parent,
		Size = Vector3.new(border, thickness, mapSize),
		CFrame = CFrame.new(origin.X + mapSize + border * 0.5, y, origin.Z + mapSize * 0.5),
		Color = Config.Colors.Paper,
	})
end

-- Étiquette verticale sur la bordure, comme « LOS ANGELES » dans la vidéo.
local function addMapLabel(parent, origin, mapSize, border, label)
	local side = label.side or "right"
	local strip
	if side == "left" then
		strip = part({
			Name = "MapLabelStrip",
			Parent = parent,
			Size = Vector3.new(border * 0.42, 0.06, mapSize * 0.64),
			CFrame = CFrame.new(origin.X - border * 0.5, 0.255, origin.Z + mapSize * 0.5),
			Color = Config.Colors.Teal,
			Transparency = 0.08,
		})
	else
		strip = part({
			Name = "MapLabelStrip",
			Parent = parent,
			Size = Vector3.new(border * 0.42, 0.06, mapSize * 0.64),
			CFrame = CFrame.new(origin.X + mapSize + border * 0.5, 0.255, origin.Z + mapSize * 0.5),
			Color = Config.Colors.Teal,
			Transparency = 0.08,
		})
	end

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Label"
	surface.Face = Enum.NormalId.Top
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 24
	surface.LightInfluence = 0
	surface.Parent = strip

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.BorderSizePixel = 0
	text.Text = string.upper(label.text)
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Config.Colors.White
	text.TextScaled = true
	text.Rotation = side == "left" and 270 or 90
	text.ZIndex = 2
	text.Parent = surface

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 20
	constraint.MinTextSize = 8
	constraint.Parent = text
end

-- Diagonal hatching around the playable map, like the reference PC build.
-- A SurfaceGui with clipped diagonal bars keeps the part count low.
local function addHatchStrip(parent, center, size)
	local base = part({
		Name = "BorderHatch",
		Parent = parent,
		Size = size,
		CFrame = CFrame.new(center),
		Color = Config.Colors.Border,
	})

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Hatch"
	surface.Face = Enum.NormalId.Top
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 16
	surface.LightInfluence = 0
	surface.Parent = base

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Config.Colors.Border
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Parent = surface

	for index = -4, 28 do
		local stripe = Instance.new("Frame")
		stripe.AnchorPoint = Vector2.new(0.5, 0.5)
		stripe.Position = UDim2.fromScale(index / 16, 0.5)
		stripe.Size = UDim2.new(0, 9, 2, 0)
		stripe.Rotation = 45
		stripe.BackgroundColor3 = Config.Colors.BorderStripe
		stripe.BorderSizePixel = 0
		stripe.Parent = frame
	end
end

local function addHatchedBorder(parent, origin, mapSize, border)
	local y = 0.21
	local thickness = 0.06
	local outer = mapSize + border * 2

	addHatchStrip(
		parent,
		Vector3.new(origin.X + mapSize * 0.5, y, origin.Z - border * 0.5),
		Vector3.new(outer, thickness, border)
	)
	addHatchStrip(
		parent,
		Vector3.new(origin.X + mapSize * 0.5, y, origin.Z + mapSize + border * 0.5),
		Vector3.new(outer, thickness, border)
	)
	addHatchStrip(
		parent,
		Vector3.new(origin.X - border * 0.5, y, origin.Z + mapSize * 0.5),
		Vector3.new(border, thickness, mapSize)
	)
	addHatchStrip(
		parent,
		Vector3.new(origin.X + mapSize + border * 0.5, y, origin.Z + mapSize * 0.5),
		Vector3.new(border, thickness, mapSize)
	)

	-- Thin dark lip so the hatching never bleeds onto the playable grid.
	local lipColor = Config.Colors.Border
	part({
		Name = "MapLipTop",
		Parent = parent,
		Size = Vector3.new(mapSize + 0.8, 0.05, 0.4),
		CFrame = CFrame.new(origin.X + mapSize * 0.5, 0.235, origin.Z + 0.2),
		Color = lipColor,
	})
	part({
		Name = "MapLipBottom",
		Parent = parent,
		Size = Vector3.new(mapSize + 0.8, 0.05, 0.4),
		CFrame = CFrame.new(origin.X + mapSize * 0.5, 0.235, origin.Z + mapSize - 0.2),
		Color = lipColor,
	})
	part({
		Name = "MapLipLeft",
		Parent = parent,
		Size = Vector3.new(0.4, 0.05, mapSize + 0.8),
		CFrame = CFrame.new(origin.X + 0.2, 0.235, origin.Z + mapSize * 0.5),
		Color = lipColor,
	})
	part({
		Name = "MapLipRight",
		Parent = parent,
		Size = Vector3.new(0.4, 0.05, mapSize + 0.8),
		CFrame = CFrame.new(origin.X + mapSize - 0.2, 0.235, origin.Z + mapSize * 0.5),
		Color = lipColor,
	})
end

function WorldBuilder.build(session)
	local origin = session.origin
	local size = session.size
	local tile = session.tile
	local map = session.map

	local mapSize = size * tile
	local center = origin + Vector3.new(mapSize / 2, 0, mapSize / 2)
	local border = 24

	local worlds = Workspace:FindFirstChild("MMWorlds")
	if not worlds then
		worlds = Instance.new("Folder")
		worlds.Name = "MMWorlds"
		worlds.Parent = Workspace
	end

	local root = Instance.new("Folder")
	root.Name = "City_" .. session.worldIndex

	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = root

	local roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = root

	local cars = Instance.new("Folder")
	cars.Name = "Cars"
	cars.Parent = root

	local fx = Instance.new("Folder")
	fx.Name = "FX"
	fx.Parent = root

	local water = Instance.new("Folder")
	water.Name = "Water"
	water.Parent = root

	local grass = Instance.new("Folder")
	grass.Name = "Grass"
	grass.Parent = root

	-- Fond clair, papier crème : la carte ressemble à une feuille posée sur un bureau.
	local backdrop = part({
		Name = "Backdrop",
		Size = Vector3.new(mapSize + 240, 1.0, mapSize + 240),
		CFrame = CFrame.new(center + Vector3.new(0, -2.2, 0)),
		Color = Config.Colors.Background,
	})
	backdrop.Parent = root

	local paper = part({
		Name = "Paper",
		Size = Vector3.new(mapSize + border * 2, 1.6, mapSize + border * 2),
		CFrame = CFrame.new(center + Vector3.new(0, -1.5, 0)),
		Color = Config.Colors.Paper,
	})
	paper.Parent = root

	-- Sol crème.
	local ground = part({
		Name = "Ground",
		Size = Vector3.new(mapSize, 1, mapSize),
		CFrame = CFrame.new(center + Vector3.new(0, -0.5, 0)),
		Color = map.land,
		CanQuery = true,
	})
	ground.Parent = root

	-- Parcs jaune-vert, dessinés sous la grille et sous l'eau.
	for _, shape in ipairs(map.grassShapes or {}) do
		drawWaterShape(grass, shape, origin, mapSize, map.grass or Config.Colors.Grass, 0.02, 0.005, 0)
	end

	-- Petits arbres plats dans les parcs : deux disques superposés, un sombre
	-- et un clair, pour retrouver les taches végétales de la référence.
	local treeRotation = CFrame.Angles(0, 0, math.rad(90))
	local function addTreeCluster(cx, cz, scale)
		local dark = part({
			Name = "Tree",
			Parent = grass,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.05, 1.45 * scale, 1.45 * scale),
			CFrame = CFrame.new(cx, 0.032, cz) * treeRotation,
			Color = Config.Colors.TreeDark,
			CastShadow = false,
		})
		part({
			Name = "TreeLeaf",
			Parent = grass,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.05, 1.02 * scale, 1.02 * scale),
			CFrame = CFrame.new(cx - 0.12 * scale, 0.042, cz - 0.12 * scale) * treeRotation,
			Color = Config.Colors.TreeLight,
			CastShadow = false,
		})
		return dark
	end

	for index, shape in ipairs(map.grassShapes or {}) do
		local cx, cz
		if shape.type == "ellipse" then
			cx, cz = shape.x, shape.y
		elseif shape.type == "rect" then
			cx, cz = shape.x + shape.w * 0.5, shape.y + shape.h * 0.5
		elseif shape.type == "bar" then
			cx, cz = (shape.x1 + shape.x2) * 0.5, (shape.y1 + shape.y2) * 0.5
		end
		if cx then
			local x = origin.X + cx * mapSize
			local z = origin.Z + cz * mapSize
			local spread = mapSize * 0.045 + (index % 2) * mapSize * 0.012
			addTreeCluster(x, z, 1.0)
			addTreeCluster(x - spread, z + spread * 0.35, 0.82)
			addTreeCluster(x + spread * 0.72, z - spread * 0.55, 0.72)
		end
	end

	-- Lignes de grille, dessinées avant l'eau pour être recouvertes par elle.
	local lineColor = Config.Colors.GridLine
	for i = 1, size - 1 do
		local offset = i * tile
		local vertical = part({
			Name = "GridV",
			Parent = root,
			Size = Vector3.new(0.10, 0.035, mapSize),
			CFrame = CFrame.new(origin + Vector3.new(offset, 0.02, mapSize / 2)),
			Color = lineColor,
			Transparency = 0.05,
		})
		vertical.Parent = root

		local horizontal = part({
			Name = "GridH",
			Parent = root,
			Size = Vector3.new(mapSize, 0.035, 0.10),
			CFrame = CFrame.new(origin + Vector3.new(mapSize / 2, 0.02, offset)),
			Color = lineColor,
			Transparency = 0.05,
		})
		horizontal.Parent = root
	end

	-- Eau en trois couches : ombre extérieure, liseré de côte blanc, puis
	-- remplissage. Le liseré blanc rend la côte lisible sur le sol crème,
	-- comme sur l'aperçu du menu.
	local outlinePadding = math.max(0.45, tile * 0.20)
	local shadowColor = map.waterDeep or Config.Colors.WaterDeep
	local coastColor = Config.Colors.Coast or Config.Colors.White
	local shapes = map.waterShapes or {}

	for _, shape in ipairs(shapes) do
		drawWaterShape(water, shape, origin, mapSize, shadowColor, 0.08, 0.06, outlinePadding * 1.8)
	end
	for _, shape in ipairs(shapes) do
		drawWaterShape(water, shape, origin, mapSize, coastColor, 0.10, 0.11, outlinePadding * 0.95)
	end
	for _, shape in ipairs(shapes) do
		drawWaterShape(water, shape, origin, mapSize, map.water, 0.10, 0.13, 0)
	end

	-- Presqu'îles sèches : elles recouvrent l'eau, avec le même liseré de
	-- côte blanc. Le raccord terre est posé au-dessus pour souder la
	-- presqu'île au continent sans laisser de trait blanc en travers.
	for _, shape in ipairs(map.dryShapes or {}) do
		drawWaterShape(water, shape, origin, mapSize, coastColor, 0.04, 0.19, outlinePadding * 0.95)
	end
	for _, shape in ipairs(map.dryShapes or {}) do
		drawWaterShape(water, shape, origin, mapSize, map.land, 0.03, 0.20, 0)
	end
	for _, shape in ipairs(map.dryPatches or {}) do
		drawWaterShape(water, shape, origin, mapSize, map.land, 0.03, 0.215, 0)
	end

	addWaterMasks(root, origin, mapSize, border)
	addHatchedBorder(root, origin, mapSize, border)
	for _, label in ipairs(map.labels or {}) do
		addMapLabel(root, origin, mapSize, border, label)
	end

	root.Parent = worlds

	return {
		folder = root,
		Buildings = buildings,
		Roads = roads,
		Cars = cars,
		FX = fx,
		Water = water,
		Grass = grass,
	}
end

return WorldBuilder
