--[[
	Pathfinding.luau
	A* sur la grille de routes, en 8 directions : les diagonales sont
	autorisées. On part d'une case de route et on vise un ensemble de cases
	(les cases de route adjacentes à la destination).
]]

local Grid = require(script.Parent.Grid)

local Pathfinding = {}

-- Une étape diagonale coûte 1 dans notre grille, donc l'heuristique
-- admissible est la distance de Chebyshev (max des deux écarts).
local function chebyshev(x1, y1, x2, y2)
	return math.max(math.abs(x1 - x2), math.abs(y1 - y2))
end

function Pathfinding.find(roads, size, startKey, goalSet)
	if type(startKey) ~= "string" or not roads[startKey] then
		return nil
	end
	if goalSet[startKey] then
		return { startKey }
	end

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

	local function heuristic(key)
		local x, y = Grid.parse(key)
		local best = math.huge
		for _, goal in ipairs(goalCells) do
			local d = chebyshev(x, y, goal[1], goal[2])
			if d < best then
				best = d
			end
		end
		return best
	end

	fScore[startKey] = heuristic(startKey)

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
		for _, neighbor in ipairs(Grid.neighbors8(cx, cy)) do
			local nx, ny = neighbor[1], neighbor[2]
			if nx >= 0 and ny >= 0 and nx < size and ny < size then
				local nk = Grid.key(nx, ny)
				if roads[nk] and not closed[nk] then
					local tentative = (gScore[current] or math.huge) + 1
					if tentative < (gScore[nk] or math.huge) then
						cameFrom[nk] = current
						gScore[nk] = tentative
						fScore[nk] = tentative + heuristic(nk)
						open[nk] = true
					end
				end
			end
		end
	end

	return nil
end

return Pathfinding
