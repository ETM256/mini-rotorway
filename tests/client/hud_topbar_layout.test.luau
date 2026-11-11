return function(T, H)
	local SIZES = { { 1920, 1080 }, { 1600, 900 }, { 1366, 768 }, { 1280, 720 }, { 844, 390 }, { 390, 844 } }

	local function rect(instance, width, height)
		local size, position, anchor = instance.Size, instance.Position, instance.AnchorPoint
		local w = width * size.X.Scale + size.X.Offset
		local h = height * size.Y.Scale + size.Y.Offset
		return {
			x = width * position.X.Scale + position.X.Offset - anchor.X * w,
			y = height * position.Y.Scale + position.Y.Offset - anchor.Y * h,
			w = w,
			h = h,
		}
	end

	local function started(width, height)
		H.asClient()
		local hud = H.load("HUD").new({})
		H.setViewport(width, height)
		H.advance(1)
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, H.load("Maps").getById("los_angeles"))
		return hud
	end

	T.test("the score panel and the time controls share one right edge and one margin", function()
		local margin = H.load("UI/Theme").Layout.Margin
		for _, size in ipairs(SIZES) do
			local hud = started(size[1], size[2])
			local score = rect(hud.scorePanel, size[1], size[2])
			local controls = rect(hud.controls, size[1], size[2])
			local label = size[1] .. "x" .. size[2]
			T.near(score.x + score.w, size[1] - margin, 0.01, "score right margin at " .. label)
			T.near(controls.x + controls.w, size[1] - margin, 0.01, "controls right margin at " .. label)
			T.near(score.y, margin, 0.01, "score top margin at " .. label)
			T.ge(controls.y, score.y + score.h, "controls under the score at " .. label)
		end
	end)

	T.test("the five counters sit side by side inside the screen at the six sizes", function()
		for _, size in ipairs(SIZES) do
			local hud = started(size[1], size[2])
			local resources = rect(hud.resources, size[1], size[2])
			local label = size[1] .. "x" .. size[2]
			T.ge(resources.x, 0, "counters inside on the left at " .. label)
			T.le(resources.x + resources.w, size[1], "counters inside on the right at " .. label)
			T.ge(resources.y, 0)
			T.le(resources.y + resources.h, size[2], "counters inside at the bottom of " .. label)
			local chips = {}
			for _, child in ipairs(hud.resources:GetChildren()) do
				if child:IsA("Frame") then
					table.insert(chips, child)
				end
			end
			T.eq(#chips, 5, "five counters")
		end
	end)

	T.test("the toast stays inside the screen and under the top bar at the six sizes", function()
		for _, size in ipairs(SIZES) do
			local hud = started(size[1], size[2])
			hud:toast("Une phrase assez longue pour un message de jeu")
			local toast = rect(hud.toastLabel, size[1], size[2])
			local score = rect(hud.scorePanel, size[1], size[2])
			local label = size[1] .. "x" .. size[2]
			T.ge(toast.x, 0, "toast inside on the left at " .. label)
			T.le(toast.x + toast.w, size[1], "toast inside on the right at " .. label)
			T.ge(toast.y, score.y + score.h, "toast under the score panel at " .. label)
		end
	end)

	T.test("the toast clears the gauge, the score and the time controls at the six sizes", function()
		local function overlaps(a, b)
			return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
		end
		for _, size in ipairs(SIZES) do
			local hud = started(size[1], size[2])
			hud:setSatisfaction(50)
			hud:toast("Une phrase assez longue pour un message de jeu")
			local toast = rect(hud.toastLabel, size[1], size[2])
			local label = size[1] .. "x" .. size[2]
			T.falsy(overlaps(toast, rect(hud.circulation, size[1], size[2])), "toast off the gauge at " .. label)
			T.falsy(overlaps(toast, rect(hud.scorePanel, size[1], size[2])), "toast off the score at " .. label)
			T.falsy(overlaps(toast, rect(hud.controls, size[1], size[2])), "toast off the controls at " .. label)
		end
	end)

	T.test("the gauge keeps clear of the Roblox menu corner", function()
		local Theme = H.load("UI/Theme")
		for _, size in ipairs(SIZES) do
			local hud = started(size[1], size[2])
			hud:setSatisfaction(50)
			T.ge(rect(hud.backButton, size[1], size[2]).x, Theme.Layout.TopLeftInset, "back button clears the corner")
			T.ge(rect(hud.circulation, size[1], size[2]).x, Theme.Layout.TopLeftInset, "gauge clears the corner")
		end
	end)
end
