return function(T, H)
	-- Bout en bout : Bootstrap.server + Main.client dans le même monde simulé.
	-- Le client « clique » avec de vraies coordonnées d'écran (caméra, rayons),
	-- le serveur construit, les messages reviennent au client.

	local function boot(mapId)
		H.runScript("Bootstrap")
		H.asClient()
		H.runScript("Main")
		H.advance(0.1)
		H.fireServer("StartGame", mapId or "los_angeles")
		H.advance(0.5)
	end

	local function screenOf(x, y)
		local Config = H.load("Config")
		local origin = H.lastSent("GameStarted").origin
		local world = origin + Vector3.new((x + 0.5) * Config.Grid.TileSize, 0, (y + 0.5) * Config.Grid.TileSize)
		local point = workspace.CurrentCamera:WorldToViewportPoint(world)
		return point.X, point.Y
	end

	local function roadSet()
		local road = H.lastSent("RoadState")
		local set = {}
		for _, key in ipairs(road and road.roads or {}) do
			set[key] = true
		end
		return set, road
	end

	local function freeRow()
		-- Ligne de 6 cases libres à partir des bâtiments connus du client.
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

	local function drag(x1, y1, x2, y2)
		local sx1, sy1 = screenOf(x1, y1)
		local sx2, sy2 = screenOf(x2, y2)
		H.input.mouseMove(sx1, sy1)
		H.input.mouseDown(sx1, sy1, 1)
		local steps = 8
		for i = 1, steps do
			H.input.mouseMove(sx1 + (sx2 - sx1) * i / steps, sy1 + (sy2 - sy1) * i / steps)
		end
		return sx2, sy2
	end

	T.test("the server and client boot without warnings or errors and the lobby shows first", function()
		H.runScript("Bootstrap")
		H.asClient()
		H.runScript("Main")
		H.advance(0.1)
		T.eq(#H.handlerErrors, 0)
		local lobby = H.localPlayer.PlayerGui:FindFirstChild("MM_Lobby")
		T.ok(lobby and lobby.Enabled, "the lobby is visible at start")
		local hud = H.localPlayer.PlayerGui:FindFirstChild("MM_HUD")
		T.ok(hud and not hud.Enabled, "the HUD is hidden in the lobby")
		T.eq(H.W.coreGui.All, false, "default Roblox CoreGui is hidden")
		T.contains(H.warnings[#H.warnings], "Server ready")
	end)

	T.test("RequestProfile after a second returns the profile to the lobby", function()
		H.runScript("Bootstrap")
		H.asClient()
		H.runScript("Main")
		H.advance(1.5)
		T.ge(#H.sent("RequestProfile", "toServer"), 1)
		T.ge(#H.sent("Profile"), 1)
	end)

	T.test("StartGame from the lobby builds the world, hides the lobby, shows the HUD, focuses the camera", function()
		boot("los_angeles")
		T.eq(#H.handlerErrors, 0)
		T.ok(H.lastSent("GameStarted"))
		T.falsy(H.localPlayer.PlayerGui.MM_Lobby.Enabled)
		T.ok(H.localPlayer.PlayerGui.MM_HUD.Enabled)
		local camera = workspace.CurrentCamera
		T.lt(camera.CFrame.LookVector.Y, -0.98)
		local Config = H.load("Config")
		local origin = H.lastSent("GameStarted").origin
		local size = Config.Grid.Size * Config.Grid.TileSize
		-- La carte est centrée dans la zone libre (hors barres du HUD) : le centre de la
		-- caméra s'écarte un peu de celui de la carte, d'au plus un dixième de sa largeur.
		T.near(camera.CFrame.Position.X, origin.X + size / 2, size * 0.1)
		T.ok(workspace:FindFirstChild("MMWorlds"))
	end)

	T.test("an unknown map id falls back to the first map instead of crashing", function()
		H.runScript("Bootstrap")
		H.asClient()
		H.runScript("Main")
		H.fireServer("StartGame", "narnia")
		H.fireServer("StartGame", 42)
		H.fireServer("StartGame", nil)
		H.advance(0.5)
		T.eq(#H.handlerErrors, 0)
		T.ok(H.lastSent("GameStarted"))
	end)

	T.test("mouse drag draws a road exactly where the player drags it", function()
		boot()
		local x, y = freeRow()
		T.ok(x, "free row found")
		local ex, ey = drag(x, y, x + 5, y)
		H.input.mouseUp(ex, ey, 1)
		H.advance(0.5)
		local set = roadSet()
		for i = 0, 5 do
			T.ok(set[(x + i) .. ":" .. y], "road missing at " .. (x + i) .. ":" .. y)
		end
		local count = 0
		for _ in pairs(set) do
			count += 1
		end
		T.eq(count, 6, "no extra cell is built")
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("a diagonal drag becomes an orthogonal path (no diagonal cells)", function()
		boot()
		local x, y = freeRow()
		local ex, ey = drag(x, y, x + 3, y + 2)
		H.input.mouseUp(ex, ey, 1)
		H.advance(0.5)
		local set = roadSet()
		local cells = {}
		for key in pairs(set) do
			local cx, cy = key:match("(%-?%d+):(%-?%d+)")
			table.insert(cells, { tonumber(cx), tonumber(cy) })
		end
		T.ge(#cells, 4)
		for _, c in ipairs(cells) do
			local hasNeighbor = false
			for _, o in ipairs(cells) do
				if math.abs(c[1] - o[1]) + math.abs(c[2] - o[2]) == 1 then
					hasNeighbor = true
				end
			end
			T.ok(hasNeighbor, "every built cell is orthogonally connected to another")
		end
	end)

	T.test("Escape cancels a drag: nothing is built and no piece is spent", function()
		boot()
		local x, y = freeRow()
		local budget = H.lastSent("State").budget
		local ex, ey = drag(x, y, x + 4, y)
		H.input.key("Escape", true)
		H.input.key("Escape", false)
		H.input.mouseUp(ex, ey, 1)
		H.advance(0.5)
		T.eq(#H.sent("DrawRoad", "toServer"), 0, "no DrawRoad request after Escape")
		T.eq(H.lastSent("State").budget, budget)
	end)

	T.test("the road is only sent on release (the preview is local)", function()
		boot()
		local x, y = freeRow()
		local ex, ey = drag(x, y, x + 3, y)
		T.eq(#H.sent("DrawRoad", "toServer"), 0, "nothing sent while dragging")
		H.input.mouseUp(ex, ey, 1)
		T.eq(#H.sent("DrawRoad", "toServer"), 1)
	end)

	T.test("middle-button panning never builds a road", function()
		boot()
		local x, y = freeRow()
		local sx, sy = screenOf(x, y)
		H.input.mouseMove(sx, sy)
		H.input.mouseDown(sx, sy, 3)
		for i = 1, 10 do
			H.input.mouseMove(sx + i * 6, sy)
		end
		H.input.mouseUp(sx + 60, sy, 3)
		H.advance(0.5)
		T.eq(#H.sent("DrawRoad", "toServer"), 0)
		T.eq(#H.sent("EraseRoads", "toServer"), 0, "the middle button never erases")
		T.eq(#H.sent("EraseRoad", "toServer"), 0, "the middle button never erases")
	end)

	T.test("mouse wheel zooms within limits, in both directions", function()
		boot()
		local CameraController = H.load("CameraController")
		T.eq(CameraController.getZoom(), 1)
		local best = 1
		for _, direction in ipairs({ -1, 1 }) do
			for _ = 1, 40 do
				H.input.wheel(direction)
			end
			best = math.max(best, CameraController.getZoom())
			T.le(CameraController.getZoom(), 3.5)
			-- Revenir au point de départ avec la direction opposée.
			for _ = 1, 80 do
				H.input.wheel(-direction)
			end
			T.eq(CameraController.getZoom() <= 3.5 and CameraController.getZoom() >= 1, true)
			for _ = 1, 80 do
				H.input.wheel(direction)
			end
			for _ = 1, 80 do
				H.input.wheel(-direction)
			end
		end
		T.gt(best, 1.5, "scrolling must be able to zoom in")
	end)

	-- Contrôles (InputController) : touche 2 = outil gomme, puis clic gauche. Le
	-- clic droit gomme aussi, quel que soit l'outil (voir le test ci-dessous).
	T.test("erase tool (key 2) removes roads through the server", function()
		boot()
		local x, y = freeRow()
		local ex, ey = drag(x, y, x + 3, y)
		H.input.mouseUp(ex, ey, 1)
		H.advance(0.3)
		local before = roadSet()
		H.input.key("Two", true)
		H.input.key("Two", false)
		local sx, sy = screenOf(x + 1, y)
		H.input.mouseMove(sx, sy)
		H.input.mouseDown(sx, sy, 1)
		H.input.mouseUp(sx, sy, 1)
		H.advance(0.3)
		local after = roadSet()
		T.falsy(after[(x + 1) .. ":" .. y], "the cell under the cursor was erased")
		T.ok(before[(x + 1) .. ":" .. y])
		T.ok(after[x .. ":" .. y], "neighbouring cells survive a single erase")
	end)

	T.test("right-button drag erases the roads it crosses, through the server", function()
		boot()
		local x, y = freeRow()
		local ex, ey = drag(x, y, x + 3, y)
		H.input.mouseUp(ex, ey, 1)
		H.advance(0.3)
		local before = roadSet()
		T.ok(before[(x + 3) .. ":" .. y], "the road was built first")
		-- Clic droit maintenu sur les mêmes cases : tout le tracé s'efface.
		local sx1, sy1 = screenOf(x, y)
		local sx2, sy2 = screenOf(x + 3, y)
		H.input.mouseMove(sx1, sy1)
		H.input.mouseDown(sx1, sy1, 2)
		for i = 1, 8 do
			H.input.mouseMove(sx1 + (sx2 - sx1) * i / 8, sy1 + (sy2 - sy1) * i / 8)
		end
		H.input.mouseUp(sx2, sy2, 2)
		H.advance(0.3)
		local after = roadSet()
		for i = 0, 3 do
			T.falsy(after[(x + i) .. ":" .. y], "right-button drag left the road at " .. (x + i))
		end
		T.eq(#H.sent("DrawRoad", "toServer"), 1, "only the initial build was sent")
		T.ge(#H.sent("EraseRoads", "toServer"), 1, "the erase reached the server")
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("a right press during a left-button stroke never replaces it", function()
		boot()
		local x, y = freeRow()
		local sx1, sy1 = screenOf(x, y)
		local sx2, sy2 = screenOf(x + 2, y)
		H.input.mouseMove(sx1, sy1)
		H.input.mouseDown(sx1, sy1, 1)
		H.input.mouseMove(sx2, sy2)
		H.input.mouseDown(sx2, sy2, 2)
		H.input.mouseUp(sx2, sy2, 2)
		H.input.mouseUp(sx2, sy2, 1)
		H.advance(0.3)
		T.eq(#H.sent("EraseRoads", "toServer"), 0, "the right button never erased during the stroke")
		local set = roadSet()
		T.ok(set[(x + 2) .. ":" .. y], "the left stroke still completed")
	end)

	T.test("P asks the server to pause and the clock stops", function()
		boot()
		H.input.key("P", true)
		H.input.key("P", false)
		H.advance(0.5)
		T.ge(#H.sent("SetPaused", "toServer"), 1)
		T.ok(H.lastSent("State").paused)
		local before = H.lastSent("State").weekProgress
		H.advance(5)
		T.eq(H.lastSent("State").weekProgress, before)
	end)

	T.test("a full week: the reward choice opens on the client, choosing resumes the game", function()
		boot()
		H.advance(61)
		T.ok(H.lastSent("WeekChoice"), "the server offered a choice")
		T.ok(H.lastSent("State").awaitingChoice)
		local hud = H.localPlayer.PlayerGui.MM_HUD
		local cards = 0
		for _, b in ipairs(H.find(hud, { class = "GuiButton" })) do
			if b.Visible and b.AbsoluteSize.X > 100 and b.AbsoluteSize.Y > 100 then
				cards += 1
			end
		end
		T.ge(cards, 2, "reward cards are clickable buttons")
		local offer = H.lastSent("WeekChoice")
		local budget = H.lastSent("State").budget
		H.fireServer("ChooseReward", offer.options[1].id)
		H.advance(0.5)
		T.falsy(H.lastSent("State").awaitingChoice)
		T.gt(H.lastSent("State").budget, budget)
	end)

	T.test("the game keeps running under Heartbeat for a few minutes without errors", function()
		boot()
		local x, y = freeRow()
		local ex, ey = drag(x, y, x + 5, y)
		H.input.mouseUp(ex, ey, 1)
		for _ = 1, 4 do
			H.advance(60, { step = 0.1 })
			local state = H.lastSent("State")
			if state.awaitingChoice then
				H.fireServer("ChooseReward", H.lastSent("WeekChoice").options[1].id)
			end
		end
		T.eq(#H.handlerErrors, 0)
		T.ge(H.lastSent("State").week, 2)
	end)

	T.test("StoreState reaches the client and draws pins above the store", function()
		boot()
		H.advance(30)
		T.ok(H.lastSent("StoreState"))
		T.ge(#H.find(workspace, { name = "DemandPin" }), 1, "a demand pin should be visible after 30 s")
	end)

	T.test("game over: the client shows the end screen and stops accepting input", function()
		boot()
		for _ = 1, 20 do
			H.advance(60, { step = 0.2 })
			local state = H.lastSent("State")
			if state.awaitingChoice then
				H.fireServer("ChooseReward", H.lastSent("WeekChoice").options[1].id)
			end
			if state.over then
				break
			end
		end
		T.ok(H.lastSent("State").over, "the game must end without any road")
		T.ok(H.lastSent("GameOver"))
		local hud = H.localPlayer.PlayerGui.MM_HUD
		local found = false
		for _, d in ipairs(H.find(hud, { class = "TextLabel" })) do
			if string.find(d.Text, tostring(H.lastSent("GameOver").score), 1, true) then
				found = true
			end
		end
		T.ok(found)
		local x, y = freeRow()
		local sx, sy = screenOf(x, y)
		H.clearRemoteLog()
		H.input.mouseDown(sx, sy, 1)
		H.input.mouseUp(sx, sy, 1)
		T.eq(#H.sent("DrawRoad", "toServer"), 0, "input is disabled after the game ends")
	end)

	T.test("ReturnToLobby tears the session down", function()
		boot()
		H.fireServer("ReturnToLobby")
		H.advance(1)
		T.eq(#H.find(workspace.MMWorlds, { class = "BasePart" }), 0, "the session world is destroyed")
	end)

	T.test("oversized or malformed requests are ignored by the server", function()
		boot()
		local huge = {}
		for i = 1, 600 do
			huge[i] = { i % 18, 1 }
		end
		H.fireServer("DrawRoad", huge)
		H.fireServer("DrawRoad", "garbage")
		H.fireServer("DrawRoad", 12)
		H.fireServer("EraseRoad", 5)
		H.fireServer("EraseRoads", "x")
		H.fireServer("SetSpeed", "fast")
		H.fireServer("SetPaused", nil)
		H.fireServer("ChooseReward", 7)
		H.fireServer("PlaceRoundabout", "a", {})
		H.advance(0.5)
		T.eq(#H.handlerErrors, 0)
		local set = roadSet()
		T.eq(next(set), nil, "an oversized request builds nothing")
	end)

	local function pinCount()
		return #H.find(workspace, { name = "DemandPin" })
	end

	local function demandsInLastStoreState()
		local total = 0
		for _, store in ipairs(H.lastSent("StoreState").stores) do
			total += store.demands
		end
		return total
	end

	T.test("restarting a game resets score, roads and demand pins on the client", function()
		boot()
		local x, y = freeRow()
		local ex, ey = drag(x, y, x + 5, y)
		H.input.mouseUp(ex, ey, 1)
		H.advance(30)
		T.gt(pinCount(), 0)
		H.fireServer("StartGame", "los_angeles")
		H.advance(1)
		T.eq(H.lastSent("State").score, 0)
		local roadsNow = roadSet()
		T.eq(next(roadsNow), nil, "the new game starts without roads")
		T.eq(pinCount(), demandsInLastStoreState(), "client pins must mirror the server's demands after a restart")
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("client demand pins always mirror the server state while playing", function()
		boot()
		for _ = 1, 8 do
			H.advance(15)
			T.eq(pinCount(), demandsInLastStoreState())
			if H.lastSent("State").awaitingChoice then
				H.fireServer("ChooseReward", H.lastSent("WeekChoice").options[1].id)
			end
		end
	end)

	-- Every StartGame bumps Bootstrap's worldCounter, so the city origin moves
	-- 700 studs further on each restart (2800 after four): precision loss and
	-- unbounded world growth after many restarts.
	T.test("restarting reuses the player's world slot (origin stays bounded)", function()
		H.runScript("Bootstrap")
		H.asClient()
		H.runScript("Main")
		for _ = 1, 10 do
			H.fireServer("StartGame", "tokyo")
			H.advance(0.2)
		end
		local origin = H.lastSent("GameStarted").origin
		T.le(origin.X, 1500, "origin after ten restarts: " .. tostring(origin))
	end)
end
