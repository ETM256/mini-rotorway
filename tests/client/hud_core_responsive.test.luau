return function(T, H)
	-- Les six formats de l'écran : paysage (1920, 1600, 1366, 1280, 844x390) et téléphone.
	local SIZES = {
		{ 1920, 1080 },
		{ 1600, 900 },
		{ 1366, 768 },
		{ 1280, 720 },
		{ 844, 390 },
		{ 390, 844 },
	}

	local function newHud()
		H.asClient()
		return H.load("HUD").new({})
	end

	local function start(hud, width, height)
		H.setViewport(width, height)
		H.advance(1)
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, H.load("Maps").getById("los_angeles"))
	end

	local function resize(width, height)
		H.setViewport(width, height)
		H.advance(1)
	end

	-- Rectangle absolu, comme le moteur : position = échelle × écran + décalage,
	-- moins AnchorPoint × taille. Un UIScale enfant met la taille à l'échelle
	-- autour de l'ancre, la position de l'ancre restant fixe.
	local function rect(instance, width, height)
		local size, position, anchor = instance.Size, instance.Position, instance.AnchorPoint
		local scaleChild = instance:FindFirstChildOfClass("UIScale")
		local factor = scaleChild and scaleChild.Scale or 1
		local w = (width * size.X.Scale + size.X.Offset) * factor
		local h = (height * size.Y.Scale + size.Y.Offset) * factor
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

	-- Éléments de la barre du haut affichés : la jauge de trafic n'existe que sous 99,5 %
	-- de satisfaction, les commandes de temps ne s'ouvrent qu'au clic sur l'horloge.
	local function topItems(hud, withControls)
		local items = { hud.backButton, hud.scorePanel }
		if hud.circulation.Visible then
			table.insert(items, hud.circulation)
		end
		if withControls and hud.controls.Visible then
			table.insert(items, hud.controls)
		end
		return items
	end

	local function label(size)
		return string.format("%dx%d", size[1], size[2])
	end

	T.test("the top bar, tool column and counters stay inside the screen at the six sizes", function()
		local hud = newHud()
		start(hud, SIZES[1][1], SIZES[1][2])
		hud:setSatisfaction(60)
		hud.controls.Visible = true
		for _, size in ipairs(SIZES) do
			resize(size[1], size[2])
			local regions = topItems(hud, true)
			table.insert(regions, hud.toolPill)
			table.insert(regions, hud.resources)
			for _, frame in ipairs(regions) do
				T.ok(inside(rect(frame, size[1], size[2]), size[1], size[2]), frame.Name .. " inside " .. label(size))
			end
		end
	end)

	T.test("the top bar, tool column and counters never overlap at the six sizes (time controls closed)", function()
		local hud = newHud()
		start(hud, SIZES[1][1], SIZES[1][2])
		hud:setSatisfaction(60)
		for _, size in ipairs(SIZES) do
			resize(size[1], size[2])
			local top = topItems(hud, false)
			local pill = rect(hud.toolPill, size[1], size[2])
			local counters = rect(hud.resources, size[1], size[2])
			for index, frame in ipairs(top) do
				local r = rect(frame, size[1], size[2])
				T.falsy(overlaps(r, pill), frame.Name .. " over the tool column at " .. label(size))
				T.falsy(overlaps(r, counters), frame.Name .. " over the counters at " .. label(size))
				for other = index + 1, #top do
					T.falsy(overlaps(r, rect(top[other], size[1], size[2])), frame.Name .. " over " .. top[other].Name .. " at " .. label(size))
				end
			end
			T.falsy(overlaps(pill, counters), "tool column over the counters at " .. label(size))
		end
	end)

	T.test("the open time controls clear the top bar and the counters at the six sizes", function()
		local hud = newHud()
		start(hud, SIZES[1][1], SIZES[1][2])
		hud.controls.Visible = true
		for _, size in ipairs(SIZES) do
			resize(size[1], size[2])
			local controls = rect(hud.controls, size[1], size[2])
			T.falsy(overlaps(controls, rect(hud.scorePanel, size[1], size[2])), "controls over the score panel at " .. label(size))
			T.falsy(overlaps(controls, rect(hud.resources, size[1], size[2])), "controls over the counters at " .. label(size))
		end
	end)

	T.test("the open time controls clear the tool column at the six sizes", function()
		local hud = newHud()
		start(hud, SIZES[1][1], SIZES[1][2])
		hud.controls.Visible = true
		for _, size in ipairs(SIZES) do
			resize(size[1], size[2])
			T.falsy(
				overlaps(rect(hud.controls, size[1], size[2]), rect(hud.toolPill, size[1], size[2])),
				"controls over the tool column at " .. label(size)
			)
		end
	end)

	T.test("getSafeInsets gives the top, right, bottom and left margins covered by the interface", function()
		local hud = newHud()
		start(hud, SIZES[1][1], SIZES[1][2])
		for _, size in ipairs(SIZES) do
			resize(size[1], size[2])
			-- Ordre renvoyé à Main : haut, droite, bas, gauche.
			local top, right, bottom, left = hud:getSafeInsets()
			for _, margin in ipairs({ top, right, bottom, left }) do
				T.ok(type(margin) == "number" and margin >= 0, "margins are non-negative numbers at " .. label(size))
			end
			local score = rect(hud.scorePanel, size[1], size[2])
			T.ok(top >= score.y + score.h, "top covers the score panel at " .. label(size))
			T.ok(top < size[2] / 2, "top stays in the upper half at " .. label(size))
			T.ok(right <= size[1] / 2 and bottom <= size[2] / 2, "right and bottom stay in their halves at " .. label(size))
			-- La colonne d'outils est marginée à droite (paysage) ou en bas (court ou téléphone).
			local pill = rect(hud.toolPill, size[1], size[2])
			T.ok(
				right >= size[1] - pill.x or bottom >= size[2] - pill.y,
				"the tool column is covered by a margin at " .. label(size)
			)
			T.ok(bottom >= size[2] - rect(hud.resources, size[1], size[2]).y, "bottom covers the counters at " .. label(size))
		end
	end)

	T.test("the modal cards are scaled to fit their own size and never exceed 1", function()
		local hud = newHud()
		start(hud, SIZES[1][1], SIZES[1][2])
		for _, size in ipairs(SIZES) do
			resize(size[1], size[2])
			for _, pair in ipairs({
				{ hud.pauseScale, hud.pauseCard },
				{ hud.overScale, hud.overCard },
				{ hud.choiceScale, hud.choiceCard },
			}) do
				local scale, card = pair[1].Scale, pair[2].Size
				T.ok(scale <= 1, "scale at most 1 at " .. label(size))
				T.ok(scale >= 0.35, "scale at least the minimum at " .. label(size))
				local fitWidth = size[1] * 0.92 / card.X.Offset
				local fitHeight = size[2] * 0.9 / card.Y.Offset
				local expected = math.max(0.35, math.min(1, fitWidth, fitHeight))
				T.near(scale, expected, 1e-6, "scale follows the card size at " .. label(size))
			end
		end
	end)
end
