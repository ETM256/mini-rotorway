return function(T, H)
	-- Cycle de vie de l'interface : destroy libère tout, sans fuite après de
	-- nombreux affichages, et les délais restés en attente ne touchent plus rien.
	-- Première image du harnais : elle crée ses propres objets (caméra, etc.). On la
	-- joue avant de mesurer, pour ne compter que ce que l'interface crée et libère.
	local function warmUp()
		H.asClient()
		H.setViewport(1366, 768)
		H.advance(1)
	end

	local function newHud(callbacks)
		warmUp()
		return H.load("HUD").new(callbacks or {})
	end

	local function startGame(hud)
		H.setViewport(1366, 768)
		H.advance(1)
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, H.load("Maps").getById("los_angeles"))
	end

	-- Un tour complet d'interface : partie, état, choix, pause, fin de partie, toast.
	local function exerciseEverything(hud)
		startGame(hud)
		hud:setState({ score = 40, budget = 12, bridges = 1, roadsBuilt = 3, satisfaction = 70, speed = 2, roundabouts = 1, over = false })
		hud:showWeekChoice({ week = 2, options = { { id = "a", kind = "roads", title = "Routes", roads = 4 } } })
		hud:showPause()
		hud:hidePause()
		hud:hideWeekChoice()
		hud:showGameOver({ score = 40, best = 10, durationSeconds = 75, stats = { deliveries = 3 } })
		hud:hideModals()
		hud:toast("Bonjour")
		hud:toast("Encore")
	end

	T.test("destroy removes the interface and releases every connection and instance", function()
		local HUD = H.load("HUD")
		warmUp()
		local connectionsBefore = H.connectionCount()
		local instancesBefore = H.instanceCount()
		local hud = HUD.new({})
		exerciseEverything(hud)
		T.ok(H.connectionCount() > connectionsBefore, "the HUD does open connections")
		hud:destroy()
		T.eq(H.connectionCount(), connectionsBefore, "no connection left")
		T.eq(H.instanceCount(), instancesBefore, "no instance left")
		T.falsy(H.localPlayer.PlayerGui:FindFirstChild("MM_HUD"), "the ScreenGui is gone")
	end)

	T.test("destroy is idempotent", function()
		local hud = newHud()
		startGame(hud)
		hud:destroy()
		T.noThrow(function()
			hud:destroy()
		end, "second destroy is harmless")
	end)

	T.test("20 show and destroy cycles leave the instance and connection counts unchanged", function()
		local HUD = H.load("HUD")
		warmUp()
		local connectionsBefore = H.connectionCount()
		local instancesBefore = H.instanceCount()
		for cycle = 1, 20 do
			local hud = HUD.new({})
			exerciseEverything(hud)
			hud:destroy()
			T.eq(H.connectionCount(), connectionsBefore, "connections after cycle " .. cycle)
			T.eq(H.instanceCount(), instancesBefore, "instances after cycle " .. cycle)
		end
	end)

	T.test("timers still pending at destroy stay silent and raise no error", function()
		local hud = newHud()
		startGame(hud)
		hud:toast("Un")
		hud:toast("Deux")
		hud:destroy()
		H.advance(30)
		T.eq(#H.handlerErrors, 0, "no handler error after the timers fire")
	end)

	T.test("a restart builds on a fresh HUD: the previous instance is released by the caller", function()
		local hud = newHud()
		startGame(hud)
		hud:destroy()
		local fresh = newHud()
		startGame(fresh)
		T.ok(fresh.gui.Enabled, "the new HUD shows the game")
		fresh:destroy()
		T.falsy(H.localPlayer.PlayerGui:FindFirstChild("MM_HUD"), "no stale ScreenGui remains")
	end)
end
