--[[
	Pathfinding.luau
	A* sur la grille de routes.

	Par défaut le réseau est orthogonal : seuls les voisins haut / bas /
	gauche / droite sont parcourus, avec une heuristique de Manhattan.
	Le mode 8 directions reste disponible pour les anciens réseaux.
]]

local Grid = require(script.Parent.Grid)

local Pathfinding = {}

local function manhattan(x1, y1, x2, y2)
	return math.abs(x1 - x2) + math.abs(y1 - y2)
end

local function chebyshev(x1, y1, x2, y2)
	return math.max(math.abs(x1 - x2), math.abs(y1 - y2))
end

-- allowDiagonals est optionnel et vaut false par défaut.
function Pathfinding.find(roads, size, startKey, goalSet, allowDiagonals)
	if type(startKey) ~= "string" or not roads[startKey] then
		return nil
	end
	if goalSet[startKey] then
		return { startKey }
	end

	local useDiagonals = allowDiagonals == true
	local heuristic = useDiagonals and chebyshev or manhattan
	local neighborList = useDiagonals and Grid.neighbors8 or Grid.neighbors

	local goalCells = {}
	for key in pairs(goalSet) do
		local gx, gy = Grid.parse(key)
		if gx then
			table.insert(goalCells, { gx, gy })
		end
	end
	if #goalCells == 0 then
		return nil
	end

	local open = { [startKey] = true }
	local gScore = { [startKey] = 0 }
	local fScore = { [startKey] = 0 }
	local cameFrom = {}
	local closed = {}

	local function estimate(key)
		local x, y = Grid.parse(key)
		local best = math.huge
		for _, goal in ipairs(goalCells) do
			local d = heuristic(x, y, goal[1], goal[2])
			if d < best then
				best = d
			end
		end
		return best
	end

	fScore[startKey] = estimate(startKey)

	while next(open) ~= nil do
		local current = nil
		local bestF = math.huge
		for key in pairs(open) do
			local f = fScore[key] or math.huge
			if f < bestF then
				current = key
				bestF = f
			end
		end
		if not current then
			break
		end
		if goalSet[current] then
			local path = { current }
			local node = current
			while cameFrom[node] do
				node = cameFrom[node]
				table.insert(path, 1, node)
			end
			return path
		end

		open[current] = nil
		closed[current] = true

		local cx, cy = Grid.parse(current)
		for _, neighbor in ipairs(neighborList(cx, cy)) do
			local nx, ny = neighbor[1], neighbor[2]
			if nx >= 0 and ny >= 0 and nx < size and ny < size then
				local nk = Grid.key(nx, ny)
				if roads[nk] and not closed[nk] then
					local tentative = (gScore[current] or math.huge) + 1
					if tentative < (gScore[nk] or math.huge) then
						cameFrom[nk] = current
						gScore[nk] = tentative
						fScore[nk] = tentative + estimate(nk)
						open[nk] = true
					end
				end
			end
		end
	end

	return nil
end

return Pathfinding
