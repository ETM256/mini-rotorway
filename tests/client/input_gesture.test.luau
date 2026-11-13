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

	T.test("a second finger before release cancels the roundabout: a pinch places nothing", function()
		local input, log = setup()
		input:setTool("roundabout")
		local sx, sy = screenOf(5, 4)
		H.input.touchBegin(1, sx, sy)
		T.eq(#log.round, 0, "the roundabout waits for the release")
		local sx2, sy2 = screenOf(12, 12)
		H.input.touchBegin(2, sx2, sy2)
		H.input.touchEnd(2, sx2, sy2)
		H.input.touchEnd(1, sx, sy)
		T.eq(#log.round, 0, "the second finger cancels it: nothing is placed")
		T.eq(#log.draw, 0)
	end)

	T.test("a single finger places the roundabout once, on release, on the cell it touched first", function()
		local input, log = setup()
		input:setTool("roundabout")
		local sx, sy = screenOf(5, 4)
		H.input.touchBegin(1, sx, sy)
		local mx, my = screenOf(6, 4)
		H.input.touchMove(1, mx, my)
		T.eq(#log.round, 0, "nothing sent while the finger is down")
		H.input.touchEnd(1, mx, my)
		T.eq(#log.round, 1, "one roundabout on release")
		T.eq(log.round[1][1], 5)
		T.eq(log.round[1][2], 4)
	end)

	T.test("the roundabout stays cancelled whichever of the two fingers lifts first", function()
		local input, log = setup()
		input:setTool("roundabout")
		local sx, sy = screenOf(5, 4)
		local sx2, sy2 = screenOf(12, 12)
		H.input.touchBegin(1, sx, sy)
		H.input.touchBegin(2, sx2, sy2)
		H.input.touchEnd(1, sx, sy)
		H.input.touchEnd(2, sx2, sy2)
		T.eq(#log.round, 0, "the first finger lifting first places nothing either")
	end)

	T.test("successive taps each place one roundabout, on their own cell", function()
		local input, log = setup()
		input:setTool("roundabout")
		local ax, ay = screenOf(5, 4)
		H.input.touchBegin(1, ax, ay)
		H.input.touchEnd(1, ax, ay)
		T.eq(#log.round, 1, "the first tap places one")
		local bx, by = screenOf(9, 7)
		H.input.touchBegin(1, bx, by)
		T.eq(#log.round, 1, "the second finger down places nothing yet")
		H.input.touchEnd(1, bx, by)
		T.eq(#log.round, 2, "the second tap places one more")
		T.eq(log.round[1][1], 5)
		T.eq(log.round[1][2], 4)
		T.eq(log.round[2][1], 9)
		T.eq(log.round[2][2], 7)
	end)

	T.test("a finger whose end never arrived leaves no stale roundabout behind it", function()
		local input, log = setup()
		input:setTool("roundabout")
		local lostX, lostY = screenOf(5, 4)
		H.input.touchBegin(1, lostX, lostY)
		-- Roblox le donne pour terminé, mais InputEnded n'a jamais été diffusé.
		H.W.fingers[1].UserInputState = Enum.UserInputState.End
		H.W.fingers[1] = nil
		-- Un appui hors carte ne vise aucune case : il ne remplace pas l'attente du doigt perdu.
		local offX, offY = screenOf(-20, -20)
		T.eq(input:cellAt(Vector2.new(offX, offY)), nil, "the tap is off the map")
		H.input.touchBegin(2, offX, offY)
		H.input.touchEnd(2, offX, offY)
		T.eq(#log.round, 0, "the lost finger's cell is not placed by another finger")
		local sx, sy = screenOf(9, 7)
		H.input.touchBegin(3, sx, sy)
		H.input.touchEnd(3, sx, sy)
		T.eq(#log.round, 1, "only the new tap places a roundabout")
		T.eq(log.round[1][1], 9)
		T.eq(log.round[1][2], 7)
	end)

	T.test("Escape cancels a pending roundabout: nothing is placed on release", function()
		local input, log = setup()
		input:setTool("roundabout")
		local sx, sy = screenOf(5, 4)
		H.input.touchBegin(1, sx, sy)
		H.input.key("Escape", true)
		H.input.key("Escape", false)
		H.input.touchEnd(1, sx, sy)
		T.eq(#log.round, 0)
	end)

	T.test("changing tool cancels a pending roundabout", function()
		local input, log = setup()
		input:setTool("roundabout")
		local sx, sy = screenOf(5, 4)
		H.input.touchBegin(1, sx, sy)
		input:setTool("build")
		H.input.touchEnd(1, sx, sy)
		T.eq(#log.round, 0)
	end)

	T.test("losing window focus cancels a pending roundabout", function()
		local input, log = setup()
		input:setTool("roundabout")
		local sx, sy = screenOf(5, 4)
		H.input.touchBegin(1, sx, sy)
		H.I.fire(H.I.getSignal(game.UserInputService, "WindowFocusReleased"))
		H.input.touchEnd(1, sx, sy)
		T.eq(#log.round, 0)
	end)

	T.test("disabling the controller cancels a pending roundabout", function()
		local input, log = setup()
		input:setTool("roundabout")
		local sx, sy = screenOf(5, 4)
		H.input.touchBegin(1, sx, sy)
		input:setEnabled(false)
		H.input.touchEnd(1, sx, sy)
		T.eq(#log.round, 0)
	end)

	T.test("a new world cancels a pending roundabout", function()
		local input, log = setup()
		local Config = H.load("Config")
		input:setTool("roundabout")
		local sx, sy = screenOf(5, 4)
		H.input.touchBegin(1, sx, sy)
		input:setWorld(origin, Config.Grid.Size, Config.Grid.TileSize)
		H.input.touchEnd(1, sx, sy)
		T.eq(#log.round, 0)
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
