return function(T, H)
	-- InputController seul (sans serveur) : on observe ce qui partirait vers
	-- les RemoteEvents, via les callbacks. Caméra zénithale, comme en jeu.

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

		local log = { draw = {}, erase = {}, pans = 0, zooms = {}, roundabouts = {} }
		local input = InputController.new({
			onDraw = function(cells)
				table.insert(log.draw, cells)
			end,
			onEraseMany = function(keys)
				table.insert(log.erase, keys)
			end,
			onRoundabout = function(x, y)
				table.insert(log.roundabouts, { x, y })
			end,
			onPan = function()
				log.pans += 1
			end,
			onZoom = function(delta)
				table.insert(log.zooms, delta)
			end,
		})
		input:setWorld(origin, Config.Grid.Size, Config.Grid.TileSize)
		input:setMapId("los_angeles")
		input:setEnabled(true)
		input:applyRoadState({ roads = {}, bridges = {}, buildings = {}, budget = 60, bridgesLeft = 3 })
		return input, log
	end

	-- Position écran du centre (ou d'un point) d'une case.
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

	local function press(x, y, button)
		local sx, sy = screenOf(x, y)
		H.input.mouseDown(sx, sy, button or 1)
	end

	local function release(x, y, button)
		local sx, sy = screenOf(x, y)
		H.input.mouseUp(sx, sy, button or 1)
	end

	-- Chaque case est voisine orthogonale de la précédente (pas de trou, pas de diagonale).
	local function assertChain(cells)
		for i = 2, #cells do
			local a, b = cells[i - 1], cells[i]
			T.eq(math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]), 1, "cell " .. i .. " follows its neighbour")
		end
	end

	local function touchInput(x, y, state)
		return {
			UserInputType = Enum.UserInputType.Touch,
			UserInputState = state or Enum.UserInputState.Begin,
			KeyCode = Enum.KeyCode.Unknown,
			Position = Vector3.new(x, y, 0),
			Delta = Vector3.zero,
		}
	end

	local function fireInput(signalName, input, processed)
		H.I.fire(H.I.getSignal(game.UserInputService, signalName), input, processed == true)
	end

	T.test("a fast jump is filled cell by cell, in order, with no gap", function()
		local _, log = setup()
		press(2, 3)
		moveTo(9, 3)
		release(9, 3)
		T.eq(#log.draw, 1, "one request for the whole stroke")
		local cells = log.draw[1]
		T.eq(#cells, 8)
		for i, cell in ipairs(cells) do
			T.eq(cell[1], i + 1, "x of cell " .. i)
			T.eq(cell[2], 3, "y of cell " .. i)
		end
		assertChain(cells)
	end)

	T.test("a diagonal jump becomes an orthogonal path through every cell", function()
		local _, log = setup()
		press(2, 2)
		moveTo(6, 5)
		release(6, 5)
		local cells = log.draw[1]
		T.eq(#cells, 8, "start + 4 horizontal + 3 vertical steps")
		T.eq(cells[1][1], 2)
		T.eq(cells[1][2], 2)
		T.eq(cells[#cells][1], 6)
		T.eq(cells[#cells][2], 5)
		assertChain(cells)
		local seen = {}
		for _, cell in ipairs(cells) do
			local key = cell[1] .. ":" .. cell[2]
			T.falsy(seen[key], "no cell is sent twice")
			seen[key] = true
		end
	end)

	T.test("repeated cells are ignored and going back retracts the stroke", function()
		local _, log = setup()
		press(2, 2)
		moveTo(5, 2)
		moveTo(5, 2)
		moveTo(3, 2)
		moveTo(3, 4)
		release(3, 4)
		local cells = log.draw[1]
		T.eq(#cells, 4)
		T.eq(cells[1][1], 2)
		T.eq(cells[2][1], 3)
		T.eq(cells[3][1], 3)
		T.eq(cells[3][2], 3)
		T.eq(cells[4][1], 3)
		T.eq(cells[4][2], 4)
		assertChain(cells)
	end)

	T.test("a long stroke is cut into requests that never exceed the cap, overlapping by one cell", function()
		local RoadConfig = H.load("RoadConfig")
		RoadConfig.Input.MaxCellsPerRequest = 5
		local _, log = setup()
		press(0, 0)
		moveTo(11, 0)
		release(11, 0)
		T.eq(#log.draw, 3, "12 cells with a cap of 5: 5 + 5 + 4 with overlaps")
		-- Une fois les recouvrements retirés, on retrouve le tracé complet, dans l'ordre.
		local flat = {}
		local previousLast = nil
		for index, chunk in ipairs(log.draw) do
			T.le(#chunk, 5, "chunk " .. index .. " respects the cap")
			assertChain(chunk)
			if previousLast then
				T.eq(chunk[1][1], previousLast[1], "chunk " .. index .. " starts on the previous last cell")
				T.eq(chunk[1][2], previousLast[2])
			end
			for i = previousLast and 2 or 1, #chunk do
				table.insert(flat, chunk[i])
			end
			previousLast = chunk[#chunk]
		end
		T.eq(#flat, 12)
		for i, cell in ipairs(flat) do
			T.eq(cell[1], i - 1, "cell " .. i .. " of the stroke")
		end
	end)

	T.test("pressing on an existing road end extends it: the road cell starts the chain", function()
		local input, log = setup()
		input:applyRoadState({ roads = { "2:3" }, bridges = {}, buildings = {}, budget = 60, bridgesLeft = 3 })
		press(2, 3)
		moveTo(5, 3)
		release(5, 3)
		T.eq(#log.draw, 1)
		local cells = log.draw[1]
		T.eq(#cells, 4, "the existing road plus three new cells")
		T.eq(cells[1][1], 2)
		T.eq(cells[4][1], 5)
		assertChain(cells)
	end)

	T.test("Escape cancels the stroke: nothing is sent and the preview is hidden", function()
		local _, log = setup()
		press(2, 3)
		moveTo(6, 3)
		H.input.key("Escape", true)
		H.input.key("Escape", false)
		release(6, 3)
		T.eq(#log.draw, 0, "no DrawRoad after Escape")
		T.eq(#log.erase, 0)
		-- Le curseur reste sur 6:3 : seul le survol de cette case peut subsister.
		local t = H.load("Config").Grid.TileSize
		for _, part in ipairs(workspace.MM_RoadPreview:GetChildren()) do
			if part.Transparency < 1 then
				local p = part.CFrame.Position
				T.ok(p.X >= 6 * t and p.X < 7 * t, "no stroke cell remains, only the hover of 6:3")
			end
		end
	end)

	T.test("switching tool in the middle of a stroke cancels it", function()
		local _, log = setup()
		press(2, 3)
		moveTo(6, 3)
		H.input.key("Two", true)
		H.input.key("Two", false)
		release(6, 3)
		T.eq(#log.draw, 0)
		T.eq(#log.erase, 0, "the erase tool does not inherit the stroke")
	end)

	T.test("erase drag collects only existing roads, contiguous, sent once on release", function()
		local input, log = setup()
		input:applyRoadState({
			roads = { "2:3", "3:3", "4:3", "5:3", "6:3" },
			bridges = {},
			buildings = {},
			budget = 60,
			bridgesLeft = 3,
		})
		H.input.key("Two", true)
		H.input.key("Two", false)
		press(2, 3)
		moveTo(8, 3)
		release(8, 3)
		T.eq(#log.erase, 1, "one request for the whole drag")
		T.eq(#log.draw, 0)
		local keys = {}
		for _, key in ipairs(log.erase[1]) do
			keys[key] = true
		end
		local count = 0
		for key in pairs(keys) do
			count += 1
			T.ok(key:match("^%d+:3$"), "erased key " .. key .. " is a road of the row")
		end
		T.eq(count, 5, "the cells 7:3 and 8:3 are not roads and are not sent")
	end)

	T.test("erase drag cancelled with Escape sends nothing", function()
		local input, log = setup()
		input:applyRoadState({ roads = { "2:3", "3:3" }, bridges = {}, buildings = {}, budget = 60, bridgesLeft = 3 })
		H.input.key("Two", true)
		H.input.key("Two", false)
		press(2, 3)
		H.input.key("Escape", true)
		H.input.key("Escape", false)
		release(2, 3)
		T.eq(#log.erase, 0)
	end)

	T.test("right mouse button erases the roads it crosses and never builds or pans", function()
		local input, log = setup()
		input:applyRoadState({ roads = { "2:3", "3:3", "4:3" }, bridges = {}, buildings = {}, budget = 60, bridgesLeft = 3 })
		press(2, 3, 2)
		moveTo(4, 3)
		moveTo(4, 5)
		release(4, 5, 2)
		T.eq(log.pans, 0, "the right button never pans")
		T.eq(#log.draw, 0, "no road from a right-button drag")
		T.eq(#log.erase, 1, "one erase request on release")
		T.eq(#log.erase[1], 3, "the three roads crossed are erased")
	end)

	T.test("roundabout tool places on click and never starts a stroke", function()
		local _, log = setup()
		H.input.key("Three", true)
		H.input.key("Three", false)
		press(4, 4)
		moveTo(7, 4)
		release(7, 4)
		T.eq(#log.roundabouts, 1)
		T.eq(log.roundabouts[1][1], 4)
		T.eq(log.roundabouts[1][2], 4)
		T.eq(#log.draw, 0)
	end)

	T.test("a single touch draws like the mouse and sends on lift", function()
		local _, log = setup()
		local sx, sy = screenOf(2, 3)
		local finger = touchInput(sx, sy)
		fireInput("InputBegan", finger, false)
		sx, sy = screenOf(5, 3)
		finger.Position = Vector3.new(sx, sy, 0)
		fireInput("InputChanged", finger, false)
		T.eq(#log.draw, 0, "nothing sent while the finger is down")
		fireInput("InputEnded", touchInput(sx, sy, Enum.UserInputState.End), false)
		T.eq(#log.draw, 0, "a different touch ending changes nothing")
		fireInput("InputEnded", finger, false)
		T.eq(#log.draw, 1)
		T.eq(#log.draw[1], 4)
		assertChain(log.draw[1])
	end)

	T.test("a second finger is a camera gesture: it cancels the stroke and pans and zooms", function()
		local _, log = setup()
		local sx, sy = screenOf(4, 4)
		local first = touchInput(sx, sy)
		fireInput("InputBegan", first, false)
		sx, sy = screenOf(6, 4)
		local second = touchInput(sx, sy)
		fireInput("InputBegan", second, false)
		T.eq(#log.draw, 0, "the stroke begun by the first finger is cancelled")

		local farX, farY = screenOf(9, 4)
		second.Position = Vector3.new(farX, farY, 0)
		fireInput("InputChanged", second, false)
		T.ge(log.pans, 1, "the centre of the two fingers pans the view")
		T.eq(#log.zooms, 1)
		T.gt(log.zooms[1], 0, "spreading the fingers zooms in")

		local nearX, nearY = screenOf(3, 4)
		first.Position = Vector3.new(nearX, nearY, 0)
		fireInput("InputChanged", first, false)
		fireInput("InputEnded", first, false)
		fireInput("InputEnded", second, false)
		T.eq(#log.draw, 0, "the gesture never builds")
	end)

	T.test("a pointer over an interface element stops the stroke at that point", function()
		local _, log = setup()
		press(2, 3)
		moveTo(3, 3)
		local sx, sy = screenOf(5, 3)
		H.W.mouse = Vector2.new(sx, sy)
		fireInput("InputChanged", {
			UserInputType = Enum.UserInputType.MouseMovement,
			UserInputState = Enum.UserInputState.Change,
			KeyCode = Enum.KeyCode.Unknown,
			Position = Vector3.new(sx, sy, 0),
			Delta = Vector3.zero,
		}, true)
		moveTo(6, 3)
		release(6, 3)
		T.eq(#log.draw, 1)
		T.eq(#log.draw[1], 2, "only the cells before the interface are kept")
		T.eq(log.draw[1][2][1], 3)
	end)

	T.test("a release missed outside the window still validates the stroke", function()
		local _, log = setup()
		press(2, 3)
		moveTo(4, 3)
		H.W.buttonsDown.MouseButton1 = nil
		moveTo(6, 3)
		T.eq(#log.draw, 1, "the stroke is committed when the drag is noticed as released")
		T.eq(#log.draw[1], 3)
		release(6, 3)
		T.eq(#log.draw, 1, "the real release afterwards sends nothing more")
	end)

	T.test("losing window focus cancels the stroke", function()
		local _, log = setup()
		press(2, 3)
		moveTo(5, 3)
		fireInput("WindowFocusReleased", nil, false)
		release(5, 3)
		T.eq(#log.draw, 0)
	end)

	T.test("disabling the controller mid-stroke cancels it and ignores later input", function()
		local input, log = setup()
		press(2, 3)
		moveTo(5, 3)
		input:setEnabled(false)
		release(5, 3)
		press(2, 3)
		release(2, 3)
		T.eq(#log.draw, 0)
	end)

	T.test("a refused cell splits the stroke: each placeable run is its own contiguous request", function()
		local input, log = setup()
		input:applyRoadState({ roads = {}, bridges = {}, buildings = { "4:3" }, budget = 60, bridgesLeft = 3 })
		press(2, 3)
		moveTo(6, 3)
		release(6, 3)
		T.eq(#log.draw, 2, "one request on each side of the building")
		T.eq(#log.draw[1], 2)
		T.eq(#log.draw[2], 2)
		assertChain(log.draw[1])
		assertChain(log.draw[2])
		for _, chunk in ipairs(log.draw) do
			for _, cell in ipairs(chunk) do
				T.ne(cell[1], 4, "the building cell is never sent")
			end
		end
		T.eq(log.draw[2][1][1], 5, "the second run starts after the building")
	end)

	T.test("pressing on a refused cell sends nothing", function()
		local input, log = setup()
		input:applyRoadState({ roads = {}, bridges = {}, buildings = { "4:3" }, budget = 60, bridgesLeft = 3 })
		press(4, 3)
		release(4, 3)
		T.eq(#log.draw, 0)
	end)

	T.test("a left click during a right-button erase never starts a road", function()
		local input, log = setup()
		input:applyRoadState({ roads = { "2:3", "3:3", "4:3" }, bridges = {}, buildings = {}, budget = 60, bridgesLeft = 3 })
		press(2, 3, 2)
		moveTo(4, 3)
		press(5, 3, 1)
		moveTo(6, 4)
		release(6, 4, 1)
		release(6, 4, 2)
		T.eq(log.pans, 0, "the right button does not pan")
		T.eq(#log.draw, 0, "the left button does not build during the erase")
		T.eq(#log.erase, 1, "the erase still completes")
	end)
end
