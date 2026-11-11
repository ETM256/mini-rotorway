return function(T, H)
	-- Marges de l'interface : la carte se cadre dans la zone libre, jamais sous
	-- la barre supérieure, les compteurs ou la barre d'outils.

	local ORIGIN = Vector3.new(700, 0, 0)
	local TOLERANCE = 1.5

	-- Marges (haut, droite, bas, gauche) de la barre, de la barre d'outils, des
	-- compteurs : valeurs représentatives, en pixels.
	local DESKTOP = { top = 56, right = 96, bottom = 72, left = 0 }
	local PHONE_PORTRAIT = { top = 48, right = 0, bottom = 120, left = 0 }
	local PHONE_LANDSCAPE = { top = 40, right = 96, bottom = 56, left = 0 }

	local CASES = {
		{ 1280, 720, DESKTOP },
		{ 1920, 1080, DESKTOP },
		{ 1366, 768, DESKTOP },
		{ 390, 844, PHONE_PORTRAIT },
		{ 844, 390, PHONE_LANDSCAPE },
	}

	local function frame(width, height, margins)
		H.reset()
		H.asClient()
		H.setViewport(width, height)
		local CameraController = H.load("CameraController")
		local Config = H.load("Config")
		if margins then
			CameraController.setSafeInsets(margins.top, margins.right, margins.bottom, margins.left)
		end
		CameraController.focus(ORIGIN, Config.Grid.Size, Config.Grid.TileSize, true)
		return CameraController, workspace.CurrentCamera, Config
	end

	local function cornersOf(Config)
		local size = Config.Grid.Size * Config.Grid.TileSize
		return {
			ORIGIN,
			ORIGIN + Vector3.new(size, 0, 0),
			ORIGIN + Vector3.new(0, 0, size),
			ORIGIN + Vector3.new(size, 0, size),
		}
	end

	T.test("the whole map stays in the free area, clear of the HUD bands, at every resolution", function()
		for _, case in ipairs(CASES) do
			local width, height, margins = case[1], case[2], case[3]
			local _, camera, Config = frame(width, height, margins)
			local left = margins.left
			local right = width - margins.right
			local top = margins.top
			local bottom = height - margins.bottom
			for index, corner in ipairs(cornersOf(Config)) do
				local point = camera:WorldToViewportPoint(corner)
				local label = string.format("%dx%d corner %d", width, height, index)
				T.ge(point.X, left - TOLERANCE, label .. " is not under the left band")
				T.le(point.X, right + TOLERANCE, label .. " is not under the right band")
				T.ge(point.Y, top - TOLERANCE, label .. " is not under the top bar")
				T.le(point.Y, bottom + TOLERANCE, label .. " is not under the bottom counters")
			end
		end
	end)

	T.test("the map is centred in the free area, not in the full screen", function()
		for _, case in ipairs(CASES) do
			local width, height, margins = case[1], case[2], case[3]
			local _, camera, Config = frame(width, height, margins)
			local centre = ORIGIN + Vector3.new(Config.Grid.Size * Config.Grid.TileSize / 2, 0, Config.Grid.Size * Config.Grid.TileSize / 2)
			local point = camera:WorldToViewportPoint(centre)
			local wantX = (margins.left + width - margins.right) / 2
			local wantY = (margins.top + height - margins.bottom) / 2
			local label = string.format("%dx%d", width, height)
			T.near(point.X, wantX, TOLERANCE, label .. ": horizontal centre of the free area")
			T.near(point.Y, wantY, TOLERANCE, label .. ": vertical centre of the free area")
		end
	end)

	T.test("without margins the framing is the full screen again", function()
		local _, camera, Config = frame(1280, 720, DESKTOP)
		local CameraController = H.load("CameraController")
		CameraController.setSafeInsets(0, 0, 0, 0)
		CameraController.refresh(true)
		local centre = ORIGIN + Vector3.new(Config.Grid.Size * Config.Grid.TileSize / 2, 0, Config.Grid.Size * Config.Grid.TileSize / 2)
		local point = camera:WorldToViewportPoint(centre)
		T.near(point.X, 640, TOLERANCE)
		T.near(point.Y, 360, TOLERANCE)
	end)

	T.test("invalid margins (negative, NaN, missing, text) are read as zero", function()
		local CameraController, camera, Config = frame(1280, 720, nil)
		local whole = camera:WorldToViewportPoint(ORIGIN)
		CameraController.setSafeInsets(-40, 0 / 0, nil, "wide")
		CameraController.refresh(true)
		local after = camera:WorldToViewportPoint(ORIGIN)
		T.near(after.X, whole.X, 1e-3, "same framing as with no margins")
		T.near(after.Y, whole.Y, 1e-3)
		T.ok(Config.Grid.Size > 0)
	end)

	T.test("margins set before any game are kept for the first framing", function()
		H.reset()
		H.asClient()
		H.setViewport(1280, 720)
		local CameraController = H.load("CameraController")
		local Config = H.load("Config")
		CameraController.setSafeInsets(56, 96, 72, 0)
		CameraController.focus(ORIGIN, Config.Grid.Size, Config.Grid.TileSize, true)
		local camera = workspace.CurrentCamera
		for _, corner in ipairs(cornersOf(Config)) do
			local point = camera:WorldToViewportPoint(corner)
			T.le(point.X, 1280 - 96 + TOLERANCE)
			T.ge(point.Y, 56 - TOLERANCE)
		end
	end)
end
