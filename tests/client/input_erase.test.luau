return function(T, H)
	-- Clic droit = effacement, quel que soit l'outil ; grille réglable (HUD).

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

		local log = { draw = {}, erase = {}, round = {}, pans = 0 }
		local input = InputController.new({
			onDraw = function(cells)
				table.insert(log.draw, cells)
			end,
			onEraseMany = function(keys)
				table.insert(log.erase, keys)
			end,
			onRoundabout = function(x, y)
				table.insert(log.round, { x, y })
			end,
			onPan = function()
				log.pans += 1
			end,
		})
		input:setWorld(origin, Config.Grid.Size, Config.Grid.TileSize)
		input:setMapId("los_angeles")
		input:setEnabled(true)
		input:applyRoadState(state or { roads = {}, bridges = {}, buildings = {}, budget = 60, bridgesLeft = 3 })
		return input, log
	end

	local function screenOf(x, y)
		local Config = H.load("Config")
		local t = Config.Grid.TileSize
		local point = workspace.CurrentCamera:WorldToViewportPoint(origin + Vector3.new((x + 0.5) * t, 0, (y + 0.5) * t))
		return point.X, point.Y
	end

	local function press(x, y, button)
		local sx, sy = screenOf(x, y)
		H.input.mouseMove(sx, sy)
		H.input.mouseDown(sx, sy, button)
	end

	local function moveTo(x, y)
		local sx, sy = screenOf(x, y)
		H.input.mouseMove(sx, sy)
	end

	local function release(x, y, button)
		local sx, sy = screenOf(x, y)
		H.input.mouseUp(sx, sy, button)
	end

	local ROADS = { roads = { "4:4", "5:4", "6:4" }, bridges = {}, buildings = {}, budget = 60, bridgesLeft = 3 }

	local function erasedKeys(log)
		local keys = {}
		for _, chunk in ipairs(log.erase) do
			for _, key in ipairs(chunk) do
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		return keys
	end

	T.test("right button erases the roads it crosses, with the build tool active", function()
		local _, log = setup(ROADS)
		press(4, 4, 2)
		moveTo(6, 4)
		release(6, 4, 2)
		T.eq(#log.draw, 0, "no road is built by the right button")
		T.deepEq(erasedKeys(log), { "4:4", "5:4", "6:4" })
	end)

	T.test("right button erases whatever the tool, and the camera tool still erases", function()
		local input, log = setup(ROADS)
		input:setTool("camera")
		press(4, 4, 2)
		moveTo(5, 4)
		release(5, 4, 2)
		T.deepEq(erasedKeys(log), { "4:4", "5:4" })
		T.eq(log.pans, 0, "the right button never pans")
	end)

	T.test("right button on bare ground sends nothing", function()
		local _, log = setup(ROADS)
		press(10, 10, 2)
		moveTo(11, 10)
		release(11, 10, 2)
		T.eq(#log.erase, 0)
		T.eq(#log.draw, 0)
	end)

	T.test("right button erases only existing roads, never an empty cell of the drag", function()
		local _, log = setup(ROADS)
		press(4, 4, 2)
		moveTo(9, 4)
		release(9, 4, 2)
		T.deepEq(erasedKeys(log), { "4:4", "5:4", "6:4" }, "cells 7 to 9 are not roads")
	end)

	T.test("Escape cancels a right-button erase: nothing is sent", function()
		local _, log = setup(ROADS)
		press(4, 4, 2)
		moveTo(6, 4)
		H.input.key("Escape", true)
		H.input.key("Escape", false)
		release(6, 4, 2)
		T.eq(#log.erase, 0)
	end)

	T.test("a second button during a stroke never replaces it", function()
		local _, log = setup(ROADS)
		press(10, 10, 1)
		moveTo(11, 10)
		press(12, 10, 2)
		moveTo(12, 10)
		release(12, 10, 2)
		release(12, 10, 1)
		T.eq(#log.erase, 0, "the right button did not erase during the left stroke")
		T.eq(#log.draw, 1, "the left stroke still completes")
		T.deepEq(log.draw[1], { { 10, 10 }, { 11, 10 }, { 12, 10 } })
	end)

	T.test("the grid stays visible when pinned, and goes back to its automatic state when unpinned", function()
		local worlds = Instance.new("Folder")
		worlds.Name = "MMWorlds"
		worlds.Parent = workspace
		local city = Instance.new("Folder")
		city.Name = "City_0"
		city.Parent = worlds
		local grid = Instance.new("Folder")
		grid.Name = "Grid"
		grid.Parent = city
		grid:SetAttribute("BaseTransparency", 0.9)
		grid:SetAttribute("ActiveTransparency", 0.3)
		local line = Instance.new("Part")
		line.Parent = grid

		local input = setup(ROADS)
		input:setTool("camera")
		T.near(line.Transparency, 0.9, 1e-6, "automatic: hidden while not building")
		input:setGridPinned(true)
		T.near(line.Transparency, 0.3, 1e-6, "pinned: the grid is raised")
		input:setGridPinned(false)
		T.near(line.Transparency, 0.9, 1e-6, "unpinned: back to the automatic state")
	end)

	T.test("a middle press cancels a left stroke, and no left press starts one while it is held", function()
		local _, log = setup()
		press(2, 3, 1)
		moveTo(4, 3)
		press(4, 3, 3)
		moveTo(7, 3)
		press(8, 3, 1)
		moveTo(9, 3)
		release(9, 3, 1)
		release(7, 3, 3)
		T.eq(#log.draw, 0, "the middle button stops the stroke: nothing is sent")
		press(14, 3, 1)
		release(14, 3, 1)
		T.eq(#log.draw, 1, "once the middle button is up, a left stroke works again")
	end)

	T.test("a right press while the middle button is held erases nothing", function()
		local _, log = setup({ roads = { "10:10", "11:10", "12:10" }, bridges = {}, buildings = {}, budget = 60, bridgesLeft = 3 })
		press(10, 10, 3)
		moveTo(11, 10)
		press(11, 10, 2)
		moveTo(12, 10)
		release(12, 10, 2)
		release(12, 10, 3)
		T.eq(#log.erase, 0, "the middle button never erases: the roads under the cursor survive")
		T.eq(#log.draw, 0, "the middle button never builds")
	end)
end
