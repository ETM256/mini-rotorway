-- Logique de StoreSystem sur une fausse Session (aucun objet Roblox) :
-- intervalles lissés, cycle de vie des demandes, surcharge, évolution,
-- payload client et source d'aléa injectable.
return function(T, H)
	local StoreConfig = H.load("StoreConfig")
	local StoreSystem = H.load("StoreSystem")

	-- Session minimale : même interface que Session pour les appels utilisés.
	local function fakeSession(opts)
		local session = {
			size = 18,
			map = { id = "fake", grassShapes = {} },
			destinations = {},
			houses = {},
			buildingList = {},
			buildings = {},
			stats = {},
			replaced = 0,
			random = opts and opts.random,
		}
		function session:isFreeCell(x, y)
			return x >= 0 and y >= 0 and x < self.size and y < self.size
				and not self.buildings[x .. ":" .. y]
		end
		function session:buildableNeighborCount(x, y)
			local count = 0
			for dx = -1, 1 do
				for dy = -1, 1 do
					local nx, ny = x + dx, y + dy
					if (dx ~= 0 or dy ~= 0) and self:isFreeCell(nx, ny) then
						count += 1
					end
				end
			end
			return count
		end
		function session:createBuilding(kind, x, y, colorIndex, storeType)
			local building = {
				id = #self.buildingList + 1,
				kind = kind,
				x = x,
				y = y,
				colorIndex = colorIndex,
				storeType = storeType,
			}
			self.buildings[x .. ":" .. y] = building
			table.insert(self.buildingList, building)
			table.insert(kind == "house" and self.houses or self.destinations, building)
			return building
		end
		function session:replaceStoreModel()
			self.replaced += 1
		end
		function session:recordStat(name, amount)
			self.stats[name] = (self.stats[name] or 0) + amount
		end
		return session
	end

	local function newSystem(opts)
		local session = fakeSession(opts)
		local system = StoreSystem.new(session)
		system:seed()
		return system, session
	end

	-- Générateur déterministe (Park-Miller) avec la même interface que math.random.
	local function seededRandom(seed)
		local state = seed
		local calls = 0
		local rng = { calls = function() return calls end }
		function rng.random(a, b)
			calls += 1
			state = (state * 16807) % 2147483647
			local u = state / 2147483647
			if a == nil then
				return u
			end
			return math.floor(a + u * (b - a + 1))
		end
		return rng
	end

	T.test("spawnIntervalRange: monotone, continue et sans saut aux paliers", function()
		local step = 0.5
		local previousMin, previousMax = StoreSystem.spawnIntervalRange(0)
		for t = step, 1500, step do
			local low, high = StoreSystem.spawnIntervalRange(t)
			T.le(low, previousMin + 1e-9, "min interval must not relax at " .. t)
			T.le(high, previousMax + 1e-9, "max interval must not relax at " .. t)
			-- La pente maximale est d'environ 0,14 par seconde : pas de saut.
			T.le(math.abs(low - previousMin), 0.2 * step + 1e-9, "min jumps at " .. t)
			T.le(math.abs(high - previousMax), 0.2 * step + 1e-9, "max jumps at " .. t)
			previousMin, previousMax = low, high
		end
	end)

	T.test("spawnIntervalRange: part du premier palier, atteint chaque palier à son début", function()
		local Tiers = StoreConfig.Spawn.Tiers
		local low, high = StoreSystem.spawnIntervalRange(0)
		T.near(low, Tiers[1].minInterval, 1e-9)
		T.near(high, Tiers[1].maxInterval, 1e-9)
		for index = 2, #Tiers do
			local start = Tiers[index - 1].untilTime
			local atStart = { StoreSystem.spawnIntervalRange(start) }
			T.near(atStart[1], Tiers[index].minInterval, 1e-9, "tier " .. index .. " min at its start")
			T.near(atStart[2], Tiers[index].maxInterval, 1e-9, "tier " .. index .. " max at its start")
		end
		local last = Tiers[#Tiers]
		local far = { StoreSystem.spawnIntervalRange(1e6) }
		T.near(far[1], last.minInterval, 1e-9, "last tier stays constant")
		T.near(far[2], last.maxInterval, 1e-9, "last tier stays constant")
	end)

	T.test("demandRampFactor: 1 au départ, RampMinMultiplier à la fin, jamais croissant", function()
		local Demand = StoreConfig.Demand
		T.near(StoreSystem.demandRampFactor(0), 1, 1e-9)
		T.near(StoreSystem.demandRampFactor(Demand.RampDuration), Demand.RampMinMultiplier, 1e-9)
		T.near(StoreSystem.demandRampFactor(Demand.RampDuration * 3), Demand.RampMinMultiplier, 1e-9)
		local previous = 1
		for t = 0, Demand.RampDuration * 2, 1 do
			local factor = StoreSystem.demandRampFactor(t)
			T.le(factor, previous + 1e-9)
			T.ge(factor, Demand.RampMinMultiplier - 1e-9)
			previous = factor
		end
	end)

	T.test("seed: un magasin, des maisons de sa couleur, statistiques comptées", function()
		local system, session = newSystem()
		T.eq(#session.destinations, StoreConfig.Spawn.StartStores)
		local store = session.destinations[1]
		T.eq(#store.houses, StoreConfig.Houses.StartHouses, "initial houses")
		for _, house in ipairs(store.houses) do
			T.eq(house.colorIndex, store.colorIndex, "house colour follows its store")
			T.eq(house.homeStore, store)
		end
		T.eq(session.stats.storesSpawned, StoreConfig.Spawn.StartStores)
		T.eq(session.stats.housesSpawned, StoreConfig.Houses.StartHouses)
		T.ok(system.spawnClock > 0, "next store is scheduled")
	end)

	T.test("cycle de vie d'une demande : ajout, réservation, libération, livraison", function()
		local system, session = newSystem()
		local store = session.destinations[1]
		store.demandClock = 1e9
		T.ok(system:addDemand(store))
		T.eq(store.demands, 1)
		T.eq(session.stats.demandsCreated, 1)

		local id = system:claimDemand(store)
		T.ok(id ~= nil, "a free demand can be claimed")
		T.eq(store.reserved, 1)
		T.falsy(system:claimDemand(store), "a claimed demand cannot be claimed twice")

		local house = { x = store.x, y = store.y, colorIndex = store.colorIndex }
		T.falsy(system:findDestination(house, true), "a fully reserved store offers nothing")
		T.eq(system:findDestination(house, false), store, "the store is still the target when not requiring availability")

		T.ok(system:releaseClaim(store, id), "release gives the demand back")
		T.eq(store.reserved, 0)
		T.eq(system:findDestination(house, true), store)
		T.eq(system:claimDemand(store), id, "the released demand is claimable again")

		T.ok(system:consumeDemand(store, id), "delivery consumes the demand")
		T.eq(store.demands, 0)
		T.eq(store.reserved, 0, "delivery clears the reservation")
		T.eq(store.delivered, 1)
		T.eq(session.stats.demandsServed, 1)
		T.falsy(system:consumeDemand(store, id), "a demand cannot be served twice")
		T.falsy(system:releaseClaim(store, id), "a missing claim releases nothing")
	end)

	T.test("destroy libère toutes les réservations", function()
		local system, session = newSystem()
		local store = session.destinations[1]
		store.demandClock = 1e9
		system:addDemand(store)
		system:claimDemand(store)
		T.eq(store.reserved, 1)
		system:destroy()
		T.eq(store.reserved, 0)
		T.eq(next(store.reservedIds), nil, "no stale reservation survives the session")
		T.eq(#system.stores, 0)
	end)

	T.test("surcharge : compte à rebours, critique, drain, remise à zéro à la livraison", function()
		local system, session = newSystem()
		local store = session.destinations[1]
		store.demandClock = 1e9
		while store.demands < store.capacity do
			system:addDemand(store)
		end
		T.ok(store.overloaded, "a full store is overloaded")
		T.near(store.overloadClock, StoreConfig.Demand.OverloadGrace, 1e-9)

		system:updateStore(store, StoreConfig.Demand.OverloadGrace / 2)
		T.falsy(store.critical, "not critical before the grace period ends")
		T.near(store.overloadClock, StoreConfig.Demand.OverloadGrace / 2, 1e-9)

		system:updateStore(store, StoreConfig.Demand.OverloadGrace)
		T.ok(store.critical, "critical once the countdown reaches zero")
		T.near(system:getOverloadDrain(), StoreConfig.Demand.OverloadDrainPerSecond, 1e-9)

		local id = store.demandIds[1]
		T.ok(system:consumeDemand(store, id))
		T.falsy(store.overloaded, "a delivery ends the overload")
		T.falsy(store.critical)
		T.near(store.overloadClock, StoreConfig.Demand.OverloadGrace, 1e-9, "countdown is reset")
		T.eq(system:getOverloadDrain(), 0)
	end)

	T.test("évolution : préconditions, limite de grands magasins avec les évolutions en cours", function()
		local Evolution = StoreConfig.Evolution
		local system, session = newSystem()
		system:spawnStore(true)
		local a, b = session.destinations[1], session.destinations[2]
		T.ok(b, "a second store exists")

		a.age, a.delivered = Evolution.MinAge - 1, Evolution.MinDeliveries
		T.falsy(system:canEvolve(a), "too young to evolve")
		a.age = Evolution.MinAge
		a.delivered = Evolution.MinDeliveries - 1
		T.falsy(system:canEvolve(a), "not enough deliveries")
		a.delivered = Evolution.MinDeliveries
		T.ok(system:canEvolve(a))

		system:beginEvolution(a)
		T.ok(a.evolving)
		T.eq(system.evolvingCount, 1)
		T.eq(session.replaced, 1, "the model is replaced once")
		system:beginEvolution(a)
		T.eq(session.replaced, 1, "an evolution cannot start twice")

		system.largeCount = Evolution.MaxLargeStores - 1
		b.age, b.delivered = Evolution.MinAge, Evolution.MinDeliveries
		T.falsy(system:canEvolve(b), "the cap counts evolutions already in progress")

		system:updateStore(a, Evolution.AnimationDuration + 0.01)
		T.falsy(a.evolving)
		T.eq(a.storeType, "large")
		T.eq(a.capacity, StoreConfig.Demand.LargeCapacity)
		T.eq(system.evolvingCount, 0)
		T.eq(system.largeCount, Evolution.MaxLargeStores)
	end)

	T.test("snapshot: payload stable et tolérant aux champs absents", function()
		local system, session = newSystem()
		local store = session.destinations[1]
		store.demandClock = 1e9
		system:addDemand(store)
		system:addDemand(store)
		local snapshot = system:snapshot()
		T.eq(#snapshot.stores, #session.destinations)
		local entry = snapshot.stores[1]
		T.eq(entry.id, store.id)
		T.eq(entry.demands, 2)
		T.eq(#entry.demandIds, 2)
		T.eq(entry.capacity, StoreConfig.Demand.SmallCapacity)
		T.eq(type(entry.overloaded), "boolean")
		T.eq(entry.storeType, "small")

		entry.demandIds[1] = "changed"
		T.ok(store.demandIds[1] ~= "changed", "the snapshot is a copy")

		store.demandIds = nil
		store.overloadClock = nil
		T.noThrow(function()
			local safe = system:snapshot()
			T.eq(safe.stores[1].demands, 0)
			T.eq(safe.stores[1].overloadClock, 0)
		end)
	end)

	T.test("source d'aléa injectable : utilisée à la place de math.random, résultats reproductibles", function()
		local function layout(seed)
			local rng = seededRandom(seed)
			local system, session = newSystem({ random = rng })
			for _ = 1, 20 do
				system:update(1)
			end
			local positions = {}
			for _, building in ipairs(session.buildingList) do
				table.insert(positions, building.x .. ":" .. building.y)
			end
			return table.concat(positions, " "), rng.calls()
		end
		local first, calls = layout(42)
		local second = layout(42)
		T.ok(calls > 0, "the injected source is used")
		T.eq(first, second, "same seed, same city")
		T.ok(first ~= layout(43), "another seed gives another city")
	end)

	T.test("interdit une case en contact (côté ou coin) avec un bâtiment", function()
		-- Sans seed : seul le bâtiment posé à la main compte pour l'espacement.
		local session = fakeSession()
		local system = StoreSystem.new(session)
		session:createBuilding("house", 5, 5, 1)
		T.falsy(system:isHouseSpotValid(6, 5), "edge contact")
		T.falsy(system:isHouseSpotValid(6, 6), "corner contact")
		T.falsy(system:isHouseSpotValid(5, 7), "two cells away in a line")
		T.ok(system:isHouseSpotValid(5, 8), "three cells away is allowed")
		T.falsy(system:isStoreSpotValid(4, 4), "stores also keep their distance")
	end)

	T.test("aucune case hors de la carte ou sans voisin constructible", function()
		local system, session = newSystem()
		T.falsy(system:isHouseSpotValid(0, 5), "left border")
		T.falsy(system:isHouseSpotValid(5, 17), "bottom border")
		T.falsy(system:isStoreSpotValid(17, 5), "right border")
		-- Case entourée d'eau/bâtiments : aucune voisine constructible.
		for dx = -1, 1 do
			for dy = -1, 1 do
				if dx ~= 0 or dy ~= 0 then
					session.buildings[(8 + dx) .. ":" .. (8 + dy)] = { x = 8 + dx, y = 8 + dy }
				end
			end
		end
		T.falsy(system:isHouseSpotValid(8, 8), "no buildable neighbour")
	end)

	T.test("groupes : avec ClusterChance = 1, chaque maison rejoint une maison de son magasin", function()
		local Houses = StoreConfig.Houses
		local saved = Houses.ClusterChance
		Houses.ClusterChance = 1
		local ok, err = pcall(function()
			local _, session = newSystem()
			local store = session.destinations[1]
			T.eq(#store.houses, Houses.StartHouses, "initial houses")
			-- L'arrondi à la case peut ajouter jusqu'à 0,71 case à la distance.
			local reach = Houses.ClusterMaxDistance + 0.75
			for index = 2, #store.houses do
				local house = store.houses[index]
				local nearest = math.huge
				for other = 1, index - 1 do
					local dx = house.x - store.houses[other].x
					local dy = house.y - store.houses[other].y
					nearest = math.min(nearest, math.sqrt(dx * dx + dy * dy))
				end
				T.le(nearest, reach, "house " .. index .. " must join a house of its store")
			end
		end)
		Houses.ClusterChance = saved
		if not ok then
			error(err, 0)
		end
	end)

	T.test("palette : jamais plus de magasins que de couleurs, couleurs uniques", function()
		local Config = H.load("Config")
		local system, session = newSystem()
		for _ = 1, 60 do
			system:spawnStore(false)
		end
		local limit = math.min(StoreConfig.Spawn.MaxStores, #Config.HouseColors)
		T.eq(#session.destinations, limit, "the store cap is the palette size")
		T.falsy(system:spawnStore(false), "no store beyond the cap")
		local seen = {}
		for _, store in ipairs(session.destinations) do
			T.falsy(seen[store.colorIndex], "colours are unique")
			seen[store.colorIndex] = true
		end
	end)
end
