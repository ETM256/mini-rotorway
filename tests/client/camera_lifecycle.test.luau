return function(T, H)
	-- Cycle de vie de la caméra : arrivée sur la carte, retour au lobby, reprise,
	-- changements de résolution et absence de fuite de connexions.

	local RESOLUTIONS = {
		{ 1920, 1080 },
		{ 1366, 768 },
		{ 844, 390 },
		{ 390, 844 },
	}
	-- Part minimale de l'écran couverte par la carte, zoomé et déplacé à l'extrême.
	local MIN_MAP_ON_SCREEN = 0.4
	local ORIGIN = Vector3.new(700, 0, 0)

	local function setup(width, height)
		H.asClient()
		H.setViewport(width, height)
		local CameraController = H.load("CameraController")
		local Config = H.load("Config")
		local size = Config.Grid.Size
		local tile = Config.Grid.TileSize
		return CameraController, workspace.CurrentCamera, Config, size, tile
	end

	local function heightAt(Config, zoom)
		local mapSize = Config.Grid.Size * Config.Grid.TileSize
		local halfFov = math.tan(math.rad(Config.Camera.FOV) * 0.5)
		return mapSize * Config.Camera.Fit / zoom * 0.5 / halfFov
	end

	-- Part de l'écran occupée par la carte (rayons depuis une grille de pixels).
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

	T.test("an arrival from the lobby descends from a wider view to the framed map", function()
		local CameraController, camera, Config, size, tile = setup(1920, 1080)
		CameraController.focus(ORIGIN, size, tile, false)
		local final = heightAt(Config, 1)
		local start = camera.CFrame.Position.Y
		T.gt(start, final * 1.2, "the camera starts further away")
		H.advance(0.3)
		local middle = camera.CFrame.Position.Y
		T.lt(middle, start, "the camera is coming down")
		T.gt(middle, final, "and is not there yet")
		H.advance(1)
		T.near(camera.CFrame.Position.Y, final, 1e-3, "the framed height is reached")
	end)

	T.test("the lobby view uses the lobby field of view and never moves the map", function()
		local CameraController, camera, Config, size, tile = setup(1920, 1080)
		CameraController.focus(ORIGIN, size, tile, true)
		CameraController.lobby()
		T.eq(camera.FieldOfView, Config.Camera.LobbyFOV)
		T.eq(camera.CameraType, Enum.CameraType.Scriptable)
		T.eq(CameraController.getMapSize(), 0)
	end)

	T.test("a viewport change re-clamps the pan so the map stays on screen", function()
		local CameraController, camera, Config, size, tile = setup(1920, 1080)
		CameraController.focus(ORIGIN, size, tile, true)
		CameraController.setZoom(2.8)
		H.advance(2)
		CameraController.pan(1e6, -1e6)
		for _, res in ipairs(RESOLUTIONS) do
			H.setViewport(res[1], res[2])
			H.advance(0.2)
			T.ge(mapOnScreen(camera, Config), MIN_MAP_ON_SCREEN, string.format("%dx%d: the map keeps covering the screen", res[1], res[2]))
		end
	end)

	T.test("repeated focus and lobby transitions raise no error and leak no connection", function()
		local CameraController, _, Config, size, tile = setup(1920, 1080)
		local function cycle(index)
			CameraController.focus(ORIGIN, size, tile, index % 2 == 0)
			CameraController.setZoom(1 + index % 3)
			CameraController.pan(200, -150)
			H.advance(0.3)
			CameraController.lobby()
			H.advance(0.1)
		end
		cycle(1)
		local baseline = H.connectionCount()
		for index = 2, 26 do
			cycle(index)
		end
		T.eq(#H.handlerErrors, 0, "no handler error during the transitions")
		T.eq(H.connectionCount(), baseline, "the camera does not accumulate connections")
		T.ok(Config.Camera.LobbyFOV > 0)
	end)

	T.test("zoom and pan requested before any focus are ignored", function()
		local CameraController, camera = setup(1920, 1080)
		CameraController.lobby()
		local before = camera.CFrame
		CameraController.zoomBy(1)
		CameraController.setZoom(2)
		CameraController.pan(10, 10)
		H.advance(1)
		T.eq(camera.CFrame, before)
		T.eq(CameraController.getZoom(), 1)
	end)
end
