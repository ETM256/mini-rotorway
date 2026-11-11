return function(T, H)
	-- Hygiène du HUD : jetons de couleur, durées d'animation, nettoyage à la destruction.

	local function hudSources()
		local list = {}
		for _, source in ipairs(H.sources()) do
			if string.find(source.file, "UI/HUD", 1, true) then
				table.insert(list, { file = source.file, code = H.stripComments(source.source) })
			end
		end
		return list
	end

	local function newHud(callbacks)
		H.asClient()
		return H.load("HUD").new(callbacks or {})
	end

	local function map()
		return H.load("Maps").getById("los_angeles")
	end

	T.test("the HUD modules know every colour by its Theme token, never by a hex or RGB literal", function()
		local sources = hudSources()
		T.ge(#sources, 7, "the HUD modules are found")
		for _, source in ipairs(sources) do
			T.falsy(string.find(source.code, "fromHex", 1, true), source.file .. " uses an inline hex")
			T.falsy(string.find(source.code, "Color3.fromRGB", 1, true), source.file .. " uses an inline RGB")
			T.falsy(string.find(source.code, "Color3.new", 1, true), source.file .. " uses an inline Color3")
		end
	end)

	T.test("the bridge colour is a Theme token fed by the central palette", function()
		local Theme = H.load("UI/Theme")
		local Config = H.load("Config")
		T.eq(Theme.Bridge, Config.Colors.BridgeChip)
	end)

	T.test("no HUD module creates its own tween: every animation goes through Theme (0.24 s at most)", function()
		for _, source in ipairs(hudSources()) do
			T.falsy(string.find(source.code, "TweenService", 1, true), source.file .. " bypasses Theme.tween")
		end
		local Theme = H.load("UI/Theme")
		T.le(Theme.Motion.Fast, 0.24)
		T.le(Theme.Motion.Standard, 0.24)
	end)

	T.test("the ScreenGui keeps its hygiene settings", function()
		local hud = newHud()
		T.eq(hud.gui.ResetOnSpawn, false)
		T.eq(hud.gui.ZIndexBehavior, Enum.ZIndexBehavior.Sibling)
		T.eq(hud.gui.IgnoreGuiInset, true, "full-screen view, same origin as the camera viewport")
		T.eq(hud.gui.DisplayOrder, 30)
	end)

	T.test("destroy cancels the help timer and the toast timer", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles" }, map())
		hud:toast("Un")
		T.ok(hud.hintTimer, "the help timer is pending")
		T.ok(hud.toastTimer, "the toast timer is pending")
		hud:destroy()
		T.eq(hud.hintTimer, nil, "help timer cancelled")
		T.eq(hud.toastTimer, nil, "toast timer cancelled")
		H.advance(40)
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("destroy stops the in-flight tweens of the top bar", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles" }, map())
		hud:setState({ score = 1, week = 2, monthProgress = 0.7, satisfaction = 40, speed = 2, paused = true })
		local fill = hud.monthFill
		hud:destroy()
		H.advance(1)
		-- Le tween annulé ne s'applique pas : la ligne garde sa taille d'avant.
		T.eq(fill.Size.X.Scale, 0, "the cancelled tween did not finish")
	end)

	T.test("a new game clears the toasts of the previous one", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles" }, map())
		hud:toast("Ancien")
		hud:showGame({ mapId = "los_angeles" }, map())
		T.falsy(hud.toastLabel.Visible, "no stale toast")
		T.eq(#hud.toastQueue, 0)
		T.eq(hud.toastTimer, nil)
	end)

	T.test("a toast sent after destroy is ignored and leaves no timer", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles" }, map())
		hud:destroy()
		hud:toast("Tard")
		T.eq(hud.toastTimer, nil, "no timer after destroy")
		T.eq(#hud.toastQueue, 0, "nothing queued after destroy")
	end)

	T.test("the pause menu marks the top bar as paused and clears it on resume", function()
		local hud = newHud({})
		hud:showGame({ mapId = "los_angeles" }, map())
		hud:showPause()
		T.ok(hud.paused, "paused while the menu is open")
		hud:hidePause()
		T.falsy(hud.paused, "running after the resume")
	end)

	T.test("a repeated payload touches no counter label", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles" }, map())
		local payload = { score = 3, budget = 20, bridges = 1, houses = 4, destinations = 2, roundabouts = 0, satisfaction = 100, speed = 1 }
		hud:setState(payload)
		local writes = 0
		local watched = { hud.budgetValue, hud.bridgeValue, hud.houseValue, hud.storeValue, hud.scoreValue }
		local connections = {}
		for _, label in ipairs(watched) do
			table.insert(connections, label:GetPropertyChangedSignal("Text"):Connect(function()
				writes += 1
			end))
		end
		hud:setState(payload)
		hud:setState({ score = 3, budget = 20, bridges = 1, houses = 5, destinations = 2, roundabouts = 0, satisfaction = 100, speed = 1 })
		T.eq(writes, 1, "only the house counter changed")
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end)
end
