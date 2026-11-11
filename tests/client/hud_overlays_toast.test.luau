return function(T, H)
	-- Toast de HUDOverlays : un message à la fois, enchaînés, puis disparition.
	local function newHud()
		H.asClient()
		local HUD = H.load("HUD")
		local hud = HUD.new({})
		hud:showGame({ mapId = "los_angeles", roundabouts = 0 }, H.load("Maps").getById("los_angeles"))
		return hud, H.localPlayer.PlayerGui:FindFirstChild("MM_HUD")
	end

	-- Texte du toast actuellement affiché parmi les messages attendus (nil sinon).
	local function visibleToast(gui, messages)
		local shown = {}
		for _, d in ipairs(H.find(gui, { class = "TextLabel" })) do
			if d.Visible and messages[d.Text] then
				table.insert(shown, d.Text)
			end
		end
		return shown
	end

	T.test("a second toast waits for the first one, then appears", function()
		local hud, gui = newHud()
		local messages = { A = true, B = true }
		hud:toast("A")
		hud:toast("B")
		T.deepEq(visibleToast(gui, messages), { "A" }, "only the first toast is visible")
		H.advance(3.2)
		T.deepEq(visibleToast(gui, messages), { "B" }, "the second toast follows")
		H.advance(3.2)
		T.deepEq(visibleToast(gui, messages), {}, "the queue empties and the toast disappears")
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("an empty or missing toast message is ignored and never queues", function()
		local hud, gui = newHud()
		T.noThrow(function()
			hud:toast(nil)
			hud:toast("")
			hud:toast(42)
		end)
		hud:toast("Z")
		T.deepEq(visibleToast(gui, { Z = true }), { "Z" }, "the next real message is shown at once")
	end)

	T.test("a burst of toasts keeps at most three waiting, dropping the oldest", function()
		local hud, gui = newHud()
		local messages = { A = true, B = true, C = true, D = true, E = true }
		hud:toast("A")
		hud:toast("B")
		hud:toast("C")
		hud:toast("D")
		hud:toast("E")
		T.deepEq(visibleToast(gui, messages), { "A" }, "one toast on screen at a time")
		H.advance(3.2)
		T.deepEq(visibleToast(gui, messages), { "C" }, "the oldest waiting toast (B) was dropped")
	end)
end
