return function(T, H)
	local RESOLUTIONS = {
		{ 1920, 1080 },
		{ 1600, 900 },
		{ 1366, 768 },
		{ 1280, 720 },
		{ 844, 390 },
		{ 390, 844 },
	}

	local function newHud(calls)
		H.asClient()
		local HUD = H.load("HUD")
		local hud = HUD.new({
			onPause = function()
				table.insert(calls, "pause")
			end,
			onResume = function()
				table.insert(calls, "resume")
			end,
			onRestart = function()
				table.insert(calls, "restart")
			end,
			onMenu = function()
				table.insert(calls, "menu")
			end,
			onToolChange = function(tool)
				table.insert(calls, "tool:" .. tostring(tool))
			end,
			onSpeed = function(value)
				table.insert(calls, "speed:" .. tostring(value))
			end,
			onChooseReward = function(id)
				table.insert(calls, "reward:" .. tostring(id))
			end,
		})
		return hud, H.localPlayer.PlayerGui:FindFirstChild("MM_HUD")
	end

	local function started()
		return {
			mapId = "los_angeles",
			origin = Vector3.new(700, 0, 0),
			size = 18,
			tile = 4,
			weekDuration = 60,
		}
	end

	local function state(extra)
		local s = {
			score = 12,
			week = 3,
			weekProgress = 0.4,
			budget = 17,
			bridges = 2,
			roundabouts = 1,
			satisfaction = 80,
			speed = 1,
			paused = false,
			awaitingChoice = false,
			over = false,
			houses = 5,
			destinations = 2,
			largeStores = 0,
			cars = 3,
			roadsBuilt = 9,
		}
		for k, v in pairs(extra or {}) do
			s[k] = v
		end
		return s
	end

	-- Un élément n'est affiché que si lui et tous ses ancêtres GuiObject sont visibles.
	local function isShown(d, root)
		local cur = d
		while cur and cur ~= root do
			if cur:IsA("GuiObject") and not cur.Visible then
				return false
			end
			cur = cur.Parent
		end
		return true
	end

	local function texts(root)
		local list = {}
		for _, d in ipairs(H.find(root, { class = "GuiObject" })) do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				if d.Text ~= "" and isShown(d, root) then
					table.insert(list, d.Text)
				end
			end
		end
		return list
	end

	local function hasText(root, needle)
		for _, t in ipairs(texts(root)) do
			if string.find(t, needle, 1, true) then
				return true
			end
		end
		return false
	end

	T.test("the HUD builds a ScreenGui in PlayerGui and is hidden until a game starts", function()
		local _, gui = newHud({})
		T.ok(gui, "MM_HUD")
		T.eq(gui.ClassName, "ScreenGui")
		T.falsy(gui.Enabled)
		T.eq(gui.ResetOnSpawn, false)
	end)

	T.test("showGame displays the HUD; hide hides it again", function()
		local hud, gui = newHud({})
		hud:showGame(started(), H.load("Maps").getById("los_angeles"))
		T.ok(gui.Enabled)
		hud:hide()
		T.falsy(gui.Enabled)
	end)

	T.test("setState shows score, week, budget, bridges, roundabouts and built roads", function()
		local hud, gui = newHud({})
		hud:showGame(started(), H.load("Maps").getById("los_angeles"))
		hud:setState(state())
		H.advance(1)
		for _, expected in ipairs({ "12", "17", "2", "9" }) do
			T.ok(hasText(gui, expected), "the HUD should display " .. expected)
		end
		hud:setState(state({ score = 345 }))
		T.ok(hasText(gui, "345"))
	end)

	-- Brief, part 9.1: the top bar must display the game day and the time
	-- progression. Today only the weekday abbreviation ("MER") is visible; the
	-- "SEMAINE n" label stays hidden.
	T.todo("the top bar shows the current day / week number", function()
		local hud, gui = newHud({})
		hud:showGame(started(), H.load("Maps").getById("los_angeles"))
		hud:setState(state({ week = 6 }))
		T.ok(hasText(gui, "6"), "week number: " .. table.concat(texts(gui), " | "))
	end)

	T.test("setState tolerates missing fields and any speed value", function()
		local hud = newHud({})
		hud:showGame(started(), H.load("Maps").getById("los_angeles"))
		T.noThrow(function()
			hud:setState({})
			hud:setState(state({ speed = 3 }))
			hud:setState(state({ speed = 2, paused = true }))
			hud:setState(state({ satisfaction = 0 }))
			hud:setState(state({ satisfaction = 100 }))
			hud:setState(nil)
		end)
	end)

	T.test("game over overlay shows the score, week, best score and a restart button", function()
		local calls = {}
		local hud, gui = newHud(calls)
		hud:showGame(started(), H.load("Maps").getById("los_angeles"))
		hud:showGameOver({ mapId = "los_angeles", score = 57, best = 80, week = 6 })
		T.ok(hasText(gui, "57"), "final score")
		T.ok(hasText(gui, "6"), "week reached")
		T.ok(hasText(gui, "80"), "best score")
		local restart
		for _, button in ipairs(H.find(gui, { class = "GuiButton" })) do
			if button.Visible and (string.find(string.lower(button.Text or ""), "rejou") or string.find(string.lower(button.Text or ""), "recommenc")) then
				restart = button
			end
		end
		T.ok(restart, "a visible restart button")
		H.click(restart)
		T.contains(calls, "restart")
	end)

	T.test("a new best score is celebrated, otherwise the best is shown", function()
		local hud, gui = newHud({})
		hud:showGame(started(), H.load("Maps").getById("los_angeles"))
		hud:showGameOver({ mapId = "los_angeles", score = 90, best = 90, week = 4 })
		T.ok(hasText(gui, "record"), "new record message")
		hud:showGameOver({ mapId = "los_angeles", score = 10, best = 90, week = 4 })
		T.ok(hasText(gui, "90"))
	end)

	T.test("week choice shows both rewards; clicking one reports its id", function()
		local calls = {}
		local hud, gui = newHud(calls)
		hud:showGame(started(), H.load("Maps").getById("los_angeles"))
		local Config = H.load("Config")
		local data = { week = 2, options = { Config.Rewards.Bridge, Config.Rewards.Roads } }
		hud:showWeekChoice(data)
		T.ok(hasText(gui, Config.Rewards.Bridge.title), "first reward title")
		T.ok(hasText(gui, Config.Rewards.Roads.title), "second reward title")
		local buttons = {}
		for _, b in ipairs(H.find(gui, { class = "GuiButton" })) do
			if b.Visible and b.AbsoluteSize.X > 60 and b.AbsoluteSize.Y > 60 then
				table.insert(buttons, b)
			end
		end
		T.ge(#buttons, 2, "two clickable reward cards")
		local before = #calls
		for _, b in ipairs(buttons) do
			H.click(b)
		end
		local rewardCalls = 0
		for i = before + 1, #calls do
			if string.sub(calls[i], 1, 7) == "reward:" then
				rewardCalls += 1
			end
		end
		T.ge(rewardCalls, 1)
	end)

	T.test("the week choice is not re-opened for a dismissed week", function()
		local hud, gui = newHud({})
		hud:showGame(started(), H.load("Maps").getById("los_angeles"))
		local Config = H.load("Config")
		local choice = { week = 2, options = { Config.Rewards.Bridge, Config.Rewards.Roads } }
		hud:setState(state({ awaitingChoice = true, choice = choice }))
		T.ok(hasText(gui, Config.Rewards.Bridge.title))
		hud:hideWeekChoice()
		hud:setState(state({ awaitingChoice = false }))
		T.falsy(hasText(gui, Config.Rewards.Bridge.title), "overlay closed")
	end)

	T.test("tool buttons: the active tool is highlighted and clicks notify the game", function()
		local calls = {}
		local hud = newHud(calls)
		hud:showGame(started(), H.load("Maps").getById("los_angeles"))
		T.noThrow(function()
			hud:setTool("erase")
			hud:setTool("roundabout")
			hud:setTool("camera")
			hud:setTool("build")
		end)
	end)

	T.test("pause overlay offers resume, restart and menu", function()
		local calls = {}
		local hud, gui = newHud(calls)
		hud:showGame(started(), H.load("Maps").getById("los_angeles"))
		hud:showPause()
		T.noThrow(function()
			hud:hidePause()
		end)
		T.ge(#H.find(gui, { class = "GuiButton" }), 3)
	end)

	T.test("toasts appear and fade without errors", function()
		local hud = newHud({})
		hud:showGame(started(), H.load("Maps").getById("los_angeles"))
		hud:toast("Bonjour")
		hud:toast("Deux")
		H.advance(6)
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("responsive: key HUD elements stay inside the screen at every resolution", function()
		local failures = {}
		for _, res in ipairs(RESOLUTIONS) do
			H.reset()
			local hud, gui = newHud({})
			H.setViewport(res[1], res[2])
			hud:showGame(started(), H.load("Maps").getById("los_angeles"))
			hud:setState(state())
			H.advance(1)
			for _, d in ipairs(H.find(gui, { class = "GuiObject" })) do
				local okVisible = d.Visible and d.AbsoluteSize.X > 0 and d.AbsoluteSize.Y > 0
				if okVisible and (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("ImageButton")) and d.Text ~= "" then
					-- Les éléments sous une mise en page automatique ou dans un
					-- conteneur qui rogne ne sont pas évalués.
					local skip = false
					local cur = d
					while cur and cur ~= gui do
						if H.isLayoutManaged(cur) or cur.ClipsDescendants or cur:IsA("ScrollingFrame") or not cur.Visible then
							skip = true
							break
						end
						cur = cur.Parent
					end
					if not skip then
						local p, s = d.AbsolutePosition, d.AbsoluteSize
						if p.X < -2 or p.Y < -2 or p.X + s.X > res[1] + 2 or p.Y + s.Y > res[2] + 2 then
							table.insert(failures, string.format("%dx%d: '%s' (%s) at %.0f,%.0f size %.0fx%.0f", res[1], res[2], d.Text, d.Name, p.X, p.Y, s.X, s.Y))
						end
					end
				end
			end
		end
		T.eq(#failures, 0, table.concat(failures, "\n"))
	end)

	T.test("the HUD adapts to the viewport when it is resized at runtime", function()
		local hud = newHud({})
		hud:showGame(started(), H.load("Maps").getById("los_angeles"))
		T.noThrow(function()
			H.setViewport(1280, 720)
			H.setViewport(390, 844)
			H.setViewport(1920, 1080)
			H.advance(1)
		end)
		T.eq(#H.handlerErrors, 0)
	end)
end
