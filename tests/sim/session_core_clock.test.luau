return function(T, H)
	local Config = H.load("Config")
	local Time = Config.Time
	local DAY = Config.Game.WeekDuration / Time.DaysPerWeek

	T.test("speed multiplies the simulated clock (1, 2, 3)", function()
		local session = H.newSession("los_angeles")
		session:setSpeed(2)
		for _ = 1, 10 do
			session:update(0.1)
		end
		T.near(session.elapsed, 2, 1e-6)
		session:setSpeed(3)
		for _ = 1, 10 do
			session:update(0.1)
		end
		T.near(session.elapsed, 5, 1e-6)
		session:setSpeed(1)
		for _ = 1, 10 do
			session:update(0.1)
		end
		T.near(session.elapsed, 6, 1e-6)
	end)

	T.test("a large real frame is split into steps and keeps the exact clock", function()
		local session = H.newSession("los_angeles")
		session:setSpeed(3)
		session:update(0.5)
		T.near(session.elapsed, 1.5, 1e-6)
	end)

	T.test("a frame is cut into whole steps, with no stray near-zero step", function()
		local session = H.newSession("los_angeles")
		local steps = 0
		local simulate = session.simulateStep
		session.simulateStep = function(self, step)
			steps += 1
			simulate(self, step)
		end
		session:update(0.7)
		T.eq(steps, 7)
		T.near(session.elapsed, 0.7, 1e-6)
	end)

	T.test("pause freezes the clock and resume continues it", function()
		local session = H.newSession("los_angeles")
		session:update(1)
		session:setPaused(true)
		local frozen = session.elapsed
		for _ = 1, 5 do
			session:update(1)
		end
		T.eq(session.elapsed, frozen)
		T.ok(H.lastSent("State").paused)
		session:setPaused(false)
		session:update(1)
		T.near(session.elapsed, frozen + 1, 1e-6)
	end)

	T.test("setSpeed only accepts the integers 1..3, anything else is ignored", function()
		local session = H.newSession("los_angeles")
		session:setSpeed(2)
		local junk = { 2.5, "3", 0, 4, -1, 0 / 0, math.huge, true }
		for _, value in ipairs(junk) do
			session:setSpeed(value)
			T.eq(session.speed, 2, "junk " .. tostring(value))
		end
		session:setSpeed(nil)
		T.eq(session.speed, 2)
		T.eq(H.lastSent("State").speed, 2)
	end)

	T.test("setPaused only accepts booleans", function()
		local session = H.newSession("los_angeles")
		session:setPaused("true")
		session:setPaused(1)
		session:setPaused(nil)
		T.falsy(session.paused)
		session:setPaused(true)
		T.ok(session.paused)
		session:setPaused("false")
		T.ok(session.paused)
	end)

	T.test("setSpeed and setPaused are ignored once the game is over", function()
		local session = H.newSession("los_angeles")
		session:gameOver()
		session:setSpeed(2)
		session:setPaused(true)
		T.eq(session.speed, 1)
		T.falsy(session.paused)
	end)

	T.test("day, weekday, month and month name follow the simulated time", function()
		local session = H.newSession("los_angeles")
		session.elapsed = 0
		session:updateClock()
		T.eq(session.day, 1)
		T.eq(session.dayOfWeek, 1)
		T.eq(session.week, 1)
		T.eq(session.month, 1)
		T.eq(session.monthName, Time.MonthNames[1])
		T.near(session.dayProgress, 0, 1e-9)

		session.elapsed = DAY * 1.5
		session:updateClock()
		T.eq(session.day, 2)
		T.eq(session.dayOfWeek, 2)
		T.near(session.dayProgress, 0.5, 1e-6)

		-- Fin de semaine 1 : le 7e jour se termine, la semaine 2 commence.
		session.elapsed = Config.Game.WeekDuration - 0.01
		session:updateClock()
		T.eq(session.week, 1)
		T.eq(session.dayOfWeek, 7)

		session.elapsed = Config.Game.WeekDuration
		session:updateClock()
		T.eq(session.week, 2)
		T.eq(session.day, 8)
		T.eq(session.dayOfWeek, 1)
		T.eq(session.monthWeek, 2)
		T.eq(session.month, 1)
	end)

	T.test("months roll over every four weeks and wrap after twelve", function()
		local session = H.newSession("los_angeles")
		local monthLength = Config.Game.WeekDuration * Time.WeeksPerMonth

		session.elapsed = monthLength - 0.01
		session:updateClock()
		T.eq(session.month, 1)
		T.eq(session.monthWeek, 4)
		T.eq(session.week, 4)

		session.elapsed = monthLength
		session:updateClock()
		T.eq(session.month, 2)
		T.eq(session.monthName, Time.MonthNames[2])
		T.eq(session.week, 5)
		T.eq(session.monthWeek, 1)
		T.near(session.monthProgress, 0, 1e-9)

		session.elapsed = 12 * monthLength
		session:updateClock()
		T.eq(session.month, 13)
		T.eq(session.monthName, Time.MonthNames[1])
	end)

	T.test("the first week ends after WeekDuration and opens exactly one choice", function()
		local session = H.newSession("los_angeles")
		H.runSession(session, Config.Game.WeekDuration + 1, 0.1, { autoChoose = false })
		T.ok(session.awaitingChoice)
		T.ok(session.paused)
		T.eq(session.week, 2)
		T.near(session.elapsed, Config.Game.WeekDuration, 0.2)
		T.eq(#H.sent("WeekChoice"), 1)

		local frozen = session.elapsed
		session:update(5)
		T.eq(session.elapsed, frozen)

		session:chooseReward(session.choice.options[1].id)
		session:update(1)
		T.near(session.elapsed, frozen + 1, 1e-6)
	end)

	T.test("State carries the day and month fields the HUD needs", function()
		H.newSession("los_angeles")
		local state = H.lastSent("State")
		T.eq(state.day, 1)
		T.eq(state.dayOfWeek, 1)
		T.eq(state.week, 1)
		T.eq(state.month, 1)
		T.eq(state.monthName, Time.MonthNames[1])
		T.eq(state.monthWeek, 1)
		T.near(state.dayProgress, 0, 1e-9)
		T.near(state.monthProgress, 0, 1e-9)
		T.near(state.weekProgress, 0, 1e-9)
	end)

	T.test("State is sent at 5 Hz of real time even at speed 3", function()
		local session = H.newSession("los_angeles")
		session:setSpeed(3)
		H.clearRemoteLog()
		local frames = 600
		for _ = 1, frames do
			session:update(1 / 60)
		end
		T.near(session.elapsed, 30, 1e-6)
		local sent = #H.sent("State")
		T.ok(sent <= 10 * 5 + 1, "State sent " .. sent .. " times in 10 s")
		T.ok(sent >= 40, "State sent only " .. sent .. " times in 10 s")
	end)

	T.test("an unchanged state is not sent again", function()
		local session = H.newSession("los_angeles")
		session:sendState()
		H.clearRemoteLog()
		session:sendState()
		session:sendState()
		T.eq(#H.sent("State"), 0)
		session:setPaused(true)
		T.eq(#H.sent("State"), 1)
	end)
end
