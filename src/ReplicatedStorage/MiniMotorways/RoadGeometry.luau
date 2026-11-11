--[[
	RoadGeometry.luau
	Géométrie pure de la surface des routes. Ce module ne crée aucune instance :
	il décrit des formes que le renderer transforme en parts, et qui restent
	testables sans Roblox.

	Repère de la case : 0..1 sur chaque axe, origine en haut à gauche, +x vers
	la droite, +y vers le bas, centre (0.5, 0.5). Les directions suivent Grid :
	N = y-1, E = x+1, S = y+1, W = x-1.

	Pièces : { kind, layer, cx, cy, w, h, r, rotation }
	  kind      "rect" (w le long de x local, h le long de y local) ou "disk" (r).
	  layer     "edge"   : liseré (RoadConfig.Visual.EdgeWidth), dessous.
	            "body"   : surface graphite (RoadWidth).
	            "bridge" : surface d'une case de pont, à la place de "body".
	            Une couche a une seule hauteur et une seule couleur : les
	            chevauchements entre pièces d'une même couche sont invisibles.
	  rotation  0, 90, 180 ou 270 degrés. Les pièces produites ici valent 0.

	Formes (demi-largeur h, rayon d'angle r = CornerRadius * RoadWidth) :
	  - aucun bras : disque de rayon h (bloc rond) ;
	  - un bras    : bras du bord jusqu'au centre + disque de rayon h (capuchon) ;
	  - droite     : un rectangle plein ;
	  - T et croix : les rectangles des bras, qui se recouvrent au centre ;
	  - virage     : deux rectangles + un disque de rayon r dans le coin
	                 extérieur. Le coin intérieur reste vif : un congé concave
	                 est un carré moins un disque, impossible avec des unions
	                 de rectangles et de disques, et l'approcher par des parts
	                 coûterait plusieurs parts par virage. Il se lit comme
	                 l'angle rentrant d'un T : largeur constante, sans
	                 triangle ni trou.
	Un bras relié à un bâtiment (raccord) s'arrête exactement au bord de la case.
	Les pièces restent dans le carré central et dans les bras.

	API :
	  RoadGeometry.Dir                            bits N=1 E=2 S=4 W=8
	  RoadGeometry.connectorKey(x, y, dir)        "x:y>dir" ; dir = "N"|"E"|"S"|"W" (lettre, pas un bit)
	  RoadGeometry.neighborMask(roads, x, y, bridges?, connectors?) -> bits
	  RoadGeometry.classify(mask) -> kind, orientation
	      kind : "isolated" | "end" | "straight" | "corner" | "tee" | "cross"
	      orientation : "" | direction du bras | "NS"/"EW" | "NE"/"ES"/"SW"/"NW"
	                    | direction du bras-tige d'un T | "NESW"
	  RoadGeometry.cellPieces(roads, bridges, connectors, x, y, options?) -> pièces
	  RoadGeometry.affectedCells(key) -> { key, voisins N, E, S, W }
	options (facultatif) : RoadWidth, EdgeWidth, CornerRadius (fraction de
	RoadWidth). Par défaut RoadConfig.Visual.

	Les clés sont au format Grid ("x:y"). roads, bridges (ponts, sous-ensemble
	ou non de roads) et connectors sont des ensembles ; une case compte comme
	route si elle est dans roads ou bridges.
]]

local Grid = require(script.Parent.Grid)
local RoadConfig = require(script.Parent.RoadConfig)

local RoadGeometry = {}

local CENTER = 0.5
local EMPTY = {}

RoadGeometry.Dir = { N = 1, E = 2, S = 4, W = 8 }

-- Ordre fixe N, E, S, W : les noms de classification en découlent.
local ARMS = {
	{ name = "N", bit = RoadGeometry.Dir.N, dx = 0, dy = -1, opposite = "S" },
	{ name = "E", bit = RoadGeometry.Dir.E, dx = 1, dy = 0, opposite = "W" },
	{ name = "S", bit = RoadGeometry.Dir.S, dx = 0, dy = 1, opposite = "N" },
	{ name = "W", bit = RoadGeometry.Dir.W, dx = -1, dy = 0, opposite = "E" },
}

local function clamp(value, low, high)
	return math.max(low, math.min(value, high))
end

local function optionOr(options, name, fallback)
	if options and options[name] ~= nil then
		return options[name]
	end
	return fallback
end

-- Bras présents dans un masque, sous la forme name -> true.
local function armsOf(mask)
	local arms = {}
	for _, arm in ipairs(ARMS) do
		if math.floor(mask / arm.bit) % 2 == 1 then
			arms[arm.name] = true
		end
	end
	return arms
end

-- Noms des bras présents, dans l'ordre N, E, S, W.
local function namesOf(arms)
	local names = ""
	for _, arm in ipairs(ARMS) do
		if arms[arm.name] then
			names = names .. arm.name
		end
	end
	return names
end

function RoadGeometry.connectorKey(x, y, dir)
	return Grid.key(x, y) .. ">" .. dir
end

function RoadGeometry.neighborMask(roads, x, y, bridges, connectors)
	roads = roads or EMPTY
	bridges = bridges or EMPTY
	connectors = connectors or EMPTY
	local mask = 0
	for _, arm in ipairs(ARMS) do
		local neighborKey = Grid.key(x + arm.dx, y + arm.dy)
		if roads[neighborKey]
			or bridges[neighborKey]
			or connectors[RoadGeometry.connectorKey(x, y, arm.name)]
		then
			mask += arm.bit
		end
	end
	return mask
end

function RoadGeometry.classify(mask)
	local arms = armsOf(mask)
	local count = 0
	for _, arm in ipairs(ARMS) do
		if arms[arm.name] then
			count += 1
		end
	end

	if count == 0 then
		return "isolated", ""
	end
	if count == 1 then
		return "end", namesOf(arms)
	end
	if count == 2 then
		if (arms.N and arms.S) or (arms.E and arms.W) then
			return "straight", namesOf(arms)
		end
		return "corner", namesOf(arms)
	end
	if count == 3 then
		-- La tige d'un T est le seul bras dont l'opposé est absent.
		local stem = ""
		for _, arm in ipairs(ARMS) do
			if arms[arm.name] and not arms[arm.opposite] then
				stem = arm.name
			end
		end
		return "tee", stem
	end
	return "cross", namesOf(arms)
end

local function addRect(out, layer, x0, x1, y0, y1)
	local w, h = x1 - x0, y1 - y0
	if w <= 0 or h <= 0 then
		return
	end
	table.insert(out, {
		kind = "rect",
		layer = layer,
		cx = (x0 + x1) * 0.5,
		cy = (y0 + y1) * 0.5,
		w = w,
		h = h,
		r = 0,
		rotation = 0,
	})
end

local function addDisk(out, layer, cx, cy, r)
	if r <= 0 then
		return
	end
	table.insert(out, {
		kind = "disk",
		layer = layer,
		cx = cx,
		cy = cy,
		w = 2 * r,
		h = 2 * r,
		r = r,
		rotation = 0,
	})
end

-- Bras d'un côté, du bord de la case jusqu'au centre.
local function addStub(out, layer, name, low, high)
	if name == "N" then
		addRect(out, layer, low, high, 0, CENTER)
	elseif name == "S" then
		addRect(out, layer, low, high, CENTER, 1)
	elseif name == "E" then
		addRect(out, layer, CENTER, 1, low, high)
	else
		addRect(out, layer, 0, CENTER, low, high)
	end
end

-- Construit une couche complète (toutes les formes d'une case).
-- Les virages utilisent un arrondi dont le centre ne dépend pas de la largeur :
-- le liseré et la surface sont donc deux arcs concentriques.
local function buildLayer(out, layer, mask, width, radius)
	local half = width * 0.5
	local r = clamp(radius, 0, half)
	local low, high = CENTER - half, CENTER + half
	local arms = armsOf(mask)

	local count = 0
	for _, arm in ipairs(ARMS) do
		if arms[arm.name] then
			count += 1
		end
	end

	if count == 0 then
		addDisk(out, layer, CENTER, CENTER, half)
		return
	end
	if count == 1 then
		addStub(out, layer, namesOf(arms), low, high)
		addDisk(out, layer, CENTER, CENTER, half)
		return
	end

	local vertical = (arms.N and "N") or (arms.S and "S") or nil
	local horizontal = (arms.E and "E") or (arms.W and "W") or nil
	if count == 2 and vertical and horizontal then
		-- Coin extérieur : opposé aux deux bras. Le centre de l'arrondi est
		-- à distance (half - r) des deux côtés extérieurs.
		local vy = vertical == "N" and -1 or 1
		local hx = horizontal == "E" and 1 or -1
		local roundX = CENTER - hx * (half - r)
		local roundY = CENTER - vy * (half - r)
		local verticalEnd = CENTER + vy * CENTER
		local horizontalEnd = CENTER + hx * CENTER
		addRect(out, layer, low, high, math.min(verticalEnd, roundY), math.max(verticalEnd, roundY))
		addRect(out, layer, math.min(horizontalEnd, roundX), math.max(horizontalEnd, roundX), low, high)
		addDisk(out, layer, roundX, roundY, r)
		return
	end

	-- Droite, T et croix : les bras opposés forment une bande pleine.
	if arms.N and arms.S then
		addRect(out, layer, low, high, 0, 1)
	else
		if arms.N then
			addStub(out, layer, "N", low, high)
		end
		if arms.S then
			addStub(out, layer, "S", low, high)
		end
	end
	if arms.E and arms.W then
		addRect(out, layer, 0, 1, low, high)
	else
		if arms.E then
			addStub(out, layer, "E", low, high)
		end
		if arms.W then
			addStub(out, layer, "W", low, high)
		end
	end
end

function RoadGeometry.cellPieces(roads, bridges, connectors, x, y, options)
	roads = roads or EMPTY
	bridges = bridges or EMPTY
	local key = Grid.key(x, y)
	if not (roads[key] or bridges[key]) then
		return {}
	end

	local visual = RoadConfig.Visual
	local roadWidth = optionOr(options, "RoadWidth", visual.RoadWidth)
	local edgeWidth = optionOr(options, "EdgeWidth", visual.EdgeWidth)
	local cornerFraction = optionOr(options, "CornerRadius", visual.CornerRadius)
	local bodyRadius = cornerFraction * roadWidth

	local mask = RoadGeometry.neighborMask(roads, x, y, bridges, connectors)
	local pieces = {}
	-- Le liseré garde le même centre d'arrondi : son rayon augmente de la moitié
	-- de l'écart entre les deux largeurs.
	buildLayer(pieces, "edge", mask, edgeWidth, bodyRadius + (edgeWidth - roadWidth) * 0.5)
	buildLayer(pieces, bridges[key] and "bridge" or "body", mask, roadWidth, bodyRadius)
	return pieces
end

-- La case et ses quatre voisins : ce sont les seules dont les pièces changent
-- quand une route apparaît, disparaît ou devient un pont.
function RoadGeometry.affectedCells(key)
	local x, y = Grid.parse(key)
	if not x then
		return {}
	end
	local cells = { key }
	for _, arm in ipairs(ARMS) do
		table.insert(cells, Grid.key(x + arm.dx, y + arm.dy))
	end
	return cells
end

return RoadGeometry
