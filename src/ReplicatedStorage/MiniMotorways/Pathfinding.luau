--[[
	Pathfinding.luau
	A* sur la grille de routes.

	Par défaut le réseau est orthogonal : seuls les voisins haut / bas /
	gauche / droite sont parcourus, avec une heuristique de Manhattan.
	Le mode 8 directions reste disponible pour les anciens réseaux (heuristique
	de Chebyshev, un déplacement diagonal coûte une case).

	Performance : chaque case reçoit un identifiant entier (y * size + x + 1)
	pour éviter de reparser des clés à chaque expansion, la liste ouverte est
	un tas binaire (O(log n) par insertion ou extraction), et la route d'une
	case est lue une seule fois. L'heuristique est la distance au but le plus
	proche : elle reste admissible et cohérente, donc la première arrivée au
	but est un plus court chemin.
]]

local Grid = require(script.Parent.Grid)

local Pathfinding = {}

-- Les 8 voisins, construits une fois : la recherche ne reconstruit pas la liste.
local EIGHT_OFFSETS = {}
for _, offset in ipairs(Grid.ORTHOGONAL_OFFSETS) do
	table.insert(EIGHT_OFFSETS, offset)
end
for _, offset in ipairs(Grid.DIAGONAL_OFFSETS) do
	table.insert(EIGHT_OFFSETS, offset)
end

local function isPositiveSize(size)
	return type(size) == "number" and size >= 1 and size == math.floor(size)
end

-- Recherche commune : le chemin le plus court part de l'une des clés de
-- starts. maxExpansions borne le nombre de cases dépilées (nil = sans limite).
local function search(roads, size, starts, goalSet, allowDiagonals, maxExpansions)
	if type(roads) ~= "table" or type(goalSet) ~= "table" or type(starts) ~= "table" then
		return nil
	end
	if not isPositiveSize(size) then
		return nil
	end

	local budget = type(maxExpansions) == "number" and maxExpansions or math.huge

	local function idOf(x, y)
		return y * size + x + 1
	end

	local function coordsOf(id)
		local x = (id - 1) % size
		return x, (id - 1 - x) / size
	end

	-- Route présente ou non, lue une fois par case et mise en cache.
	local walkable = {}
	local function isRoad(x, y)
		local id = idOf(x, y)
		local known = walkable[id]
		if known == nil then
			known = roads[Grid.key(x, y)] and true or false
			walkable[id] = known
		end
		return known
	end

	-- Seules les cases de route dans la grille peuvent être atteintes : un but
	-- hors route ou hors grille ne sert donc ni à la recherche ni à l'heuristique.
	local goalIds = {}
	local goalX, goalY = {}, {}
	for key, flag in pairs(goalSet) do
		local gx, gy = Grid.parse(key)
		if flag and gx and Grid.inRange(gx, gy, size) and isRoad(gx, gy) then
			local id = idOf(gx, gy)
			if not goalIds[id] then
				goalIds[id] = true
				goalX[#goalX + 1] = gx
				goalY[#goalY + 1] = gy
			end
		end
	end
	if #goalX == 0 then
		return nil
	end

	-- Min sur les buts : minorer la distance du but le plus proche reste admissible
	-- avec plusieurs buts, et la fonction reste cohérente.
	local function estimate(x, y)
		local best = math.huge
		for i = 1, #goalX do
			local dx = math.abs(x - goalX[i])
			local dy = math.abs(y - goalY[i])
			local d
			if allowDiagonals then
				d = math.max(dx, dy)
			else
				d = dx + dy
			end
			if d < best then
				best = d
			end
		end
		return best
	end

	-- Tas binaire parallèle : priorité (f, puis h, puis id). Les égalités sont
	-- départagées de façon déterministe : un même réseau donne toujours le même tracé.
	local heapF, heapH, heapId = {}, {}, {}
	local heapSize = 0

	local function before(i, j)
		if heapF[i] ~= heapF[j] then
			return heapF[i] < heapF[j]
		end
		if heapH[i] ~= heapH[j] then
			return heapH[i] < heapH[j]
		end
		return heapId[i] < heapId[j]
	end

	local function swap(i, j)
		heapF[i], heapF[j] = heapF[j], heapF[i]
		heapH[i], heapH[j] = heapH[j], heapH[i]
		heapId[i], heapId[j] = heapId[j], heapId[i]
	end

	local function push(f, h, id)
		heapSize += 1
		local i = heapSize
		heapF[i], heapH[i], heapId[i] = f, h, id
		while i > 1 do
			local parentIndex = math.floor(i / 2)
			if not before(i, parentIndex) then
				break
			end
			swap(i, parentIndex)
			i = parentIndex
		end
	end

	local function pop()
		local topId = heapId[1]
		heapF[1], heapH[1], heapId[1] = heapF[heapSize], heapH[heapSize], heapId[heapSize]
		heapF[heapSize], heapH[heapSize], heapId[heapSize] = nil, nil, nil
		heapSize -= 1
		local i = 1
		while true do
			local smallest = i
			local left, right = 2 * i, 2 * i + 1
			if left <= heapSize and before(left, smallest) then
				smallest = left
			end
			if right <= heapSize and before(right, smallest) then
				smallest = right
			end
			if smallest == i then
				break
			end
			swap(i, smallest)
			i = smallest
		end
		return topId
	end

	local gScore, hScore, parent, closed = {}, {}, {}, {}

	-- Départs : chaque case de départ valide est ouverte à coût 0. Si l'une
	-- d'elles est déjà un but, c'est le chemin d'une seule case.
	local started = false
	for _, startKey in ipairs(starts) do
		local sx, sy = Grid.parse(startKey)
		if sx and Grid.inRange(sx, sy, size) and isRoad(sx, sy) then
			local id = idOf(sx, sy)
			if goalIds[id] then
				return { Grid.key(sx, sy) }
			end
			if gScore[id] == nil then
				started = true
				gScore[id] = 0
				local h = estimate(sx, sy)
				hScore[id] = h
				push(h, h, id)
			end
		end
	end
	if not started then
		return nil
	end

	local function rebuild(goalId)
		local ids = {}
		local node = goalId
		while node ~= nil do
			ids[#ids + 1] = node
			node = parent[node]
		end
		local path = {}
		for i = #ids, 1, -1 do
			local x, y = coordsOf(ids[i])
			path[#path + 1] = Grid.key(x, y)
		end
		return path
	end

	local offsets = allowDiagonals and EIGHT_OFFSETS or Grid.ORTHOGONAL_OFFSETS
	local expansions = 0
	while heapSize > 0 do
		local id = pop()
		if not closed[id] then
			if goalIds[id] then
				return rebuild(id)
			end

			expansions += 1
			if expansions > budget then
				return nil
			end
			closed[id] = true

			local x, y = coordsOf(id)
			local cost = gScore[id] + 1
			for _, offset in ipairs(offsets) do
				local nx, ny = x + offset[1], y + offset[2]
				if Grid.inRange(nx, ny, size) and isRoad(nx, ny) then
					local nid = idOf(nx, ny)
					if not closed[nid] and (gScore[nid] == nil or cost < gScore[nid]) then
						gScore[nid] = cost
						parent[nid] = id
						local h = hScore[nid]
						if h == nil then
							h = estimate(nx, ny)
							hScore[nid] = h
						end
						push(cost + h, h, nid)
					end
				end
			end
		end
	end

	return nil
end

--[[
	Plus court chemin de startKey à un but de goalSet, sous forme de liste de
	clés (départ inclus), ou nil. Les cases doivent être des routes de la
	grille size x size. allowDiagonals autorise les 8 voisins. maxExpansions
	optionnel borne le travail : au-delà, la recherche renvoie nil.
]]
function Pathfinding.find(roads, size, startKey, goalSet, allowDiagonals, maxExpansions)
	return search(roads, size, { startKey }, goalSet, allowDiagonals == true, maxExpansions)
end

-- Variante à plusieurs départs (par exemple les connecteurs d'une maison) :
-- une seule recherche qui renvoie le plus court des chemins, au lieu d'une
-- recherche par départ.
function Pathfinding.findFromAny(roads, size, startKeys, goalSet, allowDiagonals, maxExpansions)
	return search(roads, size, startKeys, goalSet, allowDiagonals == true, maxExpansions)
end

return Pathfinding
