return function(T, H)
	-- Zoom à la molette : limites, sens, lissage sans dépassement, indépendance
	-- de la fréquence d'images, et absence de travail par frame au repos.

	-- Hauteur de la caméra au-dessus de la carte pour un zoom donné, en vue 16:9
	-- (la hauteur est alors la dimension qui fixe le cadrage).
	local function heightAt(Config, zoom)
		local mapSize = Config.Grid.Size * Config.Grid.TileSize
		local halfFov = math.tan(math.rad(Config.Camera.FOV) * 0.5)
		return mapSize * Config.Camera.Fit / zoom * 0.5 / halfFov
	end

	-- Démarre une vraie partie : serveur, client, puis GameStarted (qui cadre la
	-- caméra). Le client est alors prêt à recevoir la molette.
	local function startGame(width, height)
		H.runScript("Bootstrap")
		H.asClient()
		H.setViewport(width or 1920, height or 1080)
		H.runScript("Main")
		H.advance(0.1)
		H.fireServer("StartGame", "los_angeles")
		H.advance(0.5)
		-- L'arrivée sur la carte dure IntroSeconds : on la laisse se terminer.
		H.advance(1)
		local CameraController = H.load("CameraController")
		return CameraController, workspace.CurrentCamera, H.load("Config")
	end

	T.test("the wheel zooms in when scrolled forward and out when scrolled back", function()
		local CameraController = startGame()
		local before = CameraController.getZoom()
		H.input.wheel(1)
		T.gt(CameraController.getZoom(), before, "scrolling forward zooms in")
		local zoomed = CameraController.getZoom()
		H.input.wheel(-1)
		T.lt(CameraController.getZoom(), zoomed, "scrolling back zooms out")
	end)

	T.test("the zoom stays within the configured minimum and maximum", function()
		local CameraController, _, Config = startGame()
		for _ = 1, 80 do
			H.input.wheel(1)
		end
		T.near(CameraController.getZoom(), Config.Camera.ZoomMax, 1e-9, "maximum zoom")
		for _ = 1, 200 do
			H.input.wheel(-1)
		end
		T.near(CameraController.getZoom(), Config.Camera.ZoomMin, 1e-9, "minimum zoom")
		CameraController.setZoom(99)
		T.near(CameraController.getZoom(), Config.Camera.ZoomMax, 1e-9)
		CameraController.setZoom(-3)
		T.near(CameraController.getZoom(), Config.Camera.ZoomMin, 1e-9)
	end)

	T.test("a wheel step is one ZoomStep, so the zoom is progressive", function()
		local CameraController, _, Config = startGame()
		local before = CameraController.getZoom()
		H.input.wheel(1)
		T.near(CameraController.getZoom() - before, Config.Camera.ZoomStep, 1e-9)
	end)

	T.test("the zoom glides towards its target without overshoot", function()
		local CameraController, camera, Config = startGame()
		-- Le HUD réserve ses marges après GameStarted : heightAt suppose la vue
		-- entière, donc on remet les marges à zéro pour comparer la même cible.
		CameraController.setSafeInsets(0, 0, 0, 0)
		local target = 2.5
		local previous = camera.CFrame.Position.Y
		CameraController.setZoom(target)
		for _ = 1, 45 do
			H.advance(1 / 30)
			local height = camera.CFrame.Position.Y
			T.le(height, previous + 1e-9, "the camera only comes closer")
			T.ge(height, heightAt(Config, target) - 1e-6, "the camera never goes past the target")
			previous = height
		end
		T.near(camera.CFrame.Position.Y, heightAt(Config, target), 1e-3, "converged on the target")
	end)

	T.test("the zoom animation does not depend on the frame rate", function()
		local function heightAfterQuarterSecond(step)
			H.reset()
			local CameraController, camera = startGame()
			CameraController.setZoom(2)
			H.advance(0.25, { step = step })
			return camera.CFrame.Position.Y
		end
		local coarse = heightAfterQuarterSecond(1 / 20)
		local fine = heightAfterQuarterSecond(1 / 240)
		T.near(coarse, fine, 1e-3, "20 fps and 240 fps reach the same height")
	end)

	T.test("zoom keeps the camera orientation", function()
		local CameraController, camera = startGame()
		local look = camera.CFrame.LookVector
		CameraController.setZoom(2.2)
		H.advance(1)
		T.ok(camera.CFrame.LookVector:FuzzyEq(look, 1e-4), "the look direction is unchanged")
	end)

	T.test("no frame callback is kept once the zoom has settled", function()
		-- Caméra seule, sans HUD ni lobby : leurs minuteries ouvrent et ferment des
		-- connexions au repos et fausseraient le décompte global.
		H.asClient()
		H.setViewport(1920, 1080)
		local CameraController = H.load("CameraController")
		local Config = H.load("Config")
		CameraController.focus(Vector3.new(0, 0, 0), Config.Grid.Size, Config.Grid.TileSize, true)
		H.advance(2)
		local idle = H.connectionCount()
		CameraController.setZoom(2)
		T.gt(H.connectionCount(), idle, "a zoom animation listens to the frames")
		H.advance(1.5)
		T.eq(H.connectionCount(), idle, "the per-frame connection is released once the zoom has settled")
	end)
end
