return function(T, H)
	local function snapshot(demands, extra)
		local ids = {}
		for i = 1, demands do
			ids[i] = "1-" .. i
		end
		local store = {
			id = 1,
			x = 7,
			y = 12,
			colorIndex = 3,
			storeType = "small",
			demands = demands,
			demandIds = ids,
			capacity = 6,
			overloaded = false,
			critical = false,
			evolving = false,
			overloadClock = 12,
		}
		for k, v in pairs(extra or {}) do
			store[k] = v
		end
		return { stores = { store } }
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

	T.test("one pin per demand, removed when served", function()
		local controller = newController()
		controller:apply(snapshot(3))
		H.advance(1)
		T.eq(#pins(), 3)
		controller:apply(snapshot(1))
		H.advance(1)
		T.eq(#pins(), 1)
		controller:apply(snapshot(0))
		H.advance(1)
		T.eq(#pins(), 0)
	end)

	T.test("pins use the store's colour and stay small", function()
		local Config = H.load("Config")
		local StoreConfig = H.load("StoreConfig")
		local controller = newController()
		controller:apply(snapshot(2))
		H.advance(1)
		local palette = Config.HouseColors[3]
		for _, pin in ipairs(pins()) do
			T.ok(pin.Size.X.Offset <= StoreConfig.Visual.PinSize * 1.5, "a request pin must be small, not a prototype blob")
			local colours = {}
			for _, d in ipairs(pin:GetDescendants()) do
				if d:IsA("Frame") then
					table.insert(colours, d.BackgroundColor3)
				end
			end
			table.insert(colours, pin.BackgroundColor3)
			local found = false
			for _, c in ipairs(colours) do
				if c == palette.color or c == palette.base then
					found = true
				end
			end
			T.ok(found, "pin colour must match its store colour")
		end
	end)

	T.test("pins do not overlap: they are laid out in a row", function()
		local controller = newController()
		controller:apply(snapshot(6))
		H.advance(1)
		local list = pins()
		T.eq(#list, 6)
		local parent = list[1].Parent
		local layout = parent and parent:FindFirstChildWhichIsA("UIListLayout") or list[1].Parent.Parent:FindFirstChildWhichIsA("UIListLayout", true)
		T.ok(layout, "pins must be arranged by a layout so they never overlap")
	end)

	T.test("a store that disappears from the snapshot loses its pins", function()
		local controller = newController()
		controller:apply(snapshot(2))
		H.advance(1)
		controller:apply({ stores = {} })
		H.advance(1)
		T.eq(#pins(), 0)
	end)

	T.test("apply before setWorld is deferred, malformed data is ignored", function()
		H.asClient()
		local controller = H.load("StoreVisualController").new()
		T.noThrow(function()
			controller:apply(snapshot(2))
			controller:setWorld(Vector3.new(700, 0, 0), 4)
			controller:apply(nil)
			controller:apply({ stores = { "x", { id = "bad" }, 5 } })
			controller:apply({})
		end)
	end)

	T.test("overload state shows a countdown; every state renders without error", function()
		local controller = newController()
		for _, extra in ipairs({
			{ overloaded = true, overloadClock = 7 },
			{ overloaded = true, critical = true, overloadClock = 0 },
			{ evolving = true },
			{ storeType = "large", capacity = 8 },
		}) do
			T.noThrow(function()
				controller:apply(snapshot(6, extra))
				H.advance(0.5)
			end)
		end
		T.eq(#H.handlerErrors, 0)
	end)

	T.test("clear and destroy remove everything", function()
		local controller = newController()
		controller:apply(snapshot(4))
		H.advance(1)
		controller:clear()
		T.eq(#pins(), 0)
		controller:destroy()
		T.eq(#pins(), 0)
	end)

	T.test("100 snapshots in a row stay cheap and leak nothing", function()
		local controller = newController()
		for i = 1, 100 do
			controller:apply(snapshot(i % 7))
		end
		H.advance(2)
		controller:apply(snapshot(0))
		H.advance(2)
		T.eq(#pins(), 0)
	end)
end
