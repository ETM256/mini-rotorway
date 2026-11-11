-- Satisfaction, surcharge des magasins et fin de partie (SessionProgress).
return function(T, H)
	local Config = H.load("Config")
	local Progression = Config.Progression

	-- Remplit un magasin au-delà de sa capacité : il devient surchargé, puis
	-- critique après StoreConfig.Demand.OverloadGrace secondes.
	local function makeOverloaded(session)
		local store = session.destinations[1]
		for _ = 1, store.capacity + 1 do
			session.storeSystem:addDemand(store)
		end
		return store
	end

	-- Avance jusqu'à `predicate`, en résolvant les choix de semaine.
	local function runUntil(session, predicate, limit)
		local elapsed = 0
		while elapsed < limit and not session.over and not predicate(session) do
			if session.awaitingChoice then
				session:chooseReward(session.choice.options[1].id)
			end
			session:update(0.1)
			H.flush(0.1)
			elapsed += 0.1
		end
		return elapsed
	end

	T.test("no critical store: no overload in the summary, pressure 1", function()
		local session = H.newSession("los_angeles")
		local summary = session:getOverloadSummary()
		T.eq(summary.criticalCount, 0)
		T.eq(summary.pressure, 1)
		T.eq(summary.storeId, nil)
	end)

	T.test("overload turns a store critical after the grace period, then satisfaction falls", function()
		local StoreConfig = H.load("StoreConfig")
		local session = H.newSession("los_angeles")
		local store = makeOverloaded(session)
		local elapsed = runUntil(session, function(s)
			return store.critical
		end, StoreConfig.Demand.OverloadGrace + 5)
		T.ok(store.critical, "critical after the grace period")
		T.near(elapsed, StoreConfig.Demand.OverloadGrace, 1.0)
		T.eq(session:getOverloadSummary().criticalCount, 1)
	end)

	T.test("pressure grows with the time spent critical, linearly, then caps", function()
		local session = H.newSession("los_angeles")
		local store = session.destinations[1]
		store.critical = true
		local previous = 1
		for _ = 1, 40 do
			session:trackCriticalStores(10)
			local summary = session:getOverloadSummary()
			local expected = 1 + math.min(Progression.OverloadMaxExtra, summary.seconds / Progression.OverloadRampSeconds)
			T.near(summary.pressure, expected, 1e-9, "formula at " .. summary.seconds .. " s")
			T.ge(summary.pressure, previous, "pressure never decreases while critical")
			previous = summary.pressure
		end
		T.near(previous, 1 + Progression.OverloadMaxExtra, 1e-9, "pressure is capped")
	end)

	T.test("the drain is the StoreConfig rate times the pressure", function()
		local session = H.newSession("los_angeles")
		local store = session.destinations[1]
		store.critical = true
		session:trackCriticalStores(Progression.OverloadRampSeconds)
		session.satisfaction = Config.Traffic.SatisfactionMax
		local baseRate = session.storeSystem:getOverloadDrain()
		T.gt(baseRate, 0)
		session:updateSatisfaction(1)
		-- Après 120 s + 1 s critique, la pression est déjà plafonnée à 2.
		local expected = baseRate * (1 + Progression.OverloadMaxExtra)
		T.near(Config.Traffic.SatisfactionMax - session.satisfaction, expected, 1e-6)
	end)

	T.test("pause freezes satisfaction and overload timers; resume continues", function()
		local session = H.newSession("los_angeles")
		local store = makeOverloaded(session)
		runUntil(session, function(s)
			return store.critical
		end, 60)
		T.ok(store.critical)
		session:setPaused(true)
		local satisfaction = session.satisfaction
		local seconds = session:getOverloadSummary().seconds
		for _ = 1, 300 do
			session:update(0.1)
			H.flush(0.1)
		end
		T.eq(session.satisfaction, satisfaction, "satisfaction frozen while paused")
		T.eq(session:getOverloadSummary().seconds, seconds, "overload timer frozen while paused")
		session:setPaused(false)
		for _ = 1, 10 do
			session:update(0.1)
			H.flush(0.1)
		end
		T.lt(session.satisfaction, satisfaction, "satisfaction falls again after resume")
	end)

	T.test("updateSatisfaction itself does nothing while paused or a choice is open", function()
		local session = H.newSession("los_angeles")
		session.destinations[1].critical = true
		session.satisfaction = 50
		session.paused = true
		session:updateSatisfaction(5)
		T.eq(session.satisfaction, 50, "paused: no drain")
		T.eq(session:getOverloadSummary().seconds, 0, "paused: no critical time")
		session.paused = false
		session.awaitingChoice = true
		session:updateSatisfaction(5)
		T.eq(session.satisfaction, 50, "choice open: no drain")
		T.eq(session:getOverloadSummary().seconds, 0, "choice open: no critical time")
		session.awaitingChoice = false
		session:updateSatisfaction(5)
		T.lt(session.satisfaction, 50, "running: the critical store drains")
	end)

	T.test("satisfaction and overload freeze while a reward choice is open", function()
		local session = H.newSession("los_angeles")
		local store = makeOverloaded(session)
		local guard = 0
		while not session.awaitingChoice and not session.over and guard < 1000 do
			session:update(0.1)
			H.flush(0.1)
			guard += 1
		end
		T.ok(session.awaitingChoice, "a choice opens at the end of week 1")
		local satisfaction = session.satisfaction
		local seconds = session:getOverloadSummary().seconds
		for _ = 1, 200 do
			session:update(0.1)
			H.flush(0.1)
		end
		T.ok(session.awaitingChoice, "the choice stays open")
		T.eq(session.satisfaction, satisfaction)
		T.eq(session:getOverloadSummary().seconds, seconds)
		T.ok(store.overloaded)
	end)

	T.test("an unserved overload ends the game once, with the store as the reason", function()
		local session = H.newSession("los_angeles")
		local store = makeOverloaded(session)
		local before = #H.sent("GameOver")
		local previous = session.satisfaction
		local guard = 0
		while not session.over and guard < 3000 do
			if session.awaitingChoice then
				session:chooseReward(session.choice.options[1].id)
			end
			local wasCritical = store.critical
			session:update(0.1)
			H.flush(0.1)
			if wasCritical and not session.over then
				T.le(session.satisfaction, previous + 1e-9, "satisfaction never rises under overload")
			end
			previous = session.satisfaction
			guard += 1
		end
		T.ok(session.over, "the game must end when a store stays overloaded")
		T.eq(session.satisfaction, 0)
		T.eq(#H.sent("GameOver"), before + 1, "GameOver sent exactly once")

		local reason = session.gameOverReason
		T.ok(reason ~= nil, "a reason is kept for the end screen")
		T.eq(reason.kind, "overload")
		T.eq(reason.storeId, store.id)
		T.eq(reason.colorIndex, store.colorIndex)
		T.eq(reason.colorName, Config.HouseColors[store.colorIndex].name)
		T.gt(reason.seconds, 0)

		session:updateSatisfaction(1)
		session:gameOver()
		for _ = 1, 10 do
			session:update(0.5)
		end
		T.eq(#H.sent("GameOver"), before + 1, "no second GameOver")
		T.eq(session.satisfaction, 0)
	end)

	T.test("stuck cars alone end the game with the traffic reason", function()
		local session = H.newSession("los_angeles")
		session.cars = { { path = { 1 }, waitTime = 100 } }
		session.satisfaction = 0.5
		session:updateSatisfaction(1)
		T.ok(session.over)
		T.eq(session.gameOverReason.kind, "traffic")
		T.eq(session.gameOverReason.storeId, nil)
	end)

	T.test("satisfaction recovers when traffic flows", function()
		local session = H.newSession("los_angeles")
		session.satisfaction = 40
		for _ = 1, 100 do
			session:update(0.1)
			H.flush(0.1)
		end
		T.gt(session.satisfaction, 40, "no drain: satisfaction recovers")
		T.le(session.satisfaction, Config.Traffic.SatisfactionMax)
	end)

	T.test("satisfaction recovers once the overloaded store is served", function()
		local session = H.newSession("los_angeles")
		local store = makeOverloaded(session)
		runUntil(session, function(s)
			return store.critical
		end, 60)
		T.ok(store.critical)
		while #store.demandIds > 0 do
			session.storeSystem:consumeDemand(store, store.demandIds[1])
		end
		T.falsy(store.critical, "serving the demands clears the overload")
		T.eq(session:getOverloadSummary().criticalCount, 0)
		T.eq(session:getOverloadSummary().pressure, 1, "pressure resets with the overload")
		local satisfaction = session.satisfaction
		for _ = 1, 20 do
			session:update(0.1)
			H.flush(0.1)
		end
		T.gt(session.satisfaction, satisfaction, "satisfaction recovers after the store is served")
	end)
end
