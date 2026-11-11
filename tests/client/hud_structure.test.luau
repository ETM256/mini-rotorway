return function(T, H)
	-- Méthodes publiques appelées par Main.client.luau et par les tests : elles
	-- doivent rester disponibles après la découpe de HUD.luau.
	local PUBLIC_METHODS = {
		"build",
		"showGame",
		"hide",
		"setState",
		"setTool",
		"setRoundabouts",
		"setSpeed",
		"setSatisfaction",
		"showPause",
		"hidePause",
		"showGameOver",
		"showWeekChoice",
		"hideWeekChoice",
		"hideModals",
		"toast",
		"applyResponsive",
	}

	local PART_MODULES = { "UI/HUDTopBar", "UI/HUDToolbar", "UI/HUDCounters", "UI/HUDOverlays", "UI/HUDResponsive" }

	local function newHud(calls)
		H.asClient()
		local HUD = H.load("HUD")
		local hud = HUD.new({
			onToolChange = function(tool)
				table.insert(calls, "tool:" .. tostring(tool))
			end,
		})
		return hud, H.localPlayer.PlayerGui:FindFirstChild("MM_HUD")
	end

	local function map()
		return H.load("Maps").getById("los_angeles")
	end

	local function state(extra)
		local s = {
			score = 12,
			week = 3,
			weekProgress = 0.4,
			budget = 17,
			bridges = 2,
			roundabouts = 0,
			satisfaction = 80,
			speed = 1,
			over = false,
			roadsBuilt = 9,
		}
		for k, v in pairs(extra or {}) do
			s[k] = v
		end
		return s
	end

	T.test("HUD keeps its public methods after the split into part modules", function()
		local hud = newHud({})
		for _, name in ipairs(PUBLIC_METHODS) do
			T.eq(type(hud[name]), "function", "HUD:" .. name)
		end
	end)

	T.test("each part module is a mixin or a helper module that loads", function()
		for _, name in ipairs(PART_MODULES) do
			T.eq(type(H.load(name)), "function", name .. " should return a mixin function")
		end
		local Icons = H.load("UI/HUDIcons")
		for _, name in ipairs({ "pen", "trash", "roundabout", "road", "pan", "bridge" }) do
			T.eq(type(Icons[name]), "function", "HUDIcons." .. name)
		end
	end)

	T.test("resource chips carry their pictograms", function()
		local hud = newHud({})
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		-- Pictogramme route : conteneur + 3 barres. Pont : conteneur + 2 cercles + barre.
		-- Rond-point : conteneur + anneau + moyeu + 4 branches.
		T.ge(H.count(hud.budgetValue.Parent, "Frame"), 4, "road pictogram in the road chip")
		T.ge(H.count(hud.bridgeValue.Parent, "Frame"), 4, "bridge pictogram in the bridge chip")
		T.ge(H.count(hud.roundaboutValue.Parent, "Frame"), 7, "roundabout pictogram in its chip")
	end)

	T.test("week choice cards carry their pictogram", function()
		local hud = newHud({})
		hud:showGame({ mapId = "los_angeles" }, map())
		local Rewards = H.load("Config").Rewards
		hud:showWeekChoice({ week = 2, options = { Rewards.Roads, Rewards.Roundabout } })
		local cards = {}
		for _, child in ipairs(hud.choiceOptions:GetChildren()) do
			if child:IsA("Frame") then
				table.insert(cards, child)
			end
		end
		T.eq(#cards, 2, "one card per option")
		for _, card in ipairs(cards) do
			T.ge(H.count(card, "Frame"), 5, "the card should hold its pictogram")
		end
	end)

	T.test("the toolbar pill keeps the same portrait rule after a roundabout update", function()
		local hud = newHud({})
		H.setViewport(780, 1000)
		hud:showGame({ mapId = "los_angeles" }, map())
		hud:setState(state({ roundabouts = 1 }))
		H.advance(1)
		-- 780 px de large sur un écran haut : format portrait selon applyResponsive.
		-- Le bandeau est horizontal : sa hauteur est celle de la colonne paysage (58) et
		-- sa longueur couvre les quatre outils (4 x 46 + 3 x 6 + 2 x 6 = 214).
		T.eq(hud.toolPill.Size.Y.Offset, 58, "portrait strip height after setState")
		T.eq(hud.toolPill.Size.X.Offset, 214, "portrait strip length with the roundabout tool")
		H.setViewport(1920, 1080)
		H.advance(1)
		T.eq(hud.toolPill.Size.X.Offset, 58, "landscape pill width")
	end)

	T.test("a click on a tool reports the tool that is really active", function()
		local calls = {}
		local hud = newHud(calls)
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, map())
		H.click(hud.toolButtons.roundabout)
		T.contains(calls, "tool:build")
		for _, call in ipairs(calls) do
			T.falsy(string.find(call, "roundabout", 1, true), "no roundabout tool without roundabouts")
		end
	end)

	T.test("game over and toast tolerate missing values", function()
		local hud = newHud({})
		hud:showGame({ mapId = "los_angeles" }, map())
		T.noThrow(function()
			hud:showGameOver({})
			hud:toast(nil)
		end)
		T.eq(hud.finalScore.Text, "0")
		T.eq(hud.finalBest.Text, "Meilleur : 0")
		T.falsy(string.find(hud.finalWeek.Text, "nil", 1, true), "no 'nil' in the week line")
	end)

	T.test("the hint does not come back on a resize once it expired or the game is over", function()
		local hud = newHud({})
		H.setViewport(1920, 1080)
		hud:showGame({ mapId = "los_angeles" }, map())
		T.ok(hud.hint.Visible, "hint shown at the start")
		H.advance(30)
		T.falsy(hud.hint.Visible, "hint expired after its delay")
		H.setViewport(1600, 900)
		H.advance(1)
		T.falsy(hud.hint.Visible, "a resize does not bring it back")

		hud:showGame({ mapId = "los_angeles" }, map())
		hud:setState(state({ over = true }))
		H.setViewport(1280, 720)
		H.advance(1)
		T.falsy(hud.hint.Visible, "a resize does not show the hint on the game-over screen")
	end)

	T.test("the hint is hidden on a short screen and shown again when the screen grows", function()
		local hud = newHud({})
		H.setViewport(844, 390)
		hud:showGame({ mapId = "los_angeles" }, map())
		H.advance(1)
		T.falsy(hud.hint.Visible, "short screen hides the hint")
		H.setViewport(1920, 1080)
		H.advance(1)
		T.ok(hud.hint.Visible, "the hint is back on a tall screen before it expires")
	end)
end
