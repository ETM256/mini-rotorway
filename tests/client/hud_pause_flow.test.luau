return function(T, H)
	-- Bout en bout : Bootstrap.server + Main.client. Le pilotage passe par les vrais
	-- boutons du HUD et les vraies touches ; le serveur répond comme en jeu.

	local function boot()
		H.runScript("Bootstrap")
		H.asClient()
		H.runScript("Main")
		H.advance(0.1)
		H.fireServer("StartGame", "los_angeles")
		H.advance(0.5)
	end

	local function gui()
		return H.localPlayer.PlayerGui.MM_HUD
	end

	-- Vrai si l'objet et tous ses parents jusqu'à l'interface sont visibles.
	local function shown(instance)
		local node = instance
		while node and node ~= gui() do
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end
			node = node.Parent
		end
		return node ~= nil
	end

	local function button(text)
		for _, found in ipairs(H.find(gui(), { class = "TextButton", text = text })) do
			if shown(found) then
				return found
			end
		end
		return nil
	end

	local function pauseOpen()
		return button("Reprendre") ~= nil
	end

	local function hintLabel()
		for _, found in ipairs(H.find(gui(), { class = "TextLabel" })) do
			if string.find(found.Text, "Glissez", 1, true) then
				return found
			end
		end
		return nil
	end

	local function lastPaused()
		local sent = H.sent("SetPaused", "toServer")
		return sent[#sent] and sent[#sent][1]
	end

	-- Ligne de 6 cases libres : un tracé de test.
	local function freeRow()
		local road = H.lastSent("RoadState")
		local Maps = H.load("Maps")
		local map = Maps.getById("los_angeles")
		local blocked = {}
		for _, key in ipairs(road.buildings) do
			blocked[key] = true
		end
		for y = 1, 16 do
			local run = 0
			for x = 0, 17 do
				if blocked[x .. ":" .. y] or Maps.isWater(map, x, y) then
					run = 0
				else
					run += 1
					if run == 6 then
						return x - 5, y
					end
				end
			end
		end
		return nil, nil
	end

	local function screenOf(x, y)
		local Config = H.load("Config")
		local origin = H.lastSent("GameStarted").origin
		local world = origin + Vector3.new((x + 0.5) * Config.Grid.TileSize, 0, (y + 0.5) * Config.Grid.TileSize)
		local point = workspace.CurrentCamera:WorldToViewportPoint(world)
		return point.X, point.Y
	end

	-- Glisse d'un bout à l'autre de la ligne libre ; renvoie le nombre de DrawRoad émis.
	local function dragRow()
		local x, y = freeRow()
		local before = #H.sent("DrawRoad", "toServer")
		local sx1, sy1 = screenOf(x, y)
		local sx2, sy2 = screenOf(x + 5, y)
		H.input.mouseMove(sx1, sy1)
		H.input.mouseDown(sx1, sy1, 1)
		for i = 1, 8 do
			H.input.mouseMove(sx1 + (sx2 - sx1) * i / 8, sy1 + (sy2 - sy1) * i / 8)
		end
		H.input.mouseUp(sx2, sy2, 1)
		H.advance(0.3)
		return #H.sent("DrawRoad", "toServer") - before
	end

	local function pressKey(name)
		H.input.key(name, true)
		H.input.key(name, false)
		H.advance(0.3)
	end

	T.test("P opens the pause menu and asks the server to pause; P again closes it", function()
		boot()
		T.falsy(pauseOpen(), "no menu in play")
		pressKey("P")
		T.ok(pauseOpen(), "the pause menu is open")
		T.eq(lastPaused(), true, "the server was asked to pause")
		T.ok(H.lastSent("State").paused, "the clock is stopped")
		pressKey("P")
		T.falsy(pauseOpen(), "the pause menu is closed")
		T.eq(lastPaused(), false, "the server was asked to resume")
		T.falsy(H.lastSent("State").paused, "the clock runs again")
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("the top bar pause button opens the menu, Resume closes it", function()
		boot()
		local pause = H.find(gui(), { name = "pause", class = "TextButton" })[1]
		T.ok(pause, "pause button in the top bar")
		H.click(pause)
		H.advance(0.3)
		T.ok(pauseOpen(), "the pause menu is open")
		T.eq(lastPaused(), true)
		H.click(button("Reprendre"))
		H.advance(0.3)
		T.falsy(pauseOpen(), "the pause menu is closed")
		T.eq(lastPaused(), false)
	end)

	T.test("Escape closes the pause menu", function()
		boot()
		pressKey("P")
		T.ok(pauseOpen())
		pressKey("Escape")
		T.falsy(pauseOpen(), "the pause menu is closed")
		T.eq(lastPaused(), false, "the server was asked to resume")
	end)

	T.test("the map controls are off behind the menu and back after the resume", function()
		boot()
		T.ge(dragRow(), 1, "drawing works in play")
		H.fireServer("EraseRoads", H.lastSent("RoadState").roads)
		H.advance(0.3)
		pressKey("P")
		T.eq(dragRow(), 0, "no road is drawn behind the pause menu")
		pressKey("P")
		T.ge(dragRow(), 1, "drawing works again after the resume")
	end)

	T.test("the speed buttons reach the server and the top bar follows its state", function()
		boot()
		H.click(H.find(gui(), { name = "speed2", class = "TextButton" })[1])
		H.advance(0.3)
		T.eq(H.lastSent("State").speed, 2)
		T.near(H.find(gui(), { name = "speed2", class = "TextButton" })[1]:FindFirstChild("SelectionRing").Transparency, 0, 1e-6)
	end)

	T.test("Restart starts a fresh game on the same map and resets the HUD", function()
		boot()
		H.advance(10)
		pressKey("P")
		local starts = #H.sent("GameStarted")
		local sentStarts = #H.sent("StartGame", "toServer")
		H.click(button("Recommencer"))
		H.advance(0.5)
		T.eq(#H.sent("StartGame", "toServer"), sentStarts + 1, "a new game was requested")
		T.eq(H.lastSent("GameStarted").mapId, "los_angeles", "same map")
		T.eq(#H.sent("GameStarted"), starts + 1, "the server started a new game")
		T.falsy(pauseOpen(), "no menu left open")
		T.falsy(H.lastSent("State").paused, "the new game is running")
		T.ge(dragRow(), 1, "the controls are back")
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("Main menu from the pause leaves the game for the lobby", function()
		boot()
		pressKey("P")
		H.click(button("Menu principal"))
		H.advance(0.5)
		T.ge(#H.sent("ReturnToLobby", "toServer"), 1)
		T.falsy(gui().Enabled, "the HUD is hidden")
		T.ok(H.localPlayer.PlayerGui.MM_Lobby.Enabled, "the lobby is back")
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("the hints setting hides the help and bringing it back does not leave it stuck", function()
		boot()
		T.ok(shown(hintLabel()), "the help is visible when the game starts")
		pressKey("P")
		H.click(button("Paramètres"))
		local row = H.find(gui(), { text = "Astuces" })[1].Parent
		H.click(row)
		H.advance(0.3)
		T.falsy(shown(hintLabel()), "hints off: the help is gone")
		H.advance(0.2)
		H.click(row)
		H.advance(0.3)
		T.ok(shown(hintLabel()), "hints on: the help is back")
		H.advance(30)
		T.falsy(shown(hintLabel()), "the help fades by itself like at the start of a game")
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("a new game honours the stored hints setting", function()
		boot()
		pressKey("P")
		H.click(button("Paramètres"))
		H.click(H.find(gui(), { text = "Astuces" })[1].Parent)
		H.advance(0.3)
		H.click(button("Retour"))
		H.click(button("Recommencer"))
		H.advance(0.5)
		T.falsy(shown(hintLabel()), "hints stay off in the new game")
	end)

	T.todo("the grid setting pins the grid and a new game keeps it (needs the world Grid folder from WorldBuilder: maps PR)", function()
		boot()
		local function gridTransparency()
			for _, world in ipairs(workspace:GetChildren()) do
				for _, found in ipairs(H.find(world, { name = "Grid" })) do
					for _, child in ipairs(found:GetChildren()) do
						if child:IsA("BasePart") then
							return child.Transparency, found
						end
					end
				end
			end
			return nil
		end
		-- Outil « main » : la règle automatique rend la grille discrète.
		pressKey("Four")
		local idle, grid = gridTransparency()
		T.ok(grid, "the world has a grid")
		T.eq(idle, grid:GetAttribute("BaseTransparency"), "grid discreet outside construction")
		pressKey("P")
		H.click(button("Paramètres"))
		H.click(H.find(gui(), { text = "Grille visible" })[1].Parent)
		H.advance(0.3)
		T.eq(gridTransparency(), grid:GetAttribute("ActiveTransparency"), "grid pinned visible")
	end)
end
