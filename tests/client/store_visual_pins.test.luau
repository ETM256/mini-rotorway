return function(T, H)
	local function store(extra)
		local state = {
			id = 1,
			x = 7,
			y = 12,
			colorIndex = 3,
			storeType = "small",
			demands = 0,
			demandIds = {},
			capacity = 6,
			overloaded = false,
			critical = false,
			evolving = false,
			overloadClock = 12,
		}
		for k, v in pairs(extra or {}) do
			state[k] = v
		end
		return state
	end

	local function withDemands(ids, extra)
		local state = store(extra)
		state.demandIds = ids
		state.demands = #ids
		return { stores = { state } }
	end

	local function idsFrom(prefix, count)
		local ids = {}
		for i = 1, count do
			ids[i] = prefix .. "-" .. i
		end
		return ids
	end

	local function newController()
		H.asClient()
		local Controller = H.load("StoreVisualController")
		local controller = Controller.new()
		controller:setWorld(Vector3.new(700, 0, 0), 4)
		return controller
	end

	local function pins()
		return H.find(workspace, { name = "DemandPin" })
	end

	local function warning()
		return H.find(workspace, { name = "Overload" })[1]
	end

	local function billboards()
		return H.find(workspace, { name = "DemandPins" })
	end

	T.test("pins are small circles in the store colour, with a thin soft rim", function()
		local Config = H.load("Config")
		local StoreConfig = H.load("StoreConfig")
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 3)))
		H.advance(1)
		local palette = Config.HouseColors[3]
		local list = pins()
		T.eq(#list, 3)
		for _, pin in ipairs(list) do
			T.eq(pin.Size.X.Offset, StoreConfig.Visual.PinSize)
			T.eq(pin.Size.Y.Offset, StoreConfig.Visual.PinSize)
			T.eq(pin.BackgroundColor3, palette.color)
			local corner = pin:FindFirstChildWhichIsA("UICorner")
			T.ok(corner, "a pin must be round")
			T.eq(corner.CornerRadius.Scale, 0.5)
			local stroke = pin:FindFirstChildWhichIsA("UIStroke")
			T.ok(stroke, "the rim is a stroke, not a border")
			T.eq(stroke.Thickness, 1)
			T.eq(stroke.Color, palette.base)
			T.ge(stroke.Transparency, 0.3, "the rim must stay soft")
		end
	end)

	T.test("pins stay readable when zoomed out: pixel sizes, never hidden by distance", function()
		local StoreConfig = H.load("StoreConfig")
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 2)))
		H.advance(1)
		T.ge(StoreConfig.Visual.PinSize, 8, "a pin below 8 px is lost when zoomed out")
		T.le(StoreConfig.Visual.PinSize, 14, "a pin above 14 px looks like a prototype blob")
		for _, board in ipairs(billboards()) do
			T.ge(board.MaxDistance, 1000, "the camera is never far enough to hide pins")
		end
	end)

	T.test("pins wrap into rows of PinsPerRow, the first row touching the store", function()
		local StoreConfig = H.load("StoreConfig")
		local perRow = StoreConfig.Visual.PinsPerRow
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 8), { storeType = "large", capacity = 8 }))
		H.advance(1)
		local list = pins()
		T.eq(#list, 8)
		local byRow = {}
		local orders = {}
		for _, pin in ipairs(list) do
			local row = pin.Parent
			byRow[row.Name] = (byRow[row.Name] or 0) + 1
			local key = row.Name .. ":" .. tostring(pin.LayoutOrder)
			T.falsy(orders[key], "two pins share the same slot in a row")
			orders[key] = true
		end
		T.eq(byRow.Row1, perRow, "the first row is full")
		T.eq(byRow.Row2, 8 - perRow, "the overflow goes to the second row")
	end)

	T.test("a store with more pins than fit a row: the alert moves above the stack", function()
		local StoreConfig = H.load("StoreConfig")
		local visual = StoreConfig.Visual
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 1)))
		H.advance(1)
		T.eq(warning().Position.Y.Offset, -(visual.PinSize + visual.PinWarningGap))
		controller:apply(withDemands(idsFrom("1", 6)))
		H.advance(1)
		T.eq(warning().Position.Y.Offset, -(2 * visual.PinSize + visual.PinGap + visual.PinWarningGap))
	end)

	T.test("unchanged demands keep the same pin and billboard instances", function()
		local controller = newController()
		local ids = idsFrom("1", 4)
		controller:apply(withDemands(ids))
		H.advance(1)
		local before = pins()
		local boardBefore = billboards()
		for _ = 1, 20 do
			controller:apply(withDemands(ids))
		end
		H.advance(1)
		local after = pins()
		T.eq(#after, #before)
		for _, pin in ipairs(before) do
			T.contains(after, pin)
		end
		T.eq(#billboards(), #boardBefore)
		T.eq(billboards()[1], boardBefore[1])
	end)

	T.test("a served demand removes only its own pin", function()
		local controller = newController()
		controller:apply(withDemands({ "1-1", "1-2", "1-3" }))
		H.advance(1)
		local before = pins()
		T.eq(#before, 3)
		controller:apply(withDemands({ "1-1", "1-3" }))
		H.advance(1)
		local alive = 0
		for _, pin in ipairs(before) do
			if pin.Parent then
				alive += 1
			end
		end
		T.eq(alive, 2, "exactly the served pin is destroyed")
		T.eq(#pins(), 2)
	end)

	T.test("newcomers appear progressively: scaled to zero, then full size", function()
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 4)))
		for _, pin in ipairs(pins()) do
			local scale = pin:FindFirstChildWhichIsA("UIScale")
			T.eq(scale.Scale, 0, "nothing is fully visible in the first frame")
		end
		H.advance(0.3)
		local scales = {}
		for _, pin in ipairs(pins()) do
			table.insert(scales, pin:FindFirstChildWhichIsA("UIScale").Scale)
		end
		T.contains(scales, 0, "the last pin of the wave is still growing")
		H.advance(1)
		for _, pin in ipairs(pins()) do
			T.eq(pin:FindFirstChildWhichIsA("UIScale").Scale, 1)
		end
	end)

	T.test("a served pin shrinks before it disappears", function()
		local controller = newController()
		controller:apply(withDemands({ "1-1" }))
		H.advance(1)
		local pin = pins()[1]
		controller:apply(withDemands({}))
		T.ok(pin.Parent, "the pin is still there while it shrinks")
		H.advance(1)
		T.falsy(pin.Parent)
		T.eq(#pins(), 0)
	end)

	T.test("overload shows a countdown, critical shows an alert; both clear when resolved", function()
		local Config = H.load("Config")
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 6), { overloaded = true, overloadClock = 6.4 }))
		H.advance(0.5)
		T.ok(warning().Visible)
		T.eq(warning().Text, "7s", "the countdown rounds up to whole seconds")
		T.eq(warning().BackgroundColor3, Config.Colors.LobbyOrange)

		controller:apply(withDemands(idsFrom("1", 6), { overloaded = true, critical = true, overloadClock = 0 }))
		H.advance(0.5)
		T.eq(warning().Text, "!!")
		T.eq(warning().BackgroundColor3, Config.Colors.Danger)
		T.eq(warning().TextColor3, Config.Colors.Ink, "the text stays dark on the coral background")

		controller:apply(withDemands(idsFrom("1", 5)))
		H.advance(0.5)
		T.falsy(warning().Visible, "the alert disappears once the store is back under capacity")
	end)

	T.test("the store colour follows a colour change of the same store", function()
		local Config = H.load("Config")
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 2)))
		H.advance(1)
		controller:apply(withDemands(idsFrom("1", 2), { colorIndex = 5 }))
		H.advance(1)
		local palette = Config.HouseColors[5]
		for _, pin in ipairs(pins()) do
			T.eq(pin.BackgroundColor3, palette.color)
		end
	end)

	T.test("evolution moves the pins to the large silhouette; a repeated snapshot must not restart the glide", function()
		local StoreConfig = H.load("StoreConfig")
		local visual = StoreConfig.Visual
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 2)))
		H.advance(1)
		local board = billboards()[1]
		local smallZ = board.StudsOffsetWorldSpace.Z
		T.near(smallZ, -(visual.SmallSize * 0.5 + visual.PinLift), 0.001)

		local large = withDemands(idsFrom("1", 2), { storeType = "large", capacity = 8 })
		local largeZ = -(visual.LargeSize * 0.5 + visual.PinLift)
		controller:apply(large)
		H.advance(0.3)
		T.near(board.StudsOffsetWorldSpace.Z, smallZ, 0.001, "the glide is still running")
		-- Un snapshot identique au milieu du glissement ne doit pas le relancer :
		-- sinon l'arrivée, due à 0.55 s après le premier snapshot, serait repoussée.
		controller:apply(large)
		H.advance(0.3)
		T.near(board.StudsOffsetWorldSpace.Z, largeZ, 0.001, "a repeated snapshot must not restart the glide")
	end)

	T.test("a newcomer never takes the place of a pin still shrinking", function()
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 4)))
		H.advance(1)
		local leaving = nil
		for _, pin in ipairs(pins()) do
			if pin.Parent.Name == "Row1" and pin.LayoutOrder == 1 then
				leaving = pin
			end
		end
		T.ok(leaving, "the first demand sits in the first place of row 1")

		controller:apply(withDemands({ "1-2", "1-3", "1-4", "1-5" }))
		local newcomer = nil
		for _, pin in ipairs(pins()) do
			if pin.LayoutOrder == 1 and pin.Parent.Name == "Row2" then
				newcomer = pin
			end
		end
		T.ok(newcomer, "the newcomer goes to the next row while the served place is still busy")
		T.ok(leaving.Parent, "the served pin is still shrinking in its place")
		T.eq(leaving.Parent.Name, "Row1")
		H.advance(1)
		T.falsy(leaving.Parent)
		T.eq(newcomer.Parent.Name, "Row2")
		T.eq(#pins(), 4)
	end)

	T.test("a full store reuses the place of a leaving pin without leaving an orphan", function()
		local controller = newController()
		local large = { storeType = "large", capacity = 8 }
		controller:apply(withDemands(idsFrom("1", 8), large))
		H.advance(1)
		local leaving = nil
		for _, pin in ipairs(pins()) do
			if pin.Parent.Name == "Row1" and pin.LayoutOrder == 1 then
				leaving = pin
			end
		end
		T.ok(leaving)

		local ids = { "1-2", "1-3", "1-4", "1-5", "1-6", "1-7", "1-8", "1-9" }
		controller:apply(withDemands(ids, large))
		T.falsy(leaving.Parent, "no free place: the leaving pin gives its place at once")
		T.eq(#pins(), 8)
		local orders = {}
		for _, pin in ipairs(pins()) do
			T.ok(pin.Parent, "every live pin is shown")
			local key = pin.Parent.Name .. ":" .. tostring(pin.LayoutOrder)
			T.falsy(orders[key], "two pins share the same place")
			orders[key] = true
		end
	end)

	T.test("partial or malformed payloads never throw and keep the pins already shown", function()
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 3)))
		H.advance(1)
		T.noThrow(function()
			controller:apply({ stores = { { id = 1 } } })
			controller:apply({ stores = { { id = 1, x = 7, y = 12 } } })
			controller:apply({ stores = { { id = 1 }, 5, "x", { id = "bad" }, { id = 2, x = "a", y = 1 } } })
			controller:apply({ stores = "not a list" })
			controller:apply({})
			controller:apply(nil)
		end)
		H.advance(1)
		T.eq(#H.handlerErrors, 0)
		T.eq(#pins(), 3, "a payload without demand information must not erase pins")
		T.eq(#billboards(), 1)
	end)

	T.test("a store missing from the snapshot takes its pins and billboard with it", function()
		local controller = newController()
		local first = store({ id = 1 })
		first.demandIds = idsFrom("1", 2)
		local second = store({ id = 2, x = 9, y = 3, colorIndex = 4 })
		second.demandIds = idsFrom("2", 3)
		controller:apply({ stores = { first, second } })
		H.advance(1)
		T.eq(#pins(), 5)
		controller:apply({ stores = { second } })
		H.advance(1)
		T.eq(#pins(), 3)
		T.eq(#billboards(), 1)
	end)

	T.test("clear removes every instance and the controller can be reused", function()
		local controller = newController()
		local folder = workspace:FindFirstChild("MMStorePins")
		local baseline = H.instanceCount()
		controller:apply(withDemands(idsFrom("1", 5)))
		H.advance(1)
		controller:clear()
		T.eq(#pins(), 0)
		T.eq(#billboards(), 0)
		T.eq(#folder:GetChildren(), 0)
		T.eq(H.instanceCount(), baseline, "clear must not leave instances behind")
		controller:apply(withDemands(idsFrom("2", 2)))
		H.advance(1)
		T.eq(#pins(), 2)
	end)

	T.test("destroy disconnects everything; later snapshots are ignored", function()
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 3)))
		H.advance(1)
		local connections = H.connectionCount()
		controller:destroy()
		T.eq(#pins(), 0)
		T.falsy(workspace:FindFirstChild("MMStorePins"))
		T.eq(H.connectionCount(), connections)
		T.noThrow(function()
			controller:apply(withDemands(idsFrom("1", 3)))
			controller:setWorld(Vector3.new(0, 0, 0), 4)
			controller:destroy()
		end)
		H.advance(1)
		T.eq(#pins(), 0)
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("restarts do not leak: repeated worlds and snapshots keep the instance count flat", function()
		H.asClient()
		local controller = H.load("StoreVisualController").new()
		controller:setWorld(Vector3.new(700, 0, 0), 4)
		local baseline = nil
		for cycle = 1, 10 do
			controller:apply(withDemands(idsFrom("c", 6)))
			H.advance(1)
			controller:clear()
			controller:setWorld(Vector3.new(700, 0, 0), 4)
			if cycle == 1 then
				baseline = H.instanceCount()
			end
		end
		T.eq(H.instanceCount(), baseline, "each restart must reuse the same folder and leave nothing behind")
		controller:destroy()
	end)

	T.test("identical snapshots create no GUI and no connection", function()
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 4), { overloaded = true, overloadClock = 9 }))
		H.advance(1)
		local instances = H.instanceCount()
		local connections = H.connectionCount()
		for _ = 1, 50 do
			controller:apply(withDemands(idsFrom("1", 4), { overloaded = true, overloadClock = 9 }))
		end
		H.advance(1)
		T.eq(H.instanceCount(), instances)
		T.eq(H.connectionCount(), connections)
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("a real game start draws the server's demands without client errors", function()
		H.runScript("Bootstrap")
		H.asClient()
		H.runScript("Main")
		H.advance(0.1)
		H.fireServer("StartGame", "los_angeles")
		H.advance(30)
		local message = H.handlerErrors[1] and H.handlerErrors[1].message or ""
		T.eq(#H.handlerErrors, 0, message)
		T.ok(H.lastSent("StoreState"), "the server must send StoreState")
		T.ge(#pins(), 1, "the first store's demands must be drawn")
	end)

	T.test("a store is never shown with more pins than its capacity", function()
		local controller = newController()
		controller:apply(withDemands(idsFrom("1", 12), { capacity = 6 }))
		H.advance(1)
		T.eq(#pins(), 6)
	end)
end
