--[[
	RoadNetwork.luau
	Petites opérations partagées par le client et le serveur :
	  - voisinage orthogonal (ou 8 directions en mode historique) ;
	  - comptage des connexions d'une case (virage, T, croix) ;
	  - résolution d'un geste en chemin horizontal / vertical sans diagonale.

	La simulation reste dans Session : ce module ne possède aucune route et
	ne crée aucun objet.
]]

local RoadNetwork = {}

local ORTHOGONAL = {
	{ 0, -1 },
	{ 1, 0 },
	{ 0, 1 },
	{ -1, 0 },
}

local DIAGONAL = {
	{ 1, -1 },
	{ 1, 1 },
	{ -1, 1 },
	{ -1, -1 },
}

RoadNetwork.ORTHOGONAL = ORTHOGONAL
RoadNetwork.DIAGONAL = DIAGONAL

function RoadNetwork.neighbors(x, y, allowDiagonals)
	local list = {}
	for _, direction in ipairs(ORTHOGONAL) do
		list[#list + 1] = { x + direction[1], y + direction[2] }
	end
	if allowDiagonals then
		for _, direction in ipairs(DIAGONAL) do
			list[#list + 1] = { x + direction[1], y + direction[2] }
		end
	end
	return list
end

function RoadNetwork.isAdjacent(ax, ay, bx, by, allowDiagonals)
	local dx = math.abs(bx - ax)
	local dy = math.abs(by - ay)
	if dx == 0 and dy == 0 then
		return false
	end
	if dy == 0 and dx == 1 then
		return true
	end
	if dx == 0 and dy == 1 then
		return true
	end
	return allowDiagonals == true and dx == 1 and dy == 1
end

function RoadNetwork.countRoadNeighbors(roads, x, y, allowDiagonals)
	local count = 0
	for _, neighbor in ipairs(RoadNetwork.neighbors(x, y, allowDiagonals)) do
		local key = neighbor[1] .. ":" .. neighbor[2]
		if roads[key] then
			count += 1
		end
	end
	return count
end

function RoadNetwork.countRoadNeighborsAtKey(roads, key, allowDiagonals)
	local x, y = string.match(key, "^(%-?%d+):(%-?%d+)$")
	if not x then
		return 0
	end
	return RoadNetwork.countRoadNeighbors(roads, tonumber(x), tonumber(y), allowDiagonals)
end

function RoadNetwork.isIntersection(roads, x, y, allowDiagonals)
	return RoadNetwork.countRoadNeighbors(roads, x, y, allowDiagonals) >= 3
end

function RoadNetwork.isIntersectionKey(roads, key, allowDiagonals)
	return RoadNetwork.countRoadNeighborsAtKey(roads, key, allowDiagonals) >= 3
end

-- Construit un chemin orthogonal entre deux cases, sans inclure la case de
-- départ. preferredAxis vaut "x" ou "y" : il décide de l'axe parcouru en
-- premier quand le déplacement est en biais.
function RoadNetwork.manhattanPath(fromX, fromY, toX, toY, preferredAxis)
	local cells = {}
	if fromX == toX and fromY == toY then
		return cells
	end

	local dx = toX - fromX
	local dy = toY - fromY
	local horizontalFirst

	if math.abs(dy) == 0 then
		horizontalFirst = true
	elseif math.abs(dx) == 0 then
		horizontalFirst = false
	elseif preferredAxis == "x" then
		horizontalFirst = true
	elseif preferredAxis == "y" then
		horizontalFirst = false
	elseif math.abs(dx) > math.abs(dy) then
		horizontalFirst = true
	elseif math.abs(dy) > math.abs(dx) then
		horizontalFirst = false
	else
		horizontalFirst = true
	end

	local x, y = fromX, fromY
	local guard = 0
	local function add(cx, cy)
		guard += 1
		if guard <= 512 then
			cells[#cells + 1] = { cx, cy }
		end
	end

	if horizontalFirst then
		local stepX = dx > 0 and 1 or -1
		while x ~= toX and guard < 512 do
			x += stepX
			add(x, y)
		end
		local stepY = dy > 0 and 1 or -1
		while y ~= toY and guard < 512 do
			y += stepY
			add(x, y)
		end
	else
		local stepY = dy > 0 and 1 or -1
		while y ~= toY and guard < 512 do
			y += stepY
			add(x, y)
		end
		local stepX = dx > 0 and 1 or -1
		while x ~= toX and guard < 512 do
			x += stepX
			add(x, y)
		end
	end

	return cells
end

-- Ajoute les cellules intermédiaires d'un tracé déjà ordonné, en supprimant
-- les doublons. Utile pour un lot envoyé au serveur.
function RoadNetwork.flattenPath(startX, startY, cells, preferredAxis)
	local result = {}
	local seen = {}
	local x, y = startX, startY
	for _, cell in ipairs(cells or {}) do
		if type(cell) == "table" then
			local tx = math.floor(tonumber(cell[1]) or x)
			local ty = math.floor(tonumber(cell[2]) or y)
			for _, step in ipairs(RoadNetwork.manhattanPath(x, y, tx, ty, preferredAxis)) do
				local key = step[1] .. ":" .. step[2]
				if not seen[key] then
					seen[key] = true
					result[#result + 1] = step
				end
			end
			x, y = tx, ty
		end
	end
	return result
end

return RoadNetwork
