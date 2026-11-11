return function(T, H)
	-- Couches modales de HUDOverlays : menu pause, réglages, fin de partie et
	-- choix hebdomadaire. Les tests passent par l'arbre d'interface et les
	-- callbacks, comme le joueur.
	local function newHud(calls, extra)
		H.asClient()
		local HUD = H.load("HUD")
		local callbacks = {
			onResume = function()
				table.insert(calls, "resume")
			end,
			onRestart = function()
				table.insert(calls, "restart")
			end,
			onMenu = function()
				table.insert(calls, "menu")
			end,
			onChooseReward = function(id)
				table.insert(calls, "reward:" .. tostring(id))
			end,
			onSetting = function(name, value)
				table.insert(calls, "setting:" .. name .. "=" .. tostring(value))
			end,
		}
		for key, value in pairs(extra or {}) do
			callbacks[key] = value
		end
		local hud = HUD.new(callbacks)
		return hud, H.localPlayer.PlayerGui:FindFirstChild("MM_HUD")
	end

	local function started(hud)
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, H.load("Maps").getById("los_angeles"))
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

	local function hasText(root, needle)
		for _, d in ipairs(H.find(root, { class = "GuiObject" })) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and isShown(d, root) then
				if string.find(d.Text, needle, 1, true) then
					return true
				end
			end
		end
		return false
	end

	-- Bouton affiché dont le texte est exactement celui demandé.
	local function buttonNamed(root, text)
		for _, d in ipairs(H.find(root, { class = "GuiButton" })) do
			if d.Text == text and isShown(d, root) then
				return d
			end
		end
		return nil
	end

	-- Ligne cliquable (sans texte propre) qui contient le libellé demandé.
	local function rowNamed(root, label)
		for _, button in ipairs(H.find(root, { class = "GuiButton" })) do
			for _, d in ipairs(H.find(button, { class = "TextLabel" })) do
				if d.Text == label and isShown(d, root) then
					return button
				end
			end
		end
		return nil
	end

	-- Zones cliquables des cartes d'amélioration : boutons sans texte, visibles.
	local function choiceHits(root)
		local hits = {}
		for _, d in ipairs(H.find(root, { class = "GuiButton" })) do
			if d.Text == "" and isShown(d, root) and d.AbsoluteSize.X > 60 and d.AbsoluteSize.Y > 60 then
				table.insert(hits, d)
			end
		end
		return hits
	end

	local function countLabels(root, labels)
		local n = 0
		for _, d in ipairs(H.find(root, { class = "TextLabel" })) do
			if labels[d.Text] and isShown(d, root) then
				n += 1
			end
		end
		return n
	end

	local ALL_STAT_LABELS = {
		["Trajets livrés"] = true,
		["Demandes servies"] = true,
		["Magasins ouverts"] = true,
		["Maisons apparues"] = true,
		["Routes posées"] = true,
		["Semaines terminées"] = true,
	}

	local function countCount(list, value)
		local n = 0
		for _, item in ipairs(list) do
			if item == value then
				n += 1
			end
		end
		return n
	end

	local function choiceData(week)
		local Config = H.load("Config")
		return { week = week, options = { Config.Rewards.Bridge, Config.Rewards.Roads } }
	end

	-- Durée : mm:ss, minutes non bornées, et valeurs absentes ou invalides.
	T.test("the game over duration is formatted mm:ss", function()
		local cases = {
			{ 0, "00:00" },
			{ 59, "00:59" },
			{ 61, "01:01" },
			{ 3600, "60:00" },
			{ 3725, "62:05" },
		}
		local hud, gui = newHud({})
		started(hud)
		for _, case in ipairs(cases) do
			hud:showGameOver({ score = 1, best = 0, durationSeconds = case[1] })
			T.ok(hasText(gui, "Durée " .. case[2]), "duration " .. tostring(case[1]) .. " should read " .. case[2])
		end
		hud:showGameOver({ score = 1 })
		T.ok(hasText(gui, "Durée 00:00"), "a missing duration reads as zero")
	end)

	T.test("a score at or above the best is marked as a new record", function()
		local hud, gui = newHud({})
		started(hud)
		hud:showGameOver({ score = 90, best = 90, week = 4 })
		T.ok(hasText(gui, "Nouveau record"), "record mark when score equals best")
		hud:showGameOver({ score = 10, best = 90, week = 4 })
		T.falsy(hasText(gui, "Nouveau record"), "no record mark below best")
		T.ok(hasText(gui, "Meilleur : 90"), "the best score is shown instead")
		hud:showGameOver({ score = 0, best = 0 })
		T.falsy(hasText(gui, "Nouveau record"), "a zero score is never a record")
	end)

	T.test("the score is formatted with thousands separators", function()
		local hud, gui = newHud({})
		started(hud)
		hud:showGameOver({ score = 1234567, best = 2000000 })
		T.ok(hasText(gui, "1 234 567"), "large score grouped")
		T.ok(hasText(gui, "Meilleur : 2 000 000"), "best grouped")
	end)

	T.test("only the statistics that exist in the payload get a row", function()
		local hud, gui = newHud({})
		started(hud)
		hud:showGameOver({
			score = 5,
			best = 9,
			stats = { deliveries = 12, demandsServed = 5, roadsBuilt = 30, stuckSeconds = 4 },
		})
		T.eq(countLabels(gui, ALL_STAT_LABELS), 3, "three main statistics present")
		T.ok(hasText(gui, "Trajets livrés"))
		T.ok(hasText(gui, "30"), "the road count is shown")
		T.falsy(hasText(gui, "Magasins ouverts"), "absent statistic has no row")

		hud:showGameOver({ score = 5, best = 9 })
		T.eq(countLabels(gui, ALL_STAT_LABELS), 0, "no stats table means no rows")
	end)

	T.test("the end reason is written as a readable French sentence", function()
		local hud, gui = newHud({})
		started(hud)
		hud:showGameOver({ score = 5, best = 9, reason = "overload", overload = { colorName = "Corail" } })
		T.ok(hasText(gui, "Le magasin Corail est resté trop longtemps surchargé."))
		hud:showGameOver({ score = 5, best = 9, reason = "overload" })
		T.ok(hasText(gui, "Un magasin est resté trop longtemps surchargé."))
		hud:showGameOver({ score = 5, best = 9, reason = "traffic" })
		T.ok(hasText(gui, "bloquées"))
		hud:showGameOver({ score = 5, best = 9, reason = "unknown_code" })
		T.falsy(hasText(gui, "unknown_code"), "an unknown reason is not printed raw")
	end)

	T.test("malformed game over payloads do not throw", function()
		local hud, gui = newHud({})
		started(hud)
		T.noThrow(function()
			hud:showGameOver(nil)
			hud:showGameOver({ score = "x", best = {}, stats = "bad", durationSeconds = 0 / 0 })
			hud:showGameOver({ score = -3, best = 0 / 0, week = "two", overload = "nope" })
		end)
		T.ok(hasText(gui, "Partie terminée"), "the game over card is still shown")
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("the pause menu opens and closes, and shows its four actions", function()
		local hud, gui = newHud({})
		started(hud)
		hud:showPause()
		T.ok(buttonNamed(gui, "Reprendre"), "resume button")
		T.ok(buttonNamed(gui, "Recommencer"), "restart button")
		T.ok(buttonNamed(gui, "Paramètres"), "settings button")
		T.ok(buttonNamed(gui, "Menu principal"), "main menu button")
		hud:hidePause()
		T.falsy(buttonNamed(gui, "Reprendre"), "closed menu hides its buttons")
	end)

	T.test("the restart button is hidden when no restart callback is wired", function()
		local hud, gui = newHud({}, { onRestart = false })
		started(hud)
		hud:showPause()
		T.falsy(buttonNamed(gui, "Recommencer"), "no onRestart, no restart button")
		T.ok(buttonNamed(gui, "Reprendre"), "the other buttons remain")
	end)

	T.test("each pause action fires its callback exactly once", function()
		local calls = {}
		local hud, gui = newHud(calls)
		started(hud)
		hud:showPause()
		local resume = buttonNamed(gui, "Reprendre")
		H.click(resume)
		H.advance(0.2)
		H.click(resume)
		T.eq(countCount(calls, "resume"), 1, "resume fired once, a stray second click is ignored")

		hud:showPause()
		H.click(buttonNamed(gui, "Recommencer"))
		T.eq(countCount(calls, "restart"), 1, "restart fired once")

		hud:showPause()
		H.click(buttonNamed(gui, "Menu principal"))
		T.eq(countCount(calls, "menu"), 1, "menu fired once")
		T.falsy(buttonNamed(gui, "Menu principal"), "menu closes the pause overlay")
	end)

	T.test("Escape closes the pause menu, and from settings it goes back first", function()
		local calls = {}
		local hud, gui = newHud(calls)
		started(hud)
		hud:showPause()
		H.click(buttonNamed(gui, "Paramètres"))
		H.input.key("Escape", true)
		H.input.key("Escape", false)
		T.eq(countCount(calls, "resume"), 0, "first Escape only leaves the settings page")
		T.ok(buttonNamed(gui, "Reprendre"), "the main pause page is back")

		H.input.key("Escape", true)
		H.input.key("Escape", false)
		T.eq(countCount(calls, "resume"), 1, "second Escape resumes once")
		T.falsy(buttonNamed(gui, "Reprendre"), "the pause menu is closed")
	end)

	T.test("the settings page toggles grid and hints, and reports each change", function()
		local calls = {}
		local hud, gui = newHud(calls)
		started(hud)
		hud:showPause()
		H.click(buttonNamed(gui, "Paramètres"))
		local hints = rowNamed(gui, "Astuces")
		T.ok(hints, "hints row")
		H.click(hints)
		T.contains(calls, "setting:hints=false")
		H.advance(0.2)
		H.click(hints)
		T.contains(calls, "setting:hints=true")
		H.click(rowNamed(gui, "Grille visible"))
		T.contains(calls, "setting:grid=true", "the grid starts on its automatic rule: the first toggle pins it")
		T.eq(countCount(calls, "setting:hints=false"), 1, "each change reported once")
	end)

	T.test("settings keep their value when the pause menu is reopened", function()
		local calls = {}
		local hud, gui = newHud(calls)
		started(hud)
		hud:showPause()
		H.click(buttonNamed(gui, "Paramètres"))
		H.click(rowNamed(gui, "Astuces"))
		hud:hidePause()
		H.advance(0.2)
		hud:showPause()
		H.click(buttonNamed(gui, "Paramètres"))
		H.click(rowNamed(gui, "Astuces"))
		T.contains(calls, "setting:hints=true", "second toggle goes back to on, from the stored value")
	end)

	T.test("the game over screen offers restart and menu, each once", function()
		local calls = {}
		local hud, gui = newHud(calls)
		started(hud)
		hud:showGameOver({ score = 57, best = 80, week = 6 })
		T.ok(hasText(gui, "Partie terminée"))
		H.click(buttonNamed(gui, "Rejouer"))
		T.eq(countCount(calls, "restart"), 1, "restart fired once")
		T.ok(buttonNamed(gui, "Rejouer"), "the end card stays until the new game starts")
		hud:showGameOver({ score = 57, best = 80, week = 6 })
		H.click(buttonNamed(gui, "Menu principal"))
		T.eq(countCount(calls, "menu"), 1, "menu fired once")
	end)

	T.test("a restart closes the pause menu only when the new game starts", function()
		local calls = {}
		local hud, gui = newHud(calls)
		started(hud)
		hud:showPause()
		H.click(buttonNamed(gui, "Recommencer"))
		T.eq(countCount(calls, "restart"), 1, "restart requested once")
		T.ok(buttonNamed(gui, "Reprendre"), "the server has not answered: the menu stays open to retry")
		started(hud)
		T.falsy(buttonNamed(gui, "Reprendre"), "the new game closes the menu")
	end)

	T.test("a week choice shows its cards, and clicking one reports its id once", function()
		local calls = {}
		local hud, gui = newHud(calls)
		started(hud)
		hud:showWeekChoice(choiceData(2))
		local Config = H.load("Config")
		T.ok(hasText(gui, "Semaine 2"), "week title")
		T.ok(hasText(gui, Config.Rewards.Bridge.title))
		T.ok(hasText(gui, Config.Rewards.Roads.title))
		local hits = choiceHits(gui)
		T.eq(#hits, 2, "one clickable area per reward")
		H.click(hits[1])
		H.click(hits[1])
		T.eq(countCount(calls, "reward:bridge"), 1, "the reward is reported once")
		T.falsy(hasText(gui, Config.Rewards.Bridge.title), "the choice closes after a pick")
	end)

	T.test("keys 1 and 2 pick the matching week reward", function()
		local calls = {}
		local hud, gui = newHud(calls)
		started(hud)
		hud:showWeekChoice(choiceData(2))
		H.input.key("Two", true)
		H.input.key("Two", false)
		T.eq(countCount(calls, "reward:roads"), 1, "key 2 picks the second reward")
		T.falsy(hasText(gui, "Choisissez"), "the choice closed")
		H.input.key("One", true)
		H.input.key("One", false)
		T.eq(countCount(calls, "reward:bridge"), 0, "a closed choice ignores the keys")
	end)

	T.test("the circulation reward gets its own card and keeps its title", function()
		local hud, gui = newHud({})
		started(hud)
		-- Option construite ici : la récompense « circulation » de Config.Rewards
		-- arrive avec la PR du gameplay, l'interface la gère déjà via trafficFactor.
		local traffic = { id = "traffic", kind = "roads", amount = 20, roads = 20, trafficFactor = 0.93, title = "Circulation fluide", description = "Les voitures gardent moins de distance." }
		hud:showWeekChoice({ week = 3, options = { { id = "roads", kind = "roads", amount = 30, title = "+30 routes", description = "Un lot de routes." }, traffic } })
		T.ok(hasText(gui, traffic.title), "traffic reward title")
		T.ok(hasText(gui, "+20 routes"), "the resource amount is shown")
		T.eq(#choiceHits(gui), 2)
	end)

	T.test("a choice with no usable option is skipped without blocking the game", function()
		local hud, gui = newHud({})
		started(hud)
		T.noThrow(function()
			hud:showWeekChoice(nil)
			hud:showWeekChoice({ week = 2, options = "bad" })
			hud:showWeekChoice({ week = 2, options = { 1, "x", {} } })
		end)
		T.falsy(hasText(gui, "Choisissez"), "no empty choice is shown")
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("the pause menu and the game over screen replace the pending week choice", function()
		local hud, gui = newHud({})
		started(hud)
		hud:showWeekChoice(choiceData(2))
		hud:showPause()
		T.falsy(hasText(gui, "Choisissez"), "pause hides the choice")
		T.ok(buttonNamed(gui, "Reprendre"), "pause is shown")
		hud:hidePause()
		T.ok(hasText(gui, "Choisissez"), "the choice returns once the pause closes")

		hud:showPause()
		hud:showGameOver({ score = 1, best = 0 })
		T.falsy(buttonNamed(gui, "Reprendre"), "game over closes the pause menu")
		hud:hideModals()
		hud:hidePause()
		T.falsy(hasText(gui, "Choisissez"), "a game over cancels the pending choice")
	end)

	T.test("the modals are mutually exclusive: game over is final and pause cannot open over it", function()
		local hud, gui = newHud({})
		started(hud)
		hud:showGameOver({ score = 1, best = 0 })
		hud:showPause()
		T.ok(hasText(gui, "Partie terminée"), "the game over screen stays")
		T.falsy(buttonNamed(gui, "Reprendre"), "pause does not open over the game over screen")
		hud:showPause()
		hud:showGameOver({ score = 2, best = 0 })
		T.ok(hasText(gui, "Partie terminée"))
	end)

	T.test("hideModals resets every overlay, including the settings page", function()
		local hud, gui = newHud({})
		started(hud)
		hud:showPause()
		H.click(buttonNamed(gui, "Paramètres"))
		hud:hideModals()
		hud:showPause()
		T.ok(buttonNamed(gui, "Reprendre"), "the pause menu opens on its main page")
		T.falsy(rowNamed(gui, "Astuces"), "the settings page is not left open")
		hud:hideModals()
		hud:showGameOver({ score = 1, best = 0 })
		hud:hideModals()
		T.falsy(hasText(gui, "Partie terminée"))
	end)

	T.test("twenty show and hide cycles add no instances and no connections", function()
		local hud = newHud({})
		started(hud)
		local function cycle()
			hud:showPause()
			hud:hidePause()
			hud:showWeekChoice(choiceData(2))
			hud:hideWeekChoice()
			hud:showGameOver({ score = 4, best = 9, stats = { deliveries = 1 } })
			hud:hideModals()
		end
		cycle()
		local instances = H.instanceCount()
		local connections = H.connectionCount()
		for _ = 1, 20 do
			cycle()
		end
		T.eq(H.instanceCount(), instances, "instance count stable after 20 cycles")
		T.eq(H.connectionCount(), connections, "connection count stable after 20 cycles")
	end)
end
