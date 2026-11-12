return function(T, H)
	-- Les cinq formats de l'écran : paysage (1920, 1600, 1366, 1280) et téléphone.
	local SIZES = {
		{ 1920, 1080 },
		{ 1600, 900 },
		{ 1366, 768 },
		{ 1280, 720 },
		{ 390, 844 },
	}
	-- Formats où le panneau doit éviter les compteurs et la barre du haut.
	local CLEAR_SIZES = { { 1366, 768 }, { 1280, 720 }, { 390, 844 } }

	local function newHud(calls)
		H.asClient()
		local HUD = H.load("HUD")
		return HUD.new({
			onToolChange = function(tool)
				table.insert(calls or {}, tool)
			end,
		})
	end

	local function map()
		return H.load("Maps").getById("los_angeles")
	end

	-- Rectangle d'un élément, calculé comme le moteur : position = échelle × écran
	-- + décalage, moins AnchorPoint × taille, taille = échelle × écran + décalage.
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

	local function inside(r, width, height)
		return r.x >= 0 and r.y >= 0 and r.x + r.w <= width and r.y + r.h <= height
	end

	-- Deux rectangles se recouvrent si leurs intérieurs se coupent (un simple contact ne compte pas).
	local function overlaps(a, b)
		return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
	end

	local function resize(width, height)
		H.setViewport(width, height)
		H.advance(1)
	end

	T.test("the tool panel stays on screen at the five sizes, with and without roundabouts", function()
		local hud = newHud()
		resize(SIZES[1][1], SIZES[1][2])
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, map())
		for _, roundabouts in ipairs({ 0, 1 }) do
			hud:setRoundabouts(roundabouts)
			for _, size in ipairs(SIZES) do
				resize(size[1], size[2])
				local r = rect(hud.toolPill, size[1], size[2])
				T.ok(
					inside(r, size[1], size[2]),
					string.format("panel inside %dx%d with %d roundabout(s)", size[1], size[2], roundabouts)
				)
			end
		end
	end)

	T.test("the panel is a column on landscape, anchored to the right edge", function()
		local hud = newHud()
		resize(1366, 768)
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, map())
		T.ok(hud.toolPill.Size.Y.Offset > hud.toolPill.Size.X.Offset, "taller than wide on landscape")
		local r = rect(hud.toolPill, 1366, 768)
		local score = rect(hud.scorePanel, 1366, 768)
		T.near(r.x + r.w, score.x + score.w, 0.5, "right edge aligned on the score panel")
		T.near(r.y + r.h / 2, 768 / 2, 0.5, "vertically centred")
	end)

	T.test("the panel is a strip above the help line on portrait", function()
		local hud = newHud()
		resize(390, 844)
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, map())
		T.ok(hud.toolPill.Size.X.Offset > hud.toolPill.Size.Y.Offset, "wider than tall on portrait")
		local r = rect(hud.toolPill, 390, 844)
		T.near(r.x + r.w / 2, 390 / 2, 0.5, "horizontally centred")
		local hint = rect(hud.hint, 390, 844)
		T.falsy(overlaps(r, hint), "the strip does not cover the help line")
		T.ok(r.y + r.h <= rect(hud.resources, 390, 844).y, "the strip sits above the counters")
	end)

	T.test("the panel size follows the number of visible tools", function()
		local hud = newHud()
		resize(1366, 768)
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, map())
		-- Trois boutons : 3 × 46 + 2 × 6 d'espace + 2 × 6 de marge.
		T.eq(hud.toolPill.Size.Y.Offset, 162, "three tools on landscape")
		hud:setRoundabouts(1)
		T.eq(hud.toolPill.Size.Y.Offset, 214, "four tools on landscape")
		resize(390, 844)
		T.eq(hud.toolPill.Size.X.Offset, 214, "four tools on portrait")
		hud:setRoundabouts(0)
		T.eq(hud.toolPill.Size.X.Offset, 162, "three tools on portrait")
	end)

	T.test("the panel does not overlap the counters, the top bar or the controls", function()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		hud.controls.Visible = true
		for _, size in ipairs(CLEAR_SIZES) do
			resize(size[1], size[2])
			local pill = rect(hud.toolPill, size[1], size[2])
			local label = string.format("%dx%d", size[1], size[2])
			T.falsy(overlaps(pill, rect(hud.resources, size[1], size[2])), "counters at " .. label)
			T.falsy(overlaps(pill, rect(hud.scorePanel, size[1], size[2])), "score panel at " .. label)
			T.falsy(overlaps(pill, rect(hud.controls, size[1], size[2])), "time controls at " .. label)
		end
	end)

	T.test("key hints are shown on landscape and hidden on the touch strip", function()
		local hud = newHud()
		resize(1366, 768)
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		T.ok(hud.toolButtons.build:FindFirstChildOfClass("TextLabel").Visible, "hint visible on landscape")
		resize(390, 844)
		for _, id in ipairs({ "build", "erase", "roundabout", "camera" }) do
			local hint = hud.toolButtons[id]:FindFirstChildOfClass("TextLabel")
			T.falsy(hint.Visible, id .. " hint hidden on portrait")
		end
	end)
end
