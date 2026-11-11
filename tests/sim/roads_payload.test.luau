return function(T, H)
	-- Le serveur ne fait pas confiance au client : toute charge malformée est
	-- refusée sans coût, sans version de réseau et sans état renvoyé.

	local NaN = 0 / 0
	local HUGE = math.huge

	local function countKeys(t)
		local n = 0
		for _ in pairs(t) do
			n += 1
		end
		return n
	end

	-- Première case libre de terre (ni bâtiment, ni route, ni eau).
	local function landCell(session)
		local Grid, Maps = H.load("Grid"), H.load("Maps")
		for x = 0, session.size - 1 do
			for y = 0, session.size - 1 do
				local key = Grid.key(x, y)
				if not session.buildings[key] and not session.roads[key] and not Maps.isWater(session.map, x, y) then
					return x, y
				end
			end
		end
		return nil
	end

	T.test("malformed cells are refused without charge or network change", function()
		local session = H.newSession("los_angeles")
		local budget = session.budget
		local version = session.roadVersion
		local sent = #H.sent("RoadState")
		session:drawRoad({
			{ "3", "4" },
			{ NaN, 2 },
			{ 2, NaN },
			{ HUGE, 1 },
			{ 1, -HUGE },
			{ {}, 1 },
			{ true, 1 },
			{ 1 },
			{},
			{ nil, 3 },
			"3:4",
			7,
			true,
			{ -1, 3 },
			{ 3, -1 },
			{ 100000, 0 },
			{ 1e300, 0 },
			{ 0, 1e300 },
		})
		T.eq(countKeys(session.roads), 0)
		T.eq(session.budget, budget)
		T.eq(session.roadVersion, version, "no network change, no new version")
		T.eq(#H.sent("RoadState"), sent, "nothing sent to the client")
		for key in pairs(session.roads) do
			T.fail("unexpected road key " .. key)
		end
	end)

	T.test("negative zero is the cell 0:y, never a separate key", function()
		local session = H.newSession("los_angeles")
		local Maps = H.load("Maps")
		local negZero = -1 * 0.0
		T.eq(1 / negZero, -HUGE, "the test value really is negative zero")
		local column = nil
		for y = 0, session.size - 1 do
			if not session.buildings["0:" .. y] and not Maps.isWater(session.map, 0, y) then
				column = y
				break
			end
		end
		T.ok(column, "a free dry cell in column 0")
		session:drawRoad({ { negZero, column } })
		T.eq(countKeys(session.roads), 1)
		T.ok(session.roads["0:" .. column], "stored under the canonical key")
		for key in pairs(session.roads) do
			T.falsy(string.find(key, "-", 1, true), "no negative key: " .. key)
		end
	end)

	T.test("fractions are floored to the cell they fall in", function()
		local session = H.newSession("los_angeles")
		local x, y = landCell(session)
		T.ok(x, "a free dry cell")
		session:drawRoad({ { x + 0.99, y + 0.01 } })
		T.ok(session.roads[x .. ":" .. y], "floored to the cell")
		T.eq(countKeys(session.roads), 1)
	end)

	T.test("a batch above MaxCellsPerRequest is refused whole, the limit itself is accepted", function()
		local RoadConfig = H.load("RoadConfig")
		local max = RoadConfig.Input.MaxCellsPerRequest
		local session = H.newSession("los_angeles")
		local x, y = landCell(session)
		T.ok(x, "a free dry cell")
		local tooMany = {}
		for i = 1, max + 1 do
			tooMany[i] = { x, y }
		end
		session:drawRoad(tooMany)
		T.eq(countKeys(session.roads), 0, "oversized batch refused")
		local exact = {}
		for i = 1, max do
			exact[i] = { x, y }
		end
		session:drawRoad(exact)
		T.eq(countKeys(session.roads), 1, "a batch of exactly the limit is processed")
	end)

	T.test("an oversized erase batch is refused whole", function()
		local RoadConfig = H.load("RoadConfig")
		local max = RoadConfig.Input.MaxCellsPerRequest
		local session = H.newSession("los_angeles")
		local x, y = landCell(session)
		session:drawRoad({ { x, y } })
		local keys = {}
		for i = 1, max + 1 do
			keys[i] = x .. ":" .. y
		end
		session:eraseRoads(keys)
		T.eq(countKeys(session.roads), 1, "road kept: the batch was refused")
	end)

	T.test("placeRoundabout ignores non-number coordinates and NaN", function()
		local session = H.newSession("los_angeles")
		local x, y = landCell(session)
		session:drawRoad({ { x, y } })
		session.roundaboutsLeft = 3
		session:placeRoundabout("x", "y")
		session:placeRoundabout(NaN, y)
		session:placeRoundabout(x, HUGE)
		session:placeRoundabout(nil, nil)
		session:placeRoundabout({}, 1)
		T.eq(session.roundaboutsLeft, 3, "no roundabout placed")
		T.eq(countKeys(session.roundaboutParts), 0)
	end)

	T.test("eraseRoad and eraseRoads refuse keys that are not canonical road keys", function()
		local session = H.newSession("los_angeles")
		local x, y = landCell(session)
		session:drawRoad({ { x, y } })
		local budget = session.budget
		T.falsy(session:eraseRoad(x .. ":" .. y .. " "))
		T.falsy(session:eraseRoad("0" .. x .. ":" .. y))
		T.falsy(session:eraseRoad(nil))
		T.falsy(session:eraseRoad(42))
		session:eraseRoads({ NaN, HUGE, {}, true })
		T.eq(countKeys(session.roads), 1, "the road is still there")
		T.eq(session.budget, budget)
	end)

	T.test("remote payloads are checked by the server before reaching the session", function()
		H.runScript("Bootstrap")
		H.asClient()
		H.fireServer("StartGame", "los_angeles")
		H.advance(0.5)
		local budget = H.lastSent("State").budget
		local roadStates = #H.sent("RoadState")
		H.fireServer("DrawRoad", { { "a", "b" }, { NaN, 1 }, { HUGE, 2 }, 9 })
		H.fireServer("DrawRoad", "not a table")
		H.fireServer("DrawRoad", nil)
		H.fireServer("EraseRoad", 12)
		H.fireServer("EraseRoads", "x")
		H.fireServer("PlaceRoundabout", NaN, "y")
		local huge = {}
		for i = 1, 600 do
			huge[i] = { 0, 0 }
		end
		H.fireServer("DrawRoad", huge)
		H.advance(0.2)
		T.eq(H.lastSent("State").budget, budget, "no budget spent")
		T.eq(#H.sent("RoadState"), roadStates, "no road state change was sent")
	end)
end
