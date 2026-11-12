return function(T, H)
	local function newHud()
		H.asClient()
		local HUD = H.load("HUD")
		return HUD.new({
			onRestart = function() end,
			onMenu = function() end,
			onResume = function() end,
		})
	end

	local function map()
		return H.load("Maps").getById("los_angeles")
	end

	local function rect(instance, width, height)
		local size = instance.Size
		local position = instance.Position
		local anchor = instance.AnchorPoint
		local w = width * size.X.Scale + size.X.Offset
		local h = height * size.Y.Scale + size.Y.Offset
		return {
			x = width * position.X.Scale + position.X.Offset - anchor.X * w,
			y = height * position.Y.Scale + position.Y.Offset - anchor.Y * h,
			w = w,
			h = h,
		}
	end

	local function overlaps(a, b)
		return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
	end

	local function resize(width, height)
		H.setViewport(width, height)
		H.advance(1)
	end

	T.test("the back button is drawn with frames, not an arrow glyph", function()
		local hud = newHud()
		T.eq(hud.backButton.Text, "", "aucun glyphe de flèche dans la police")
		local bars = 0
		for _, frame in ipairs(H.find(hud.backButton, { class = "Frame" })) do
			if frame.BackgroundTransparency < 1 then
				bars += 1
			end
		end
		T.ge(bars, 3, "un trait et deux ailes dessinés")
		hud:destroy()
	end)

	T.test("no HUD text uses a character outside Latin-1 or basic punctuation", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles" }, map())
		for _, label in ipairs(H.find(hud.gui, { class = "TextLabel" })) do
			for _, code in utf8.codes(label.Text) do
				T.lt(code, 0x2000, "caractère risqué dans « " .. label.Text .. " »")
			end
		end
		for _, button in ipairs(H.find(hud.gui, { class = "TextButton" })) do
			for _, code in utf8.codes(button.Text) do
				T.lt(code, 0x2000, "caractère risqué dans « " .. button.Text .. " »")
			end
		end
		hud:destroy()
	end)

	T.test("on a narrow short landscape screen the tool strip clears the counters", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		for _, size in ipairs({ { 760, 360 }, { 780, 360 }, { 800, 360 }, { 812, 375 }, { 844, 390 }, { 926, 428 } }) do
			resize(size[1], size[2])
			local pill = rect(hud.toolPill, size[1], size[2])
			local chips = rect(hud.resources, size[1], size[2])
			T.falsy(overlaps(pill, chips), "bandeau et compteurs séparés à " .. size[1] .. "x" .. size[2])
			T.ge(pill.x, 0, "dans l'écran à gauche")
			T.le(pill.x + pill.w, size[1], "dans l'écran à droite")
			T.ge(pill.y, 0, "dans l'écran en haut")
			T.le(pill.y + pill.h, size[2], "dans l'écran en bas")
			for _, region in ipairs({ hud.controls, hud.scorePanel }) do
				T.falsy(overlaps(pill, rect(region, size[1], size[2])), "bandeau hors de la barre du haut à " .. size[1] .. "x" .. size[2])
			end
		end
		hud:destroy()
	end)

	T.test("a wide short landscape screen keeps the strip in the bottom right corner", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		resize(1000, 400)
		T.eq(hud.toolPill.AnchorPoint, Vector2.new(1, 1), "coin bas droit")
		T.eq(hud.toolPill.Position.X.Scale, 1)
		hud:destroy()
	end)

	T.test("safe insets follow the stacked strip", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		resize(800, 360)
		local _, _, bottom = hud:getSafeInsets()
		local pill = rect(hud.toolPill, 800, 360)
		T.ge(bottom, 360 - pill.y, "la marge basse couvre le bandeau empilé")
		hud:destroy()
	end)

	T.test("closing the pause menu clears the hover state of its buttons", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles" }, map())
		H.advance(0.5)
		hud:showPause()
		H.advance(0.5)
		local resume
		for _, found in ipairs(H.find(hud.pauseOverlay, { class = "TextButton", text = "Reprendre" })) do
			resume = found
		end
		T.ok(resume, "bouton Reprendre")
		local base = resume.BackgroundColor3
		H.I.fire(H.I.getSignal(resume, "MouseEnter"))
		H.advance(0.5)
		T.near(resume.MotionScale.Scale, 1.03, 1e-6, "survol installé")

		hud:hidePause()
		T.near(resume.MotionScale.Scale, 1, 1e-6, "la couche fermée repart sans survol")
		T.eq(resume.BackgroundColor3, base)
		hud:destroy()
	end)

	T.test("a very large score shrinks instead of overflowing the game over card", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles" }, map())
		hud:showGameOver({ score = 123456789, best = 5 })
		T.eq(hud.finalScore.TextScaled, true)
		local limit = hud.finalScore:FindFirstChildOfClass("UITextSizeConstraint")
		T.ok(limit, "taille bornée")
		T.eq(limit.MaxTextSize, 50, "taille normale conservée pour les scores courants")
		hud:destroy()
	end)

	T.test("choice cards cancel their selection tweens before they are destroyed", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles" }, map())
		local options = {
			{ id = "a", kind = "roads", title = "Routes", description = "d", roads = 3 },
			{ id = "b", kind = "bridges", title = "Ponts", description = "d", roads = 1 },
		}
		hud:showWeekChoice({ week = 1, options = options })
		local hit = H.find(hud.choiceOptions, { class = "TextButton" })[1]
		T.ok(hit, "zone cliquable")
		local card = hit.Parent
		H.I.fire(H.I.getSignal(hit, "MouseEnter"))
		hud:showWeekChoice({ week = 2, options = options })
		T.falsy(card.Parent, "ancienne carte détruite")
		H.advance(1)
		T.eq(#H.find(hud.choiceOptions, { class = "TextButton" }), 2)
		hud:destroy()
	end)

	T.test("the hint speaks of mouse buttons on desktop and of fingers on touch-only devices", function()
		local hud = newHud()
		T.contains(hud.hint.Text, "clic droit", "clavier et souris")
		hud:destroy()

		local input = game:GetService("UserInputService")
		input.TouchEnabled = true
		input.KeyboardEnabled = false
		input.MouseEnabled = false
		local touchHud = newHud()
		T.falsy(string.find(touchHud.hint.Text, "clic", 1, true), "pas de clic sur un appareil tactile")
		T.falsy(string.find(touchHud.hint.Text, "molette", 1, true), "pas de molette sur un appareil tactile")
		T.contains(touchHud.hint.Text, "pincez")
		touchHud:destroy()
	end)

	T.test("every HUD panel sinks input so a click on it never reaches the road tools", function()
		local hud = newHud()
		local panels = { hud.scorePanel, hud.controls, hud.toolPill }
		for _, chip in ipairs(hud.resources:GetChildren()) do
			if chip:IsA("Frame") then
				table.insert(panels, chip)
			end
		end
		T.eq(#panels, 8, "trois panneaux et cinq pastilles")
		for _, panel in ipairs(panels) do
			T.eq(panel.Active, true, "panneau actif : " .. panel.Name)
		end
		hud:destroy()
	end)
end
