return function(T, H)
	local function newHud()
		H.asClient()
		return H.load("HUD").new({})
	end

	-- Rectangle relatif au parent (de taille width × height), calculé comme le moteur.
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

	local function overlaps(a, b)
		return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
	end

	-- Case de pictogramme : le cadre de 20 px créé par HUDCounters.
	local function slotOf(chip)
		for _, child in ipairs(chip:GetChildren()) do
			if child:IsA("Frame") and child.Size.X.Offset == 20 and child.Size.Y.Offset == 20 then
				return child
			end
		end
		return nil
	end

	T.test("each counter pictogram sits inside its chip, clear of the number", function()
		local hud = newHud()
		hud:setState({ budget = 20, bridges = 1, roadsBuilt = 0, roundabouts = 1, score = 0, week = 1 })
		local counters = {
			{ "rond-point", hud.roundaboutValue },
			{ "routes", hud.budgetValue },
			{ "ponts", hud.bridgeValue },
			{ "maisons", hud.houseValue },
			{ "destinations", hud.storeValue },
		}
		for _, pair in ipairs(counters) do
			local chip = pair[2].Parent
			local slot = slotOf(chip)
			T.ok(slot ~= nil, pair[1] .. " has a 20 px pictogram slot")
			if slot then
				local cw, ch = chip.Size.X.Offset, chip.Size.Y.Offset
				local icon = rect(slot, cw, ch)
				local number = rect(pair[2], cw, ch)
				T.ok(inside(icon, cw, ch), pair[1] .. " pictogram inside its chip")
				T.ok(inside(number, cw, ch), pair[1] .. " number inside its chip")
				T.falsy(overlaps(icon, number), pair[1] .. " pictogram clear of the number")
			end
		end
	end)

	T.test("counter values come from the payload, missing ones read as zero", function()
		local hud = newHud()
		hud:setState({ budget = 42, bridges = 3, houses = 9, destinations = 5, roundabouts = 2, score = 0, week = 1 })
		T.eq(hud.budgetValue.Text, "42", "budget")
		T.eq(hud.bridgeValue.Text, "3", "bridges")
		T.eq(hud.houseValue.Text, "9", "houses")
		T.eq(hud.storeValue.Text, "5", "destinations")
		T.eq(hud.roundaboutValue.Text, "2", "roundabouts")
		hud:setState({ score = 5 })
		T.eq(hud.budgetValue.Text, "0", "missing budget falls back to zero")
		T.eq(hud.bridgeValue.Text, "0", "missing bridges fall back to zero")
		T.eq(hud.houseValue.Text, "0", "missing houses fall back to zero")
	end)

	T.test("the five counters share one size, one radius and one icon box", function()
		local hud = newHud()
		local chips = {}
		for _, value in ipairs({ hud.budgetValue, hud.bridgeValue, hud.roundaboutValue, hud.houseValue, hud.storeValue }) do
			table.insert(chips, value.Parent)
		end
		for _, chip in ipairs(chips) do
			T.eq(chip.Size, chips[1].Size, "same size")
			T.eq(chip:FindFirstChildOfClass("UICorner").CornerRadius, chips[1]:FindFirstChildOfClass("UICorner").CornerRadius, "same radius")
			T.eq(slotOf(chip).Size, slotOf(chips[1]).Size, "same icon box")
			T.eq(chip.BackgroundColor3, chips[1].BackgroundColor3, "same fill")
		end
	end)
end
