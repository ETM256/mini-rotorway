return function(T, H)
	local RESOLUTIONS = {
		{ 1920, 1080 },
		{ 1600, 900 },
		{ 1366, 768 },
		{ 1280, 720 },
		{ 844, 390 }, -- mobile paysage
		{ 390, 844 }, -- mobile portrait
	}

	local ORIGIN = Vector3.new(700, 0, 0)

	local function focus(width, height)
		H.asClient()
		H.setViewport(width, height)
		local CameraController = H.load("CameraController")
		local Config = H.load("Config")
		CameraController.focus(ORIGIN, Config.Grid.Size, Config.Grid.TileSize, true)
		return CameraController, workspace.CurrentCamera, Config
	end

	local function mapCorners(Config)
		local size = Config.Grid.Size * Config.Grid.TileSize
		return {
			ORIGIN,
			ORIGIN + Vector3.new(size, 0, 0),
			ORIGIN + Vector3.new(0, 0, size),
			ORIGIN + Vector3.new(size, 0, size),
		}
	end

	T.test("the camera looks (almost) straight down at the centre of the map", function()
		local _, camera, Config = focus(1920, 1080)
		local size = Config.Grid.Size * Config.Grid.TileSize
		local look = camera.CFrame.LookVector
		T.lt(look.Y, -0.98, "an overhead view, not a tilted perspective")
		T.near(camera.CFrame.Position.X, ORIGIN.X + size / 2, 1e-6)
		T.gt(camera.CFrame.Position.Y, size)
		T.eq(camera.CameraType, Enum.CameraType.Scriptable)
		T.le(camera.FieldOfView, 30, "a near-orthographic field of view")
	end)

	T.test("the whole map fits on screen at every target resolution", function()
		for _, res in ipairs(RESOLUTIONS) do
			H.reset()
			local _, camera, Config = focus(res[1], res[2])
			for i, corner in ipairs(mapCorners(Config)) do
				local point, onScreen = camera:WorldToViewportPoint(corner)
				T.ok(onScreen, string.format("%dx%d: map corner %d is off screen (%.0f, %.0f)", res[1], res[2], i, point.X, point.Y))
			end
		end
	end)

	T.test("the map fills a good part of the screen (not a tiny postage stamp)", function()
		for _, res in ipairs(RESOLUTIONS) do
			H.reset()
			local _, camera, Config = focus(res[1], res[2])
			local a = camera:WorldToViewportPoint(ORIGIN)
			local b = camera:WorldToViewportPoint(ORIGIN + Vector3.new(Config.Grid.Size * Config.Grid.TileSize, 0, 0))
			local width = math.abs(b.X - a.X)
			T.gt(width / math.min(res[1], res[2]), 0.6, string.format("%dx%d", res[1], res[2]))
		end
	end)

	T.test("changing the viewport recentres the map", function()
		local _, camera, Config = focus(1920, 1080)
		H.setViewport(844, 390)
		for _, corner in ipairs(mapCorners(Config)) do
			local _, onScreen = camera:WorldToViewportPoint(corner)
			T.ok(onScreen)
		end
	end)

	T.test("zoom is clamped, progressive and keeps the orientation", function()
		local CameraController, camera = focus(1920, 1080)
		local look0 = camera.CFrame.LookVector
		T.eq(CameraController.getZoom(), 1)
		CameraController.zoomBy(-5)
		T.eq(CameraController.getZoom(), 1, "no zooming out past the full map")
		local last = 1
		for _ = 1, 30 do
			CameraController.zoomBy(0.14)
			T.ge(CameraController.getZoom(), last)
			T.le(CameraController.getZoom() - last, 0.15, "zoom steps are progressive")
			last = CameraController.getZoom()
		end
		T.ge(last, 2)
		T.le(last, 3.5, "an upper zoom limit exists")
		CameraController.setZoom(99)
		T.eq(CameraController.getZoom(), H.load("Config").Camera.ZoomMax, "the target is clamped to ZoomMax")
		T.le(CameraController.getZoom(), 3.5)
		H.advance(1)
		T.ok(camera.CFrame.LookVector:FuzzyEq(look0, 0.01), "the camera keeps its orientation")
	end)

	T.test("zooming in actually brings the camera closer", function()
		local CameraController, camera = focus(1920, 1080)
		local before = camera.CFrame.Position.Y
		CameraController.setZoom(2)
		H.advance(1)
		T.lt(camera.CFrame.Position.Y, before * 0.6)
	end)

	T.test("panning is blocked at zoom 1 and limited when zoomed so the map never disappears", function()
		local CameraController, camera, Config = focus(1920, 1080)
		local size = Config.Grid.Size * Config.Grid.TileSize
		CameraController.pan(500, 500)
		H.advance(1)
		T.near(camera.CFrame.Position.X, ORIGIN.X + size / 2, 1e-6, "no pan at zoom 1")
		CameraController.setZoom(2.5)
		CameraController.pan(10000, -10000)
		CameraController.pan(10000, -10000)
		H.advance(1)
		local inside = 0
		for _, corner in ipairs(mapCorners(Config)) do
			local _, visible = camera:WorldToViewportPoint(corner)
			if visible then
				inside += 1
			end
		end
		T.ge(inside, 1, "after the largest pan a part of the map must still be on screen")
		T.le(inside, 3, "zoomed in, not every corner fits")
	end)

	T.test("zoom and pan are inert outside a game (lobby view)", function()
		local CameraController, camera = focus(1920, 1080)
		CameraController.lobby()
		local cf = camera.CFrame
		CameraController.zoomBy(1)
		CameraController.pan(10, 10)
		CameraController.setZoom(2)
		H.advance(1)
		T.eq(camera.CFrame, cf)
		T.eq(CameraController.getMapSize(), 0)
	end)

	-- La distance de la caméra (Position.Y, pose au-dessus de la carte) se règle
	-- image par image vers la cible du zoom : pas d'à-coup, pas de dépassement.
	T.test("zoom eases toward its clamped target frame by frame, without overshoot, and converges", function()
		local CameraController, camera, Config = focus(1920, 1080)
		local Camera = Config.Camera
		local size = Config.Grid.Size * Config.Grid.TileSize
		local startY = camera.CFrame.Position.Y
		-- Au zoom 1 la distance vaut size * Fit / 2 / tan(FOV / 2) : repère indépendant du code.
		T.near(startY, size * Camera.Fit * 0.5 / math.tan(math.rad(Camera.FOV) * 0.5), startY * 1e-3)

		CameraController.setZoom(99)
		T.eq(CameraController.getZoom(), Camera.ZoomMax, "the target is clamped to ZoomMax")
		T.eq(camera.CFrame.Position.Y, startY, "nothing moves before a frame is rendered")

		local previousY, firstY = startY, nil
		for _ = 1, 90 do -- 3 s de frames à 30 Hz
			H.advance(1 / 30)
			local y = camera.CFrame.Position.Y
			T.le(y, previousY + 1e-9, "the camera never moves away while zooming in")
			firstY = firstY or y
			previousY = y
		end
		T.lt(firstY, startY, "the first frame already moves the camera")
		T.gt(firstY, previousY + startY * 0.01, "one frame is not the end: the move is tweened, not snapped")
		T.near(previousY, startY / Camera.ZoomMax, startY * 1e-3, "converged to the zoom target")

		H.advance(1)
		T.near(camera.CFrame.Position.Y, previousY, 1e-6, "stays at the target once settled")
	end)
end
