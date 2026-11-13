-- Circulation : une voiture de retour dont la dernière case atteinte (sa sortie
-- du magasin) disparaît repart par un autre connecteur du même bâtiment, au lieu
-- de rester sur place jusqu'au délai de demande. Une voiture loin de son bâtiment
-- n'est jamais renvoyée vers les connecteurs de celui-ci.
return function(T, H)
	local function stepRun(session, seconds, dt)
		local elapsed = 0
		while elapsed < seconds and not session.over do
			session:update(dt)
			H.flush(dt)
			elapsed += dt
			if session.awaitingChoice then
				session:chooseReward(session.choice.options[1].id)
			end
		end
	end

	-- Joue jusqu'à ce que `ready(session)` soit vrai (au plus `limit` secondes).
	local function runUntil(session, limit, ready)
		local elapsed = 0
		while elapsed < limit and not session.over and not ready(session) do
			stepRun(session, 0.1, 0.1)
			elapsed += 0.1
		end
	end

	local function flatDistance(a, b)
		local dx = a.X - b.X
		local dz = a.Z - b.Z
		return math.sqrt(dx * dx + dz * dz)
	end

	-- Une maison et un magasin de même couleur, reliés par une route, puis une
	-- seconde route, sur terre, qui part d'un autre côté du magasin et rejoint le
	-- réseau : le magasin a alors deux connecteurs sur le réseau.
	local function twoConnectorStore()
		local session = H.newSession("los_angeles")
		session.budget = 400
		local house, store = H.houseAndStore(session)
		T.ok(house ~= nil and store ~= nil, "the map needs a house and a store of the same colour")
		H.connect(session, house, store)

		local Grid = H.load("Grid")
		local sides = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
		-- Une route voisine du magasin est un de ses connecteurs (la sortie déjà
		-- posée) : elle ne compte pas, sinon le second connecteur ne serait relié au
		-- réseau que par la sortie, et l'effacer le couperait du réseau.
		local function touchesRoad(x, y)
			for _, side in ipairs(sides) do
				local nx, ny = x + side[1], y + side[2]
				local nearStore = math.abs(nx - store.x) + math.abs(ny - store.y) == 1
				if session.roads[Grid.key(nx, ny)] and not nearStore then
					return true
				end
			end
			return false
		end
		-- Case libre sur terre : un pont demande un budget de ponts que la recherche
		-- ne réserve pas, et un tracé coupé laisserait un connecteur isolé.
		local function dryFree(x, y)
			local ok, kind = session:canDraw(x, y)
			return ok and kind == "road"
		end

		-- Recherche en largeur de cases libres, depuis un côté du magasin jusqu'à
		-- une case voisine d'une route existante.
		local queue, cameFrom, head = {}, {}, 1
		for _, side in ipairs(sides) do
			local x, y = store.x + side[1], store.y + side[2]
			local key = Grid.key(x, y)
			if dryFree(x, y) and cameFrom[key] == nil then
				cameFrom[key] = false
				table.insert(queue, { x, y })
			end
		end
		local drawn = nil
		while head <= #queue and not drawn do
			local cur = queue[head]
			head += 1
			local key = Grid.key(cur[1], cur[2])
			if touchesRoad(cur[1], cur[2]) then
				drawn = {}
				local node = key
				while node do
					local x, y = Grid.parse(node)
					table.insert(drawn, 1, { x, y })
					node = cameFrom[node] or nil
				end
				session:drawRoad(drawn)
			else
				for _, side in ipairs(sides) do
					local nx, ny = cur[1] + side[1], cur[2] + side[2]
					local nkey = Grid.key(nx, ny)
					if cameFrom[nkey] == nil and dryFree(nx, ny) then
						cameFrom[nkey] = key
						table.insert(queue, { nx, ny })
					end
				end
			end
		end

		local complete = drawn ~= nil
		for _, cell in ipairs(drawn or {}) do
			complete = complete and session.roads[Grid.key(cell[1], cell[2])] == true
		end
		T.ok(complete, "the second road must be drawn in full and reach the network")
		T.ge(#store.connections, 2, "the store needs two connectors")
		return session, store
	end

	-- Voiture repartie du magasin, dont la sortie est la dernière case atteinte.
	local function carHeadingBack(session)
		for _, car in ipairs(session.cars) do
			if car.state == "back" and car.lastKey then
				return car
			end
		end
		return nil
	end

	-- Voiture de retour à plus de trois cases du centre de son magasin.
	local function carFarBack(session, store)
		local Grid = H.load("Grid")
		local centre = Grid.center(session.origin, store.x, store.y, 0)
		for _, car in ipairs(session.cars) do
			if
				car.state == "back"
				and car.dest == store
				and car.lastKey
				and flatDistance(car.center, centre) > 3 * session.tile
			then
				return car
			end
		end
		return nil
	end

	T.test("a car whose exit cell is erased leaves its store by another connector", function()
		local StoreConfig = H.load("StoreConfig")
		local session, store = twoConnectorStore()
		runUntil(session, 300, function(s)
			return carHeadingBack(s) ~= nil
		end)
		local car = carHeadingBack(session)
		T.ok(car ~= nil, "a car must deliver and head back")
		if not car then
			return
		end
		local exit = car.lastKey
		T.ok(session.roads[exit], "the exit cell is a road before the erase")

		session:eraseRoads({ exit })
		session:update(0.1)
		T.ok(car.path ~= nil, "the car must find a route through the store's other connector")
		if car.path then
			for i = car.index, #car.path do
				T.ne(car.path[i], exit, "the new route never uses the erased cell")
			end
			T.ok(car.seg ~= nil, "the car has a segment to drive")
			if car.seg then
				T.le(car.seg.length, 2 * session.tile, "the car leaves from the store, it does not jump across the map")
			end
		end

		-- Elle rentre chez elle bien avant le délai de demande qui la ferait disparaître.
		runUntil(session, StoreConfig.Demand.ClaimTimeout - 2, function()
			return car.part == nil
		end)
		T.falsy(car.part, "the car got back home")
		T.eq(car.lostTime, 0, "the car never stood still waiting for a route")
	end)

	T.test("a car far from its store is never routed back to the store's connectors", function()
		local Grid = H.load("Grid")
		local session, store = twoConnectorStore()
		runUntil(session, 300, function(s)
			return carFarBack(s, store) ~= nil
		end)
		local car = carFarBack(session, store)
		T.ok(car ~= nil, "a car must be on its way back, far from the store")
		if not car then
			return
		end
		-- La dernière case atteinte de la voiture n'est plus une route : le magasin
		-- reste relié à la maison, mais la voiture, loin de lui, ne doit pas revenir
		-- se poser sur ses connecteurs.
		local gone = Grid.key(0, 0)
		T.falsy(session.roads[gone], "the test needs an empty cell")
		T.ok(session:findRoute(store, car.house, nil) ~= nil, "the store still reaches its house")
		car.lastKey = gone
		T.eq(session:findPath(car), nil, "a car far from its store must not be routed back to the store")
	end)
end
