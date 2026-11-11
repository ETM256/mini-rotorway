return function(T, H)
	-- Partie 6.4 du cahier des charges : les rivières sont de vrais obstacles.
	-- Une carte « à rivière » est coupée en deux régions de terre ; la zone de
	-- départ (le centre) en garde la majorité, et l'autre rive se rejoint par un
	-- pont, c'est-à-dire en traversant au plus deux cases d'eau.

	local MIN_LAND_SHARE = 0.65
	local MIN_START_SHARE = 0.55
	local MAX_BRIDGE_CELLS = 2
	local MIN_RIVER_MAPS = 4
	local MIN_FAR_SHARE = 0.15
	local START_AREA_CELLS = 4

	local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

	-- Régions de terre (voisins par côté, comme les routes), région de départ
	-- et coût minimal, en cases d'eau traversées, pour atteindre chaque case de terre.
	local function analyse(map, n)
		local Maps = H.load("Maps")
		local function index(x, y)
			return y * n + x
		end
		local land = {}
		local landCount = 0
		for y = 0, n - 1 do
			for x = 0, n - 1 do
				local isLand = not Maps.isWater(map, x, y)
				land[index(x, y)] = isLand
				if isLand then
					landCount += 1
				end
			end
		end

		local regionOf = {}
		local regions = 0
		for y = 0, n - 1 do
			for x = 0, n - 1 do
				if land[index(x, y)] and not regionOf[index(x, y)] then
					regions += 1
					local queue = { { x, y } }
					regionOf[index(x, y)] = regions
					local head = 1
					while head <= #queue do
						local cx, cy = queue[head][1], queue[head][2]
						head += 1
						for _, d in ipairs(NEIGHBOURS) do
							local nx, ny = cx + d[1], cy + d[2]
							if nx >= 0 and ny >= 0 and nx < n and ny < n and land[index(nx, ny)] and not regionOf[index(nx, ny)] then
								regionOf[index(nx, ny)] = regions
								table.insert(queue, { nx, ny })
							end
						end
					end
				end
			end
		end

		local first = math.floor((n - START_AREA_CELLS) / 2)
		local centreLand = true
		local startRegions = {}
		local cost = {}
		for y = 0, n - 1 do
			for x = 0, n - 1 do
				cost[index(x, y)] = math.huge
			end
		end
		for y = first, first + START_AREA_CELLS - 1 do
			for x = first, first + START_AREA_CELLS - 1 do
				if land[index(x, y)] then
					startRegions[regionOf[index(x, y)]] = true
					cost[index(x, y)] = 0
				else
					centreLand = false
				end
			end
		end

		-- Relaxations répétées jusqu'à stabilité : la grille est petite.
		local changed = true
		while changed do
			changed = false
			for y = 0, n - 1 do
				for x = 0, n - 1 do
					local here = cost[index(x, y)]
					if here < math.huge then
						for _, d in ipairs(NEIGHBOURS) do
							local nx, ny = x + d[1], y + d[2]
							if nx >= 0 and ny >= 0 and nx < n and ny < n then
								local step = land[index(nx, ny)] and 0 or 1
								if here + step < cost[index(nx, ny)] then
									cost[index(nx, ny)] = here + step
									changed = true
								end
							end
						end
					end
				end
			end
		end

		local startCount, farCount, maxBridge = 0, 0, 0
		for y = 0, n - 1 do
			for x = 0, n - 1 do
				if land[index(x, y)] then
					if startRegions[regionOf[index(x, y)]] then
						startCount += 1
					else
						farCount += 1
						maxBridge = math.max(maxBridge, cost[index(x, y)])
					end
				end
			end
		end

		return {
			landShare = landCount / (n * n),
			startShare = landCount > 0 and startCount / landCount or 0,
			farShare = landCount > 0 and farCount / landCount or 0,
			regions = regions,
			maxBridge = maxBridge,
			centreLand = centreLand,
		}
	end

	T.test("every map keeps at least 65% land and a land centre for the start", function()
		local n = H.load("Config").Grid.Size
		for _, map in ipairs(H.load("Maps").all()) do
			local result = analyse(map, n)
			T.ge(result.landShare, MIN_LAND_SHARE, map.id .. ": land share")
			T.ok(result.centreLand, map.id .. ": the start area must be land")
		end
	end)

	T.test("the start area holds at least 55% of the land on every map", function()
		local n = H.load("Config").Grid.Size
		for _, map in ipairs(H.load("Maps").all()) do
			local result = analyse(map, n)
			T.ge(result.startShare, MIN_START_SHARE, map.id .. ": start region share")
		end
	end)

	T.test("every land cell is reachable from the start with at most two water cells", function()
		local n = H.load("Config").Grid.Size
		for _, map in ipairs(H.load("Maps").all()) do
			local result = analyse(map, n)
			T.le(result.maxBridge, MAX_BRIDGE_CELLS, map.id .. ": the far bank needs a bridge over too much water")
		end
	end)

	T.test("at least four maps are cut in two by a river, with a real far bank", function()
		local n = H.load("Config").Grid.Size
		local split = 0
		for _, map in ipairs(H.load("Maps").all()) do
			local result = analyse(map, n)
			if result.regions >= 2 then
				split += 1
				T.ge(result.farShare, MIN_FAR_SHARE, map.id .. ": far bank is too small to matter")
				T.ge(result.maxBridge, 1, map.id .. ": a split map must need a bridge")
			end
		end
		T.ge(split, MIN_RIVER_MAPS, "rivers must separate the land on enough maps")
	end)
end
