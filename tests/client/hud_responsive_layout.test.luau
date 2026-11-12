return function(T, H)
	-- Les six formats : paysage (1920, 1600, 1366, 1280, 844x390 court) et téléphone.
	local SIZES = {
		{ 1920, 1080 },
		{ 1600, 900 },
		{ 1366, 768 },
		{ 1280, 720 },
		{ 844, 390 },
		{ 390, 844 },
	}
	-- Un contact de 1 px est toléré : les arrondis des coordonnées ne comptent pas.
	local TOLERANCE = 1

	local function newHud()
		H.asClient()
		local HUD = H.load("HUD")
		return HUD.new({})
	end

	local function map()
		return H.load("Maps").getById("los_angeles")
	end

	-- Rectangle absolu calculé comme le moteur : position = échelle × écran + décalage,
	-- moins AnchorPoint × taille, taille = échelle × écran + décalage.
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

	-- Deux rectangles se recouvrent si leurs intérieurs se coupent de plus de TOLERANCE.
	local function overlaps(a, b)
		return a.x + TOLERANCE < b.x + b.w
			and b.x + TOLERANCE < a.x + a.w
			and a.y + TOLERANCE < b.y + b.h
			and b.y + TOLERANCE < a.y + a.h
	end

	-- Éléments visibles de l'interface, nommés pour les messages d'échec.
	local function regions(hud)
		local list = {
			{ "retour", hud.backButton },
			{ "score", hud.scorePanel },
			{ "outils", hud.toolPill },
			{ "compteurs", hud.resources },
		}
		if hud.circulation.Visible then
			table.insert(list, { "jauge", hud.circulation })
		end
		if hud.controls.Visible then
			table.insert(list, { "commandes", hud.controls })
		end
		if hud.hint.Visible then
			table.insert(list, { "aide", hud.hint })
		end
		return list
	end

	local function resize(width, height)
		H.setViewport(width, height)
		H.advance(1)
	end

	-- Partie en cours, jauge affichée et commandes de temps ouvertes : le cas le plus chargé.
	local function busyHud(width, height)
		local hud = newHud()
		resize(width, height)
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		hud:setSatisfaction(40)
		hud.controls.Visible = true
		resize(width, height)
		return hud
	end

	T.test("every interface region stays inside the viewport at the six sizes", function()
		for _, size in ipairs(SIZES) do
			local hud = busyHud(size[1], size[2])
			local label = string.format("%dx%d", size[1], size[2])
			for _, region in ipairs(regions(hud)) do
				T.ok(inside(rect(region[2], size[1], size[2]), size[1], size[2]), region[1] .. " inside " .. label)
			end
		end
	end)

	T.test("no two visible regions overlap at the six sizes", function()
		for _, size in ipairs(SIZES) do
			local hud = busyHud(size[1], size[2])
			local list = regions(hud)
			local label = string.format("%dx%d", size[1], size[2])
			for i = 1, #list do
				for j = i + 1, #list do
					local a = list[i]
					local b = list[j]
					T.falsy(
						overlaps(rect(a[2], size[1], size[2]), rect(b[2], size[1], size[2])),
						string.format("%s and %s apart at %s", a[1], b[1], label)
					)
				end
			end
		end
	end)

	T.test("the safe insets frame the interface on each format", function()
		for _, size in ipairs(SIZES) do
			local hud = busyHud(size[1], size[2])
			local top, right, bottom, left = hud:getSafeInsets()
			local label = string.format("%dx%d", size[1], size[2])
			for name, value in pairs({ top = top, right = right, bottom = bottom, left = left }) do
				T.ok(type(value) == "number" and value >= 0 and value % 1 == 0, name .. " is a whole number at " .. label)
				T.ok(value < size[1] and value < size[2], name .. " leaves part of the map at " .. label)
			end
			-- Chaque bord couvert par un élément est au moins aussi grand que cet élément.
			local tool = rect(hud.toolPill, size[1], size[2])
			local counters = rect(hud.resources, size[1], size[2])
			if tool.w >= tool.h then
				T.ok(bottom >= size[2] - tool.y, "bottom inset covers the tool strip at " .. label)
			else
				T.ok(right >= size[1] - tool.x, "right inset covers the tool column at " .. label)
			end
			T.ok(bottom >= size[2] - counters.y, "bottom inset covers the counters at " .. label)
		end
	end)

	T.test("the hint stays hidden when the session setting turns hints off", function()
		local hud = newHud()
		resize(1366, 768)
		hud:showPause()
		local label = H.find(hud.pauseOverlay, { text = "Paramètres" })[1]
		H.click(label.Parent)
		H.advance(0.2)
		local hints = H.find(hud.pauseOverlay, { text = "Astuces" })[1]
		H.click(hints.Parent)
		H.advance(0.2)
		hud:hidePause()
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, map())
		T.falsy(hud.hint.Visible, "hint hidden in the next game")
	end)

	T.test("destroy releases the interface and is idempotent", function()
		-- Un premier cycle charge les modules et lance des tweens : on laisse finir
		-- ceux-ci avant de compter, sinon la référence serait faussée.
		newHud():destroy()
		H.advance(1)
		local instancesBefore = H.instanceCount()
		local connectionsBefore = H.connectionCount()
		local hud = newHud()
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		-- Les tweens de la barre (0,22 s) finissent seuls avant la fermeture.
		H.advance(1)
		hud:destroy()
		T.falsy(hud.gui.Parent, "ScreenGui removed from PlayerGui")
		T.eq(H.instanceCount(), instancesBefore, "every instance of the interface is destroyed")
		T.eq(H.connectionCount(), connectionsBefore, "every connection of the interface is released")
		local ok = pcall(function()
			hud:destroy()
		end)
		T.ok(ok, "second destroy is a no-op")
	end)
end
