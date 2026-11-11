return function(T, H)
	local Theme = H.load("UI/Theme")
	local IDS = { "build", "erase", "roundabout", "camera" }

	local function newHud(calls)
		H.asClient()
		local HUD = H.load("HUD")
		return HUD.new({
			onToolChange = function(tool)
				table.insert(calls, tool)
			end,
		})
	end

	local function map()
		return H.load("Maps").getById("los_angeles")
	end

	-- Identifiants des boutons dont l'anneau de sélection est visible.
	local function selectedIds(hud)
		local selected = {}
		for _, id in ipairs(IDS) do
			local ring = hud.toolButtons[id]:FindFirstChild("SelectionRing")
			if ring and ring.Transparency == 0 then
				table.insert(selected, id)
			end
		end
		return selected
	end

	T.test("exactly one tool button is selected, and it is the active tool", function()
		local hud = newHud({})
		H.setViewport(1366, 768)
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		for _, id in ipairs(IDS) do
			hud:setTool(id)
			-- La sélection est animée : on laisse passer la durée du fondu.
			H.advance(0.2)
			local selected = selectedIds(hud)
			T.eq(#selected, 1, "one selected button when the tool is " .. id)
			T.eq(selected[1], id, "the selected button is " .. id)
			T.eq(hud.toolButtons[id].BackgroundColor3, Theme.Selected, id .. " takes the selected colour")
		end
	end)

	T.test("a roundabout request without any roundabout selects the build tool", function()
		local hud = newHud({})
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, map())
		hud:setTool("roundabout")
		H.advance(0.2)
		T.eq(hud.tool, "build", "the active tool falls back to build")
		T.eq(selectedIds(hud)[1], "build", "the build button is selected")
	end)

	T.test("the toolbar offers the four tool ids read by the input controller", function()
		local hud = newHud({})
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, map())
		local count = 0
		for name, button in pairs(hud.toolButtons) do
			count += 1
			T.contains(IDS, name, "unexpected tool " .. name)
			T.eq(button.Name, name, "button named after its tool")
		end
		T.eq(count, 4, "four tool buttons")
	end)

	T.test("each click reports its own tool exactly once", function()
		local calls = {}
		local hud = newHud(calls)
		H.setViewport(1366, 768)
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		for _, id in ipairs(IDS) do
			-- Laisse passer le délai anti double-clic entre deux outils.
			H.advance(0.5)
			local before = #calls
			H.click(hud.toolButtons[id])
			T.eq(#calls, before + 1, id .. " click reports one call")
			T.eq(calls[#calls], id, id .. " click reports its id")
		end
	end)

	T.test("a double click reports once, and a later click is reported again", function()
		local calls = {}
		local hud = newHud(calls)
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, map())
		H.advance(0.5)
		local button = hud.toolButtons.erase
		H.click(button)
		H.click(button)
		T.eq(#calls, 1, "the second click within the debounce is ignored")
		H.advance(0.5)
		H.click(button)
		T.eq(#calls, 2, "a click after the debounce is reported")
		T.eq(calls[2], "erase", "the reported tool is erase")
	end)

	T.test("every tool button is a touch-sized, active and selectable target", function()
		local hud = newHud({})
		H.setViewport(390, 844)
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		for _, id in ipairs(IDS) do
			local button = hud.toolButtons[id]
			T.ge(button.Size.X.Offset, 40, id .. " width is at least 40 px")
			T.ge(button.Size.Y.Offset, 40, id .. " height is at least 40 px")
			T.ok(button.Active, id .. " is active")
			T.ok(button.Selectable, id .. " is selectable")
			T.eq(button.Size.X.Offset, hud.toolButtons.build.Size.X.Offset, id .. " has the same size as build")
		end
	end)

	T.test("each button shows its key hint, 1 to 4, from the keyboard layout", function()
		local hud = newHud({})
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		local expected = { build = "1", erase = "2", roundabout = "3", camera = "4" }
		for id, key in pairs(expected) do
			local labels = H.find(hud.toolButtons[id], { class = "TextLabel" })
			T.eq(#labels, 1, id .. " has one key hint")
			T.eq(labels[1].Text, key, id .. " key hint")
		end
	end)

	T.test("hover and press feedback scales the button by at most 1.04", function()
		local hud = newHud({})
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, map())
		local button = hud.toolButtons.build
		local scale = button:FindFirstChild("MotionScale")
		T.ok(scale ~= nil, "the button has a motion scale")
		H.I.fire(H.I.getSignal(button, "MouseEnter"))
		H.advance(0.3)
		T.ok(scale.Scale > 1 and scale.Scale <= 1.04, "hover scale is above 1 and at most 1.04")
		H.I.fire(H.I.getSignal(button, "MouseLeave"))
		H.advance(0.3)
		T.near(scale.Scale, 1, 0.001, "leaving the button restores the scale")
	end)

	T.test("destroying the panel releases its connections without errors", function()
		local hud = newHud({})
		hud:showGame({ mapId = "los_angeles", roundabouts = 1 }, map())
		local before = H.connectionCount()
		T.noThrow(function()
			hud.toolPill:Destroy()
		end)
		T.ok(H.connectionCount() < before, "the panel's connections are disconnected")
		T.eq(#H.handlerErrors, 0, "no handler error after the panel is destroyed")
	end)
end
