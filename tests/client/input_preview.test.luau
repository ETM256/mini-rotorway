return function(T, H)
	-- Aperçu, visée, grille et cycle de vie d'InputController (sans serveur).

	local origin = Vector3.new(0, 0, 0)

	local function setup(state)
		H.asClient()
		H.setViewport(1280, 720)
		local Config = H.load("Config")
		local InputController = H.load("InputController")
		local camera = workspace.CurrentCamera
		camera.FieldOfView = Config.Camera.FOV
		local size = Config.Grid.Size * Config.Grid.TileSize
		local center = origin + Vector3.new(size / 2, 0, size / 2)
		local height = Config.Camera.Height
		camera.CFrame = CFrame.lookAt(center + Vector3.new(0, height, height * Config.Camera.BackRatio), center)

		local input = InputController.new({
			onDraw = function() end,
			onEraseMany = function() end,
		})
		input:setWorld(origin, Config.Grid.Size, Config.Grid.TileSize)
		input:setMapId("los_angeles")
		input:setEnabled(true)
		input:applyRoadState(state or { roads = {}, bridges = {}, buildings = {}, budget = 60, bridgesLeft = 3 })
		return input
	end

	local function screenOf(x, y, fx, fy)
		local Config = H.load("Config")
		local t = Config.Grid.TileSize
		local world = origin + Vector3.new((x + (fx or 0.5)) * t, 0, (y + (fy or 0.5)) * t)
		local point = workspace.CurrentCamera:WorldToViewportPoint(world)
		return point.X, point.Y
	end

	local function moveTo(x, y)
		local sx, sy = screenOf(x, y)
		H.input.mouseMove(sx, sy)
	end

	local function pressCell(x, y, button)
		local sx, sy = screenOf(x, y)
		H.input.mouseDown(sx, sy, button or 1)
	end

	local function releaseCell(x, y, button)
		local sx, sy = screenOf(x, y)
		H.input.mouseUp(sx, sy, button or 1)
	end

	-- Marqueurs d'aperçu visibles, dans l'ordre de création (= ordre du tracé).
	local function visibleMarkers()
		local list = {}
		local folder = workspace:FindFirstChild("MM_RoadPreview")
		for _, part in ipairs(folder and folder:GetChildren() or {}) do
			if part.Transparency < 1 then
				table.insert(list, part)
			end
		end
		return list
	end

	-- Vrai si le centre de la pièce tombe dans la case x, y (origine en 0, 0).
	local function inCell(part, x, y)
		local t = H.load("Config").Grid.TileSize
		local p = part.CFrame.Position
		return p.X >= x * t and p.X < (x + 1) * t and p.Z >= y * t and p.Z < (y + 1) * t
	end

	-- Pièces visibles d'une case (une route en compte plusieurs : liseré, surface).
	local function piecesIn(x, y)
		local list = {}
		for _, part in ipairs(visibleMarkers()) do
			if inCell(part, x, y) then
				table.insert(list, part)
			end
		end
		return list
	end

	-- Couleur commune aux pièces d'une case, « mixed » si elles diffèrent, nil si aucune.
	local function colourIn(x, y)
		local colour = nil
		for _, part in ipairs(piecesIn(x, y)) do
			if colour ~= nil and part.Color ~= colour then
				return "mixed"
			end
			colour = part.Color
		end
		return colour
	end

	-- Cherche une rangée : case libre, case d'eau, puis trois cases libres.
	local function findWaterRun()
		local Maps = H.load("Maps")
		local Config = H.load("Config")
		local map = Maps.getById("los_angeles")
		for y = 0, Config.Grid.Size - 1 do
			for x = 0, Config.Grid.Size - 5 do
				if not Maps.isWater(map, x, y)
					and Maps.isWater(map, x + 1, y)
					and not Maps.isWater(map, x + 2, y)
					and not Maps.isWater(map, x + 3, y)
					and not Maps.isWater(map, x + 4, y)
				then
					return x, y
				end
			end
		end
		return nil
	end

	T.test("cell picking: points near the cell edges map to that cell, no half-tile shift", function()
		local input = setup()
		for _, cell in ipairs({ { 0, 0 }, { 3, 7 }, { 10, 12 }, { 17, 17 } }) do
			for _, offset in ipairs({ { 0.1, 0.1 }, { 0.9, 0.9 }, { 0.1, 0.9 }, { 0.9, 0.1 }, { 0.5, 0.5 } }) do
				local sx, sy = screenOf(cell[1], cell[2], offset[1], offset[2])
				local found = input:cellAt(Vector2.new(sx, sy))
				T.ok(found ~= nil, "cell " .. cell[1] .. ":" .. cell[2] .. " is picked")
				if found then
					T.eq(found[1], cell[1], "x for offset " .. offset[1] .. "," .. offset[2])
					T.eq(found[2], cell[2], "y for offset " .. offset[1] .. "," .. offset[2])
				end
			end
		end
	end)

	T.test("points outside the map pick nothing", function()
		local input = setup()
		local sx, sy = screenOf(-2, 5)
		T.eq(input:cellAt(Vector2.new(sx, sy)), nil)
		sx, sy = screenOf(20, 5)
		T.eq(input:cellAt(Vector2.new(sx, sy)), nil)
	end)

	T.test("the preview colours refused cells: building, water without bridge, no budget", function()
		local Config = H.load("Config")
		local RoadConfig = H.load("RoadConfig")
		local x, y = findWaterRun()
		T.ok(x ~= nil, "los_angeles has a water cell between land cells")
		if not x then
			return
		end
		local input = setup({
			roads = {},
			bridges = {},
			buildings = { x .. ":" .. y },
			budget = 2,
			bridgesLeft = 0,
		})
		moveTo(x, y)
		pressCell(x, y)
		for i = 1, 4 do
			moveTo(x + i, y)
		end
		local valid = RoadConfig.Visual.PreviewValidColor
		local refused = RoadConfig.Visual.PreviewInvalidColor
		-- Bâtiment, eau sans pont, deux cases payées, puis budget épuisé.
		local expected = { refused, refused, valid, valid, refused }
		local labels = { "building", "water without bridge", "first paid cell", "second paid cell", "budget exhausted" }
		for i, colour in ipairs(expected) do
			T.ok(#piecesIn(x + i - 1, y) >= 2, labels[i] .. ": an edge and a body")
			T.eq(colourIn(x + i - 1, y), colour, labels[i])
		end
		-- Une case droite entre deux voisins a la largeur de la route, pas celle du liseré.
		local width = RoadConfig.Visual.RoadWidth * Config.Grid.TileSize
		local wide = false
		for _, part in ipairs(piecesIn(x + 2, y)) do
			if math.abs(part.Size.Z - width) < 1e-6 then
				wide = true
			end
		end
		T.ok(wide, "a straight paid cell is as wide as the road")
		input:cancelDrag()
	end)

	T.test("cells already holding a road are not redrawn and cost nothing", function()
		local RoadConfig = H.load("RoadConfig")
		local input = setup({ roads = { "3:3" }, bridges = {}, buildings = {}, budget = 2, bridgesLeft = 0 })
		moveTo(2, 3)
		pressCell(2, 3)
		moveTo(5, 3)
		T.eq(#piecesIn(3, 3), 0, "3:3 holds a road: it is not previewed")
		T.eq(colourIn(2, 3), RoadConfig.Visual.PreviewValidColor, "2:3 is paid")
		T.eq(colourIn(4, 3), RoadConfig.Visual.PreviewValidColor, "4:3 is paid with the second unit")
		T.eq(colourIn(5, 3), RoadConfig.Visual.PreviewInvalidColor, "5:3 has no budget left")
		input:cancelDrag()
	end)

	T.test("a long zigzag stroke keeps the marker pool bounded and reuses it", function()
		local Config = H.load("Config")
		setup()
		moveTo(0, 0)
		pressCell(0, 0)
		for row = 0, Config.Grid.Size - 1 do
			local fromX, toX = 0, Config.Grid.Size - 1
			if row % 2 == 1 then
				fromX, toX = toX, fromX
			end
			moveTo(fromX, row)
			moveTo(toX, row)
		end
		local folder = workspace:FindFirstChild("MM_RoadPreview")
		-- Une case compte au plus six pièces (liseré et surface, trois formes chacun).
		T.le(#folder:GetChildren(), 6 * Config.Grid.Size * Config.Grid.Size, "at most six pieces per cell")
		local before = #folder:GetChildren()
		for _ = 1, 30 do
			moveTo(Config.Grid.Size - 1, Config.Grid.Size - 1)
			moveTo(0, 0)
		end
		T.eq(#folder:GetChildren(), before, "moving over the same cells creates no new marker")
		-- Le relâchement sur 0:0 ne laisse que le survol de cette case.
		moveTo(0, 0)
		releaseCell(0, 0)
		local visible = visibleMarkers()
		T.le(#visible, 2, "after release only the hover of the cursor cell remains")
		for _, part in ipairs(visible) do
			T.ok(inCell(part, 0, 0), "a piece left after release sits under the cursor")
		end
	end)

	T.test("the hover marker follows the tool: shown for build, hidden for camera, coral on a road for erase", function()
		local RoadConfig = H.load("RoadConfig")
		setup({ roads = { "4:4" }, bridges = {}, buildings = {}, budget = 60, bridgesLeft = 3 })
		moveTo(7, 7)
		-- Une case isolée : un liseré et une surface, tous deux en survol.
		T.eq(#visibleMarkers(), 2, "build: the hover cell's edge and body")
		for _, part in ipairs(visibleMarkers()) do
			T.ok(inCell(part, 7, 7), "the hover piece sits under the cursor")
			T.near(part.Transparency, RoadConfig.Visual.PreviewHoverTransparency, 1e-6)
		end

		H.input.key("Four", true)
		H.input.key("Four", false)
		T.eq(#visibleMarkers(), 0, "camera tool: nothing to preview")

		H.input.key("Two", true)
		H.input.key("Two", false)
		moveTo(7, 7)
		T.eq(#visibleMarkers(), 0, "erase over empty ground: nothing to remove")
		moveTo(4, 4)
		local markers = visibleMarkers()
		T.eq(#markers, 2, "erase over a road: its edge and body are marked")
		T.eq(markers[1].Color, RoadConfig.Visual.PreviewInvalidColor)
	end)

	T.test("destroy releases every connection, the preview folder and the ghost, and ignores input", function()
		H.asClient()
		local before = H.connectionCount()
		local input = setup()
		local during = H.connectionCount()
		T.ge(during - before, 5, "the controller binds its input, focus and frame events")
		T.ok(workspace:FindFirstChild("MM_RoadPreview") ~= nil)

		input:destroy()
		T.eq(H.connectionCount(), before, "no connection survives destroy")
		T.eq(workspace:FindFirstChild("MM_RoadPreview"), nil, "the preview folder is removed")
		T.eq(workspace:FindFirstChild("MM_Ghost"), nil, "the ghost part is removed")

		T.noThrow(function()
			pressCell(2, 2)
			releaseCell(2, 2)
			H.input.key("Two", true)
			H.input.key("Two", false)
		end)
		input:destroy()
		T.eq(H.connectionCount(), before, "a second destroy is harmless")
	end)

	T.test("the grid is raised while building and restored on release", function()
		local Config = H.load("Config")
		local worlds = Instance.new("Folder")
		worlds.Name = "MMWorlds"
		worlds.Parent = workspace
		local city = Instance.new("Folder")
		city.Name = "City_0"
		city.Parent = worlds
		local grid = Instance.new("Folder")
		grid.Name = "Grid"
		grid:SetAttribute("BaseTransparency", Config.Terrain.GridBaseTransparency)
		grid:SetAttribute("ActiveTransparency", Config.Terrain.GridActiveTransparency)
		grid.Parent = city
		local line = Instance.new("Part")
		line.Name = "GridV"
		line.Transparency = Config.Terrain.GridBaseTransparency
		line.Parent = grid

		local input = setup()
		T.near(line.Transparency, Config.Terrain.GridActiveTransparency, 1e-6, "build tool: grid raised")

		H.input.key("Four", true)
		H.input.key("Four", false)
		T.near(line.Transparency, Config.Terrain.GridBaseTransparency, 1e-6, "camera tool: grid discreet")

		H.input.key("Two", true)
		H.input.key("Two", false)
		pressCell(3, 3)
		T.near(line.Transparency, Config.Terrain.GridActiveTransparency, 1e-6, "erase drag: grid raised")
		releaseCell(3, 3)
		T.near(line.Transparency, Config.Terrain.GridBaseTransparency, 1e-6, "erase tool idle: grid discreet again")

		input:destroy()
		T.near(line.Transparency, Config.Terrain.GridBaseTransparency, 1e-6, "destroy restores the base look")
	end)

	T.test("without a grid folder yet, the controller still works", function()
		local input = setup()
		T.noThrow(function()
			input:setTool("erase")
			input:setTool("build")
			input:setEnabled(false)
			input:setEnabled(true)
		end)
		T.eq(H.handlerErrors[1], nil, "no handler error when the grid is missing")
	end)

	T.test("a grid that appears after the world is set is raised on the next hover tick", function()
		local Config = H.load("Config")
		local RoadConfig = H.load("RoadConfig")
		setup()
		local worlds = Instance.new("Folder")
		worlds.Name = "MMWorlds"
		worlds.Parent = workspace
		local city = Instance.new("Folder")
		city.Name = "City_0"
		city.Parent = worlds
		local grid = Instance.new("Folder")
		grid.Name = "Grid"
		grid:SetAttribute("BaseTransparency", Config.Terrain.GridBaseTransparency)
		grid:SetAttribute("ActiveTransparency", Config.Terrain.GridActiveTransparency)
		grid.Parent = city
		local line = Instance.new("Part")
		line.Name = "GridV"
		line.Transparency = Config.Terrain.GridBaseTransparency
		line.Parent = grid

		-- Le rafraîchissement périodique suffit : aucun geste n'est nécessaire.
		H.advance(RoadConfig.Input.HoverRefresh + 0.01, { frames = true })
		T.near(line.Transparency, Config.Terrain.GridActiveTransparency, 1e-6, "build tool: raised on the tick")
	end)
end
