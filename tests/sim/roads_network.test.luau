return function(T, H)
	-- Réseau : une seule mise à jour par lot, version qui ne bouge que si le
	-- réseau change, connexions des bâtiments (côté orthogonal uniquement).

	local function countKeys(t)
		local n = 0
		for _ in pairs(t) do
			n += 1
		end
		return n
	end

	local function open(session, x, y)
		local Grid, Maps = H.load("Grid"), H.load("Maps")
		local key = Grid.key(x, y)
		return Grid.inBounds(x, y)
			and not session.buildings[key]
			and not session.roads[key]
			and not Maps.isWater(session.map, x, y)
	end

	-- Une ligne horizontale de `length` cases de terre libres, ou nil.
	local function freeRun(session, length)
		for y = 0, session.size - 1 do
			local run = {}
			for x = 0, session.size - 1 do
				if open(session, x, y) then
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

	T.test("a batch bumps roadVersion once and sends one State and one RoadState", function()
		local session = H.newSession("los_angeles")
		local run = freeRun(session, 5)
		T.ok(run, "free run of five")
		local version = session.roadVersion
		H.clearRemoteLog()
		session:drawRoad(run)
		T.eq(session.roadVersion, version + 1, "one version for the whole batch")
		T.eq(#H.sent("RoadState"), 1)
		T.eq(#H.sent("State"), 1)
	end)

	T.test("an erase batch bumps roadVersion once and sends one RoadState", function()
		local session = H.newSession("los_angeles")
		local run = freeRun(session, 6)
		T.ok(run, "free run of six")
		session:drawRoad(run)
		local keys = {}
		for index = 2, 4 do
			table.insert(keys, run[index][1] .. ":" .. run[index][2])
		end
		local version = session.roadVersion
		H.clearRemoteLog()
		session:eraseRoads(keys)
		T.eq(session.roadVersion, version + 1, "one version for the whole erase batch")
		T.eq(#H.sent("RoadState"), 1)
		T.eq(countKeys(session.roads), 3)
	end)

	T.test("a batch that changes nothing bumps nothing and sends nothing", function()
		local session = H.newSession("los_angeles")
		local run = freeRun(session, 3)
		T.ok(run, "free run of three")
		session:drawRoad(run)
		local version = session.roadVersion
		local budget = session.budget
		session.roundaboutsLeft = 0
		H.clearRemoteLog()
		session:drawRoad(run)
		session:eraseRoads({ "junk", "9:9" })
		session:placeRoundabout(run[1][1], run[1][2])
		T.eq(session.roadVersion, version)
		T.eq(session.budget, budget)
		T.eq(#H.sent("RoadState"), 0)
		T.eq(#H.sent("State"), 0)
	end)

	T.test("placing a roundabout keeps the network version and sends no road state", function()
		local session = H.newSession("los_angeles")
		local run = freeRun(session, 3)
		T.ok(run, "free run of three")
		session:drawRoad(run)
		session.roundaboutsLeft = 1
		local version = session.roadVersion
		H.clearRemoteLog()
		session:placeRoundabout(run[2][1], run[2][2])
		T.eq(countKeys(session.roundaboutParts), 1)
		T.eq(session.roadVersion, version)
		T.eq(#H.sent("RoadState"), 0)
	end)

	T.test("erasing re-renders the neighbours at once and the next frame changes nothing", function()
		local session = H.newSession("los_angeles")
		local run = freeRun(session, 3)
		T.ok(run, "free run of three")
		session:drawRoad(run)
		H.runSession(session, 0.2)
		local first, last = run[1][1] .. ":" .. run[1][2], run[3][1] .. ":" .. run[3][2]
		local before = session.roadParts[first]
		session:eraseRoads({ run[2][1] .. ":" .. run[2][2] })
		T.ok(session.roadParts[first] ~= before, "the neighbour became a dead end straight away")
		T.eq(next(session.roadDirty), nil, "nothing left to render")
		local after, afterLast = session.roadParts[first], session.roadParts[last]
		H.runSession(session, 0.1)
		T.ok(session.roadParts[first] == after and session.roadParts[last] == afterLast, "the next frame keeps the parts")
	end)

	T.test("erasing the middle of a line keeps both ends and removes only the given cells", function()
		local session = H.newSession("los_angeles")
		local run = freeRun(session, 7)
		T.ok(run, "free run of seven")
		session:drawRoad(run)
		session:eraseRoads({
			run[3][1] .. ":" .. run[3][2],
			run[4][1] .. ":" .. run[4][2],
			run[5][1] .. ":" .. run[5][2],
		})
		T.eq(countKeys(session.roads), 4)
		T.ok(session.roads[run[1][1] .. ":" .. run[1][2]], "start kept")
		T.ok(session.roads[run[7][1] .. ":" .. run[7][2]], "end kept")
		T.falsy(session.roads[run[4][1] .. ":" .. run[4][2]], "middle gone")
	end)

	T.test("a house beside a road is connected through its side, erasing it disconnects", function()
		local session = H.newSession("los_angeles")
		local house = session.houses[1]
		local Grid = H.load("Grid")
		local side = nil
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local x, y = house.x + d[1], house.y + d[2]
			if open(session, x, y) then
				side = { x, y }
				break
			end
		end
		T.ok(side, "a free side cell next to the house")
		session:drawRoad({ side })
		T.ok(house.connected, "side contact connects")
		T.eq(#house.connections, 1)
		T.eq(house.connections[1], Grid.key(side[1], side[2]))
		session:eraseRoad(Grid.key(side[1], side[2]))
		T.falsy(house.connected, "erasing the side road disconnects")
		T.eq(#house.connections, 0)
		session:drawRoad({ side })
		T.ok(house.connected, "rebuilding reconnects")
	end)

	T.test("every recorded connection is an orthogonal neighbour that is a road", function()
		local session = H.newSession("los_angeles")
		local house, store = H.houseAndStore(session)
		T.ok(house and store, "a house and a store of the same colour")
		local path = H.connect(session, house, store)
		T.ok(path, "a path exists")
		for _, building in ipairs(session.buildingList) do
			for _, key in ipairs(building.connections) do
				local x, y = H.load("Grid").parse(key)
				local distance = math.abs(x - building.x) + math.abs(y - building.y)
				T.eq(distance, 1, "connection " .. key .. " touches a side")
				T.ok(session.roads[key], "connection is a road")
			end
		end
	end)

	T.test("removing a path cell next to a store updates the store connection in the same batch", function()
		local session = H.newSession("los_angeles")
		local house, store = H.houseAndStore(session)
		local path = H.connect(session, house, store)
		T.ok(path, "a path exists")
		local storeKeys = {}
		for _, key in ipairs(store.connections) do
			table.insert(storeKeys, key)
		end
		T.ok(#storeKeys >= 1, "store has at least one connection")
		local removeAll = {}
		for _, key in ipairs(storeKeys) do
			table.insert(removeAll, key)
		end
		session:eraseRoads(removeAll)
		T.falsy(store.connected, "store lost every side road")
	end)
end
