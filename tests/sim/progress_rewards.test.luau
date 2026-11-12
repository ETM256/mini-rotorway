-- Choix hebdomadaires et récompenses (SessionProgress).
return function(T, H)
	local Config = H.load("Config")
	local Progression = Config.Progression

	-- Fait avancer la partie jusqu'à l'ouverture d'un choix de fin de semaine.
	local function advanceToChoice(session)
		local guard = 0
		while not session.awaitingChoice and not session.over and guard < 400 do
			session:update(0.5)
			H.flush(0.5)
			guard += 1
		end
		return session.awaitingChoice
	end

	-- Ouvre des propositions (graines fixes) jusqu'à voir `id`. Renvoie l'option
	-- et laisse le choix ouvert ; sinon renvoie nil avec le choix fermé.
	local function offerWith(session, id)
		for seed = 1, 300 do
			H.seed(seed)
			session.awaitingChoice = false
			session.paused = false
			session.choice = nil
			session:offerWeekChoice()
			for _, option in ipairs(session.choice.options) do
				if option.id == id then
					return option
				end
			end
		end
		session.awaitingChoice = false
		session.paused = false
		session.choice = nil
		return nil
	end

	-- Bonus de routes attendu pour une semaine (même règle que SessionProgress).
	local function expectedBonus(week)
		local steps = math.floor((week - 1) / Progression.RoadsWeeksPerStep)
		return math.min(Progression.RoadsMaxBonus, steps * Progression.RoadsPerStep)
	end

	T.test("the week rollover offers two distinct, valid choices and pauses the game", function()
		local session = H.newSession("los_angeles")
		T.ok(advanceToChoice(session), "a week must end with a reward choice")
		T.eq(session.week, 2)
		T.ok(session.paused, "the game pauses during the choice")
		local offer = H.lastSent("WeekChoice")
		T.ok(offer, "WeekChoice sent")
		T.eq(#offer.options, 2)
		T.ne(offer.options[1].id, offer.options[2].id)
		for _, option in ipairs(offer.options) do
			T.ok(option.kind == "roads" or option.kind == "bridges" or option.kind == "roundabouts")
			T.eq(type(option.title), "string")
			T.eq(type(option.description), "string")
		end
	end)

	T.test("across seeds the two cards differ and at most one is a special card", function()
		for seed = 1, 40 do
			H.reset()
			H.seed(seed)
			local session = H.newSession("los_angeles")
			session:offerWeekChoice()
			local options = session.choice.options
			T.ne(options[1].id, options[2].id, "seed " .. seed)
			local special = 0
			for _, option in ipairs(options) do
				if option.kind ~= "roads" or option.trafficFactor then
					special += 1
				end
			end
			T.le(special, 1, "seed " .. seed .. ": one special card at most")
		end
	end)

	T.test("the random source is injectable: a fixed source gives a fixed offer", function()
		local session = H.newSession("los_angeles")
		-- random(1, n) renvoie 1 (premier outil) ; random() renvoie 0.
		session.random = {
			random = function(a)
				if a == nil then
					return 0
				end
				return a
			end,
		}
		local ids = {}
		for _, option in ipairs(session:pickWeekChoices()) do
			ids[option.id] = true
		end
		T.ok(ids.bridge, "the first special (bridge) is picked")
		T.ok(ids.roads_large, "the second card is the large road lot")
		T.falsy(ids.roads, "only one plain lot per offer")
	end)

	T.test("invalid ids are rejected and nothing changes", function()
		local session = H.newSession("los_angeles")
		advanceToChoice(session)
		local offered = {}
		for _, option in ipairs(session.choice.options) do
			offered[option.id] = true
		end
		local budget, bridges, roundabouts = session.budget, session.bridgesLeft, session.roundaboutsLeft
		for _, id in ipairs({ "roads", "roads_large", "bridge", "roundabout", "traffic", "highway" }) do
			if not offered[id] then
				session:chooseReward(id)
			end
		end
		session:chooseReward(nil)
		session:chooseReward(42)
		session:chooseReward("")
		T.ok(session.awaitingChoice, "invalid ids do not close the choice")
		T.eq(session.budget, budget)
		T.eq(session.bridgesLeft, bridges)
		T.eq(session.roundaboutsLeft, roundabouts)
	end)

	T.test("a choice is consumed exactly once and the game resumes", function()
		local session = H.newSession("los_angeles")
		local stats = {}
		session.recordStat = function(_, name, amount)
			stats[name] = (stats[name] or 0) + amount
		end
		advanceToChoice(session)
		local first, second = session.choice.options[1], session.choice.options[2]
		session:chooseReward(first.id)
		local budget, bridges = session.budget, session.bridgesLeft
		T.falsy(session.awaitingChoice)
		T.falsy(session.paused)
		T.eq(session.choice, nil)
		session:chooseReward(first.id)
		session:chooseReward(second.id)
		T.eq(session.budget, budget, "a second choice is ignored")
		T.eq(session.bridgesLeft, bridges)
		T.falsy(H.lastSent("State").awaitingChoice)
		T.eq(stats.rewardsChosen, 1, "rewardsChosen counted once")
		T.eq(stats.weeksCompleted, 1, "weeksCompleted counted at the rollover")

		local weekTime = session.weekTime
		for _ = 1, 20 do
			session:update(0.1)
			H.flush(0.1)
		end
		T.gt(session.weekTime, weekTime, "the clock runs again after the choice")
	end)

	T.test("a second offer while a choice is open changes nothing", function()
		local session = H.newSession("los_angeles")
		session:offerWeekChoice()
		local choice = session.choice
		local sent = #H.sent("WeekChoice")
		session:offerWeekChoice()
		T.eq(session.choice, choice, "the open choice is kept")
		T.eq(#H.sent("WeekChoice"), sent, "no second WeekChoice is sent")
		T.eq(session.stats.weeksCompleted, 1, "weeksCompleted counted once")
	end)

	T.test("road lots give exactly their amount in week 1", function()
		local cases = {
			{ id = "roads", amount = Config.Rewards.Roads.amount },
			{ id = "roads_large", amount = Config.Rewards.RoadsLarge.amount },
		}
		for _, case in ipairs(cases) do
			local session = H.newSession("los_angeles")
			local option = offerWith(session, case.id)
			T.ok(option, case.id .. " must be offered for some seed")
			local before = session.budget
			session:chooseReward(case.id)
			T.eq(session.budget, before + case.amount, case.id)
		end
	end)

	T.test("tools give their roads and the tool exactly, in week 1", function()
		local session = H.newSession("los_angeles")
		local bridgeOption = offerWith(session, "bridge")
		T.ok(bridgeOption, "bridge offered for some seed")
		local budget, bridges = session.budget, session.bridgesLeft
		session:chooseReward("bridge")
		T.eq(session.budget, budget + Config.Rewards.Bridge.roads)
		T.eq(session.bridgesLeft, bridges + Config.Rewards.Bridge.amount)

		session = H.newSession("los_angeles")
		T.ok(offerWith(session, "roundabout"), "roundabout offered for some seed")
		budget = session.budget
		local roundabouts = session.roundaboutsLeft
		session:chooseReward("roundabout")
		T.eq(session.budget, budget + Config.Rewards.Roundabout.roads)
		T.eq(session.roundaboutsLeft, roundabouts + Config.Rewards.Roundabout.amount)
	end)

	T.test("road lots scale gently with the week and stay capped", function()
		local session = H.newSession("los_angeles")
		local previous = 0
		for week = 1, 40 do
			session.week = week
			local option = offerWith(session, "roads")
			T.ok(option, "roads offered in week " .. week)
			local bonus = expectedBonus(week)
			T.eq(option.amount, Config.Rewards.Roads.amount + bonus, "week " .. week)
			T.eq(option.title, "+" .. option.amount .. " routes")
			T.ge(option.amount, previous, "amounts never shrink")
			previous = option.amount
		end
		T.eq(expectedBonus(1), 0, "week 1 keeps the base lot")
		T.le(previous - Config.Rewards.Roads.amount, Progression.RoadsMaxBonus, "bonus is capped")
	end)

	T.test("offers never mutate Config.Rewards", function()
		for seed = 1, 30 do
			H.reset()
			H.seed(seed)
			local C = H.load("Config")
			local session = H.newSession("los_angeles")
			session.week = 12
			session:offerWeekChoice()
			for _, option in ipairs(session.choice.options) do
				T.ne(option, C.Rewards.Roads)
				T.ne(option, C.Rewards.RoadsLarge)
				T.ne(option, C.Rewards.Traffic)
			end
			T.eq(C.Rewards.Roads.amount, 30)
			T.eq(C.Rewards.Roads.title, "+30 routes")
			T.eq(C.Rewards.RoadsLarge.amount, 40)
		end
	end)

	T.test("the traffic improvement is a smaller lot than a plain one (a real trade-off)", function()
		T.lt(Config.Rewards.Traffic.amount, Config.Rewards.Roads.amount)
		T.gt(Config.Rewards.Traffic.trafficFactor, 0)
		T.lt(Config.Rewards.Traffic.trafficFactor, 1)
	end)

	T.test("traffic improvements stack down to the floor, then stop being offered", function()
		local session = H.newSession("los_angeles")
		T.eq(session:getTrafficMultiplier(), 1, "no upgrade at the start")
		local guard = 0
		while session:getTrafficMultiplier() > Progression.TrafficMinFactor and guard < 10 do
			local before = session:getTrafficMultiplier()
			local option = offerWith(session, "traffic")
			T.ok(option, "traffic offered while below the floor")
			session:chooseReward("traffic")
			T.lt(session:getTrafficMultiplier(), before, "each upgrade shortens the spacing")
			T.ge(session:getTrafficMultiplier(), Progression.TrafficMinFactor)
			guard += 1
		end
		T.eq(session:getTrafficMultiplier(), Progression.TrafficMinFactor, "clamped to the floor")
		T.falsy(offerWith(session, "traffic"), "a maxed upgrade is not offered again")
	end)

	T.test("tools at their maximum are not offered; the budget is capped", function()
		local session = H.newSession("los_angeles")
		session.budget = Config.Roads.MaxBudget - 1
		session.bridgesLeft = Config.Roads.MaxBridges - 1
		session.roundaboutsLeft = Config.Roads.MaxRoundabouts
		T.ok(offerWith(session, "bridge"), "bridge still offered below the cap")
		session.bridgesLeft = Config.Roads.MaxBridges - 1
		session.budget = Config.Roads.MaxBudget - 1
		session:chooseReward("bridge")
		T.eq(session.budget, Config.Roads.MaxBudget, "budget capped")
		T.eq(session.bridgesLeft, Config.Roads.MaxBridges, "bridges capped")

		for seed = 1, 30 do
			H.seed(seed)
			session.awaitingChoice = false
			for _, option in ipairs(session:pickWeekChoices()) do
				T.falsy(option.id == "bridge", "a maxed bridge is not offered")
				T.falsy(option.id == "roundabout", "a maxed roundabout is not offered (seed " .. seed .. ")")
			end
		end
	end)
end
