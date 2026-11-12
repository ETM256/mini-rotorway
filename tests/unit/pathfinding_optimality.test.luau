-- Optimalité de Pathfinding.find : chaque résultat est comparé à un BFS
-- indépendant (oracle) sur 200 grilles aléatoires, graine par graine.
return function(T, H)
	local SEEDS = 200

	local OFFSETS4 = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
	local OFFSETS8 = {
		{ 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 },
		{ 1, -1 }, { 1, 1 }, { -1, 1 }, { -1, -1 },
	}

	local function keyOf(x, y)
		return x .. ":" .. y
	end

	-- BFS multi-sources : distance minimale d'une case de starts à une case de goals.
	-- Les buts hors route ne sont jamais atteints, donc jamais comptés.
	local function bfsDistance(roads, size, starts, goals, diagonals)
		local offsets = diagonals and OFFSETS8 or OFFSETS4
		local dist = {}
		local queue = {}
		local head = 1
		for _, s in ipairs(starts) do
			local k = keyOf(s[1], s[2])
			if roads[k] and dist[k] == nil then
				dist[k] = 0
				queue[#queue + 1] = s
			end
		end
		while head <= #queue do
			local cur = queue[head]
			head += 1
			local k = keyOf(cur[1], cur[2])
			if goals[k] then
				return dist[k]
			end
			for _, o in ipairs(offsets) do
				local nx, ny = cur[1] + o[1], cur[2] + o[2]
				local nk = keyOf(nx, ny)
				if nx >= 0 and ny >= 0 and nx < size and ny < size and roads[nk] and dist[nk] == nil then
					dist[nk] = dist[k] + 1
					queue[#queue + 1] = { nx, ny }
				end
			end
		end
		return nil
	end

	-- Grille aléatoire : chaque case est une route avec la probabilité density.
	local function randomGrid(size, density)
		local roads, cells = {}, {}
		for x = 0, size - 1 do
			for y = 0, size - 1 do
				if math.random() < density then
					roads[keyOf(x, y)] = true
					cells[#cells + 1] = { x, y }
				end
			end
		end
		return roads, cells
	end

	-- Vérifie qu'un chemin part du départ, finit sur un but, passe par des routes
	-- dans la grille, avec des pas adjacents et la longueur optimale.
	local function checkPath(Grid, path, roads, size, startKey, goals, diagonals, expectedLength, label)
		T.eq(path[1], startKey, label .. " starts at start")
		T.ok(goals[path[#path]], label .. " ends on a goal")
		T.eq(#path, expectedLength, label .. " length is optimal")
		local previousX, previousY
		for _, key in ipairs(path) do
			T.ok(roads[key], label .. " cell is a road " .. key)
			local x, y = Grid.parse(key)
			T.ok(x >= 0 and y >= 0 and x < size and y < size, label .. " in bounds")
			if previousX then
				local dx, dy = math.abs(x - previousX), math.abs(y - previousY)
				if diagonals then
					T.eq(math.max(dx, dy), 1, label .. " diagonal step")
				else
					T.eq(dx + dy, 1, label .. " orthogonal step")
				end
			end
			previousX, previousY = x, y
		end
	end

	local function runOracle(H_, diagonals)
		local P = H_.load("Pathfinding")
		local Grid = H_.load("Grid")
		local mode = diagonals and "diag" or "orth"
		local solved = 0
		for seed = 1, SEEDS do
			H_.seed(seed * 7919 + (diagonals and 1 or 0))
			local size = math.random(4, 14)
			local density = 0.45 + math.random() * 0.4
			local roads, cells = randomGrid(size, density)
			if #cells >= 2 then
				local startCell = cells[math.random(#cells)]
				local startKey = keyOf(startCell[1], startCell[2])

				-- Un ou deux buts sur route, plus parfois une case hors route qui doit être ignorée.
				local goals = {}
				for _ = 1, math.random(1, 2) do
					local c = cells[math.random(#cells)]
					goals[keyOf(c[1], c[2])] = true
				end
				if math.random() < 0.3 then
					local ox, oy = math.random(0, size - 1), math.random(0, size - 1)
					if not roads[keyOf(ox, oy)] then
						goals[keyOf(ox, oy)] = true
					end
				end

				local expected = bfsDistance(roads, size, { startCell }, goals, diagonals)
				local label = mode .. " seed " .. seed
				local path = P.find(roads, size, startKey, goals, diagonals)
				if expected == nil then
					T.eq(path, nil, label .. " unreachable")
				else
					solved += 1
					T.ok(path, label .. " found")
					if path then
						checkPath(Grid, path, roads, size, startKey, goals, diagonals, expected + 1, label)
					end
				end
			end
		end
		-- Garde-fou sur le jeu de données : au moins un quart des grilles doit être résoluble.
		T.ge(solved, math.floor(SEEDS / 4), mode .. " oracle exercised")
	end

	T.test("orthogonal A* matches a BFS oracle on 200 random grids", function()
		runOracle(H, false)
	end)

	T.test("diagonal A* matches a BFS oracle on 200 random grids", function()
		runOracle(H, true)
	end)

	T.test("with several goals the nearest one wins, not the first listed", function()
		local P = H.load("Pathfinding")
		local roads = {}
		for x = 0, 9 do
			roads[keyOf(x, 0)] = true
		end
		local path = P.find(roads, 18, "0:0", { ["9:0"] = true, ["3:0"] = true })
		T.eq(path[#path], "3:0")
		T.eq(#path, 4)
	end)
end
