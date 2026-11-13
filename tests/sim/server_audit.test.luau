return function(T, H)
	-- Audit serveur (vague 4) : cycle de vie du profil et émission de StoreState.
	-- Les latences du DataStore sont simulées par task.wait dans un faux magasin.

	local STORE = "MiniMotorwaysV1"

	-- Remplace GetAsync / UpdateAsync du magasin par des versions qui attendent
	-- `latency` secondes virtuelles et comptent leurs appels.
	local function slowStore(latency, stored)
		local store = H.W.dataStores[STORE]
		local counts = { get = 0, set = 0, written = nil }
		local real = store.UpdateAsync
		function store.GetAsync(_, _)
			counts.get += 1
			task.wait(latency)
			return stored
		end
		function store.UpdateAsync(self, key, fn)
			counts.set += 1
			task.wait(latency)
			counts.written = real(self, key, fn)
			return counts.written
		end
		return counts
	end

	T.test("two simultaneous profile loads share one GetAsync", function()
		local Profile = H.load("Profile")
		local counts = slowStore(0.5, { schema = 2, records = { los_angeles = 40 } })
		local player = H.asClient()
		local results = {}
		task.spawn(function()
			results[1] = Profile.load(player)
		end)
		task.spawn(function()
			results[2] = Profile.load(player)
		end)
		H.advance(3, { frames = false })
		T.eq(counts.get, 1, "a single read for both callers")
		T.ok(results[1] ~= nil and results[1] == results[2], "both callers get the same records table")
		T.eq(results[1].los_angeles, 40)
	end)

	T.test("flushAll waits for a write already in flight (BindToClose)", function()
		local Profile = H.load("Profile")
		local counts = slowStore(2, nil)
		local player = H.asClient()
		Profile.load(player)
		T.eq(Profile.submit(player, "los_angeles", 77), 77)

		task.spawn(Profile.save, player)
		H.advance(0.5, { frames = false })
		T.eq(counts.set, 1, "the write has started")
		T.eq(counts.written, nil, "and is not finished")

		local flushed = false
		task.spawn(function()
			Profile.flushAll()
			flushed = true
		end)
		H.advance(0.5, { frames = false })
		T.falsy(flushed, "flushAll does not return while the write is pending")
		H.advance(3, { frames = false })
		T.ok(flushed, "flushAll returns once the write is done")
		T.eq(counts.written.records.los_angeles, 77)
	end)

	T.test("a player leaving during the profile read leaves nothing cached", function()
		H.runScript("Bootstrap")
		local counts = slowStore(1, nil)
		H.clearRemoteLog()
		local player = H.newPlayer("Leaver", 3003)
		-- Le harnais ne tire pas PlayerAdded au parentage : on l'émet.
		H.I.fire(H.I.getSignal(game.Players, "PlayerAdded"), player)
		H.advance(0.3, { frames = false })
		H.I.fire(H.I.getSignal(game.Players, "PlayerRemoving"), player)
		H.advance(3, { frames = false })

		T.eq(counts.get, 1, "the read ran once")
		T.eq(#H.sent("Profile"), 0, "no profile is sent to a player who left")
		-- Sans entrée en cache, une nouvelle demande relit le DataStore.
		task.spawn(H.load("Profile").load, player)
		H.advance(3, { frames = false })
		T.eq(counts.get, 2, "the cache entry was released, not leaked")
	end)

	T.test("StoreState is not re-sent every 0.2 s once a store is critical", function()
		local session = H.newSession("los_angeles")
		local system = session.storeSystem
		local store = session.destinations[1]
		T.ok(store, "a store exists")
		-- Isole l'horloge de surcharge : ni demande ni évolution pendant le test.
		store.demandClock = 1e6
		store.evolveClock = 1e6
		system:markOverload(store)
		store.overloadClock = 5

		system.dirty = false
		system:updateStore(store, 0.1)
		T.ok(system.dirty, "the countdown is sent while it still runs")
		T.falsy(store.critical)

		store.overloadClock = 0.1
		system.dirty = false
		system:updateStore(store, 0.2)
		T.ok(store.critical, "the store turns critical")
		T.ok(system.dirty, "the change to critical is sent")

		system.dirty = false
		system:updateStore(store, 0.2)
		T.falsy(system.dirty, "a critical store with a frozen clock does not force a send")
		T.eq(system:snapshot().stores[1].overloadClock, 0, "the payload clock stays clamped at 0")
	end)
end
