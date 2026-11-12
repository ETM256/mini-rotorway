return function(T, H)
	-- Bootstrap.server reçoit des payloads de clients non fiables : ces tests
	-- envoient des entrées valides, invalides et hostiles depuis de faux joueurs.

	local function lastFor(player, remote)
		local found = nil
		for _, entry in ipairs(H.remoteLog()) do
			if entry.remote == remote and entry.dir == "toClient" and entry.player == player then
				found = entry.args[1]
			end
		end
		return found
	end

	local function countFor(player, remote)
		local n = 0
		for _, entry in ipairs(H.remoteLog()) do
			if entry.remote == remote and entry.dir == "toClient" and entry.player == player then
				n += 1
			end
		end
		return n
	end

	local function startAs(player, mapId)
		H.localPlayer = player
		H.fireServer("StartGame", mapId or "los_angeles")
		H.advance(0.2)
	end

	-- StartGame suit un seau à jetons (rafale 3, puis un départ toutes les 2 s) :
	-- on attend assez pour que chaque relance soit servie.
	local function restartAs(player, mapId)
		H.advance(2.5)
		startAs(player, mapId)
	end

	local function worldsFolder()
		return workspace:FindFirstChild("MMWorlds")
	end

	local function countWarnings(text)
		local n = 0
		for _, line in ipairs(H.warnings) do
			if string.find(line, text, 1, true) then
				n += 1
			end
		end
		return n
	end

	T.test("hostile and malformed payloads change nothing and throw nothing", function()
		H.runScript("Bootstrap")
		H.fireServer("StartGame", "los_angeles")
		H.advance(0.2)
		local state = H.lastSent("State")
		local roads = #H.lastSent("RoadState").roads
		local big = {}
		for i = 1, 600 do
			big[i] = { i % 18, 1 }
		end
		local sparse = { [1] = { 0, 1 }, [3] = { 0, 2 } }
		local withNames = { { 0, 1 }, name = "x" }
		local cases = {
			function() H.fireServer("DrawRoad", "garbage") end,
			function() H.fireServer("DrawRoad", 12) end,
			function() H.fireServer("DrawRoad", big) end,
			function() H.fireServer("DrawRoad", { "x" }) end,
			function() H.fireServer("DrawRoad", { { 0, 0 / 0 } }) end,
			function() H.fireServer("DrawRoad", { { math.huge, 1 } }) end,
			function() H.fireServer("DrawRoad", sparse) end,
			function() H.fireServer("DrawRoad", withNames) end,
			function() H.fireServer("DrawRoad", { { 0, 1, { 0, 1 } } }) end,
			function() H.fireServer("EraseRoad", 5) end,
			function() H.fireServer("EraseRoad", string.rep("1", 200)) end,
			function() H.fireServer("EraseRoads", "x") end,
			function() H.fireServer("EraseRoads", { 1, 2 }) end,
			function() H.fireServer("SetSpeed", "fast") end,
			function() H.fireServer("SetSpeed", 0 / 0) end,
			function() H.fireServer("SetPaused", nil) end,
			function() H.fireServer("SetPaused", "yes") end,
			function() H.fireServer("PlaceRoundabout", "a", {}) end,
			function() H.fireServer("PlaceRoundabout", 0 / 0, 1) end,
			function() H.fireServer("ChooseReward", 7) end,
			function() H.fireServer("ChooseReward", string.rep("x", 300)) end,
		}
		for _, case in ipairs(cases) do
			case()
		end
		H.advance(0.5)
		T.eq(#H.handlerErrors, 0, "no handler error")
		local after = H.lastSent("State")
		T.eq(after.budget, state.budget, "budget unchanged")
		T.eq(after.speed, state.speed, "speed unchanged")
		T.eq(after.paused, false, "not paused by a bad SetPaused")
		T.eq(#H.lastSent("RoadState").roads, roads, "no road created")
	end)

	T.test("a valid road is accepted (control for the test above)", function()
		H.runScript("Bootstrap")
		startAs(H.newPlayer("Builder", 2001))
		local Maps = H.load("Maps")
		local map = Maps.getById("los_angeles")
		local taken = {}
		for _, key in ipairs(H.lastSent("RoadState").buildings) do
			taken[key] = true
		end
		local cell = nil
		for y = 0, 17 do
			for x = 0, 17 do
				if not cell and not taken[x .. ":" .. y] and not Maps.isWater(map, x, y) then
					cell = { x, y }
				end
			end
		end
		T.ok(cell, "a free land cell exists")
		H.fireServer("DrawRoad", { cell })
		H.advance(0.3)
		T.eq(#H.lastSent("RoadState").roads, 1, "one road built")
	end)

	T.test("actions without an active session are ignored silently", function()
		H.runScript("Bootstrap")
		H.fireServer("DrawRoad", { { 1, 1 } })
		H.fireServer("EraseRoad", "1:1")
		H.fireServer("SetSpeed", 2)
		H.fireServer("SetPaused", true)
		H.fireServer("PlaceRoundabout", 1, 1)
		H.fireServer("ChooseReward", "any")
		H.fireServer("ReturnToLobby")
		H.advance(0.5)
		T.eq(#H.handlerErrors, 0)
		local noise = 0
		for _, line in ipairs(H.warnings) do
			if not string.find(line, "Server ready", 1, true) then
				noise += 1
			end
		end
		T.eq(noise, 0, "nothing to report for a client without a session")
		T.eq(worldsFolder() and #worldsFolder():GetChildren() or 0, 0)
	end)

	T.test("returning to the lobby destroys the world; later actions are ignored", function()
		H.runScript("Bootstrap")
		local player = H.newPlayer("Lobbyist", 2006)
		startAs(player)
		T.eq(#worldsFolder():GetChildren(), 1, "the world exists during the game")
		H.localPlayer = player
		H.fireServer("ReturnToLobby")
		H.advance(0.2)
		T.eq(#worldsFolder():GetChildren(), 0, "the world is gone")
		H.fireServer("SetSpeed", 2)
		H.fireServer("DrawRoad", { { 1, 1 } })
		H.advance(0.3)
		T.eq(#H.handlerErrors, 0, "no error after returning to the lobby")
		T.eq(#worldsFolder():GetChildren(), 0, "nothing is rebuilt")
	end)

	T.test("rate limit: a burst is capped, then tokens refill over time", function()
		H.runScript("Bootstrap")
		startAs(H.newPlayer("Flooder", 2002))
		local Session = H.load("Session")
		local calls = 0
		local original = Session.setSpeed
		Session.setSpeed = function(self, value)
			calls += 1
			return original(self, value)
		end
		for _ = 1, 40 do
			H.fireServer("SetSpeed", 2)
		end
		T.ge(calls, 1, "the first requests are served")
		T.le(calls, 10, "the burst is capped (SetSpeed burst = 10)")

		H.advance(1)
		local before = calls
		for _ = 1, 20 do
			H.fireServer("SetSpeed", 3)
		end
		T.ge(calls - before, 3, "tokens refill after a second")
		T.le(calls - before, 5, "refill is limited to the configured rate")
	end)

	T.test("one player's flood does not starve another player", function()
		H.runScript("Bootstrap")
		local flooder = H.newPlayer("Flooder", 2003)
		local other = H.newPlayer("Calm", 2004)
		startAs(flooder)
		startAs(other)
		for _ = 1, 50 do
			H.localPlayer = flooder
			H.fireServer("SetSpeed", 2)
		end
		H.localPlayer = other
		H.fireServer("SetSpeed", 3)
		H.advance(0.3)
		T.eq(lastFor(other, "State").speed, 3, "the calm player's request is served")
	end)

	T.test("StartGame twice keeps exactly one world and the same origin", function()
		H.runScript("Bootstrap")
		local player = H.newPlayer("Restarter", 2005)
		startAs(player, "tokyo")
		local origins = { lastFor(player, "GameStarted").origin }
		for i = 2, 4 do
			restartAs(player, "tokyo")
			origins[i] = lastFor(player, "GameStarted").origin
		end
		T.eq(countFor(player, "GameStarted"), 4, "every restart is served")
		T.eq(#worldsFolder():GetChildren(), 1, "the previous world is destroyed")
		for i = 2, 4 do
			T.near(origins[i].X, origins[1].X, 1e-6, "same origin after restart " .. i)
		end
	end)

	T.test("world origins are recycled: a leaving player's slot goes to the next player", function()
		H.runScript("Bootstrap")
		local a = H.newPlayer("A", 3001)
		local b = H.newPlayer("B", 3002)
		startAs(a)
		startAs(b)
		local originA = lastFor(a, "GameStarted").origin
		local originB = lastFor(b, "GameStarted").origin
		T.ne(originA.X, originB.X, "two players never share an origin")

		H.I.fire(H.I.getSignal(game.Players, "PlayerRemoving"), a)
		local c = H.newPlayer("C", 3003)
		startAs(c)
		T.near(lastFor(c, "GameStarted").origin.X, originA.X, 1e-6, "the freed slot is reused")
		T.eq(#worldsFolder():GetChildren(), 2, "A's world is gone, B and C remain")
	end)

	T.test("a player who keeps restarting never drifts further away", function()
		H.runScript("Bootstrap")
		local player = H.newPlayer("Drifter", 3004)
		startAs(player)
		local first = lastFor(player, "GameStarted").origin.X
		for _ = 1, 10 do
			restartAs(player)
		end
		T.eq(countFor(player, "GameStarted"), 11, "every restart is served")
		T.near(lastFor(player, "GameStarted").origin.X, first, 1e-6, "origin after ten restarts")
	end)

	T.test("leaving the server destroys the session and saves the profile exactly once", function()
		H.runScript("Bootstrap")
		local player = H.newPlayer("Leaver", 3005)
		startAs(player)
		H.load("Profile").submit(player, "los_angeles", 420)
		local store = H.W.dataStores.MiniMotorwaysV1
		local writes = 0
		local real = store.SetAsync
		store.SetAsync = function(self, key, value)
			if key == "player_3005" then
				writes += 1
			end
			return real(self, key, value)
		end

		H.I.fire(H.I.getSignal(game.Players, "PlayerRemoving"), player)
		H.I.fire(H.I.getSignal(game.Players, "PlayerRemoving"), player)
		T.eq(#worldsFolder():GetChildren(), 0, "the world is destroyed")
		T.eq(writes, 1, "one write, no second save on a repeated event")
		local saved = store._data["player_3005"]
		T.eq(saved.schema, 2)
		T.eq(saved.records.los_angeles, 420)
	end)

	T.test("a player who leaves while the profile is loading gets no world", function()
		H.runScript("Bootstrap")
		-- Le DataStore répond lentement : la partie attend la lecture du profil.
		H.load("Profile")
		local store = H.W.dataStores.MiniMotorwaysV1
		local real = store.GetAsync
		store.GetAsync = function(self, key)
			task.wait(1)
			return real(self, key)
		end
		local player = H.newPlayer("Early", 6001)
		H.localPlayer = player
		H.fireServer("StartGame", "los_angeles")
		H.advance(0.2)
		H.I.fire(H.I.getSignal(game.Players, "PlayerRemoving"), player)
		H.advance(2)
		T.eq(countFor(player, "GameStarted"), 0, "no game starts for a player who left")
		T.eq(worldsFolder() and #worldsFolder():GetChildren() or 0, 0, "no world is built")
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("a session that cannot be built is reported by Toast and leaves no world", function()
		H.runScript("Bootstrap")
		local Session = H.load("Session")
		local original = Session.new
		Session.new = function()
			error("construction impossible")
		end
		local player = H.newPlayer("Unbuilt", 6002)
		startAs(player)
		Session.new = original

		T.eq(#H.handlerErrors, 0, "the error does not reach the engine")
		T.eq(countFor(player, "GameStarted"), 0, "no game started")
		T.ok(countFor(player, "Toast") >= 1, "the player is told by Toast")
		T.eq(#worldsFolder():GetChildren(), 0, "no world left behind")
		T.ge(countWarnings("session"), 1, "the failure is reported on the server")
	end)

	T.test("a failing session is stopped alone and its player is told by Toast", function()
		H.runScript("Bootstrap")
		local alice = H.newPlayer("Alice", 4001)
		local bob = H.newPlayer("Bob", 4002)
		startAs(alice, "los_angeles")
		startAs(bob, "tokyo")

		local Session = H.load("Session")
		local original = Session.update
		local updates = {}
		Session.update = function(self, dt)
			local name = self.player.Name
			updates[name] = (updates[name] or 0) + 1
			if self.player == bob then
				error("panne simulee")
			end
			return original(self, dt)
		end
		H.advance(1)

		T.eq(updates.Bob, 1, "Bob's session is destroyed after its first failure")
		T.ge(updates.Alice, 5, "Alice's session keeps running")
		T.eq(#H.handlerErrors, 0, "the loop itself does not die")
		T.eq(#worldsFolder():GetChildren(), 1, "only Alice's world remains")
		T.ok(countFor(bob, "Toast") >= 1, "Bob receives a Toast")
		T.ge(countWarnings("session"), 1, "the failure is reported on the server")
	end)

	T.test("a handler error is reported once per kind and never reaches the engine", function()
		H.runScript("Bootstrap")
		startAs(H.newPlayer("Breaker", 4003))
		local Session = H.load("Session")
		Session.drawRoad = function()
			error("erreur simulee dans drawRoad")
		end
		H.fireServer("DrawRoad", { { 1, 1 } })
		H.fireServer("DrawRoad", { { 2, 1 } })
		H.advance(0.3)
		T.eq(#H.handlerErrors, 0, "the error is caught by the server")
		T.eq(countWarnings("DrawRoad"), 1, "same kind of error is reported once")
	end)

	T.test("reset and profile requests answer with the Profile remote", function()
		H.runScript("Bootstrap")
		local player = H.newPlayer("Resetter", 5001)
		H.localPlayer = player
		H.fireServer("RequestProfile")
		H.advance(0.1)
		T.ok(lastFor(player, "Profile"), "profile sent on request")
		H.fireServer("ResetRecords")
		H.advance(0.1)
		T.eq(next(lastFor(player, "Profile")), nil, "an empty profile after reset")
	end)

	T.test("lighting: post effects are removed and shadows stay off", function()
		local Lighting = game:GetService("Lighting")
		for _, className in ipairs({ "BloomEffect", "SunRaysEffect", "BlurEffect", "ColorCorrectionEffect", "Atmosphere" }) do
			Instance.new(className).Parent = Lighting
		end
		H.runScript("Bootstrap")
		for _, className in ipairs({ "BloomEffect", "SunRaysEffect", "BlurEffect", "ColorCorrectionEffect", "Atmosphere" }) do
			T.falsy(Lighting:FindFirstChildOfClass(className), className .. " must be removed")
		end
		T.eq(Lighting.GlobalShadows, false)
		T.ok(Lighting.Brightness <= 1, "a soft, not glaring, light")
	end)

	T.test("bootstrap is safe to run twice (no duplicated worlds folder)", function()
		H.runScript("Bootstrap")
		H.runScript("Bootstrap")
		local count = 0
		for _, child in ipairs(workspace:GetChildren()) do
			if child.Name == "MMWorlds" then
				count += 1
			end
		end
		T.eq(count, 1)
	end)
end
