-- Logique de circulation : trajets en cache, espacement amélioré, score,
-- accessibilité, arrêt avant une intersection occupée, boucle d'attente,
-- stationnement et coût par image.
return function(T, H)
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

	-- Joue jusqu'à ce que `ready(session)` soit vrai (au plus `limit` secondes),
	-- puis résout un éventuel choix de semaine : les routes ne sont éditables
	-- qu'une fois le choix fait.
	local function runUntil(session, limit, ready)
		local elapsed = 0
		while elapsed < limit and not session.over and not ready(session) do
			stepRun(session, 0.1, 0.1)
			elapsed += 0.1
		end
		if session.awaitingChoice then
			session:chooseReward(session.choice.options[1].id)
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

	-- Voiture factice pour des scénarios sans maison : Session:createCar prend
	-- des bâtiments quelconques tant que le trajet est fourni.
	local function dummyCar(session, path, houseCell, destCell)
		local house = { x = houseCell[1], y = houseCell[2], colorIndex = 1 }
		local dest = { x = destCell[1], y = destCell[2], colorIndex = 1 }
		return session:createCar(house, dest, nil, path)
	end

	local function freeCell(session)
		local Grid = H.load("Grid")
		local Maps = H.load("Maps")
		for x = 1, session.size - 2 do
			for y = 1, session.size - 2 do
				local clear = not Maps.isWater(session.map, x, y)
				for dx = -1, 1 do
					for dy = -1, 1 do
						local key = Grid.key(x + dx, y + dy)
						clear = clear and not session.roads[key] and not session.buildings[key]
					end
				end
				if clear then
					return x, y
				end
			end
		end
		return nil
	end

	-- 1 ---------------------------------------------------------------------------

	T.test("a road batch that leaves a car's route intact does not trigger any path search", function()
		local session = connectedGame()
		runUntil(session, 200, function(s)
			return #s.cars > 1
		end)
		T.gt(#session.cars, 0, "the scenario needs cars on the road")
		local searches = 0
		local computeRoute = session.computeRoute
		session.computeRoute = function(...)
			searches += 1
			return computeRoute(...)
		end
		local x, y = freeCell(session)
		T.ok(x ~= nil, "a free cell is needed")
		session:drawRoad({ { x, y } })
		local version = session.roadVersion
		for _, car in ipairs(session.cars) do
			if car.path then
				T.eq(car.roadVersion, version, "an intact route is kept as it is")
			end
		end
		session:update(0.1)
		T.eq(searches, 0, "no A* for an unrelated road")
	end)

	T.test("erasing a cell of a car's route re-paths that car once", function()
		local session = connectedGame()
		local victim = nil
		runUntil(session, 200, function(s)
			for _, car in ipairs(s.cars) do
				if not victim and car.path and #car.path - car.index >= 3 then
					victim = car
				end
			end
			return victim ~= nil
		end)
		T.ok(victim ~= nil, "a car with a long route is needed")
		if not victim or not victim.path then
			return
		end
		local cut = victim.path[victim.index + 2]
		local oldVersion = victim.roadVersion
		session:eraseRoads({ cut })
		T.ne(victim.roadVersion, session.roadVersion, "a broken route is left stale")
		T.ne(oldVersion, session.roadVersion)
		stepRun(session, 0.2, 0.1)
		if victim.path then
			for i = victim.index, #victim.path do
				T.ok(session.roads[victim.path[i]], "the new route avoids the erased cell")
			end
		end
	end)

	-- 2 ---------------------------------------------------------------------------

	T.test("the circulation upgrade shortens the safety distance of every car", function()
		local Config = H.load("Config")
		local session = connectedGame()
		local car = nil
		stepRun(session, 40, 0.1, function(s)
			car = car or s.cars[1]
		end)
		T.ok(car ~= nil and car.seg ~= nil, "a moving car is needed")
		-- Une voiture factice à 80 % de la distance de sécurité devant la voiture.
		session.frontGap = function()
			return Config.Traffic.CarSpacing * 0.8
		end
		session.upgrades.traffic = 1
		session:updateCar(car, 0.1)
		T.ok(car.blocked, "at the normal spacing the car must hold back")
		session.upgrades.traffic = 0.5
		session:updateCar(car, 0.1)
		T.falsy(car.blocked, "with a shorter safety distance the car follows closer")
	end)

	-- 3 ---------------------------------------------------------------------------

	T.test("every delivery goes through Session:onDelivery exactly once", function()
		local session, store = connectedGame()
		local calls = 0
		local onDelivery = session.onDelivery
		session.onDelivery = function(self, house, destination)
			calls += 1
			return onDelivery(self, house, destination)
		end
		stepRun(session, 150, 0.1)
		T.gt(store.delivered, 0)
		T.eq(calls, store.delivered, "one onDelivery per consumed demand")
		T.eq(session.stats.deliveries, store.delivered, "the delivery statistic comes from onDelivery")
		T.gt(session.score, 0)
	end)

	-- 4 ---------------------------------------------------------------------------

	T.test("the delivery pulse tween belongs to the session and destroy() stops it", function()
		local session, store = connectedGame()
		session:destinationPulse(store)
		T.ok(next(session.tweens) ~= nil, "the pulse tween must be tracked")
		session:destroy()
		T.eq(next(session.tweens), nil, "no tween survives destroy()")
	end)

	-- 5 ---------------------------------------------------------------------------

	T.test("a house asks the stores package for a reachable store with one multi-goal search", function()
		local Pathfinding = H.load("Pathfinding")
		local singles, multis = 0, 0
		local find, findFromAny = Pathfinding.find, Pathfinding.findFromAny
		Pathfinding.find = function(...)
			singles += 1
			return find(...)
		end
		Pathfinding.findFromAny = function(...)
			multis += 1
			return findFromAny(...)
		end
		local session, store = connectedGame()
		local predicates, accepted = 0, 0
		local findDestination = session.findDestinationForHouse
		session.findDestinationForHouse = function(self, house, requireAvailable, isReachable)
			T.eq(type(isReachable), "function", "the third argument is the reachability test")
			predicates += 1
			if isReachable(store) then
				accepted += 1
			end
			T.falsy(isReachable({}), "an unknown store is not reachable")
			return findDestination(self, house, requireAvailable, isReachable)
		end
		stepRun(session, 120, 0.1)
		T.gt(predicates, 0, "houses must look for a destination")
		T.gt(accepted, 0, "the connected store is reachable")
		T.gt(multis, 0)
		T.eq(singles, 0, "no one-goal A* per store")
		T.gt(store.delivered, 0)
	end)

	-- 6 ---------------------------------------------------------------------------

	T.test("a car that cannot take the next intersection waits before it, never inside it", function()
		local Grid = H.load("Grid")
		local RoadConfig = H.load("RoadConfig")
		local session, store = connectedGame()
		local target = nil
		stepRun(session, 60, 0.1, function(s)
			for _, car in ipairs(s.cars) do
				if not target and car.path then
					for j = car.index + 2, #car.path do
						if s.intersections[car.path[j]] and not s.intersectionReservations[car.path[j]] then
							target = car.path[j]
							break
						end
					end
				end
			end
		end)
		T.ok(target ~= nil, "an intersection on a route is needed")
		if not target then
			return
		end
		-- Une autre voiture tient l'intersection : personne ne doit y entrer.
		local owner = { id = 0, path = {}, held = {} }
		session.intersectionReservations[target] = owner
		local halfLength = session.tile * RoadConfig.Vehicle.LengthTiles * 0.5
		local stopped = 0
		stepRun(session, 40, 0.1, function(s)
			session.intersectionReservations[target] = owner
			for _, car in ipairs(s.cars) do
				if car.heading and car.center then
					local front = car.center + car.heading * halfLength
					local x, y = Grid.cellFromWorld(s.origin, front)
					T.ne(Grid.key(x, y), target, "a car front entered a reserved intersection")
					if car.blocked then
						stopped += 1
					end
				end
			end
		end)
		T.gt(stopped, 0, "cars must queue before the intersection")
		session.intersectionReservations[target] = nil
		local before = store.delivered
		stepRun(session, 60, 0.1)
		T.gt(store.delivered, before, "traffic resumes once the intersection is free")
	end)

	-- Quatre intersections voisines en anneau, chacune avec une branche : les
	-- quatre cases sont des intersections.
	local function buildRing(session)
		local Grid = H.load("Grid")
		local x0, y0 = nil, nil
		local Maps = H.load("Maps")
		for x = 2, session.size - 4 do
			for y = 2, session.size - 4 do
				local clear = true
				for dx = -1, 2 do
					for dy = -1, 2 do
						clear = clear and not Maps.isWater(session.map, x + dx, y + dy)
							and not session.buildings[Grid.key(x + dx, y + dy)]
							and not session.roads[Grid.key(x + dx, y + dy)]
					end
				end
				if clear and not x0 then
					x0, y0 = x, y
				end
			end
		end
		T.ok(x0 ~= nil, "a free 4x4 area is needed")
		session.budget = 100
		session:drawRoad({ { x0, y0 }, { x0 + 1, y0 }, { x0 + 1, y0 + 1 }, { x0, y0 + 1 } })
		session:drawRoad({ { x0 - 1, y0 }, { x0 + 2, y0 + 1 }, { x0, y0 + 2 }, { x0 + 1, y0 - 1 } })
		local ring = {
			Grid.key(x0, y0),
			Grid.key(x0 + 1, y0),
			Grid.key(x0 + 1, y0 + 1),
			Grid.key(x0, y0 + 1),
		}
		return ring, x0, y0
	end

	-- 6 (suite) --------------------------------------------------------------------

	-- Place une voiture factice au centre de `startKey`, qu'elle tient, prête à
	-- suivre `path` (dont `startKey` est le premier nœud).
	local function placeCar(session, path, houseCell, destCell)
		local Grid = H.load("Grid")
		local car = dummyCar(session, path, houseCell, destCell)
		local x, y = Grid.parse(path[1])
		car.center = Grid.center(session.origin, x, y, 0.5)
		car.pos = car.center
		car.lastKey = path[1]
		car.index = 2
		car.held = { path[1] }
		session.intersectionReservations[path[1]] = car
		session:startSegment(car)
		return car
	end

	T.test("four cars converging on four joined junctions with crossing routes all get through", function()
		local Grid = H.load("Grid")
		local session = H.newSession("los_angeles")
		session.storeSystem.spawnClock = 1e9
		session.storeSystem.houseClock = 1e9
		local ring, x0, y0 = buildRing(session)
		for _, key in ipairs(ring) do
			T.ok(session.intersections[key], "ring cell " .. key .. " must be an intersection")
		end
		-- Les quatre branches, chacune contre sa case de l'anneau.
		local stubs = {
			Grid.key(x0 - 1, y0),
			Grid.key(x0 + 1, y0 - 1),
			Grid.key(x0 + 2, y0 + 1),
			Grid.key(x0, y0 + 2),
		}
		local cars = {}
		for i = 1, 4 do
			-- Entre par sa branche, traverse trois cases de l'anneau, sort par la
			-- branche de la case d'arrivée : les routes se croisent toutes.
			local last = (i + 1) % 4 + 1
			local path = { stubs[i], ring[i], ring[i % 4 + 1], ring[last], stubs[last] }
			cars[i] = placeCar(session, path, { x0 - 4, y0 + i }, { x0 + 9, y0 + i })
		end
		local together = 0
		stepRun(session, 25, 0.1, function(s)
			local inside = 0
			for _, key in ipairs(ring) do
				for _, car in ipairs(s.cars) do
					if car.center then
						local x, y = Grid.cellFromWorld(s.origin, car.center)
						if Grid.key(x, y) == key then
							inside += 1
						end
					end
				end
			end
			together = math.max(together, inside)
		end)
		T.eq(#H.handlerErrors, 0)
		for i, car in ipairs(cars) do
			T.ge(car.index, 5, "car " .. i .. " never crossed the ring")
			T.ok(car.pos.X == car.pos.X, "NaN position")
		end
		T.le(together, 3, "the four cars must not all be inside the ring at once")
	end)

	T.test("a head-on deadlock between two held junctions is broken and both cars pass", function()
		local session = H.newSession("los_angeles")
		session.storeSystem.spawnClock = 1e9
		session.storeSystem.houseClock = 1e9
		local ring, x0, y0 = buildRing(session)
		-- A tient ring[1] et veut ring[2] ; B tient ring[2] et veut ring[1].
		local a = placeCar(session, { ring[1], ring[2], ring[3], ring[4] }, { x0 - 4, y0 }, { x0 + 9, y0 })
		local b = placeCar(session, { ring[2], ring[1], ring[4], ring[3] }, { x0 - 4, y0 + 1 }, { x0 + 9, y0 + 1 })
		stepRun(session, 0.5, 0.1)
		T.ok(a.blocked and b.blocked, "both cars wait for each other")
		stepRun(session, 20, 0.1)
		T.eq(#H.handlerErrors, 0)
		T.ge(a.index, 4, "car A is still stuck")
		T.ge(b.index, 4, "car B is still stuck")
	end)

	-- Priorité inversée : la voiture qui suit prend la suite de cases avant celle
	-- qui la précède, puis se retrouve bloquée derrière elle. Chacune attendrait
	-- l'autre pour toujours.
	T.test("a car stopped behind another never keeps the junction its leader is waiting for", function()
		local Grid = H.load("Grid")
		local session = H.newSession("los_angeles")
		session.storeSystem.spawnClock = 1e9
		session.storeSystem.houseClock = 1e9
		local ring, x0, y0 = buildRing(session)
		session:drawRoad({ { x0 + 2, y0 + 1 }, { x0 + 3, y0 + 1 }, { x0 + 4, y0 + 1 } })
		local east1 = Grid.key(x0 + 2, y0 + 1)
		local east2 = Grid.key(x0 + 3, y0 + 1)
		T.ok(session.roads[Grid.key(x0 + 4, y0 + 1)] ~= nil, "the approach road must exist")
		-- Une autre voiture tient le carrefour : le meneur L attend au point d'arrêt.
		local owner = { id = 0, path = {}, held = {} }
		session.intersectionReservations[ring[3]] = owner
		-- Les voitures sont mises à jour de la dernière à la première : F est créée
		-- en dernier, elle passe avant L.
		local leader = placeCar(session, { east1, ring[3], ring[4], ring[1] }, { x0 + 7, y0 }, { x0 - 4, y0 + 1 })
		local follower = placeCar(session, { east2, east1, ring[3], ring[4] }, { x0 + 8, y0 }, { x0 - 4, y0 })
		-- F démarre plus près de L que la distance de sécurité : elle est déjà arrêtée derrière.
		follower.s = 1
		stepRun(session, 8, 0.1, function()
			session.intersectionReservations[ring[3]] = owner
		end)
		T.ok(leader.blocked, "the leader waits before the junction")
		T.lt(follower.index, 4, "the follower has not entered the junction")
		T.ok(session:frontGap(follower) ~= nil, "the follower is held back by the leader")
		session.intersectionReservations[ring[3]] = nil
		stepRun(session, 15, 0.1)
		T.eq(#H.handlerErrors, 0)
		T.ge(leader.index, 3, "the leader got through the junction")
		T.ge(follower.index, 3, "the follower followed it")
	end)

	-- 8 (réservation) -----------------------------------------------------------------

	T.test("giving up a route never releases the node a car is standing on", function()
		local Grid = H.load("Grid")
		local session = H.newSession("los_angeles")
		session.storeSystem.spawnClock = 1e9
		session.storeSystem.houseClock = 1e9
		local ring, x0, y0 = buildRing(session)
		local path = { ring[1], ring[2], ring[3], ring[4], ring[1] }
		local car = dummyCar(session, path, { x0 - 3, y0 }, { x0 + 9, y0 })
		local x, y = Grid.parse(ring[1])
		car.center = Grid.center(session.origin, x, y, 0.5)
		car.pos = car.center
		car.lastKey = ring[1]
		car.index = 2
		car.held = { ring[1], ring[2] }
		session.intersectionReservations[ring[1]] = car
		session.intersectionReservations[ring[2]] = car
		session:startSegment(car)
		-- Le trajet de retour n'existe plus : la maison factice n'a aucun connecteur.
		car.state = "back"
		session.roadVersion += 1
		session:replanCar(car)
		T.eq(car.path, nil, "the dummy house has no route")
		T.eq(session.intersectionReservations[ring[1]], car, "the standing cell stays reserved")
		T.falsy(session.intersectionReservations[ring[2]], "the cell ahead is given back")
	end)

	-- 7 ---------------------------------------------------------------------------

	T.test("a parked car stays inside its building cell, never over the connector cell", function()
		local Config = H.load("Config")
		local session = connectedGame()
		local checked = 0
		local half = session.tile * 0.5
		local reach = Config.Dimensions.Car.Length * session.tile * 0.5
		for _, building in ipairs(session.buildingList) do
			local base = H.load("Grid").center(session.origin, building.x, building.y, 0)
			for _, key in ipairs(building.connections or {}) do
				local spot = session:parkingSpot(building, key)
				local offset = spot - Vector3.new(base.X, spot.Y, base.Z)
				local farEnd = offset.Magnitude + reach
				T.le(farEnd, half + 1e-6, "the car sticks out of the building cell by " .. (farEnd - half) .. " studs")
				T.ge(offset.Magnitude, reach - 1e-6, "the car must not sit under the building centre")
				checked += 1
			end
		end
		T.gt(checked, 0, "buildings must be connected")
	end)

	-- 10 --------------------------------------------------------------------------

	T.test("16 cars on a 300-cell network simulate 10 s in well under 2 s of CPU", function()
		local Grid = H.load("Grid")
		local Pathfinding = H.load("Pathfinding")
		local session = H.newSession("los_angeles")
		session.storeSystem.spawnClock = 1e9
		session.storeSystem.houseClock = 1e9
		local count = 0
		for x = 0, session.size - 1 do
			for y = 0, session.size - 1 do
				if not (x % 5 == 1 and y % 5 == 1) then
					session.roads[Grid.key(x, y)] = true
					count += 1
				end
			end
		end
		T.ge(count, 300)
		session.roadVersion += 1
		session:rebuildRoadTopology()
		for i = 0, 15 do
			local far = i < 8 and 17 or 0
			local path = Pathfinding.find(session.roads, session.size, Grid.key(0, i), { [Grid.key(17, far)] = true })
			T.ok(path ~= nil and #path >= 20, "a long route is needed")
			dummyCar(session, path, { -1, i }, { 18, far })
		end
		local started = H.cpuClock()
		stepRun(session, 10, 0.1)
		T.lt(H.cpuClock() - started, 2, "traffic costs too much CPU")
		T.ge(#session.cars, 16)
	end)
end
