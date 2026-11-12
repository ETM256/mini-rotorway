return function(T, H)
	local function stepUntil(session, predicate, limit, dt)
		local elapsed = 0
		while elapsed < limit and not predicate(session) do
			session:update(dt or 0.1)
			H.flush(dt or 0.1)
			elapsed += dt or 0.1
		end
		return elapsed
	end

	-- Session:setSpeed n'accepte que les entiers 1..3 ; toute autre valeur est
	-- ignorée et la vitesse garde sa valeur précédente (pas de clamp).
	T.test("setSpeed accepts integers 1..3 and ignores anything else", function()
		local session = H.newSession("los_angeles")
		T.eq(session.speed, 1, "starts at speed 1")
		session:setSpeed(2)
		T.eq(session.speed, 2)
		session:setSpeed(3)
		T.eq(session.speed, 3)
		session:setSpeed(1)
		T.eq(session.speed, 1)
		T.eq(H.lastSent("State").speed, 1)

		session:setSpeed(2)
		for _, junk in ipairs({ 99, -4, 0, 4, "fast", 2.7, 1.5, 0 / 0, math.huge }) do
			session:setSpeed(junk)
			T.eq(session.speed, 2, "junk value ignored: " .. tostring(junk))
		end
		session:setSpeed(nil)
		T.eq(session.speed, 2, "nil ignored")
		T.eq(H.lastSent("State").speed, 2)
	end)

	T.test("pause freezes the clock, stores, demands and cars; resume continues", function()
		local session = H.newSession("los_angeles")
		H.runSession(session, 10)
		local store = session.destinations[1]
		session:setPaused(true)
		T.ok(H.lastSent("State").paused)
		local weekTime, age, demands = session.weekTime, store.age, store.demands
		stepUntil(session, function()
			return false
		end, 30)
		T.eq(session.weekTime, weekTime)
		T.eq(store.age, age)
		T.eq(store.demands, demands)
		session:setPaused(false)
		stepUntil(session, function()
			return false
		end, 5)
		T.gt(session.weekTime, weekTime)
		T.gt(store.age, age)
	end)

	T.test("a week lasts Config.Game.WeekDuration seconds, then the game waits for a reward choice", function()
		local Config = H.load("Config")
		local session = H.newSession("los_angeles")
		local elapsed = stepUntil(session, function(s)
			return s.awaitingChoice
		end, Config.Game.WeekDuration + 5)
		T.near(elapsed, Config.Game.WeekDuration, 0.2)
		T.eq(session.week, 2)
		T.ok(session.paused, "the game pauses during the choice")
		local offer = H.lastSent("WeekChoice")
		T.ok(offer, "WeekChoice sent")
		T.eq(#offer.options, 2, "two options are offered")
		T.ne(offer.options[1].id, offer.options[2].id)
		local state = H.lastSent("State")
		T.ok(state.awaitingChoice)
	end)

	T.test("while the choice is open, time is frozen", function()
		local session = H.newSession("los_angeles")
		stepUntil(session, function(s)
			return s.awaitingChoice
		end, 70)
		local store = session.destinations[1]
		local age, week = store.age, session.week
		stepUntil(session, function()
			return false
		end, 20)
		T.eq(store.age, age)
		T.eq(session.week, week)
		T.ok(session.awaitingChoice)
	end)

	T.test("chooseReward: invalid ids are ignored; a valid one applies and resumes", function()
		local session = H.newSession("los_angeles")
		stepUntil(session, function(s)
			return s.awaitingChoice
		end, 70)
		local budget, bridges, roundabouts = session.budget, session.bridgesLeft, session.roundaboutsLeft
		session:chooseReward("not-a-reward")
		session:chooseReward(nil)
		session:chooseReward(42)
		T.ok(session.awaitingChoice, "invalid ids do not close the choice")
		T.eq(session.budget, budget)
		local option = session.choice.options[1]
		session:chooseReward(option.id)
		T.falsy(session.awaitingChoice)
		T.falsy(session.paused)
		T.eq(session.choice, nil)
		local gained = (option.kind == "roads" and option.amount or 0) + (option.roads or 0)
		T.eq(session.budget, budget + gained)
		if option.kind == "bridges" then
			T.eq(session.bridgesLeft, bridges + option.amount)
		elseif option.kind == "roundabouts" then
			T.eq(session.roundaboutsLeft, roundabouts + option.amount)
		end
		session:chooseReward(option.id)
		T.eq(session.budget, budget + gained, "a reward cannot be claimed twice")
		T.falsy(H.lastSent("State").awaitingChoice)
	end)

	T.test("every offered option is a real, bounded reward and the two differ", function()
		local Config = H.load("Config")
		for run = 1, 40 do
			H.reset()
			H.seed(run)
			local session = H.newSession("los_angeles")
			session:offerWeekChoice()
			local options = session.choice.options
			T.eq(#options, 2)
			T.ne(options[1].id, options[2].id)
			local special = 0
			for _, option in ipairs(options) do
				T.ok(option.kind == "roads" or option.kind == "bridges" or option.kind == "roundabouts")
				if option.kind ~= "roads" then
					special += 1
				end
			end
			T.le(special, 1, "at most one special tool is offered")
			session:chooseReward(options[1].id)
			T.le(session.budget, Config.Roads.MaxBudget)
		end
	end)

	T.test("tools at their maximum are not offered again", function()
		local Config = H.load("Config")
		local session = H.newSession("los_angeles")
		session.bridgesLeft = Config.Roads.MaxBridges
		session.roundaboutsLeft = Config.Roads.MaxRoundabouts
		for _ = 1, 20 do
			for _, option in ipairs(session:pickWeekChoices()) do
				T.eq(option.kind, "roads")
			end
		end
	end)

	T.test("rewards respect MaxBudget / MaxBridges / MaxRoundabouts", function()
		local Config = H.load("Config")
		local session = H.newSession("los_angeles")
		session.budget = Config.Roads.MaxBudget - 1
		session.bridgesLeft = Config.Roads.MaxBridges - 1
		session:offerWeekChoice()
		for _, option in ipairs(session.choice.options) do
			session.awaitingChoice = true
			session.choice = { week = 1, options = { option } }
			session:chooseReward(option.id)
			T.le(session.budget, Config.Roads.MaxBudget)
			T.le(session.bridgesLeft, Config.Roads.MaxBridges)
			T.le(session.roundaboutsLeft, Config.Roads.MaxRoundabouts)
		end
	end)

	T.test("an unserved game ends: overload drains satisfaction, GameOver is sent with the score", function()
		local session = H.newSession("los_angeles")
		local before = #H.sent("GameOver")
		local elapsed = H.runSession(session, 900, 0.5)
		T.ok(session.over, "the game must end when nothing is served (elapsed " .. elapsed .. ")")
		T.eq(session.satisfaction, 0)
		T.eq(#H.sent("GameOver"), before + 1, "GameOver must be sent exactly once")
		local payload = H.lastSent("GameOver")
		T.eq(payload.mapId, "los_angeles")
		T.eq(payload.score, session.score)
		T.ok(payload.best ~= nil, "best score")
		T.eq(payload.week, session.week)
		T.ok(H.lastSent("State").over)
		local before2 = session.score
		session:update(1)
		session:gameOver()
		T.eq(#H.sent("GameOver"), before + 1, "no duplicate GameOver")
		T.eq(session.score, before2)
		-- Une partie terminée n'accepte plus de routes.
		session:drawRoad({ { 0, 0 } })
		T.eq(next(session.roads), nil)
	end)

	T.test("overload: a full store warns, then turns critical after the grace period", function()
		local StoreConfig = H.load("StoreConfig")
		local session = H.newSession("los_angeles")
		local store = session.destinations[1]
		local sawOverloaded, sawCritical = false, false
		local overloadedAt, criticalAt
		local elapsed = 0
		while elapsed < 300 and not session.over do
			session:update(0.2)
			H.flush(0.2)
			elapsed += 0.2
			if session.awaitingChoice then
				session:chooseReward(session.choice.options[1].id)
			end
			if store.overloaded and not sawOverloaded then
				sawOverloaded, overloadedAt = true, elapsed
			end
			if store.critical and not sawCritical then
				sawCritical, criticalAt = true, elapsed
			end
		end
		T.ok(sawOverloaded)
		T.ok(sawCritical)
		T.near(criticalAt - overloadedAt, StoreConfig.Demand.OverloadGrace, 1.0)
	end)

	T.test("serving the store clears the overload", function()
		local session = H.newSession("los_angeles")
		local store = session.destinations[1]
		for _ = 1, store.capacity + 2 do
			session.storeSystem:addDemand(store)
		end
		T.ok(store.overloaded)
		T.eq(store.demands, store.capacity)
		local id = store.demandIds[1]
		session.storeSystem:claimDemand(store)
		T.ok(session.storeSystem:consumeDemand(store, id))
		T.falsy(store.overloaded, "overload must clear once a demand is served")
		T.falsy(session.storeSystem:consumeDemand(store, id), "a demand cannot be served twice")
	end)

	T.test("difficulty ramps up: stores appear faster later in the game", function()
		local Tiers = H.load("StoreConfig").Spawn.Tiers
		for i = 2, #Tiers do
			T.le(Tiers[i].minInterval, Tiers[i - 1].minInterval)
			T.le(Tiers[i].maxInterval, Tiers[i - 1].maxInterval)
			-- Pas de saut brutal : l'intervalle ne chute pas de plus de 60% d'un palier au suivant.
			T.ge(Tiers[i].minInterval, Tiers[i - 1].minInterval * 0.4)
		end
	end)

	T.test("a 10-minute game on every map ends or runs cleanly (no errors, no NaN, bounded cars)", function()
		local Maps = H.load("Maps")
		for _, map in ipairs(Maps.all()) do
			H.reset()
			local session = H.newSession(map.id)
			session.budget = 200
			local store = session.destinations[1]
			for _, house in ipairs(session.houses) do
				H.connect(session, house, store)
			end
			session:setSpeed(3)
			H.runSession(session, 600, 0.25)
			T.ok(session.satisfaction == session.satisfaction, map.id .. " satisfaction NaN")
			T.ok(session.score == session.score)
			T.le(#session.cars, #session.houses, map.id .. ": more cars than houses")
			T.le(#session.destinations, H.load("StoreConfig").Spawn.MaxStores)
			session:destroy()
		end
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("a destroyed session ignores late calls instead of erroring", function()
		local session = H.newSession("los_angeles")
		session:destroy()
		T.noThrow(function()
			session:update(0.1)
			session:drawRoad({ { 1, 1 } })
			session:eraseRoad("1:1")
			session:placeRoundabout(1, 1)
			session:setSpeed(2)
			session:setPaused(true)
			session:chooseReward("roads")
		end)
	end)
end
