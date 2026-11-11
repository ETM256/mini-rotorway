return function(T, H)
	-- Déplacement de la vue : la carte reste à l'écran à tout zoom, suit le
	-- curseur ou les doigts, et aucun geste de déplacement ne construit de route.

	local RESOLUTIONS = {
		{ 1920, 1080 },
		{ 1600, 900 },
		{ 1366, 768 },
		{ 1280, 720 },
		{ 844, 390 },
		{ 390, 844 },
	}
	local ZOOMS = { 1, 1.5, 2, 2.8 }
	-- Part minimale de l'écran couverte par la carte après un déplacement
	-- extrême, zoomé. Le pire cas mesuré est un écran large en coin (environ 0.49).
	local MIN_MAP_ON_SCREEN = 0.4
	local ORIGIN = Vector3.new(700, 0, 0)

	local function focus(width, height)
		H.asClient()
		H.setViewport(width, height)
		local CameraController = H.load("CameraController")
		local Config = H.load("Config")
		CameraController.focus(ORIGIN, Config.Grid.Size, Config.Grid.TileSize, true)
		return CameraController, workspace.CurrentCamera, Config
	end

	-- Une vraie partie : serveur, client, puis GameStarted qui cadre la caméra.
	local function startGame()
		H.reset()
		H.runScript("Bootstrap")
		H.asClient()
		H.setViewport(1920, 1080)
		H.runScript("Main")
		H.advance(0.1)
		H.fireServer("StartGame", "los_angeles")
		H.advance(1.5)
		return H.load("CameraController"), workspace.CurrentCamera, H.load("Config")
	end

	-- Centre de la carte, à l'écran comme dans le monde.
	local function mapCentre(Config)
		local half = Config.Grid.Size * Config.Grid.TileSize / 2
		return ORIGIN + Vector3.new(half, 0, half)
	end

	-- Part des points d'une grille 9 x 9 posée sur la carte qui tombent à l'écran.
	local function visibleShare(camera, Config)
		local size = Config.Grid.Size * Config.Grid.TileSize
		local visible, total = 0, 0
		for i = 0, 8 do
			for j = 0, 8 do
				local point = ORIGIN + Vector3.new(size * (i + 0.5) / 9, 0, size * (j + 0.5) / 9)
				local _, onScreen = camera:WorldToViewportPoint(point)
				total += 1
				if onScreen then
					visible += 1
				end
			end
		end
		return visible / total
	end

	-- Part de l'écran occupée par la carte : des rayons issus d'une grille de
	-- pixels touchent le sol, et on compte ceux qui tombent dans la carte.
	local function mapOnScreen(camera, Config)
		local size = Config.Grid.Size * Config.Grid.TileSize
		local view = camera.ViewportSize
		local covered, total = 0, 0
		for i = 0, 8 do
			for j = 0, 8 do
				local ray = camera:ViewportPointToRay(view.X * (i + 0.5) / 9, view.Y * (j + 0.5) / 9)
				total += 1
				if ray.Direction.Y < 0 then
					local hit = ray.Origin + ray.Direction * ((ORIGIN.Y - ray.Origin.Y) / ray.Direction.Y)
					local u, v = hit.X - ORIGIN.X, hit.Z - ORIGIN.Z
					if u >= 0 and u <= size and v >= 0 and v <= size then
						covered += 1
					end
				end
			end
		end
		return covered / total
	end

	-- Événements tactiles : le même objet suit un doigt de Began à Ended, comme
	-- le fait Roblox, et InputController le retrouve par son identité.
	local function touchAt(x, y)
		return {
			UserInputType = Enum.UserInputType.Touch,
			UserInputState = Enum.UserInputState.Begin,
			Position = Vector3.new(x, y, 0),
			Delta = Vector3.zero,
			KeyCode = Enum.KeyCode.Unknown,
		}
	end

	local function fireInput(signal, event)
		H.I.fire(H.I.getSignal(game.UserInputService, signal), event, false)
	end

	local function moveTouch(event, x, y)
		event.Position = Vector3.new(x, y, 0)
		fireInput("InputChanged", event)
	end

	T.test("at every zoom and every extreme pan, the map keeps covering the screen", function()
		for _, res in ipairs(RESOLUTIONS) do
			for _, zoom in ipairs(ZOOMS) do
				for _, sx in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						H.reset()
						local CameraController, camera, Config = focus(res[1], res[2])
						CameraController.setZoom(zoom)
						H.advance(2)
						CameraController.pan(sx * 1e6, sz * 1e6)
						local label = string.format("%dx%d zoom %.1f pan (%d,%d)", res[1], res[2], zoom, sx, sz)
						if zoom == 1 then
							T.eq(visibleShare(camera, Config), 1, label .. ": the whole map is framed and does not move")
						else
							T.ge(mapOnScreen(camera, Config), MIN_MAP_ON_SCREEN, label .. ": the map must not disappear")
						end
					end
				end
			end
		end
	end)

	T.test("the pan limit does not depend on the pan history", function()
		local CameraController, camera = focus(1920, 1080)
		CameraController.setZoom(2.5)
		H.advance(2)
		CameraController.pan(1e6, 0)
		local pushed = camera.CFrame.Position.X
		CameraController.pan(-1e6, 0)
		CameraController.pan(1e6, 0)
		T.near(camera.CFrame.Position.X, pushed, 1e-6, "pushing against the edge always gives the same view")
	end)

	T.test("a middle-button drag moves the map with the cursor, one pixel per pixel", function()
		local CameraController, camera, Config = startGame()
		CameraController.setZoom(2)
		H.advance(1)

		local before = camera:WorldToViewportPoint(mapCentre(Config))
		H.input.mouseMove(900, 500)
		H.input.mouseDown(900, 500, 3)
		H.input.mouseMove(900, 540)
		H.input.mouseUp(900, 540, 3)
		local after = camera:WorldToViewportPoint(mapCentre(Config))

		T.near(after.Y - before.Y, 40, 0.5, "the map follows the cursor downwards")
		T.near(after.X - before.X, 0, 0.5)
		T.falsy(H.lastSent("DrawRoad"), "a middle-button drag never draws a road")
		T.falsy(H.lastSent("EraseRoads"), "a middle-button drag never erases a road")
	end)

	T.test("two fingers move the map once, at the speed of the fingers, and build nothing", function()
		local CameraController, camera, Config = startGame()
		CameraController.setZoom(2)
		H.advance(1)

		-- Le premier doigt pose un tracé sur la carte : le second doigt doit l'annuler.
		local first = touchAt(900, 540)
		local second = touchAt(1020, 540)
		fireInput("InputBegan", first)
		fireInput("InputBegan", second)
		local before = camera:WorldToViewportPoint(mapCentre(Config))
		moveTouch(first, 900, 580)
		moveTouch(second, 1020, 580)
		fireInput("InputEnded", first)
		fireInput("InputEnded", second)
		local after = camera:WorldToViewportPoint(mapCentre(Config))

		T.near(after.Y - before.Y, 40, 0.5, "the centre moved by 40 px, not twice that")
		T.falsy(H.lastSent("DrawRoad"), "a two-finger gesture never draws a road")
	end)

	T.test("a pinch zooms by the finger spread, through RoadConfig.Input.PinchZoomGain", function()
		local CameraController, _, Config = startGame()
		local gain = H.load("RoadConfig").Input.PinchZoomGain
		local first = touchAt(900, 540)
		local second = touchAt(1020, 540)
		fireInput("InputBegan", first)
		fireInput("InputBegan", second)

		-- Écart 120 -> 240 px : rapport 2, donc zoom + (2 - 1) * gain.
		local zoom = CameraController.getZoom()
		moveTouch(second, 1140, 540)
		local expected = math.clamp(zoom + gain, Config.Camera.ZoomMin, Config.Camera.ZoomMax)
		T.near(CameraController.getZoom(), expected, 1e-6, "spreading the fingers zooms in")

		-- Écart 240 -> 120 px : rapport 0.5, le zoom revient du même montant.
		zoom = CameraController.getZoom()
		moveTouch(second, 1020, 540)
		expected = math.clamp(zoom - 0.5 * gain, Config.Camera.ZoomMin, Config.Camera.ZoomMax)
		T.near(CameraController.getZoom(), expected, 1e-6, "pinching back zooms out")

		fireInput("InputEnded", first)
		fireInput("InputEnded", second)
		T.falsy(H.lastSent("DrawRoad"), "a pinch never draws a road")
	end)

	T.test("panning is inert outside a game (lobby view)", function()
		local CameraController, camera = focus(1920, 1080)
		CameraController.lobby()
		local before = camera.CFrame
		CameraController.pan(500, 500)
		CameraController.panByPixels(120, -80)
		H.advance(1)
		T.eq(camera.CFrame, before)
	end)
end
