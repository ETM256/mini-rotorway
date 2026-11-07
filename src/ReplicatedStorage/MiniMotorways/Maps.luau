--[[
	Maps.luau
	Les villes du jeu. Chaque carte décrit :
	  - son nom / sa description / ses couleurs
	  - sa géographie : waterShapes, dryShapes et grassShapes, des formes
	    normalisées (0..1) utilisées à la fois par l'aperçu du menu et par le
	    rendu 3D
	  - un petit tracé de routes pour l'aperçu circulaire du menu
	  - les étiquettes verticales visibles sur la bordure de la carte
]]

local Config = require(script.Parent.Config)
local C = Config.Colors

local Maps = {}

local function circle(nx, ny, cx, cy, rx, ry)
	local dx = (nx - cx) / rx
	local dy = (ny - cy) / ry
	return dx * dx + dy * dy <= 1
end

-- Distance à un segment normalisé : sert aux chenaux et aux bandes d'eau.
local function segment(nx, ny, x1, y1, x2, y2, thickness)
	local dx = x2 - x1
	local dy = y2 - y1
	local lengthSquared = dx * dx + dy * dy
	if lengthSquared <= 0 then
		return false
	end
	local t = ((nx - x1) * dx + (ny - y1) * dy) / lengthSquared
	t = math.clamp(t, 0, 1)
	local px = x1 + dx * t
	local py = y1 + dy * t
	local radius = thickness * 0.5
	return (nx - px) * (nx - px) + (ny - py) * (ny - py) <= radius * radius
end

local list = {
	{
		id = "dubai",
		name = "Dubaï",
		mode = "Classique",
		description = "Reliez les quartiers de Dubaï et traversez la marina avant la fin du temps imparti.",
		header = Color3.fromHex("F8DB95"),
		accent = Color3.fromHex("E8C37A"),
		labels = {
			{ text = "DUBAÏ", side = "right" },
			{ text = "MARINA", side = "left" },
		},
		previewRoads = {
			{ 0.22, 0.22, 0.72, 0.22 },
			{ 0.72, 0.22, 0.72, 0.58 },
			{ 0.30, 0.48, 0.76, 0.48 },
			{ 0.30, 0.48, 0.30, 0.76 },
		},
		waterShapes = {
			{ type = "rect", x = -0.12, y = 0.83, w = 1.28, h = 0.35, radius = 0.08 },
			{ type = "bar", x1 = 0.22, y1 = 0.84, x2 = 0.43, y2 = 0.62, thickness = 0.070 },
			{ type = "bar", x1 = 0.43, y1 = 0.62, x2 = 0.60, y2 = 0.82, thickness = 0.060 },
			{ type = "ellipse", x = 0.76, y = 0.34, rx = 0.115, ry = 0.075 },
			{ type = "ellipse", x = 0.60, y = 0.18, rx = 0.070, ry = 0.045 },
		},
		grassShapes = {
			{ type = "ellipse", x = 0.36, y = 0.36, rx = 0.14, ry = 0.09 },
			{ type = "ellipse", x = 0.80, y = 0.68, rx = 0.12, ry = 0.08 },
		},
		isWater = function(nx, ny)
			if ny > 0.84 + 0.018 * math.sin(nx * 12) then
				return true
			end
			if math.abs(0.52 * nx + ny - 0.98) < 0.035 and nx > 0.22 and nx < 0.60 then
				return true
			end
			if circle(nx, ny, 0.76, 0.34, 0.115, 0.075) then
				return true
			end
			if circle(nx, ny, 0.60, 0.18, 0.070, 0.045) then
				return true
			end
			return false
		end,
	},
	{
		id = "los_angeles",
		name = "Los Angeles",
		mode = "Classique",
		description = "Gérez le quadrillage d'autoroutes de la métropole californienne grandissante.",
		header = Color3.fromHex("FFDD94"),
		accent = Color3.fromHex("E8C37A"),
		land = Color3.fromHex("FFF8DC"),
		water = Color3.fromHex("A5DAC6"),
		waterEdge = Color3.fromHex("8FC9B7"),
		waterDeep = Color3.fromHex("7FB7A5"),
		grass = Color3.fromHex("EFEC8C"),
		labels = {
			{ text = "LOS ANGELES", side = "right" },
			{ text = "SANTA MONICA", side = "left" },
		},
		previewRoads = {
			{ 0.27, 0.12, 0.27, 0.54 },
			{ 0.27, 0.54, 0.52, 0.54 },
			{ 0.52, 0.54, 0.52, 0.88 },
			{ 0.52, 0.54, 0.78, 0.54 },
		},
		-- La côte ouest est une goutte d'eau inclinée qui reste à l'intérieur
		-- du cercle. La baie du bas est large et arrondie, avec une presqu'île
		-- centrale, et le chenal vertical finit dans cette baie.
		-- Les ellipses tournées reprennent les formes de la référence :
		-- rotation en degrés dans le repère de l'écran (x à droite, y en bas).
		waterShapes = {
			-- Côte ouest : une grande ellipse inclinée, complétée par des
			-- capsules le long de la côte pour casser le côté « ovale ».
			{ type = "ellipse", x = 0.1548, y = 0.5708, rx = 0.0955, ry = 0.2236, rotation = 163.3 },
			{ type = "bar", x1 = 0.060, y1 = 0.310, x2 = 0.100, y2 = 0.380, thickness = 0.055 },
			{ type = "bar", x1 = 0.065, y1 = 0.340, x2 = 0.120, y2 = 0.620, thickness = 0.060 },
			{ type = "bar", x1 = 0.090, y1 = 0.600, x2 = 0.160, y2 = 0.760, thickness = 0.070 },
			{ type = "ellipse", x = 0.2200, y = 0.8200, rx = 0.0900, ry = 0.0450, rotation = 15 },
			-- Baie du bas : grande ellipse couchée, bord supérieur presque
			-- droit et lobe de droite en capsule, comme sur la référence.
			{ type = "ellipse", x = 0.5570, y = 0.8070, rx = 0.1010, ry = 0.2790, rotation = 81.4 },
			{ type = "bar", x1 = 0.580, y1 = 0.700, x2 = 0.870, y2 = 0.740, thickness = 0.060 },
			{ type = "bar", x1 = 0.700, y1 = 0.750, x2 = 0.860, y2 = 0.760, thickness = 0.080 },
			-- Chenal vertical, fin, qui rejoint la baie.
			{ type = "bar", x1 = 0.70, y1 = 0.32, x2 = 0.70, y2 = 0.70, thickness = 0.018 },
			{ type = "ellipse", x = 0.70, y = 0.70, rx = 0.075, ry = 0.050 },
		},
		-- Presqu'île crème au centre de la baie : le raccord au continent
		-- est coupé à ras du littoral, sans gros capuchon rond. Seule la
		-- pointe côté eau reste arrondie.
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
			-- Parc allongé en haut à droite, avec un petit point détaché.
			{ type = "ellipse", x = 0.7905, y = 0.1976, rx = 0.0526, ry = 0.1187, rotation = 140.6 },
			{ type = "circle", x = 0.88, y = 0.28, r = 0.020 },
			-- Parc étroit qui longe la côte ouest.
			{ type = "ellipse", x = 0.2019, y = 0.3646, rx = 0.0275, ry = 0.1261, rotation = 145.9 },
			-- Parc de la presqu'île, en bas à gauche.
			{ type = "ellipse", x = 0.310, y = 0.700, rx = 0.080, ry = 0.120, rotation = 54 },
			{ type = "circle", x = 0.35, y = 0.72, r = 0.018 },
		},
	},
	{
		id = "beijing",
		name = "Pékin",
		mode = "Classique",
		description = "Construisez les routes qui permettent aux millions d'habitants de Pékin d'arriver au travail à l'heure.",
		header = Color3.fromHex("7AA09E"),
		accent = Color3.fromHex("5F8A88"),
		labels = {
			{ text = "PÉKIN", side = "right" },
			{ text = "HAIDIAN", side = "left" },
		},
		previewRoads = {
			{ 0.18, 0.34, 0.82, 0.34 },
			{ 0.55, 0.18, 0.55, 0.78 },
			{ 0.34, 0.56, 0.82, 0.56 },
			{ 0.18, 0.34, 0.18, 0.62 },
		},
		waterShapes = {
			{ type = "rect", x = -0.10, y = -0.12, w = 1.20, h = 0.20, radius = 0.06 },
			{ type = "bar", x1 = -0.05, y1 = 0.085, x2 = 0.45, y2 = 0.060, thickness = 0.050 },
			{ type = "bar", x1 = 0.45, y1 = 0.060, x2 = 1.05, y2 = 0.085, thickness = 0.050 },
			{ type = "ellipse", x = 0.73, y = 0.28, rx = 0.075, ry = 0.055 },
			{ type = "ellipse", x = 0.22, y = 0.72, rx = 0.045, ry = 0.060 },
			{ type = "bar", x1 = 0.47, y1 = 0.62, x2 = 0.47, y2 = 0.86, thickness = 0.032 },
		},
		grassShapes = {
			{ type = "ellipse", x = 0.33, y = 0.42, rx = 0.12, ry = 0.09 },
			{ type = "ellipse", x = 0.78, y = 0.72, rx = 0.10, ry = 0.07 },
		},
		isWater = function(nx, ny)
			if ny < 0.07 + 0.012 * math.sin(nx * 16) then
				return true
			end
			if circle(nx, ny, 0.73, 0.28, 0.075, 0.055) then
				return true
			end
			if circle(nx, ny, 0.22, 0.72, 0.045, 0.06) then
				return true
			end
			if math.abs(nx - 0.47) < 0.012 and ny > 0.62 and ny < 0.86 then
				return true
			end
			return false
		end,
	},
	{
		id = "tokyo",
		name = "Tokyo",
		mode = "Classique",
		description = "Reliez les quartiers de Tokyo, la plus grande métropole du monde.",
		header = Color3.fromHex("E9A7A0"),
		accent = Color3.fromHex("D98A82"),
		labels = {
			{ text = "TOKYO", side = "right" },
			{ text = "SHIBUYA", side = "left" },
		},
		previewRoads = {
			{ 0.20, 0.22, 0.70, 0.22 },
			{ 0.70, 0.22, 0.70, 0.60 },
			{ 0.30, 0.46, 0.74, 0.46 },
			{ 0.20, 0.22, 0.20, 0.52 },
		},
		waterShapes = {
			{ type = "ellipse", x = 0.88, y = 0.90, rx = 0.26, ry = 0.22 },
			{ type = "bar", x1 = 0.28, y1 = 0.83, x2 = 1.02, y2 = 0.18, thickness = 0.045 },
		},
		grassShapes = {
			{ type = "ellipse", x = 0.36, y = 0.28, rx = 0.10, ry = 0.07 },
			{ type = "ellipse", x = 0.55, y = 0.70, rx = 0.09, ry = 0.06 },
		},
		isWater = function(nx, ny)
			if circle(nx, ny, 0.88, 0.90, 0.26, 0.22) then
				return true
			end
			if math.abs(0.9 * nx + ny - 1.08) < 0.022 and nx > 0.28 and ny > 0.15 then
				return true
			end
			return false
		end,
	},
	{
		id = "dar_es_salam",
		name = "Dar es Salaam",
		mode = "Classique",
		description = "Développez votre réseau pour suivre la croissance rapide de Dar es Salaam.",
		header = Color3.fromHex("B5E0CE"),
		accent = Color3.fromHex("8FCBB4"),
		labels = {
			{ text = "DAR ES SALAAM", side = "right" },
			{ text = "KIGAMBONI", side = "left" },
		},
		previewRoads = {
			{ 0.14, 0.64, 0.58, 0.64 },
			{ 0.58, 0.64, 0.58, 0.32 },
			{ 0.30, 0.42, 0.76, 0.42 },
			{ 0.58, 0.32, 0.82, 0.32 },
		},
		waterShapes = {
			{ type = "rect", x = 0.82, y = -0.20, w = 0.25, h = 1.40, radius = 0.16 },
			{ type = "circle", x = 0.84, y = 0.06, r = 0.060 },
			{ type = "circle", x = 0.81, y = 0.18, r = 0.070 },
			{ type = "circle", x = 0.84, y = 0.31, r = 0.060 },
			{ type = "circle", x = 0.80, y = 0.44, r = 0.070 },
			{ type = "circle", x = 0.84, y = 0.57, r = 0.060 },
			{ type = "circle", x = 0.81, y = 0.70, r = 0.070 },
			{ type = "circle", x = 0.84, y = 0.83, r = 0.060 },
			{ type = "circle", x = 0.80, y = 0.94, r = 0.070 },
			{ type = "ellipse", x = 0.62, y = 0.18, rx = 0.10, ry = 0.07 },
			{ type = "bar", x1 = 0.45, y1 = 0.60, x2 = 0.72, y2 = 0.64, thickness = 0.032 },
			{ type = "bar", x1 = 0.72, y1 = 0.64, x2 = 1.05, y2 = 0.62, thickness = 0.032 },
		},
		grassShapes = {
			{ type = "ellipse", x = 0.32, y = 0.28, rx = 0.12, ry = 0.08 },
			{ type = "ellipse", x = 0.52, y = 0.76, rx = 0.10, ry = 0.07 },
		},
		isWater = function(nx, ny)
			local coast = 0.87 - 0.03 * math.sin(ny * 8)
			if nx > coast then
				return true
			end
			if circle(nx, ny, 0.62, 0.18, 0.10, 0.07) then
				return true
			end
			if math.abs(ny - (0.62 + 0.05 * math.sin(nx * 9))) < 0.016 and nx > 0.45 then
				return true
			end
			return false
		end,
	},
	{
		id = "london",
		name = "Londres",
		mode = "Classique",
		description = "Traversez la Tamise et redessinez les rues de la capitale britannique.",
		header = Color3.fromHex("C9D6D9"),
		accent = Color3.fromHex("A8B8C0"),
		labels = {
			{ text = "LONDRES", side = "right" },
			{ text = "SOUTH BANK", side = "left" },
		},
		previewRoads = {
			{ 0.20, 0.28, 0.80, 0.28 },
			{ 0.50, 0.24, 0.50, 0.72 },
			{ 0.25, 0.72, 0.75, 0.72 },
			{ 0.25, 0.72, 0.25, 0.86 },
		},
		waterShapes = {
			{ type = "bar", x1 = -0.05, y1 = 0.52, x2 = 0.25, y2 = 0.62, thickness = 0.100 },
			{ type = "bar", x1 = 0.25, y1 = 0.62, x2 = 0.50, y2 = 0.52, thickness = 0.100 },
			{ type = "bar", x1 = 0.50, y1 = 0.52, x2 = 0.75, y2 = 0.42, thickness = 0.100 },
			{ type = "bar", x1 = 0.75, y1 = 0.42, x2 = 1.05, y2 = 0.48, thickness = 0.100 },
			{ type = "ellipse", x = 0.18, y = 0.62, rx = 0.045, ry = 0.035 },
		},
		grassShapes = {
			{ type = "ellipse", x = 0.72, y = 0.72, rx = 0.12, ry = 0.08 },
			{ type = "ellipse", x = 0.30, y = 0.28, rx = 0.09, ry = 0.06 },
		},
		isWater = function(nx, ny)
			local riverY = 0.52 + 0.10 * math.sin(nx * 5.0)
			if math.abs(ny - riverY) < 0.05 then
				return true
			end
			if circle(nx, ny, 0.18, 0.62, 0.045, 0.035) then
				return true
			end
			return false
		end,
	},
}

-- Couleurs communes : le papier crème et l'eau menthe restent identiques
-- d'une carte à l'autre, seuls les en-têtes et accents changent.
for _, map in ipairs(list) do
	map.land = map.land or C.Land
	map.water = map.water or C.Water
	map.waterEdge = map.waterEdge or C.WaterEdge
	map.waterDeep = map.waterDeep or C.WaterDeep
	map.grass = map.grass or C.Grass
	map.mode = map.mode or "Classique"
	map.labels = map.labels or {}
	map.grassShapes = map.grassShapes or {}
	map.dryShapes = map.dryShapes or {}
	map.dryPatches = map.dryPatches or {}
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

-- Teste un point normalisé contre une forme d'eau / d'herbe.
-- Les mêmes formes servent à l'aperçu du menu et au rendu 3D du terrain.
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

function Maps.isWater(map, x, y)
	local size = Config.Grid.Size
	local nx = (x + 0.5) / size
	local ny = (y + 0.5) / size

	-- Les presqu'îles et raccords secs reprennent le dessus de l'eau.
	-- Ils doivent donc être considérés comme de la terre pour les routes.
	for _, shape in ipairs(map.dryShapes or {}) do
		if pointInShape(shape, nx, ny) then
			return false
		end
	end
	for _, shape in ipairs(map.dryPatches or {}) do
		if pointInShape(shape, nx, ny) then
			return false
		end
	end

	for _, shape in ipairs(map.waterShapes or {}) do
		if pointInShape(shape, nx, ny) then
			return true
		end
	end
	return false
end

function Maps.isGrass(map, x, y)
	local size = Config.Grid.Size
	local nx = (x + 0.5) / size
	local ny = (y + 0.5) / size
	for _, shape in ipairs(map.grassShapes or {}) do
		if pointInShape(shape, nx, ny) then
			return true
		end
	end
	return false
end

return Maps
