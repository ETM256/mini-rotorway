return function(T, H)
	-- Robustesse des entrées, de la caméra et du câblage client face à ce que
	-- Roblox peut faire en vrai : doigt jamais relâché, fenêtre perdue clic milieu
	-- tenu, valeurs non finies, composant d'interface en échec au démarrage.

	local ORIGIN = Vector3.new(700, 0, 0)

	local function boot()
		H.runScript("Bootstrap")
		H.asClient()
		H.runScript("Main")
		H.advance(0.1)
		H.fireServer("StartGame", "los_angeles")
		H.advance(1.5)
	end

	local function screenOf(x, y)
		local Config = H.load("Config")
		local origin = H.lastSent("GameStarted").origin
		local world = origin + Vector3.new((x + 0.5) * Config.Grid.TileSize, 0, (y + 0.5) * Config.Grid.TileSize)
		local point = workspace.CurrentCamera:WorldToViewportPoint(world)
		return point.X, point.Y
	end

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

	local function poseOf()
		return workspace.CurrentCamera.CFrame
	end

	local function isNumber(cframe)
		for _, value in ipairs({ cframe:GetComponents() }) do
			if value ~= value or math.abs(value) == math.huge then
				return false
			end
		end
		return true
	end

	-- ------------------------------------------------------------- pause ---

	T.test("P toggles the pause exactly once per key press, through Main only", function()
		boot()
		local before = #H.sent("SetPaused", "toServer")
		H.input.key("P", true)
		H.input.key("P", false)
		H.advance(0.3)
		T.eq(#H.sent("SetPaused", "toServer") - before, 1, "one SetPaused for one press")
		H.input.key("P", true)
		H.input.key("P", false)
		H.advance(0.3)
		T.eq(#H.sent("SetPaused", "toServer") - before, 2, "the second press resumes, once")
	end)

	T.test("InputController ignores the P key: the pause belongs to Main", function()
		H.asClient()
		local InputController = H.load("InputController")
		local requested = 0
		local controller = InputController.new({
			onPauseRequest = function()
				requested += 1
			end,
		})
		controller:setEnabled(true)
		H.input.key("P", true)
		H.input.key("P", false)
		T.eq(requested, 0)
		controller:destroy()
	end)

	-- ------------------------------------------------------------- tactile ---

	T.test("a finger whose end never arrived does not block the next stroke", function()
		boot()
		local x, y = freeRow()
		T.ok(x, "a free row of 6 cells is needed")
		local lostX, lostY = screenOf(x, y + 1)
		H.input.touchBegin(1, lostX, lostY)
		-- Roblox le donne pour terminé, mais InputEnded n'a jamais été diffusé.
		H.W.fingers[1].UserInputState = Enum.UserInputState.End
		H.W.fingers[1] = nil

		local sx, sy = screenOf(x, y)
		H.input.touchBegin(2, sx, sy)
		for i = 1, 3 do
			local mx, my = screenOf(x + i, y)
			H.input.touchMove(2, mx, my)
		end
		H.input.touchEnd(2, screenOf(x + 3, y))
		H.advance(0.3)
		local sent = H.sent("DrawRoad", "toServer")
		T.eq(#sent, 1, "the new finger still draws a road")
		T.eq(#sent[1][1], 4)
	end)

	-- ------------------------------------------------------------ fenêtre ---

	T.test("losing the window with the middle button held stops the pan", function()
		boot()
		-- À zoom 1 la carte tient entière : le déplacement n'a de portée qu'une fois zoomé.
		H.load("CameraController").setZoom(2.5)
		H.advance(2)
		local start = poseOf().Position
		H.input.mouseMove(900, 500)
		H.input.mouseDown(900, 500, 3)
		H.input.mouseMove(910, 500)
		H.advance(0.1)
		local moved = poseOf().Position
		T.gt((moved - start).Magnitude, 0.1, "the middle drag pans the view")
		H.I.fire(H.I.getSignal(game.UserInputService, "WindowFocusReleased"))
		H.input.mouseMove(920, 500)
		H.advance(0.1)
		T.near((poseOf().Position - moved).Magnitude, 0, 1e-6, "the view no longer follows the cursor")
	end)

	-- ------------------------------------------------------------ caméra ---

	T.test("non-finite zoom and pan requests never poison the camera pose", function()
		H.asClient()
		H.setViewport(1920, 1080)
		local CameraController = H.load("CameraController")
		local Config = H.load("Config")
		CameraController.focus(ORIGIN, Config.Grid.Size, Config.Grid.TileSize, true)
		local reference = poseOf()
		CameraController.zoomBy(0 / 0)
		CameraController.setZoom(math.huge)
		CameraController.pan(0 / 0, 0)
		CameraController.pan(0, -math.huge)
		CameraController.panByPixels(0 / 0, 5)
		CameraController.setSafeInsets(math.huge, 0 / 0, -4, math.huge)
		H.advance(1)
		T.ok(isNumber(poseOf()), "every component of the pose is finite")
		T.eq(CameraController.getZoom(), 1, "the zoom target is unchanged")
		T.near((poseOf().Position - reference.Position).Magnitude, 0, 1e-6)
	end)

	T.test("a focus on an invalid map leaves the camera in its previous state", function()
		H.asClient()
		H.setViewport(1920, 1080)
		local CameraController = H.load("CameraController")
		CameraController.lobby()
		local lobby = poseOf()
		CameraController.focus(nil, 18, 4, true)
		CameraController.focus(ORIGIN, 0 / 0, 4, true)
		CameraController.focus(ORIGIN, 18, 0, true)
		CameraController.zoomBy(1)
		CameraController.pan(5, 5)
		T.eq(CameraController.getMapSize(), 0, "no map is registered")
		T.near((poseOf().Position - lobby.Position).Magnitude, 0, 1e-9, "the lobby pose is kept")
	end)

	T.test("a tiny or zero viewport at startup still gives a finite pose", function()
		H.asClient()
		local CameraController = H.load("CameraController")
		local Config = H.load("Config")
		for _, size in ipairs({ { 1, 1 }, { 0, 0 }, { 1, 800 }, { 800, 1 } }) do
			H.setViewport(size[1], size[2])
			CameraController.focus(ORIGIN, Config.Grid.Size, Config.Grid.TileSize, false)
			H.advance(1)
			T.ok(isNumber(poseOf()), string.format("%dx%d: finite pose", size[1], size[2]))
			CameraController.setSafeInsets(60, 20, 90, 20)
			T.ok(isNumber(poseOf()), string.format("%dx%d: finite pose with insets", size[1], size[2]))
		end
	end)

	-- ------------------------------------------------------------ démarrage ---

	T.test("a HUD that fails to show does not keep the camera and the input from starting", function()
		H.runScript("Bootstrap")
		H.asClient()
		local HUD = H.load("UI/HUD")
		HUD.showGame = function()
			error("simulated HUD failure")
		end
		H.runScript("Main")
		H.advance(0.1)
		H.fireServer("StartGame", "los_angeles")
		H.advance(1.5)

		local found = false
		for _, text in ipairs(H.warnings) do
			if string.find(text, "simulated HUD failure", 1, true) then
				found = true
			end
		end
		T.ok(found, "the failure is reported, not swallowed")

		local started = H.lastSent("GameStarted")
		local half = started.size * started.tile / 2
		local expected = started.origin + Vector3.new(half, 0, half)
		local camera = workspace.CurrentCamera
		T.eq(camera.CameraType, Enum.CameraType.Scriptable)
		local ray = camera.CFrame
		local aim = ray.Position + ray.LookVector * (-ray.Position.Y / ray.LookVector.Y)
		-- Les marges du HUD décalent légèrement la visée : elle reste au cœur de la carte.
		T.lt((aim - expected).Magnitude, half * 0.25, "the camera looks at the middle of the map")

		local x, y = freeRow()
		T.ok(x, "a free row of 6 cells is needed")
		local sx, sy = screenOf(x, y)
		H.input.mouseMove(sx, sy)
		H.input.mouseDown(sx, sy, 1)
		local mx, my = screenOf(x + 2, y)
		H.input.mouseMove(mx, my)
		H.input.mouseUp(mx, my, 1)
		H.advance(0.3)
		T.eq(#H.sent("DrawRoad", "toServer"), 1, "the input is enabled and draws")
	end)
end
