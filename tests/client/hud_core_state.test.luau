return function(T, H)
	-- Diffusion de l'état serveur : chaque module n'est mis à jour que si un de ses
	-- champs a changé depuis le dernier état reçu.
	local MODULE_METHODS = { "setCalendar", "updateCounters", "setRoundabouts", "setSatisfaction", "setSpeed" }

	local function newHud()
		H.asClient()
		local hud = H.load("HUD").new({})
		H.setViewport(1366, 768)
		H.advance(1)
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, H.load("Maps").getById("los_angeles"))
		return hud
	end

	-- Compte les appels aux méthodes de mise à jour, sans changer leur comportement.
	local function spyOn(hud)
		local calls = {}
		for _, name in ipairs(MODULE_METHODS) do
			calls[name] = 0
			local original = hud[name]
			hud[name] = function(self, ...)
				calls[name] += 1
				return original(self, ...)
			end
		end
		return calls
	end

	local function payload(overrides)
		local state = {
			score = 0,
			week = 1,
			weekProgress = 0,
			day = 1,
			dayOfWeek = 1,
			dayProgress = 0,
			month = 1,
			monthName = "Janvier",
			monthWeek = 1,
			monthProgress = 0,
			budget = 20,
			bridges = 0,
			roundabouts = 0,
			satisfaction = 100,
			speed = 1,
			roadsBuilt = 0,
		}
		for key, value in pairs(overrides or {}) do
			state[key] = value
		end
		return state
	end

	local function totalCalls(calls)
		local total = 0
		for _, count in pairs(calls) do
			total += count
		end
		return total
	end

	T.test("the first state of a game updates every module once", function()
		local hud = newHud()
		local calls = spyOn(hud)
		hud:setState(payload())
		for _, name in ipairs(MODULE_METHODS) do
			T.eq(calls[name], 1, name .. " called once")
		end
	end)

	T.test("an identical state changes nothing", function()
		local hud = newHud()
		hud:setState(payload())
		local calls = spyOn(hud)
		hud:setState(payload())
		T.eq(totalCalls(calls), 0, "no module is refreshed")
	end)

	T.test("a budget change refreshes the counters and nothing else", function()
		local hud = newHud()
		hud:setState(payload())
		local calls = spyOn(hud)
		hud:setState(payload({ budget = 19 }))
		T.eq(calls.updateCounters, 1, "counters refreshed")
		T.eq(calls.setCalendar + calls.setRoundabouts + calls.setSatisfaction + calls.setSpeed, 0, "other modules untouched")
		T.eq(hud.budgetValue.Text, "19", "the budget shows the new value")
	end)

	T.test("a satisfaction change refreshes the gauge and nothing else", function()
		local hud = newHud()
		hud:setState(payload())
		local calls = spyOn(hud)
		hud:setState(payload({ satisfaction = 60 }))
		T.eq(calls.setSatisfaction, 1, "gauge refreshed")
		T.eq(calls.updateCounters + calls.setCalendar + calls.setRoundabouts + calls.setSpeed, 0, "other modules untouched")
		T.eq(hud.satisfactionText.Text, "60%", "the gauge shows the new value")
	end)

	T.test("a score change only rewrites the score label", function()
		local hud = newHud()
		hud:setState(payload())
		local calls = spyOn(hud)
		hud:setState(payload({ score = 120 }))
		T.eq(totalCalls(calls), 0, "no module is refreshed")
		T.eq(hud.scoreValue.Text, "120", "the score shows the new value")
	end)

	T.test("a missing field falls back to its default once, then is not rewritten", function()
		local hud = newHud()
		hud:setState(payload())
		local calls = spyOn(hud)
		-- payload(...) ne peut pas effacer un champ (pairs ignore les nil) : on le retire ici.
		local missing = payload()
		missing.satisfaction = nil
		hud:setState(missing)
		T.eq(calls.setSatisfaction, 1, "the gauge is refreshed when the field disappears")
		T.eq(hud.satisfactionText.Text, "0%", "a missing satisfaction reads as 0")
		hud:setState(missing)
		T.eq(calls.setSatisfaction, 1, "a missing field that stays missing is not rewritten")
	end)

	T.test("a new game re-applies every module on its first state", function()
		local hud = newHud()
		hud:setState(payload({ budget = 7 }))
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, H.load("Maps").getById("los_angeles"))
		local calls = spyOn(hud)
		hud:setState(payload({ budget = 7 }))
		for _, name in ipairs(MODULE_METHODS) do
			T.eq(calls[name], 1, name .. " re-applied for the new game")
		end
		T.eq(hud.budgetValue.Text, "7", "the counters show the new game's budget")
	end)

	T.test("a missing state is ignored and a destroyed HUD ignores every state", function()
		local hud = newHud()
		hud:setState(payload())
		local calls = spyOn(hud)
		hud:setState(nil)
		T.eq(totalCalls(calls), 0, "nil state does nothing")
		hud:destroy()
		hud:setState(payload({ budget = 3, satisfaction = 10 }))
		T.eq(totalCalls(calls), 0, "destroyed HUD does nothing")
	end)

	T.test("the help line follows the settings when a new game starts", function()
		local hud = newHud()
		hud.settings.hints = false
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, H.load("Maps").getById("los_angeles"))
		T.falsy(hud.hint.Visible, "hints off: no help line on a new game")
		hud.settings.hints = true
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, H.load("Maps").getById("los_angeles"))
		T.ok(hud.hint.Visible, "hints on: the help line is back")
	end)
end
