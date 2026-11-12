-- StoreSystem sur de vraies sessions headless (toutes les cartes) : règles de
-- placement, arbres, groupes de maisons, réservations, horloge et surcharge.
return function(T, H)
	local Maps = H.load("Maps")
	local StoreConfig = H.load("StoreConfig")

	-- Vérifie les invariants de disposition. Les arbres sont lus dans le monde
	-- construit (parties « Tree » du dossier Grass), pas recalculés ici.
	local function checkLayout(session, label)
		local size = session.size
		local seenColours = {}
		for _, store in ipairs(session.destinations) do
			T.falsy(seenColours[store.colorIndex], label .. ": two stores share a colour")
			seenColours[store.colorIndex] = true
		end
		T.le(#session.destinations, StoreConfig.Spawn.MaxStores, label .. ": too many stores")
		T.le(#session.houses, StoreConfig.Houses.MaxHouses, label .. ": too many houses")

		local housesOf = {}
		for _, house in ipairs(session.houses) do
			local home = house.homeStore
			T.ok(home ~= nil, label .. ": house without a home store")
			if home then
				T.eq(house.colorIndex, home.colorIndex, label .. ": house colour differs from its store")
				local dx, dy = house.x - home.x, house.y - home.y
				local squared = dx * dx + dy * dy
				local Houses = StoreConfig.Houses
				T.ok(
					squared >= Houses.MinDistanceFromStore ^ 2 and squared <= Houses.MaxDistanceFromStore ^ 2,
					label .. ": house outside the ring of its store"
				)
				housesOf[home] = (housesOf[home] or 0) + 1
			end
		end
		for _, count in pairs(housesOf) do
			T.le(count, StoreConfig.Houses.MaxHousesPerStore, label .. ": too many houses for one store")
		end

		local trees = {}
		local origin, tile = session.origin, session.tile
		if session.world and session.world.Grass then
			for _, child in ipairs(session.world.Grass:GetChildren()) do
				if child.Name == "Tree" then
					table.insert(trees, {
						x = math.floor((child.Position.X - origin.X) / tile),
						y = math.floor((child.Position.Z - origin.Z) / tile),
					})
				end
			end
		end

		local list = session.buildingList
		for index, building in ipairs(list) do
			local inside = building.x >= 1 and building.y >= 1
				and building.x <= size - 2 and building.y <= size - 2
			T.ok(inside, label .. ": " .. building.key .. " is outside the playable area")
			T.falsy(Maps.isWater(session.map, building.x, building.y), label .. ": " .. building.key .. " on water")
			T.falsy(session.roads[building.key], label .. ": " .. building.key .. " on a road")
			for _, tree in ipairs(trees) do
				-- Un bâtiment déborde sur les cases voisines : aucun arbre dans le 3x3.
				local reach = math.max(math.abs(building.x - tree.x), math.abs(building.y - tree.y))
				T.ok(reach >= 2, label .. ": " .. building.key .. " covers a tree")
			end
			for other = index + 1, #list do
				local b = list[other]
				local gap = math.max(math.abs(building.x - b.x), math.abs(building.y - b.y))
				T.ok(gap >= 2, label .. ": " .. building.key .. " touches " .. b.key)
			end
		end
		return #trees
	end

	T.test("placement : règles respectées sur chaque carte pendant dix minutes simulées", function()
		local treesSeen = 0
		for _, map in ipairs(Maps.all()) do
			H.reset()
			local session = H.newSession(map.id)
			session.satisfaction = 1e9
			session.budget = 300
			H.runSession(session, 600, 0.25)
			treesSeen += checkLayout(session, map.id)
			T.ok(#session.destinations >= 2, map.id .. ": no second store after ten minutes")
			session:destroy()
		end
		T.ok(treesSeen > 0, "the trees were not found in any map: the test checks nothing")
	end)

	T.test("groupes : dans une vraie partie, des maisons se regroupent autour de leur magasin", function()
		local reach = StoreConfig.Houses.ClusterMaxDistance + 0.75
		local grouped, total = 0, 0
		for seed = 1, 4 do
			H.reset()
			H.seed(seed)
			local session = H.newSession("los_angeles")
			session.satisfaction = 1e9
			H.runSession(session, 300, 0.25)
			for _, store in ipairs(session.destinations) do
				for _, house in ipairs(store.houses) do
					total += 1
					for _, other in ipairs(store.houses) do
						if other ~= house then
							local dx, dy = house.x - other.x, house.y - other.y
							if math.sqrt(dx * dx + dy * dy) <= reach then
								grouped += 1
								break
							end
						end
					end
				end
			end
			session:destroy()
		end
		T.ge(grouped, 6, string.format("houses must sit next to a house of their store (%d of %d)", grouped, total))
	end)

	T.test("réservations : chaque demande réservée correspond à une voiture qui la porte", function()
		local session = H.newSession("los_angeles")
		session.budget = 500
		session.satisfaction = 1e9
		for _, house in ipairs(session.houses) do
			H.connect(session, house, session.destinations[1])
		end
		for _ = 1, 24 do
			H.runSession(session, 10, 0.1)
			for _, store in ipairs(session.destinations) do
				local carrying = 0
				for _, car in ipairs(session.cars) do
					if car.claim and car.dest == store and car.demandId then
						carrying += 1
					end
				end
				T.eq(store.reserved, carrying, "reserved demands must match the cars carrying them")
				local marked = 0
				for _ in pairs(store.reservedIds) do
					marked += 1
				end
				T.eq(marked, store.reserved, "reservedIds and the counter must agree")
				T.le(store.reserved, store.demands, "more reservations than demands")
				T.eq(store.demands, #store.demandIds, "demand counter drifted")
			end
		end
		session:destroy()
	end)

	T.test("horloge : le spawn suit le temps simulé, donc la vitesse 3 avance trois fois plus vite", function()
		local session = H.newSession("los_angeles")
		session:setSpeed(3)
		-- Quinze secondes réelles restent dans la première semaine (60 s simulées).
		H.runSession(session, 15, 0.1)
		T.near(session.elapsed, 45, 0.5, "store clock must run at game speed")
		T.falsy(session.storeSystem.elapsed, "the stores read Session's clock, they keep no private one")
		session:destroy()
	end)

	T.test("surcharge : un magasin non servi finit critique et fait baisser la satisfaction", function()
		local session = H.newSession("los_angeles")
		session.satisfaction = 1e9
		local store = session.destinations[1]
		H.runSession(session, 150, 0.1)
		T.ok(store.overloaded, "an unserved store must fill up")
		T.ok(store.critical, "the countdown must run out")
		T.lt(session.satisfaction, 1e9, "a critical store drains satisfaction")
		session:destroy()
	end)

	T.test("évolution : la limite de grands magasins tient pendant une longue partie", function()
		local session = H.newSession("los_angeles")
		session.budget = 800
		session.satisfaction = 1e9
		for _, store in ipairs(session.destinations) do
			for _, house in ipairs(session.houses) do
				if house.homeStore == store then
					H.connect(session, house, store)
				end
			end
		end
		H.runSession(session, 700, 0.25)
		local system = session.storeSystem
		T.le(system.largeCount + system.evolvingCount, StoreConfig.Evolution.MaxLargeStores)
		local large = 0
		for _, store in ipairs(session.destinations) do
			if store.storeType == "large" then
				large += 1
				T.eq(store.capacity, StoreConfig.Demand.LargeCapacity)
			end
		end
		T.eq(large, system.largeCount, "the large counter must match the stores")
		session:destroy()
	end)

	T.test("destroy : aucune réservation ne survit à la partie", function()
		local session = H.newSession("los_angeles")
		session.budget = 500
		session.satisfaction = 1e9
		for _, house in ipairs(session.houses) do
			H.connect(session, house, session.destinations[1])
		end
		H.runSession(session, 60, 0.1)
		local stores = {}
		for _, store in ipairs(session.destinations) do
			table.insert(stores, store)
		end
		session:destroy()
		T.eq(session.storeSystem, nil)
		for _, store in ipairs(stores) do
			T.eq(store.reserved, 0)
			T.eq(next(store.reservedIds), nil, "a stale reservation survived the session")
		end
	end)
end
