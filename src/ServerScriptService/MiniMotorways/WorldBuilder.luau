--[[
	WorldBuilder.luau
	Construit le décor 3D d'une ville : un plateau clair posé sur un fond à
	peine plus foncé, une grille très discrète, l'eau et les parcs (formes de
	Maps), quelques arbres, puis les dossiers qui recevront routes, bâtiments
	et voitures.
	Les formes d'eau sont celles de l'aperçu du menu. Les rectangles et les barres
	sont rognés au bord du plateau ; les ellipses doivent rester dans la carte
	(vérifié par les tests).
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local SessionUtil = require(script.Parent.SessionUtil)
local part = SessionUtil.makePart

local WorldBuilder = {}

-- Un Cylinder a son axe selon X : la rotation le couche debout, son disque
-- est alors dans le plan XZ, comme les cases vues d'en haut.
local CYLINDER_UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

-- Hauteurs des couches, en studs, au-dessus du plateau (y = 0). Chaque couche
-- est posée au-dessus de la précédente : aucune surface coplanaire, donc pas de
-- scintillement. Les routes (RoadConfig.Layers, dessus de 0.29 à 0.40) restent
-- au-dessus du décor (0.18 au plus).
local LAYER_THICKNESS = 0.08
local GRASS_TOP = 0.015
local SHORE_TOP = 0.10
local WATER_TOP = 0.12
local DRY_SHORE_TOP = 0.16
local DRY_TOP = 0.18

-- La grille passe sous l'eau : elle disparaît sous les lacs, comme dans le
-- jeu d'origine, et ne concurrence pas les routes. Les lignes sont translucides
-- et se croisent : les horizontales sont posées 0.01 plus haut que les
-- verticales, sinon les deux se disputeraient le même plan à chaque croisement.
local GRID_Y = 0.02
local GRID_THICKNESS = 0.03
local GRID_H_LIFT = 0.01

local TREE_TOP = 0.075
local TREE_THICKNESS = 0.03
-- Carré de cases au centre du plateau, sans arbre (zone de départ).
local START_AREA_CELLS = 4
local TREE_SHADOW_TOP = 0.05
local TREE_SHADOW_THICKNESS = 0.02

-- Plateau : dalle de 1 stud dont le dessus est à y = 0. Les ombres de bord
-- descendent par paliers, sous le plateau, et le fond est plus bas encore.
local BOARD_THICKNESS = 1
local SHADOW_THICKNESS = 0.2
local SHADOW_Y = -1.1
local SHADOW_STEP = 0.1
local BACKDROP_THICKNESS = 0.4
local BACKDROP_Y = -1.6

-- Disque (ou ellipse) plat vu du dessus. Un Cylinder garde un dessus plan à la
-- hauteur voulue ; une sphère aplatie (SpecialMesh) aurait un dôme dont seul le
-- centre atteint cette hauteur, donc une forme visiblement plus petite que celle
-- que Maps.isWater / Maps.isGrass utilisent.
-- width : étendue selon X, depth : étendue selon Z (avant rotation de lacet).
local function addDisk(parent, name, at, width, depth, color, yaw)
	return part({
		Name = name,
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(LAYER_THICKNESS, width, depth),
		CFrame = CFrame.new(at) * CFrame.Angles(0, yaw or 0, 0) * CYLINDER_UPRIGHT,
		Color = color,
	})
end

local function isOutside(nx, ny)
	return nx < 0 or nx > 1 or ny < 0 or ny > 1
end

-- Coupe un segment normalisé au plateau [0, 1]² (Liang-Barsky). Renvoie les
-- extrémités rognées, ou rien si le segment ne touche pas le plateau.
local function clipSegment(x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	local ps = { -dx, dx, -dy, dy }
	local qs = { x1, 1 - x1, y1, 1 - y1 }
	local t0, t1 = 0, 1
	for i = 1, 4 do
		local p, q = ps[i], qs[i]
		if p == 0 then
			if q < 0 then
				return nil
			end
		elseif p < 0 then
			t0 = math.max(t0, q / p)
		else
			t1 = math.min(t1, q / p)
		end
	end
	if t0 > t1 then
		return nil
	end
	return x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1
end

-- Dessine une forme normalisée (0..1) sur le plateau. top est le dessus de la
-- couche, grow élargit la forme (liseré de côte). Les rectangles et les barres
-- sont rognés au bord du plateau, pour ne jamais dépasser de la carte.
local function addShape(parent, name, shape, board, color, top, grow)
	local origin, extent = board.origin, board.extent
	local centerY = top - LAYER_THICKNESS * 0.5
	local kind = shape.type

	if kind == "rect" then
		local minX = math.max(origin.X, origin.X + shape.x * extent - grow)
		local maxX = math.min(origin.X + extent, origin.X + (shape.x + shape.w) * extent + grow)
		local minZ = math.max(origin.Z, origin.Z + shape.y * extent - grow)
		local maxZ = math.min(origin.Z + extent, origin.Z + (shape.y + shape.h) * extent + grow)
		if maxX <= minX or maxZ <= minZ then
			return
		end
		part({
			Name = name,
			Parent = parent,
			Size = Vector3.new(maxX - minX, LAYER_THICKNESS, maxZ - minZ),
			CFrame = CFrame.new((minX + maxX) * 0.5, centerY, (minZ + maxZ) * 0.5),
			Color = color,
		})
		return
	end

	if kind == "circle" or kind == "ellipse" then
		local rxNorm = shape.rx or shape.r or 0.05
		local ryNorm = shape.ry or shape.r or rxNorm
		-- La rotation de l'aperçu est horaire à l'écran ; en 3D, l'axe Z
		-- descend et l'axe Y tourne dans le sens inverse.
		local yaw = math.rad(-(shape.rotation or 0))
		addDisk(
			parent,
			name,
			Vector3.new(origin.X + shape.x * extent, centerY, origin.Z + shape.y * extent),
			(rxNorm * extent + grow) * 2,
			(ryNorm * extent + grow) * 2,
			color,
			yaw
		)
		return
	end

	if kind == "bar" then
		local radius = (shape.thickness or 0.04) * extent * 0.5 + grow
		-- Rogner le segment (et non pincer ses extrémités) garde la direction de
		-- la barre telle que Maps.isWater la voit dans le plateau.
		local x1, y1, x2, y2 = clipSegment(shape.x1, shape.y1, shape.x2, shape.y2)
		if not x1 then
			return
		end
		local from = Vector3.new(origin.X + x1 * extent, centerY, origin.Z + y1 * extent)
		local to = Vector3.new(origin.X + x2 * extent, centerY, origin.Z + y2 * extent)
		local delta = to - from
		if delta.Magnitude <= 0 then
			return
		end
		local middle = (from + to) * 0.5
		part({
			Name = name,
			Parent = parent,
			Size = Vector3.new(radius * 2, LAYER_THICKNESS, delta.Magnitude),
			CFrame = CFrame.lookAt(middle, middle + delta.Unit),
			Color = color,
		})
		local function addCap(at)
			addDisk(parent, name, at, radius * 2, radius * 2, color)
		end
		-- Un bout posé hors du plateau reste coupé net : un bout rond dépasserait
		-- de la carte. Une presqu'île garde aussi son côté terre coupé net.
		if not isOutside(shape.x2, shape.y2) then
			addCap(to)
		end
		if not shape.flatStart and not isOutside(shape.x1, shape.y1) then
			addCap(from)
		end
	end
end

-- Générateur pseudo-aléatoire (congruence linéaire) seedé par l'identifiant de
-- la carte : le décor est identique d'une partie à l'autre, et math.random
-- reste disponible pour le reste du jeu.
local function seededRandom(text)
	local state = 1
	for i = 1, #text do
		state = (state * 31 + string.byte(text, i)) % 2147483647
	end
	if state == 0 then
		state = 1
	end
	return function()
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

-- Arbres vus du dessus : de petits disques plats, par groupes de 2 ou 3 dans
-- les cases de parc. Un arbre n'est posé que si son centre et ses bords
-- tombent dans le parc, hors de l'eau. Renvoie les cases occupées par un arbre
-- (clé « x:y », comme Grid.key) pour que les bâtiments les évitent.
local function addTrees(grass, map, board)
	local terrain = Config.Terrain
	local origin, cells, tile = board.origin, board.cells, board.tile
	local rand = seededRandom(map.id)
	local treeCells = {}

	-- La zone de départ, au centre, reste sans arbre : le joueur y commence
	-- toujours sur un terrain dégagé.
	local startFirst = math.floor((cells - START_AREA_CELLS) / 2)
	local function inStartArea(x, y)
		return x >= startFirst
			and x < startFirst + START_AREA_CELLS
			and y >= startFirst
			and y < startFirst + START_AREA_CELLS
	end

	local function usableCell(x, y)
		return x >= 0
			and y >= 0
			and x < cells
			and y < cells
			and not inStartArea(x, y)
			and Maps.isGrass(map, x, y)
			and not Maps.isWater(map, x, y)
	end

	local function usableAt(lx, lz)
		return usableCell(math.floor(lx / tile), math.floor(lz / tile))
	end

	-- lx, lz : position locale, en studs, à partir du coin du plateau.
	local function addDisc(name, lx, lz, diameter, top, thickness, color, transparency)
		part({
			Name = name,
			Parent = grass,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(thickness, diameter, diameter),
			CFrame = CFrame.new(origin.X + lx, top - thickness * 0.5, origin.Z + lz) * CYLINDER_UPRIGHT,
			Color = color,
			Transparency = transparency,
		})
	end

	-- Tous les arbres de la carte se partagent cette liste : deux groupes
	-- voisins ne doivent pas se superposer.
	local placed = {}
	for cy = 0, cells - 1 do
		for cx = 0, cells - 1 do
			if usableCell(cx, cy) and rand() < Config.Terrain.TreeClusterChance then
				local count = 2 + math.floor(rand() * 2)
				local centerX = (cx + 0.5) * tile
				local centerZ = (cy + 0.5) * tile
				for _ = 1, count do
					local angle = rand() * math.pi * 2
					local distance = rand() * terrain.TreeSpread
					local diameter = terrain.TreeDiameter * (0.85 + rand() * 0.3)
					local tone = rand() < 0.5 and Config.Colors.TreeDark or Config.Colors.TreeLight
					local lx = centerX + math.cos(angle) * distance
					local lz = centerZ + math.sin(angle) * distance

					local half = diameter * 0.5
					local clear = usableAt(lx, lz)
						and usableAt(lx - half, lz)
						and usableAt(lx + half, lz)
						and usableAt(lx, lz - half)
						and usableAt(lx, lz + half)
					local spaced = true
					for _, other in ipairs(placed) do
						local dx = other.x - lx
						local dz = other.z - lz
						if dx * dx + dz * dz < terrain.TreeMinSpacing * terrain.TreeMinSpacing then
							spaced = false
						end
					end

					if clear and spaced then
						table.insert(placed, { x = lx, z = lz })
						addDisc(
							"TreeShadow",
							lx + terrain.TreeShadowOffset,
							lz + terrain.TreeShadowOffset,
							diameter * terrain.TreeShadowScale,
							TREE_SHADOW_TOP,
							TREE_SHADOW_THICKNESS,
							Config.Colors.BuildingShadow,
							terrain.TreeShadowTransparency
						)
						addDisc("Tree", lx, lz, diameter, TREE_TOP, TREE_THICKNESS, tone, 0)
						treeCells[math.floor(lx / tile) .. ":" .. math.floor(lz / tile)] = true
					end
				end
			end
		end
	end
	return treeCells
end

-- Grille : une ligne par limite de case intérieure, posée à origin + i * tile,
-- exactement là où Grid.center place les bords de cases.
local function addGrid(grid, board)
	local origin, extent, tile = board.origin, board.extent, board.tile
	local width = Config.Terrain.GridLineWidth
	local transparency = Config.Terrain.GridBaseTransparency
	for i = 1, board.cells - 1 do
		local offset = i * tile
		part({
			Name = "GridV",
			Parent = grid,
			Size = Vector3.new(width, GRID_THICKNESS, extent),
			CFrame = CFrame.new(origin.X + offset, GRID_Y, origin.Z + extent * 0.5),
			Color = Config.Colors.GridTerrain,
			Transparency = transparency,
		})
		part({
			Name = "GridH",
			Parent = grid,
			Size = Vector3.new(extent, GRID_THICKNESS, width),
			CFrame = CFrame.new(origin.X + extent * 0.5, GRID_Y + GRID_H_LIFT, origin.Z + offset),
			Color = Config.Colors.GridTerrain,
			Transparency = transparency,
		})
	end
end

function WorldBuilder.build(session)
	local origin = session.origin
	local size = session.size
	local tile = session.tile
	local map = session.map

	local extent = size * tile
	local center = origin + Vector3.new(extent / 2, 0, extent / 2)
	local board = { origin = origin, extent = extent, cells = size, tile = tile }

	local worlds = Workspace:FindFirstChild("MMWorlds")
	if not worlds then
		worlds = Instance.new("Folder")
		worlds.Name = "MMWorlds"
		worlds.Parent = Workspace
	end

	local root = Instance.new("Folder")
	root.Name = "City_" .. session.worldIndex

	local function folder(name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		return f
	end

	local buildings = folder("Buildings")
	local roads = folder("Roads")
	local cars = folder("Cars")
	local fx = folder("FX")
	local water = folder("Water")
	local grass = folder("Grass")
	local grid = folder("Grid")
	-- Le client règle la transparence de la grille pendant la construction.
	grid:SetAttribute("BaseTransparency", Config.Terrain.GridBaseTransparency)
	grid:SetAttribute("ActiveTransparency", Config.Terrain.GridActiveTransparency)

	-- Fond : une seule dalle, à peine plus foncée que le plateau.
	local backdropSize = extent + Config.Terrain.BackdropMargin * 2
	part({
		Name = "Background",
		Parent = root,
		Size = Vector3.new(backdropSize, BACKDROP_THICKNESS, backdropSize),
		CFrame = CFrame.new(center.X, BACKDROP_Y, center.Z),
		Color = Config.Colors.Background,
	})

	-- Ombre de bord très douce : deux couches transparentes, légèrement décalées
	-- en profondeur pour ne jamais être coplanaires.
	for index, layer in ipairs(Config.Terrain.BoardShadow) do
		local shadowSize = extent + layer.grow * 2
		part({
			Name = "BoardShadow",
			Parent = root,
			Size = Vector3.new(shadowSize, SHADOW_THICKNESS, shadowSize),
			CFrame = CFrame.new(center.X, SHADOW_Y - (index - 1) * SHADOW_STEP, center.Z),
			Color = Config.Colors.CardShadow,
			Transparency = layer.transparency,
		})
	end

	-- Plateau clair et uniforme : le seul élément qui reçoit les clics.
	part({
		Name = "Ground",
		Parent = root,
		Size = Vector3.new(extent, BOARD_THICKNESS, extent),
		CFrame = CFrame.new(center.X, -BOARD_THICKNESS * 0.5, center.Z),
		Color = map.land,
		CanQuery = true,
	})

	-- Parcs, puis arbres dans les parcs, puis grille : tout sous l'eau.
	local grassShapes = map.grassShapes or {}
	local waterShapes = map.waterShapes or {}
	local dryShapes = map.dryShapes or {}

	for _, shape in ipairs(grassShapes) do
		addShape(grass, "Grass", shape, board, map.grass, GRASS_TOP, 0)
	end
	local treeCells = addTrees(grass, map, board)
	addGrid(grid, board)

	-- Eau : liseré clair fin, puis remplissage. Les presqu'îles recouvrent
	-- l'eau avec leur propre liseré, puis leur terre ; les parcs secs les
	-- plus petits sont posés en dernier.
	local shoreline = Config.Terrain.Shoreline
	local coast = Config.Colors.Coast
	for _, shape in ipairs(waterShapes) do
		addShape(water, "Shore", shape, board, coast, SHORE_TOP, shoreline)
	end
	for _, shape in ipairs(waterShapes) do
		addShape(water, "Water", shape, board, map.water, WATER_TOP, 0)
	end
	for _, shape in ipairs(dryShapes) do
		addShape(water, "Shore", shape, board, coast, DRY_SHORE_TOP, shoreline)
	end
	for _, shape in ipairs(dryShapes) do
		addShape(water, "Land", shape, board, map.land, DRY_TOP, 0)
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
		Grid = grid,
		-- Cases occupées par un arbre : les bâtiments doivent les éviter.
		treeCells = treeCells,
	}
end

return WorldBuilder
