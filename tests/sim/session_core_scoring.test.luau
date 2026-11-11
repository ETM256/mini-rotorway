return function(T, H)
	local Config = H.load("Config")
	local SessionUtil = H.load("SessionUtil")

	T.test("recordStat accumulates counters and ignores invalid input", function()
		local session = H.newSession("los_angeles")
		session:recordStat("deliveries", 2)
		session:recordStat("deliveries", 3)
		T.eq(session.stats.deliveries, 5)
		session:recordStat("deliveries", "4")
		session:recordStat("deliveries", 0 / 0)
		session:recordStat(nil, 1)
		T.eq(session.stats.deliveries, 5)
		session:recordStat("customCounter", 1.5)
		T.eq(session.stats.customCounter, 1.5)
	end)

	T.test("every standard counter exists at zero before the first event", function()
		local fresh = H.load("Session").new(H.newPlayer("Other", 1100), "los_angeles", 9)
		for _, name in ipairs({ "deliveries", "carsSpawned", "roadsBuilt", "roadsErased", "demandsServed", "weeksCompleted", "rewardsChosen", "stuckSeconds" }) do
			T.eq(fresh.stats[name], 0, name)
		end
		fresh:destroy()
	end)

	T.test("onDelivery pays the base score, a first-store bonus and a long-trip bonus", function()
		local session = H.newSession("los_angeles")
		session.score = 0
		local house = { x = 1, y = 1 }
		local near = { id = 101, x = 2, y = 2 }
		local far = { id = 102, x = 1, y = 1 + Config.Game.LongTripCells }

		local first = session:onDelivery(house, near)
		T.eq(first, Config.Game.DeliveryScore + Config.Game.NewStoreBonus)

		local repeated = session:onDelivery(house, near)
		T.eq(repeated, Config.Game.DeliveryScore)

		local long = session:onDelivery(house, far)
		T.eq(long, Config.Game.DeliveryScore + Config.Game.NewStoreBonus + Config.Game.LongTripBonus)

		T.eq(session.score, first + repeated + long)
		T.eq(session.stats.deliveries, 3)
	end)

	T.test("onDelivery restores satisfaction without going above the maximum", function()
		local session = H.newSession("los_angeles")
		session.satisfaction = 50
		session:onDelivery({ x = 1, y = 1 }, { id = 1, x = 1, y = 2 })
		T.eq(session.satisfaction, 50 + Config.Game.DeliverySatisfaction)
		session.satisfaction = Config.Traffic.SatisfactionMax - 1
		session:onDelivery({ x = 1, y = 1 }, { id = 2, x = 1, y = 2 })
		T.eq(session.satisfaction, Config.Traffic.SatisfactionMax)
	end)

	T.test("onDelivery ignores a missing destination and does nothing after game over", function()
		local session = H.newSession("los_angeles")
		T.eq(session:onDelivery({ x = 1, y = 1 }, nil), 0)
		T.eq(session.score, 0)
		session:gameOver()
		T.eq(session:onDelivery({ x = 1, y = 1 }, { id = 3, x = 1, y = 2 }), 0)
		T.eq(session.score, 0)
	end)

	T.test("gameOver fires once and sends the end-of-game summary", function()
		local session = H.newSession("los_angeles")
		session:onDelivery({ x = 1, y = 1 }, { id = 1, x = 1, y = 2 })
		session.elapsed = 125.4
		session:updateClock()
		H.clearRemoteLog()

		session:gameOver()
		session:gameOver()
		local payloads = H.sent("GameOver")
		T.eq(#payloads, 1)

		local payload = payloads[1][1]
		T.eq(payload.mapId, "los_angeles")
		T.eq(payload.score, session.score)
		T.ok(payload.best >= payload.score)
		T.eq(payload.week, session.week)
		T.eq(payload.durationSeconds, 125)
		T.eq(payload.day, session.day)
		T.eq(payload.dayOfWeek, session.dayOfWeek)
		T.eq(payload.month, session.month)
		T.eq(payload.monthName, session.monthName)
		T.eq(payload.stats.deliveries, 1)
		T.eq(payload.reason, "satisfaction")
		T.isType(payload.overload, "table")
		T.eq(payload.overload.criticalCount, 0)
		T.ok(H.lastSent("State").over)
	end)

	T.test("gameOver reports the reason recorded by the progress system", function()
		local session = H.newSession("los_angeles")
		session.gameOverReason = { kind = "overload" }
		H.clearRemoteLog()
		session:gameOver()
		T.eq(H.sent("GameOver")[1][1].reason, "overload")
	end)

	T.test("a finished game is frozen: no clock, no stats from the simulation", function()
		local session = H.newSession("los_angeles")
		session:gameOver()
		local elapsed = session.elapsed
		session:update(5)
		T.eq(session.elapsed, elapsed)
	end)

	T.test("destroy is idempotent and leaves no instance under Workspace.MMWorlds", function()
		local worlds = Instance.new("Folder")
		worlds.Name = "MMWorlds"
		worlds.Parent = workspace

		local session = H.newSession("los_angeles")
		T.ok(H.count(worlds) > 0, "the world was built")

		session:destroy()
		session:destroy()
		T.eq(H.count(worlds), 0)
		T.eq(session.world, nil)
		T.eq(session.storeSystem, nil)
		T.eq(#session.cars, 0)
		T.eq(#session.houses, 0)
		T.eq(#session.destinations, 0)
		T.eq(next(session.roads), nil)
		T.eq(next(session.buildings), nil)
		T.ok(session.over)
		T.falsy(session.running)
	end)

	T.test("destroy stops the tweens it tracks", function()
		local function snapshot(tweens)
			local set, count = {}, 0
			for tween in pairs(tweens) do
				set[tween] = true
				count += 1
			end
			return set, count
		end

		local session = H.newSession("los_angeles")
		-- La partie crée déjà ses propres tweens : on compte seulement l'ajout.
		local before, countBefore = snapshot(session.tweens)
		local part = SessionUtil.makePart({ Size = Vector3.new(4, 1, 4), Parent = workspace })
		SessionUtil.animateRoadPart(part, Vector3.new(4, 1, 4), 0, session.tweens)
		local after, countAfter = snapshot(session.tweens)
		T.eq(countAfter - countBefore, 1, "animateRoadPart tracks exactly one tween")

		local added = nil
		for tween in pairs(after) do
			if not before[tween] then
				added = tween
			end
		end
		T.ok(added ~= nil, "the new tween is the one tracked")

		session:destroy()
		local _, left = snapshot(session.tweens)
		T.eq(left, 0, "destroy empties the tracked tweens")
		T.eq(added.PlaybackState, Enum.PlaybackState.Cancelled, "destroy cancels the tween it tracked")
	end)

	T.test("start() on a session already started rebuilds a fresh game", function()
		local worlds = Instance.new("Folder")
		worlds.Name = "MMWorlds"
		worlds.Parent = workspace

		local session = H.newSession("los_angeles")
		local houses = #session.houses
		local destinations = #session.destinations
		session:recordStat("deliveries", 5)
		session.score = 40
		session.elapsed = 99
		session:updateClock()
		session:setSpeed(3)
		session:setPaused(true)

		session:start()
		T.eq(session.score, 0)
		T.eq(session.elapsed, 0)
		T.eq(session.week, 1)
		T.eq(session.speed, 1)
		T.falsy(session.paused)
		T.falsy(session.over)
		T.eq(session.stats.deliveries, 0)
		T.eq(session.budget, Config.Roads.StartBudget)
		T.eq(#session.houses, houses)
		T.eq(#session.destinations, destinations)
		T.eq(#worlds:GetChildren(), 1)
	end)

	T.test("a session created but not started builds nothing", function()
		local worlds = Instance.new("Folder")
		worlds.Name = "MMWorlds"
		worlds.Parent = workspace
		local session = H.load("Session").new(H.newPlayer("Idle", 1200), "los_angeles", 4)
		T.eq(H.count(worlds), 0)
		T.eq(session.world, nil)
		session:destroy()
		session:destroy()
	end)

	T.test("Session.new accepts any worldIndex and keeps the origin finite", function()
		local Session = H.load("Session")
		local player = H.newPlayer("Index", 1300)
		local inputs = { nil, -3, 2.7, 0 / 0, math.huge, -math.huge, "abc", 3 }
		for _, index in ipairs(inputs) do
			local session = Session.new(player, "los_angeles", index)
			T.ok(session.origin.X == session.origin.X, "origin is a number")
			T.ok(math.abs(session.origin.X) < math.huge, "origin is finite")
			T.ok(session.origin.X >= 0, "origin is not negative")
			session:destroy()
		end
		local third = Session.new(player, "los_angeles", 3)
		T.eq(third.origin.X, 3 * Config.World.OriginSpacing)
		third:destroy()
	end)

	T.test("the session does not count stuckSeconds itself: traffic records blocked time", function()
		local session = H.newSession("los_angeles")
		session.updateCar = function()
			return false
		end
		session.cars[#session.cars + 1] = { path = { 1 }, waitTime = 100, state = "out" }
		session:update(1)
		T.eq(session.stats.stuckSeconds, 0)
	end)

	T.test("gameOver without a player ends the game and fires no remote", function()
		local session = H.load("Session").new(nil, "los_angeles", 5)
		T.noThrow(function()
			session:gameOver()
		end)
		T.ok(session.over)
		session:destroy()
	end)

	T.test("animateModelScale does nothing on a part that is not a Model", function()
		local part = SessionUtil.makePart({ Size = Vector3.new(2, 2, 2), Parent = workspace })
		SessionUtil.animateModelScale(part, 0.5, 1, 0.4)
		T.eq(part.Size, Vector3.new(2, 2, 2))
	end)
end
