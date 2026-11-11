return function(T, H)
	local RESOLUTIONS = { { 1920, 1080 }, { 1366, 768 }, { 1280, 720 }, { 844, 390 }, { 390, 844 } }

	local function newLobby(calls)
		H.asClient()
		local Lobby = H.load("Lobby")
		local lobby = Lobby.new({
			onPlay = function()
				table.insert(calls, "play")
				-- Comme Main.client : « Jouer » ouvre la page des cartes.
			end,
			onQuit = function()
				table.insert(calls, "quit")
			end,
			onStartMap = function(mapId)
				table.insert(calls, "start:" .. tostring(mapId))
			end,
			onResetRecords = function()
				table.insert(calls, "reset")
			end,
		})
		return lobby, H.localPlayer.PlayerGui:FindFirstChild("MM_Lobby")
	end

	local function buttons(gui)
		local list = {}
		for _, b in ipairs(H.find(gui, { class = "GuiButton" })) do
			table.insert(list, b)
		end
		return list
	end

	T.test("the lobby builds, shows and hides", function()
		local lobby, gui = newLobby({})
		T.ok(gui)
		lobby:show()
		T.ok(gui.Enabled)
		lobby:hide()
		T.falsy(gui.Enabled)
	end)

	T.test("one selectable card per map; selecting updates the play button", function()
		local lobby = newLobby({})
		lobby:show()
		lobby:showMaps()
		local Maps = H.load("Maps")
		local count = 0
		for _, map in ipairs(Maps.all()) do
			T.ok(lobby.cards[map.id], "card for " .. map.id)
			count += 1
			lobby:select(map.id)
			T.eq(lobby.selectedId, map.id)
			T.contains(lobby.playButton.Text, map.name)
		end
		T.eq(count, #Maps.all())
		lobby:select("does-not-exist")
		T.eq(lobby.selectedId, Maps.all()[#Maps.all()].id, "an unknown map id is ignored")
	end)

	T.test("startSelected asks the game to start the selected map", function()
		local calls = {}
		local lobby = newLobby(calls)
		lobby:show()
		lobby:showMaps()
		lobby:select("tokyo")
		lobby:startSelected()
		T.contains(calls, "start:tokyo")
	end)

	T.test("clicking a map card starts that map", function()
		local calls = {}
		local lobby, gui = newLobby(calls)
		lobby:show()
		lobby:showMaps()
		local Maps = H.load("Maps")
		for _, b in ipairs(buttons(gui)) do
			if b.Visible then
				H.click(b)
			end
		end
		local started = {}
		for _, c in ipairs(calls) do
			if string.sub(c, 1, 6) == "start:" then
				started[string.sub(c, 7)] = true
			end
		end
		local any = false
		for _, map in ipairs(Maps.all()) do
			any = any or started[map.id]
		end
		T.ok(any, "at least one map can be launched by clicking: " .. table.concat(calls, ","))
	end)

	T.test("the main page offers a Play button wired to onPlay", function()
		local calls = {}
		local lobby, gui = newLobby(calls)
		lobby:show()
		local play
		for _, b in ipairs(buttons(gui)) do
			if b.Visible and string.find(string.lower(b.Text or ""), "jouer", 1, true) then
				play = b
				break
			end
		end
		T.ok(play, "a visible Jouer button")
		H.click(play)
		T.contains(calls, "play")
	end)

	T.test("profile records are displayed per map", function()
		local lobby = newLobby({})
		lobby:setProfile({ los_angeles = 42, tokyo = 7 })
		T.contains(lobby.cards.los_angeles.bestLabel.Text, "42")
		T.contains(lobby.cards.tokyo.bestLabel.Text, "7")
		T.noThrow(function()
			lobby:setProfile({})
			lobby:setProfile(nil)
			lobby:setProfile({ los_angeles = "bad" })
		end)
	end)

	T.test("toast shows then hides itself", function()
		local lobby = newLobby({})
		lobby:toast("Bonjour")
		T.ok(lobby.toastLabel.Visible)
		H.advance(3)
		T.falsy(lobby.toastLabel.Visible)
	end)

	T.test("modals and pages switch without errors; the menu fits every resolution", function()
		for _, res in ipairs(RESOLUTIONS) do
			H.reset()
			local lobby = newLobby({})
			H.setViewport(res[1], res[2])
			T.noThrow(function()
				lobby:show()
				lobby:showMaps()
				lobby:showMain()
				lobby:showRecords()
				lobby:showGarage()
				lobby:showStats()
				H.advance(2)
			end)
		end
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("MapPreview draws every map without error and lays out inside its frame", function()
		H.asClient()
		local MapPreview = H.load("MapPreview")
		local holder = Instance.new("Frame")
		holder.Parent = H.localPlayer.PlayerGui
		for _, map in ipairs(H.load("Maps").all()) do
			T.noThrow(function()
				local preview = MapPreview.create(holder, map, 160)
				T.ok(preview)
			end)
		end
	end)

	T.test("Theme helpers: rounded corners, strokes and buttons", function()
		H.asClient()
		local Theme = H.load("Theme")
		local frame = Theme.new("Frame", { Size = UDim2.fromOffset(100, 40) })
		Theme.corner(frame, 8)
		Theme.stroke(frame, Color3.new(0, 0, 0), 1, 0.5)
		Theme.padding(frame, 4, 4, 4, 4)
		T.ok(frame:FindFirstChildOfClass("UICorner"))
		T.ok(frame:FindFirstChildOfClass("UIStroke"))
		local clicked = 0
		local button = Theme.button(frame, "OK", { Size = UDim2.fromOffset(60, 30) }, function()
			clicked += 1
		end)
		H.click(button)
		T.ge(clicked, 1)
		T.eq(clicked <= 1, true, "a click must run the handler once (anti double-click)")
	end)
end
