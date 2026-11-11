return function(T, H)
	local function countKeys(t)
		local n = 0
		for _ in pairs(t) do
			n += 1
		end
		return n
	end

	local function freeLine(session, length)
		-- Ligne horizontale de cases libres (ni bâtiment ni eau).
		local Maps, Grid = H.load("Maps"), H.load("Grid")
		for y = 0, session.size - 1 do
			local run = {}
			for x = 0, session.size - 1 do
				if not session.buildings[Grid.key(x, y)] and not Maps.isWater(session.map, x, y) then
					table.insert(run, { x, y })
					if #run == length then
						return run
					end
				else
					run = {}
				end
			end
		end
		return nil
	end

	local function waterCell(session)
		local Maps = H.load("Maps")
		for x = 0, session.size - 1 do
			for y = 0, session.size - 1 do
				if Maps.isWater(session.map, x, y) then
					return { x, y }
				end
			end
		end
		return nil
	end

	T.test("drawRoad consumes one road piece per new cell", function()
		local session = H.newSession("los_angeles")
		local start = session.budget
		local cells = freeLine(session, 5)
		session:drawRoad(cells)
		T.eq(countKeys(session.roads), 5)
		T.eq(session.budget, start - 5)
		local state = H.lastSent("State")
		T.eq(state.budget, start - 5)
		T.eq(state.roadsBuilt, 5)
	end)

	T.test("drawing the same cells twice charges nothing the second time", function()
		local session = H.newSession("los_angeles")
		local cells = freeLine(session, 4)
		session:drawRoad(cells)
		local budget = session.budget
		session:drawRoad(cells)
		T.eq(session.budget, budget)
		T.eq(countKeys(session.roads), 4)
	end)

	T.test("buildings, out-of-map cells and junk are refused without charge", function()
		local session = H.newSession("los_angeles")
		local budget = session.budget
		local house = session.houses[1]
		session:drawRoad({ { house.x, house.y }, { -1, 0 }, { 0, -1 }, { 99, 99 }, { "a", "b" }, "junk", { nil, 3 }, 7 })
		T.eq(countKeys(session.roads), 0)
		T.eq(session.budget, budget)
		session:drawRoad(nil)
		session:drawRoad("x")
		session:drawRoad(12)
		T.eq(countKeys(session.roads), 0)
	end)

	T.test("fractional cell coordinates are floored (server validates client input)", function()
		local session = H.newSession("los_angeles")
		local cells = freeLine(session, 1)
		session:drawRoad({ { cells[1][1] + 0.9, cells[1][2] + 0.4 } })
		T.ok(session.roads[cells[1][1] .. ":" .. cells[1][2]])
	end)

	T.test("the budget caps construction", function()
		local session = H.newSession("los_angeles")
		session.budget = 3
		session:drawRoad(freeLine(session, 6))
		T.eq(countKeys(session.roads), 3)
		T.eq(session.budget, 0)
		session:drawRoad(freeLine(session, 8))
		T.eq(countKeys(session.roads), 3, "no road without a budget")
	end)

	T.test("water needs a bridge: refused without one, charged a bridge + a piece with one", function()
		local session = H.newSession("los_angeles")
		local cell = waterCell(session)
		T.ok(cell, "map has water")
		session.bridgesLeft = 0
		local budget = session.budget
		session:drawRoad({ cell })
		T.eq(countKeys(session.roads), 0)
		T.eq(session.budget, budget)
		session.bridgesLeft = 1
		session:drawRoad({ cell })
		T.eq(countKeys(session.roads), 1)
		T.eq(session.bridgesLeft, 0)
		T.eq(session.budget, budget - 1)
		T.ok(session.bridges[cell[1] .. ":" .. cell[2]])
	end)

	T.test("eraseRoad refunds the piece (and the bridge) and removes the visuals", function()
		local session = H.newSession("los_angeles")
		H.runSession(session, 1)
		local baseline = H.count(session.world.folder)
		local cell = waterCell(session)
		local line = freeLine(session, 3)
		session.bridgesLeft = 1
		session:drawRoad({ cell })
		session:drawRoad(line)
		H.runSession(session, 1)
		local budget = session.budget
		T.ok(session:eraseRoad(cell[1] .. ":" .. cell[2]))
		T.eq(session.budget, budget + 1)
		T.eq(session.bridgesLeft, 1)
		T.falsy(session:eraseRoad(cell[1] .. ":" .. cell[2]), "erasing twice does nothing")
		session:eraseRoads({ line[1][1] .. ":" .. line[1][2], line[2][1] .. ":" .. line[2][2], line[3][1] .. ":" .. line[3][2], "junk", 5 })
		T.eq(countKeys(session.roads), 0)
		H.runSession(session, 1)
		T.eq(H.count(session.world.folder), baseline, "erasing every road must remove every road part")
		T.eq(session.budget, budget + 4)
	end)

	T.test("erasing never refunds beyond MaxBudget", function()
		local Config = H.load("Config")
		local session = H.newSession("los_angeles")
		local cells = freeLine(session, 2)
		session:drawRoad(cells)
		session.budget = Config.Roads.MaxBudget
		session:eraseRoads({ cells[1][1] .. ":" .. cells[1][2] })
		T.eq(session.budget, Config.Roads.MaxBudget)
	end)

	T.test("roads can be built while the player has paused, not while a reward choice is open", function()
		local session = H.newSession("los_angeles")
		session:setPaused(true)
		local cells = freeLine(session, 2)
		session:drawRoad(cells)
		T.eq(countKeys(session.roads), 2)
		session:setPaused(false)
		session:offerWeekChoice()
		session:drawRoad(freeLine(session, 4))
		T.eq(countKeys(session.roads), 2, "no construction during the choice")
		T.falsy(session:eraseRoad(cells[1][1] .. ":" .. cells[1][2]))
	end)

	T.test("a road touching a house side connects it; erasing it disconnects again", function()
		local session = H.newSession("los_angeles")
		local house, store = H.houseAndStore(session)
		T.falsy(house.connected)
		local path = H.connect(session, house, store)
		T.ok(path, "a path exists between the starting buildings")
		T.ok(house.connected, "house connected")
		T.ok(store.connected, "store connected")
		local keys = {}
		for _, c in ipairs(path) do
			table.insert(keys, c[1] .. ":" .. c[2])
		end
		session:eraseRoads(keys)
		T.falsy(house.connected)
		T.falsy(store.connected)
	end)

	T.test("a diagonal-only touch does not connect a building (orthogonal network)", function()
		local RoadConfig = H.load("RoadConfig")
		T.skipIf(RoadConfig.AllowDiagonals or RoadConfig.BuildingConnection ~= "orthogonal", "diagonal connections enabled")
		local session = H.newSession("los_angeles")
		local house = session.houses[1]
		local Maps, Grid = H.load("Maps"), H.load("Grid")
		for _, d in ipairs({ { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
			local x, y = house.x + d[1], house.y + d[2]
			local free = Grid.inBounds(x, y) and not session.buildings[Grid.key(x, y)] and not Maps.isWater(session.map, x, y)
			local sideFree = true
			for _, n in ipairs({ { d[1], 0 }, { 0, d[2] } }) do
				if session.roads[Grid.key(house.x + n[1], house.y + n[2])] then
					sideFree = false
				end
			end
			if free and sideFree then
				session:drawRoad({ { x, y } })
				T.falsy(house.connected, "diagonal contact must not connect")
				return
			end
		end
		T.skip("no free diagonal cell around the first house")
	end)

	T.test("roundabout: needs the tool, sits on a road, is refunded when erased", function()
		local session = H.newSession("los_angeles")
		local cells = freeLine(session, 3)
		session:drawRoad(cells)
		local mid = cells[2]
		session.roundaboutsLeft = 0
		session:placeRoundabout(mid[1], mid[2])
		T.eq(session.roundaboutsLeft, 0)
		T.eq(countKeys(session.roundaboutParts), 0)
		session.roundaboutsLeft = 1
		session:placeRoundabout(mid[1], mid[2])
		T.eq(session.roundaboutsLeft, 0)
		T.eq(countKeys(session.roundaboutParts), 1)
		session:eraseRoad(mid[1] .. ":" .. mid[2])
		T.eq(session.roundaboutsLeft, 1)
		T.eq(countKeys(session.roundaboutParts), 0)
		for x = 0, session.size - 1 do
			if not session.roads[x .. ":" .. 5] then
				session:placeRoundabout(x, 5)
				break
			end
		end
		T.eq(session.roundaboutsLeft, 1, "no roundabout without a road")
	end)

	T.test("RoadState tells the client about roads, bridges and buildings after each change", function()
		local session = H.newSession("los_angeles")
		session.bridgesLeft = 1
		local water = waterCell(session)
		session:drawRoad({ water })
		session:drawRoad(freeLine(session, 3))
		local road = H.lastSent("RoadState")
		T.eq(#road.roads, 4)
		T.eq(#road.bridges, 1)
		T.eq(road.budget, session.budget)
		T.ge(road.roadVersion, 1)
		T.eq(road.count, 4)
	end)

	T.test("a long drag far from any building keeps the world cheap (parts per road cell)", function()
		local session = H.newSession("los_angeles")
		session.budget = 100
		H.runSession(session, 1)
		local before = H.count(session.world.folder, "BasePart")
		local line = freeLine(session, 8)
		session:drawRoad(line)
		H.runSession(session, 1)
		local perCell = (H.count(session.world.folder, "BasePart") - before) / #line
		T.le(perCell, 16, "road visuals use too many parts per cell: " .. perCell)
	end)

	-- Part 16 of the brief: keep road models light. One renderer driven by
	-- RoadGeometry: a straight cell is 2 parts, a turn 6, never more than 8.
	T.test("road visuals use at most 8 parts per road cell (straight line: 2)", function()
		local session = H.newSession("los_angeles")
		session.budget = 100
		H.runSession(session, 1)
		local before = H.count(session.world.folder, "BasePart")
		local line = freeLine(session, 8)
		session:drawRoad(line)
		H.runSession(session, 1)
		T.le((H.count(session.world.folder, "BasePart") - before) / #line, 8)
		T.le(H.count(session.world.Roads, "BasePart") / #line, 4, "edge + body, plus the two end caps")
	end)

	T.test("drawing and erasing in a loop does not grow the world (no leaked parts)", function()
		local session = H.newSession("los_angeles")
		session.budget = 100
		local line = freeLine(session, 6)
		local keys = {}
		for _, c in ipairs(line) do
			table.insert(keys, c[1] .. ":" .. c[2])
		end
		session:drawRoad(line)
		session:eraseRoads(keys)
		H.runSession(session, 1)
		local baseline = H.count(session.world.folder)
		for _ = 1, 6 do
			session:drawRoad(line)
			H.runSession(session, 0.5)
			session:eraseRoads(keys)
			H.runSession(session, 0.5)
		end
		T.eq(H.count(session.world.folder), baseline)
	end)
end
