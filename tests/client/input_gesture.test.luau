return function(T, H)
	-- Écran tactile : un second doigt ne démarre jamais un tracé, un outil ou un
	-- effacement ; il devient un geste de caméra.

	local origin = Vector3.new(0, 0, 0)

	local function setup()
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
		input:applyRoadState({
			roads = { "4:4", "5:4", "6:4" },
			bridges = {},
			buildings = {},
			budget = 60,
			bridgesLeft = 3,
		})
		return input, log
	end

	local function screenOf(x, y)
		local Config = H.load("Config")
		local t = Config.Grid.TileSize
		local point = workspace.CurrentCamera:WorldToViewportPoint(origin + Vector3.new((x + 0.5) * t, 0, (y + 0.5) * t))
		return point.X, point.Y
	end

	T.test("a second finger while a roundabout is placed starts nothing new", function()
		local input, log = setup()
		input:setTool("roundabout")
		local sx, sy = screenOf(10, 10)
		H.input.touchBegin(1, sx, sy)
		T.eq(#log.round, 1, "the first finger places the roundabout")
		local sx2, sy2 = screenOf(12, 12)
		H.input.touchBegin(2, sx2, sy2)
		H.input.touchEnd(2, sx2, sy2)
		H.input.touchEnd(1, sx, sy)
		T.eq(#log.round, 1, "the second finger places nothing")
		T.eq(#log.draw, 0)
	end)

	T.test("a second finger during an erase stroke cancels it: nothing is erased", function()
		local input, log = setup()
		input:setTool("erase")
		local sx, sy = screenOf(4, 4)
		H.input.touchBegin(1, sx, sy)
		local mx, my = screenOf(5, 4)
		H.input.touchMove(1, mx, my)
		local sx2, sy2 = screenOf(8, 8)
		H.input.touchBegin(2, sx2, sy2)
		H.input.touchEnd(1, mx, my)
		H.input.touchEnd(2, sx2, sy2)
		T.eq(#log.erase, 0, "the erase stroke is cancelled by the second finger")
		T.eq(log.pans, 0, "a pan needs a movement of both fingers")
	end)

	T.test("a second finger during a build stroke cancels it: nothing is drawn", function()
		local _, log = setup()
		local sx, sy = screenOf(10, 2)
		H.input.touchBegin(1, sx, sy)
		local mx, my = screenOf(11, 2)
		H.input.touchMove(1, mx, my)
		local sx2, sy2 = screenOf(14, 8)
		H.input.touchBegin(2, sx2, sy2)
		H.input.touchEnd(1, mx, my)
		H.input.touchEnd(2, sx2, sy2)
		T.eq(#log.draw, 0, "a stroke interrupted by a second finger is never sent")
	end)

	T.test("once both fingers lift, a new single finger draws normally", function()
		local _, log = setup()
		local sx, sy = screenOf(10, 2)
		local sx2, sy2 = screenOf(14, 8)
		H.input.touchBegin(1, sx, sy)
		H.input.touchBegin(2, sx2, sy2)
		H.input.touchEnd(1, sx, sy)
		H.input.touchEnd(2, sx2, sy2)
		H.input.touchBegin(3, sx, sy)
		local mx, my = screenOf(12, 2)
		H.input.touchMove(3, mx, my)
		H.input.touchEnd(3, mx, my)
		T.eq(#log.draw, 1, "the new finger draws one stroke")
	end)
end
