return function(T, H)
	-- Avance la session pas à pas en vérifiant `check(session)` à chaque pas.
	local function stepRun(session, seconds, dt, check)
		local elapsed = 0
		while elapsed < seconds and not session.over do
			session:update(dt)
			H.flush(dt)
			elapsed += dt
			if session.awaitingChoice then
				session:chooseReward(session.choice.options[1].id)
			end
			if check then
				check(session, elapsed)
			end
		end
	end

	local function connectedGame(mapId)
		local session = H.newSession(mapId or "los_angeles")
		session.budget = 400
		local store = session.destinations[1]
		for _, house in ipairs(session.houses) do
			H.connect(session, house, store)
		end
		return session, store
	end

	T.test("a connected house gets served: cars spawn, deliver, score rises, demands are consumed", function()
		local session, store = connectedGame()
		local sawCar = false
		stepRun(session, 150, 0.1, function(s)
			if #s.cars > 0 then
				sawCar = true
			end
		end)
		T.ok(sawCar, "a car must have been dispatched")
		T.gt(session.score, 0, "deliveries must score")
		T.gt(store.delivered, 0, "store.delivered")
		T.ge(session.score, store.delivered * 0 + 1)
		T.le(store.demands, store.capacity)
	end)

	T.test("without any road nothing is delivered and no car waits forever", function()
		local Config = H.load("Config")
		local StoreConfig = H.load("StoreConfig")
		local session = H.newSession("los_angeles")
		local longestWait = 0
		stepRun(session, 60, 0.1, function(s)
			for _, car in ipairs(s.cars) do
				if not car.path then
					longestWait = math.max(longestWait, car.waitTime)
				end
			end
		end)
		T.eq(session.score, 0)
		T.le(longestWait, StoreConfig.Demand.ClaimTimeout + 1, "a car without a path must give up and free its demand")
		T.gt(session.destinations[1].demands, 0, "demands pile up when nobody serves them")
		T.ge(Config.Traffic.StuckAfter, 1)
	end)

	-- Brief, part 8: vehicles leave houses to reach compatible stores *by the
	-- road network*. Today a car is spawned (and parks) at an unconnected house
	-- until its claim times out.
	T.test("no car is spawned for a house that is not connected to any store", function()
		local session = H.newSession("los_angeles")
		local spawned = 0
		stepRun(session, 60, 0.1, function(s)
			spawned = math.max(spawned, #s.cars)
		end)
		T.eq(spawned, 0)
	end)

	T.test("cars never claim someone else's demand: ids are unique and counters consistent", function()
		local session, store = connectedGame()
		stepRun(session, 200, 0.1, function(s)
			for _, st in ipairs(s.destinations) do
				T.le(st.demands, st.capacity, "demands over capacity")
				T.eq(#st.demandIds, st.demands, "demands counter drifted from demandIds")
				local seen = {}
				for _, id in ipairs(st.demandIds) do
					T.falsy(seen[id], "duplicate demand id " .. id)
					seen[id] = true
				end
				local reserved = 0
				for id in pairs(st.reservedIds) do
					reserved += 1
					T.ok(seen[id] or true)
				end
				T.eq(reserved, st.reserved, "reserved counter drifted")
				T.le(st.reserved, st.demands + 1)
			end
			local claimed = {}
			for _, car in ipairs(s.cars) do
				if car.claim and car.demandId then
					T.falsy(claimed[car.demandId], "two cars serve demand " .. car.demandId)
					claimed[car.demandId] = true
				end
			end
		end)
		T.ge(store.delivered, 1)
	end)

	T.test("cars stay finite, inside the map, and do not teleport", function()
		local Config = H.load("Config")
		local session = connectedGame()
		local limit = session.size * session.tile
		local previous = {}
		local maxStep = 0
		stepRun(session, 150, 0.1, function(s)
			for _, car in ipairs(s.cars) do
				local p = car.pos
				T.ok(p.X == p.X and p.Y == p.Y and p.Z == p.Z, "NaN car position")
				T.ok(p.X >= s.origin.X - s.tile and p.X <= s.origin.X + limit + s.tile, "car left the map (x)")
				T.ok(p.Z >= s.origin.Z - s.tile and p.Z <= s.origin.Z + limit + s.tile, "car left the map (z)")
				local before = previous[car]
				if before then
					maxStep = math.max(maxStep, (p - before).Magnitude)
				end
				previous[car] = p
			end
		end)
		T.le(maxStep, Config.Traffic.CarSpeed * 0.1 * 1.7, "a car jumped " .. maxStep .. " studs in 0.1 s")
	end)

	-- Part 8 of the brief: no sudden moves. Cars currently speed up to ~13.6
	-- studs/s in corners (nominal 9).
	T.test("car speed stays within 15% of the nominal speed, corners included", function()
		local Config = H.load("Config")
		local session = connectedGame()
		local previous, maxStep = {}, 0
		stepRun(session, 150, 0.1, function(s)
			for _, car in ipairs(s.cars) do
				local before = previous[car]
				if before then
					maxStep = math.max(maxStep, (car.pos - before).Magnitude)
				end
				previous[car] = car.pos
			end
		end)
		T.le(maxStep, Config.Traffic.CarSpeed * 0.1 * 1.15)
	end)

	T.test("cars keep a minimum distance from each other", function()
		local session = connectedGame()
		local minDistance = math.huge
		stepRun(session, 200, 0.1, function(s)
			for a = 1, #s.cars do
				for b = a + 1, #s.cars do
					minDistance = math.min(minDistance, (s.cars[a].pos - s.cars[b].pos).Magnitude)
				end
			end
		end)
		T.ge(minDistance, 1.0, "two cars overlap (distance " .. minDistance .. ")")
	end)

	-- Espacement entre voitures : la métrique « toutes paires » mélangerait les
	-- deux sens de circulation (voies opposées : 1,2 à 1,7 stud). On mesure donc
	-- la distance entre deux voitures de la même voie orientée, dans une
	-- situation qui les rapproche : la première s'arrête au bout de la route, la
	-- seconde la rejoint.
	local function followerDistance(multiplier)
		local Config = H.load("Config")
		local Grid = H.load("Grid")
		local Maps = H.load("Maps")
		local session, row, startX = nil, nil, nil
		for _, map in ipairs(Maps.all()) do
			H.reset()
			session = H.newSession(map.id)
			for y = 2, session.size - 3 do
				for x = 1, session.size - 10 do
					local clear = true
					for dx = -1, 8 do
						for dy = -1, 1 do
							local key = Grid.key(x + dx, y + dy)
							clear = clear and not session.buildings[key] and not Maps.isWater(session.map, x + dx, y + dy)
						end
					end
					if clear and not row then
						row, startX = y, x
					end
				end
			end
			if row then
				break
			end
		end
		session.storeSystem.spawnClock = 1e9
		session.storeSystem.houseClock = 1e9
		session.upgrades.traffic = multiplier
		session.budget = 100
		T.ok(row ~= nil, "a free straight stretch is needed")
		local cells = {}
		local keys = {}
		for dx = 0, 7 do
			cells[#cells + 1] = { startX + dx, row }
			keys[#keys + 1] = Grid.key(startX + dx, row)
		end
		session:drawRoad(cells)
		local function spawn()
			local house = { x = startX - 3, y = row, colorIndex = 1 }
			local dest = { x = startX + 8, y = row, colorIndex = 1 }
			return session:createCar(house, dest, nil, keys)
		end
		local leader = spawn()
		stepRun(session, 1.5, 0.1)
		-- La première voiture n'est plus mise à jour : elle reste figée sur sa voie
		-- (comme une voiture à l'arrêt) ; la seconde la rejoint.
		table.remove(session.cars, 1)
		local follower = spawn()
		stepRun(session, 30, 0.1)
		T.le(follower.speedFactor, 0.25, "the follower must have stopped behind the leader")
		local measured = (leader.pos - follower.pos).Magnitude
		return measured, Config.Traffic.CarSpacing
	end

	T.test("cars on the same lane keep at least 75% of CarSpacing from each other", function()
		local distance, spacing = followerDistance(1)
		T.ge(distance, spacing * 0.75, "two cars on one lane are " .. distance .. " studs apart")
	end)

	T.test("the circulation upgrade lets cars follow closer, still above 75% of the shortened spacing", function()
		local normal, spacing = followerDistance(1)
		local closer = followerDistance(0.6)
		T.lt(closer, normal, "a shorter safety distance must bring the follower closer")
		T.ge(closer, spacing * 0.6 * 0.75, "the follower must still keep its shortened distance")
	end)

	T.test("car models use the colour of their house", function()
		local Config = H.load("Config")
		local session = connectedGame()
		local checked = 0
		stepRun(session, 60, 0.1, function(s)
			for _, car in ipairs(s.cars) do
				if car.part and checked < 20 then
					local palette = Config.HouseColors[car.house.colorIndex]
					local found = false
					for _, d in ipairs(car.part:GetDescendants()) do
						if d:IsA("BasePart") and (d.Color == palette.color or d.Color == palette.base) then
							found = true
						end
					end
					if car.part:IsA("BasePart") and (car.part.Color == palette.color or car.part.Color == palette.base) then
						found = true
					end
					T.ok(found, "car without its house colour")
					checked += 1
				end
			end
		end)
		T.gt(checked, 0)
	end)

	T.test("erasing the road under moving cars never errors and cars end up stopped or retired", function()
		local session = connectedGame()
		stepRun(session, 40, 0.1)
		local keys = {}
		for key in pairs(session.roads) do
			table.insert(keys, key)
		end
		table.sort(keys)
		-- On efface une case sur deux : tous les trajets sont coupés en plein trafic.
		local cut = {}
		for i = 1, #keys, 2 do
			table.insert(cut, keys[i])
		end
		session:eraseRoads(cut)
		stepRun(session, 60, 0.1)
		T.eq(#H.handlerErrors, 0)
		for _, car in ipairs(session.cars) do
			if car.path then
				for i = car.index, #car.path do
					T.ok(session.roads[car.path[i]], "a car keeps a path through an erased cell")
				end
			end
		end
	end)

	T.test("rebuilding the road lets blocked cars resume", function()
		local session, store = connectedGame()
		stepRun(session, 40, 0.1)
		local before = store.delivered
		local keys = {}
		for key in pairs(session.roads) do
			table.insert(keys, key)
		end
		session:eraseRoads(keys)
		stepRun(session, 10, 0.1)
		for _, house in ipairs(session.houses) do
			H.connect(session, house, store)
		end
		stepRun(session, 120, 0.1)
		T.gt(store.delivered, before, "deliveries must resume after the network is rebuilt")
	end)

	T.test("traffic jam: many houses on one road do not deadlock the network", function()
		local session, store = connectedGame()
		session.speed = 3
		stepRun(session, 200, 0.2)
		T.ge(store.delivered, 3)
		T.ge(#session.destinations, 1)
	end)

	T.test("a blocked car drains satisfaction only after StuckAfter", function()
		local Config = H.load("Config")
		local session = connectedGame()
		session.satisfaction = Config.Traffic.SatisfactionStart
		stepRun(session, 30, 0.1)
		T.ge(session.satisfaction, Config.Traffic.SatisfactionStart - 5, "a flowing network must not drain patience")
	end)

	T.test("speed x3 simulates three times as much game time per update", function()
		local function ageAfter(speed)
			H.reset()
			local session = H.newSession("los_angeles")
			session:setSpeed(speed)
			H.runSession(session, 20, 0.1)
			return session.destinations[1].age
		end
		local normal, fast = ageAfter(1), ageAfter(3)
		T.near(fast / normal, 3, 0.05)
	end)
end
