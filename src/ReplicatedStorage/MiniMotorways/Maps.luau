--[[
	Maps.luau
	Les villes du jeu. Chaque carte décrit :
	  - son nom / sa description / son mode / les couleurs de son en-tête
	  - sa géographie : waterShapes, dryShapes et grassShapes, des formes
	    normalisées (0..1). Ce sont les seules données de terrain : l'aperçu
	    du menu, le rendu 3D et la règle de construction (Maps.isWater) les
	    lisent toutes les trois, donc elles ne peuvent pas se contredire.
	  - un petit tracé de routes pour l'aperçu circulaire du menu

	Les rivières et côtes sont des chaînes d'ellipses tournées : une seule
	pièce par ellipse au rendu, et des contours doux. Une rivière compte un
	segment par ellipse, rx suivant le segment : une barre coûte trois pièces
	par couche (corps et deux bouts), une ellipse une seule.
]]

local Config = require(script.Parent.Config)
local C = Config.Colors

local Maps = {}

local list = {
	{
		id = "dubai",
		name = "Dubaï",
		mode = "Classique",
		description = "Reliez les quartiers de Dubaï et traversez la marina avant la fin du temps imparti.",
		header = Color3.fromHex("F8DB95"),
		accent = Color3.fromHex("E8C37A"),
		previewRoads = {
			{ 0.22, 0.22, 0.72, 0.22 },
			{ 0.72, 0.22, 0.72, 0.58 },
			{ 0.30, 0.48, 0.76, 0.48 },
			{ 0.30, 0.48, 0.30, 0.76 },
		},
		-- Golfe au sud, côte basse et légèrement ondulée.
		-- Marina : un chenal étroit qui pénètre dans la terre.
		waterShapes = {
			{ type = "ellipse", x = 0.240, y = 0.849, rx = 0.181, ry = 0.090, rotation = 5.7 },
			{ type = "ellipse", x = 0.240, y = 0.847, rx = 0.181, ry = 0.090, rotation = 8.0 },
			{ type = "ellipse", x = 0.398, y = 0.850, rx = 0.132, ry = 0.090, rotation = 1.4 },
			{ type = "ellipse", x = 0.618, y = 0.848, rx = 0.133, ry = 0.090, rotation = -11.3 },
			{ type = "ellipse", x = 0.761, y = 0.847, rx = 0.181, ry = 0.090, rotation = -9.1 },
			{ type = "ellipse", x = 0.760, y = 0.849, rx = 0.181, ry = 0.090, rotation = -5.7 },
			{ type = "ellipse", x = 0.730, y = 0.879, rx = 0.062, ry = 0.043, rotation = -104.0 },
			{ type = "ellipse", x = 0.710, y = 0.790, rx = 0.072, ry = 0.043, rotation = -101.3 },
			{ type = "ellipse", x = 0.690, y = 0.690, rx = 0.072, ry = 0.043, rotation = -101.3 },
			{ type = "ellipse", x = 0.690, y = 0.605, rx = 0.058, ry = 0.043, rotation = -74.1 },
			{ type = "ellipse", x = 0.700, y = 0.540, rx = 0.050, ry = 0.040, rotation = 0 },
			-- Rivière sinueuse du bord nord au bord sud, qui traverse le golfe : elle coupe
			-- la ville en deux et se franchit par un pont.
			{ type = "ellipse", x = 0.284, y = 0.130, rx = 0.112, ry = 0.035, rotation = 101.2 },
			{ type = "ellipse", x = 0.292, y = 0.335, rx = 0.112, ry = 0.035, rotation = 72.5 },
			{ type = "ellipse", x = 0.306, y = 0.520, rx = 0.103, ry = 0.035, rotation = 100.1 },
			{ type = "ellipse", x = 0.304, y = 0.700, rx = 0.103, ry = 0.035, rotation = 81.2 },
			{ type = "ellipse", x = 0.340, y = 0.887, rx = 0.100, ry = 0.035, rotation = 77.5 },
			-- Lacs intérieurs, coupés par la grille mais jamais au centre.
			{ type = "ellipse", x = 0.800, y = 0.300, rx = 0.100, ry = 0.065, rotation = -20 },
			{ type = "ellipse", x = 0.270, y = 0.180, rx = 0.070, ry = 0.045, rotation = 10 },
		},
		-- Parcs discrets, éloignés des rivages.
		grassShapes = {
			{ type = "ellipse", x = 0.440, y = 0.300, rx = 0.070, ry = 0.045, rotation = 0 },
			{ type = "ellipse", x = 0.160, y = 0.560, rx = 0.060, ry = 0.045, rotation = 0 },
		},
	},
	{
		id = "los_angeles",
		name = "Los Angeles",
		mode = "Classique",
		description = "Gérez le quadrillage d'autoroutes de la métropole californienne grandissante.",
		header = Color3.fromHex("FFDD94"),
		accent = Color3.fromHex("E8C37A"),
		previewRoads = {
			{ 0.27, 0.12, 0.27, 0.54 },
			{ 0.27, 0.54, 0.52, 0.54 },
			{ 0.52, 0.54, 0.52, 0.88 },
			{ 0.52, 0.54, 0.78, 0.54 },
		},
		-- La côte ouest est une goutte d'eau inclinée, complétée par des
		-- ellipses fines le long de la côte. La baie du bas est large et arrondie,
		-- avec une presqu'île centrale ; le chenal du nord finit dans la baie.
		-- Rotation en degrés dans le repère de l'écran (x à droite, y en bas).
		waterShapes = {
			{ type = "ellipse", x = 0.172, y = 0.571, rx = 0.096, ry = 0.224, rotation = 163.3 },
			{ type = "ellipse", x = 0.102, y = 0.480, rx = 0.158, ry = 0.030, rotation = 78.9 },
			{ type = "ellipse", x = 0.125, y = 0.680, rx = 0.105, ry = 0.035, rotation = 66.4 },
			{ type = "ellipse", x = 0.220, y = 0.820, rx = 0.090, ry = 0.045, rotation = 15 },
			{ type = "ellipse", x = 0.557, y = 0.807, rx = 0.101, ry = 0.279, rotation = 81.4 },
			-- Chenal qui traverse la ville du nord au sud, à l'ouest du centre : un pont
			-- est nécessaire pour relier les quartiers de part et d'autre.
			{ type = "ellipse", x = 0.298, y = 0.125, rx = 0.105, ry = 0.035, rotation = 94.2 },
			{ type = "ellipse", x = 0.310, y = 0.315, rx = 0.099, ry = 0.035, rotation = 76.8 },
			{ type = "ellipse", x = 0.306, y = 0.480, rx = 0.096, ry = 0.035, rotation = 106.7 },
			{ type = "ellipse", x = 0.306, y = 0.650, rx = 0.105, ry = 0.035, rotation = 75.1 },
			{ type = "ellipse", x = 0.346, y = 0.863, rx = 0.123, ry = 0.035, rotation = 82.8 },
			-- Petit étang d'une case, au nord : un point de passage pour un pont.
			{ type = "ellipse", x = 0.4722, y = 0.1389, rx = 0.030, ry = 0.030, rotation = 0 },
			{ type = "ellipse", x = 0.725, y = 0.720, rx = 0.161, ry = 0.030, rotation = 7.9 },
			{ type = "ellipse", x = 0.780, y = 0.755, rx = 0.100, ry = 0.040, rotation = 3.6 },
			{ type = "ellipse", x = 0.700, y = 0.700, rx = 0.075, ry = 0.050, rotation = 0 },
		},
		-- Presqu'île crème au centre de la baie : le raccord au continent
		-- est coupé à ras du littoral, seule la pointe côté eau reste arrondie.
		dryShapes = {
			{
				type = "bar",
				x1 = 0.540,
				y1 = 0.680,
				x2 = 0.540,
				y2 = 0.820,
				thickness = 0.100,
				flatStart = true,
			},
		},
		grassShapes = {
			-- Parc allongé en haut à droite.
			{ type = "ellipse", x = 0.790, y = 0.198, rx = 0.053, ry = 0.119, rotation = 140.6 },
			-- Parc du nord-ouest, loin de la côte et du chenal.
			{ type = "ellipse", x = 0.170, y = 0.160, rx = 0.050, ry = 0.040, rotation = 0 },
		},
	},
	{
		id = "beijing",
		name = "Pékin",
		mode = "Classique",
		description = "Construisez les routes qui permettent aux millions d'habitants de Pékin d'arriver au travail à l'heure.",
		header = Color3.fromHex("7AA09E"),
		accent = Color3.fromHex("5F8A88"),
		previewRoads = {
			{ 0.18, 0.34, 0.82, 0.34 },
			{ 0.55, 0.18, 0.55, 0.78 },
			{ 0.34, 0.56, 0.82, 0.56 },
			{ 0.18, 0.34, 0.18, 0.62 },
		},
		-- Fleuve sinueux qui traverse le nord de la ville, d'un bord à l'autre.
		waterShapes = {
			{ type = "ellipse", x = 0.156, y = 0.190, rx = 0.097, ry = 0.043, rotation = -7.6 },
			{ type = "ellipse", x = 0.140, y = 0.170, rx = 0.062, ry = 0.043, rotation = -14.0 },
			{ type = "ellipse", x = 0.220, y = 0.200, rx = 0.078, ry = 0.043, rotation = 45.0 },
			{ type = "ellipse", x = 0.300, y = 0.255, rx = 0.064, ry = 0.043, rotation = 20.6 },
			{ type = "ellipse", x = 0.380, y = 0.245, rx = 0.068, ry = 0.043, rotation = -32.0 },
			{ type = "ellipse", x = 0.460, y = 0.200, rx = 0.066, ry = 0.043, rotation = -26.6 },
			{ type = "ellipse", x = 0.540, y = 0.205, rx = 0.068, ry = 0.043, rotation = 32.0 },
			{ type = "ellipse", x = 0.620, y = 0.260, rx = 0.071, ry = 0.043, rotation = 36.9 },
			{ type = "ellipse", x = 0.700, y = 0.250, rx = 0.078, ry = 0.043, rotation = -45.0 },
			{ type = "ellipse", x = 0.780, y = 0.195, rx = 0.064, ry = 0.043, rotation = -20.6 },
			{ type = "ellipse", x = 0.804, y = 0.210, rx = 0.140, ry = 0.043, rotation = 14.6 },
			{ type = "ellipse", x = 0.056, y = 0.180, rx = 0.040, ry = 0.043, rotation = -7.6 },
			{ type = "ellipse", x = 0.945, y = 0.210, rx = 0.036, ry = 0.043, rotation = 14.6 },
			-- Deux lacs : l'un à l'est, l'autre au sud-ouest.
			{ type = "ellipse", x = 0.800, y = 0.500, rx = 0.090, ry = 0.060, rotation = -15 },
			{ type = "ellipse", x = 0.200, y = 0.780, rx = 0.050, ry = 0.040, rotation = 0 },
		},
		grassShapes = {
			{ type = "ellipse", x = 0.300, y = 0.380, rx = 0.080, ry = 0.050, rotation = 0 },
			{ type = "ellipse", x = 0.720, y = 0.740, rx = 0.100, ry = 0.070, rotation = 0 },
		},
	},
	{
		id = "tokyo",
		name = "Tokyo",
		mode = "Classique",
		description = "Reliez les quartiers de Tokyo, la plus grande métropole du monde.",
		header = Color3.fromHex("E9A7A0"),
		accent = Color3.fromHex("D98A82"),
		previewRoads = {
			{ 0.20, 0.22, 0.70, 0.22 },
			{ 0.70, 0.22, 0.70, 0.60 },
			{ 0.30, 0.46, 0.74, 0.46 },
			{ 0.20, 0.22, 0.20, 0.52 },
		},
		-- Baie au sud-est, bordée d'une côte en diagonale, et une rivière
		-- qui s'en échappe vers l'ouest.
		waterShapes = {
			{ type = "ellipse", x = 0.595, y = 0.836, rx = 0.120, ry = 0.100, rotation = -26.6 },
			{ type = "ellipse", x = 0.720, y = 0.840, rx = 0.098, ry = 0.100, rotation = -23.5 },
			{ type = "ellipse", x = 0.835, y = 0.844, rx = 0.088, ry = 0.100, rotation = -33.7 },
			{ type = "ellipse", x = 0.849, y = 0.811, rx = 0.080, ry = 0.100, rotation = -45.0 },
			{ type = "ellipse", x = 0.834, y = 0.733, rx = 0.112, ry = 0.100, rotation = -43.5 },
			-- Comble le coin sud-est : sans cela, un îlot de terre isolé reste.
			{ type = "ellipse", x = 0.840, y = 0.860, rx = 0.100, ry = 0.080, rotation = 0 },
			{ type = "ellipse", x = 0.640, y = 0.810, rx = 0.092, ry = 0.037, rotation = -105.9 },
			{ type = "ellipse", x = 0.570, y = 0.720, rx = 0.073, ry = 0.037, rotation = -158.2 },
			{ type = "ellipse", x = 0.460, y = 0.680, rx = 0.082, ry = 0.037, rotation = -161.6 },
			{ type = "ellipse", x = 0.350, y = 0.640, rx = 0.073, ry = 0.037, rotation = -158.2 },
			{ type = "ellipse", x = 0.250, y = 0.580, rx = 0.083, ry = 0.037, rotation = -141.3 },
			{ type = "ellipse", x = 0.150, y = 0.500, rx = 0.083, ry = 0.037, rotation = -141.3 },
			{ type = "ellipse", x = 0.154, y = 0.430, rx = 0.100, ry = 0.037, rotation = -158.2 },
		},
		grassShapes = {
			{ type = "ellipse", x = 0.340, y = 0.280, rx = 0.100, ry = 0.060, rotation = -20 },
			{ type = "ellipse", x = 0.620, y = 0.360, rx = 0.080, ry = 0.050, rotation = 0 },
		},
	},
	{
		id = "dar_es_salam",
		name = "Dar es Salaam",
		mode = "Classique",
		description = "Développez votre réseau pour suivre la croissance rapide de Dar es Salaam.",
		header = Color3.fromHex("B5E0CE"),
		accent = Color3.fromHex("8FCBB4"),
		previewRoads = {
			{ 0.14, 0.64, 0.58, 0.64 },
			{ 0.58, 0.64, 0.58, 0.32 },
			{ 0.30, 0.42, 0.76, 0.42 },
			{ 0.58, 0.32, 0.82, 0.32 },
		},
		-- Côte orientale sinueuse, un bras de mer qui pénètre la ville et une lagune.
		waterShapes = {
			{ type = "ellipse", x = 0.850, y = 0.190, rx = 0.130, ry = 0.090, rotation = 95.7 },
			{ type = "ellipse", x = 0.850, y = 0.190, rx = 0.130, ry = 0.090, rotation = 86.7 },
			{ type = "ellipse", x = 0.850, y = 0.306, rx = 0.111, ry = 0.090, rotation = 93.8 },
			{ type = "ellipse", x = 0.850, y = 0.456, rx = 0.111, ry = 0.090, rotation = 93.8 },
			{ type = "ellipse", x = 0.850, y = 0.600, rx = 0.108, ry = 0.090, rotation = 90.0 },
			{ type = "ellipse", x = 0.850, y = 0.747, rx = 0.109, ry = 0.090, rotation = 88.1 },
			{ type = "ellipse", x = 0.850, y = 0.831, rx = 0.109, ry = 0.090, rotation = 86.2 },
			{ type = "ellipse", x = 0.849, y = 0.835, rx = 0.106, ry = 0.090, rotation = 101.3 },
			{ type = "ellipse", x = 0.790, y = 0.610, rx = 0.066, ry = 0.030, rotation = -168.7 },
			{ type = "ellipse", x = 0.700, y = 0.630, rx = 0.065, ry = 0.030, rotation = 143.1 },
			{ type = "ellipse", x = 0.630, y = 0.700, rx = 0.065, ry = 0.030, rotation = 126.9 },
			{ type = "ellipse", x = 0.560, y = 0.770, rx = 0.065, ry = 0.030, rotation = 143.1 },
			{ type = "ellipse", x = 0.660, y = 0.220, rx = 0.080, ry = 0.050, rotation = 30 },
		},
		grassShapes = {
			{ type = "ellipse", x = 0.300, y = 0.300, rx = 0.100, ry = 0.060, rotation = 0 },
			{ type = "ellipse", x = 0.340, y = 0.780, rx = 0.080, ry = 0.050, rotation = 20 },
		},
	},
	{
		id = "london",
		name = "Londres",
		mode = "Classique",
		description = "Traversez la Tamise et redessinez les rues de la capitale britannique.",
		header = Color3.fromHex("C9D6D9"),
		accent = Color3.fromHex("A8B8C0"),
		previewRoads = {
			{ 0.20, 0.28, 0.80, 0.28 },
			{ 0.50, 0.24, 0.50, 0.72 },
			{ 0.25, 0.72, 0.75, 0.72 },
			{ 0.25, 0.72, 0.25, 0.86 },
		},
		-- La Tamise serpente d'ouest en est et sépare la ville en deux rives.
		waterShapes = {
			{ type = "ellipse", x = 0.167, y = 0.590, rx = 0.112, ry = 0.044, rotation = -19.4 },
			{ type = "ellipse", x = 0.180, y = 0.600, rx = 0.094, ry = 0.044, rotation = 33.7 },
			{ type = "ellipse", x = 0.300, y = 0.670, rx = 0.089, ry = 0.044, rotation = 26.6 },
			{ type = "ellipse", x = 0.430, y = 0.710, rx = 0.093, ry = 0.044, rotation = 8.1 },
			{ type = "ellipse", x = 0.560, y = 0.690, rx = 0.089, ry = 0.044, rotation = -26.6 },
			{ type = "ellipse", x = 0.680, y = 0.590, rx = 0.114, ry = 0.044, rotation = -49.4 },
			{ type = "ellipse", x = 0.790, y = 0.470, rx = 0.093, ry = 0.044, rotation = -45.0 },
			{ type = "ellipse", x = 0.877, y = 0.390, rx = 0.072, ry = 0.044, rotation = -36.9 },
			{ type = "ellipse", x = 0.853, y = 0.350, rx = 0.088, ry = 0.044, rotation = -8.7 },
			-- Les deux bouts de la Tamise atteignent les bords du plateau,
			-- sinon les rives se rejoignent par le bord sans pont.
			{ type = "ellipse", x = 0.056, y = 0.630, rx = 0.034, ry = 0.044, rotation = -19.4 },
			{ type = "ellipse", x = 0.935, y = 0.355, rx = 0.045, ry = 0.044, rotation = -8.7 },
			-- Petit étang dans le parc de l'ouest.
			{ type = "ellipse", x = 0.160, y = 0.200, rx = 0.040, ry = 0.030, rotation = 0 },
		},
		grassShapes = {
			{ type = "ellipse", x = 0.300, y = 0.300, rx = 0.090, ry = 0.060, rotation = 0 },
			{ type = "ellipse", x = 0.740, y = 0.200, rx = 0.060, ry = 0.050, rotation = 0 },
			{ type = "ellipse", x = 0.300, y = 0.840, rx = 0.090, ry = 0.050, rotation = 0 },
		},
	},
}

-- Terrain uniforme sur toutes les cartes : seuls l'en-tête et l'accent
-- (couleurs d'interface du menu) changent d'une ville à l'autre.
for _, map in ipairs(list) do
	map.land = C.Land
	map.water = C.Water
	map.waterEdge = C.WaterEdge
	map.waterDeep = C.WaterDeep
	map.grass = C.Park
	map.dryShapes = map.dryShapes or {}
	map.grassShapes = map.grassShapes or {}
end

function Maps.all()
	return list
end

function Maps.getById(id)
	for _, map in ipairs(list) do
		if map.id == id then
			return map
		end
	end
	return nil
end

-- Teste un point normalisé contre une forme (rect, cercle, ellipse, bar).
local function pointInShape(shape, nx, ny)
	if shape.type == "rect" then
		return nx >= shape.x
			and nx <= shape.x + shape.w
			and ny >= shape.y
			and ny <= shape.y + shape.h
	end

	if shape.type == "circle" or shape.type == "ellipse" then
		local rx = shape.rx or shape.r or 0.05
		local ry = shape.ry or shape.r or rx
		local dx = nx - shape.x
		local dy = ny - shape.y
		local angle = math.rad(shape.rotation or 0)
		local cosA = math.cos(angle)
		local sinA = math.sin(angle)
		local localX = dx * cosA + dy * sinA
		local localY = -dx * sinA + dy * cosA
		return (localX / rx) * (localX / rx) + (localY / ry) * (localY / ry) <= 1
	end

	if shape.type == "bar" then
		local x1 = shape.x1
		local y1 = shape.y1
		local x2 = shape.x2
		local y2 = shape.y2
		local dx = x2 - x1
		local dy = y2 - y1
		local lengthSquared = dx * dx + dy * dy
		local t = 0
		if lengthSquared > 0 then
			t = ((nx - x1) * dx + (ny - y1) * dy) / lengthSquared
			-- Même règle que le rendu : avec flatStart, le bout x1 est coupé
			-- droit, sans capuchon rond au-delà.
			if shape.flatStart and t < 0 then
				return false
			end
			t = math.clamp(t, 0, 1)
		end
		local px = x1 + dx * t
		local py = y1 + dy * t
		local ddx = nx - px
		local ddy = ny - py
		local radius = (shape.thickness or 0.04) * 0.5
		return ddx * ddx + ddy * ddy <= radius * radius
	end

	return false
end

local function anyShape(shapes, nx, ny)
	for _, shape in ipairs(shapes) do
		if pointInShape(shape, nx, ny) then
			return true
		end
	end
	return false
end

-- Règle unique de l'eau : un point est de l'eau s'il tombe dans une forme
-- d'eau et hors de toute forme sèche (presqu'île).
-- Une cellule est classée par son centre : une cellule dont le centre est
-- sur la terre reste construisible, même si un de ses bords touche le rivage.
function Maps.isWaterAt(map, nx, ny)
	if anyShape(map.dryShapes, nx, ny) then
		return false
	end
	return anyShape(map.waterShapes, nx, ny)
end

-- Cache par carte : chaque cellule n'est évaluée qu'une fois, au lieu de
-- recalculer les ellipses tournées à chaque test de construction.
local waterCells = setmetatable({}, { __mode = "k" })

local function cellWaterRows(map)
	local size = Config.Grid.Size
	local cached = waterCells[map]
	if cached and cached.size == size then
		return cached.rows
	end
	local rows = {}
	for y = 0, size - 1 do
		local row = {}
		for x = 0, size - 1 do
			row[x] = Maps.isWaterAt(map, (x + 0.5) / size, (y + 0.5) / size)
		end
		rows[y] = row
	end
	waterCells[map] = { size = size, rows = rows }
	return rows
end

function Maps.isWater(map, x, y)
	local row = cellWaterRows(map)[y]
	local cached = row and row[x]
	if cached ~= nil then
		return cached
	end
	-- Hors de la grille : même règle, sans cache.
	local size = Config.Grid.Size
	return Maps.isWaterAt(map, (x + 0.5) / size, (y + 0.5) / size)
end

function Maps.isGrass(map, x, y)
	local size = Config.Grid.Size
	return anyShape(map.grassShapes, (x + 0.5) / size, (y + 0.5) / size)
end

return Maps
