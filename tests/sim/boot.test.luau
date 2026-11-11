return function(T, H)
	local function maps()
		return H.load("Maps").all()
	end

	local function countKeys(t)
		local n = 0
		for _ in pairs(t) do
			n += 1
		end
		return n
	end

	T.test("every map starts: 1 store + start houses of the same colour, none on water", function()
		local Maps = H.load("Maps")
		local Config = H.load("Config")
		local StoreConfig = H.load("StoreConfig")
		for _, map in ipairs(maps()) do
			H.reset()
			local session = H.newSession(map.id)
			T.eq(#session.destinations, StoreConfig.Spawn.StartStores, map.id .. " stores")
			T.eq(#session.houses, StoreConfig.Houses.StartHouses, map.id .. " houses")
			local store = session.destinations[1]
			for _, house in ipairs(session.houses) do
				T.eq(house.colorIndex, store.colorIndex, map.id .. ": a house must share its store's colour")
			end
			local cells = {}
			for _, b in ipairs(session.buildingList) do
				T.falsy(Maps.isWater(session.map, b.x, b.y), map.id .. ": building on water at " .. b.key)
				T.ok(b.x >= 0 and b.y >= 0 and b.x < Config.Grid.Size and b.y < Config.Grid.Size, map.id .. " out of bounds")
				T.falsy(cells[b.key], map.id .. ": two buildings share " .. b.key)
				cells[b.key] = true
			end
		end
	end)

	T.test("start publishes GameStarted, State and RoadState to the client", function()
		local session, player = H.newSession("los_angeles")
		local started = H.lastSent("GameStarted")
		T.ok(started, "GameStarted")
		T.eq(started.mapId, "los_angeles")
		T.eq(started.size, session.size)
		T.eq(started.tile, session.tile)
		T.gt(started.weekDuration, 0)
		T.isType(started.origin, "Vector3")
		local state = H.lastSent("State")
		T.ok(state, "State")
		T.eq(state.score, 0)
		T.eq(state.week, 1)
		T.eq(state.houses, #session.houses)
		T.eq(state.destinations, #session.destinations)
		local road = H.lastSent("RoadState")
		T.ok(road, "RoadState")
		T.eq(#road.buildings, #session.buildingList)
		T.eq(#road.roads, 0)
		for _, entry in ipairs(H.remoteLog()) do
			T.eq(entry.player, player, "server messages go to the session's player only")
		end
	end)

	T.test("the world is built under Workspace and destroyed with the session", function()
		local before = H.count(workspace)
		local session = H.newSession("los_angeles")
		T.gt(H.count(workspace), before + 50, "terrain, grid and buildings exist")
		T.ok(session.world and session.world.folder, "session.world.folder")
		T.ok(session.world.folder:IsDescendantOf(workspace))
		session:destroy()
		H.flush(5)
		T.eq(session.world, nil)
		for _, child in ipairs(workspace:GetDescendants()) do
			T.falsy(child:IsA("BasePart") and child.Name == "Road", "road part left behind")
		end
		T.eq(H.count(workspace:FindFirstChild("MMWorlds") or Instance.new("Folder")), 0, "MMWorlds must be empty after destroy")
	end)

	T.test("destroy leaves no event connections behind", function()
		local baseline = H.connectionCount()
		local session = H.newSession("los_angeles")
		H.runSession(session, 5)
		session:destroy()
		H.flush(5)
		T.le(H.connectionCount(), baseline + 2, "leaked connections")
	end)

	T.test("each player gets an isolated world far from the others", function()
		H.setupRemotes()
		local Session = H.load("Session")
		local a = Session.new(H.newPlayer("A", 1), "los_angeles", 1)
		local b = Session.new(H.newPlayer("B", 2), "tokyo", 2)
		T.gt((a.origin - b.origin).Magnitude, a.size * a.tile * 2, "origins must not overlap")
		a:start()
		b:start()
		a:destroy()
		T.ok(b.world and b.world.folder.Parent, "destroying one session keeps the other")
		T.eq(#b.destinations, 1)
	end)

	T.test("same seed gives the same starting layout (deterministic generation)", function()
		local function layout()
			H.reset()
			local session = H.newSession("los_angeles")
			local keys = {}
			for _, b in ipairs(session.buildingList) do
				table.insert(keys, b.kind .. b.key .. b.colorIndex)
			end
			return table.concat(keys, ",")
		end
		T.eq(layout(), layout())
	end)

	T.test("buildings keep a spacing: no two stores closer than the configured distance", function()
		local StoreConfig = H.load("StoreConfig")
		for run = 1, 5 do
			H.reset()
			H.seed(run * 97)
			local session = H.newSession("london")
			H.runSession(session, 400, 0.5)
			T.ge(#session.destinations, 2, "stores should have appeared")
			for i = 1, #session.destinations do
				for j = i + 1, #session.destinations do
					local a, b = session.destinations[i], session.destinations[j]
					local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
					T.ge(d, StoreConfig.Spawn.MinStoreDistance - 1e-6, "stores " .. a.key .. " / " .. b.key)
				end
			end
			if session.over then
				session:destroy()
			end
		end
	end)

	T.test("buildings are never glued together (minimum spacing, on every map)", function()
		local StoreConfig = H.load("StoreConfig")
		local minimum = math.min(StoreConfig.Spawn.MinBuildingDistance, StoreConfig.Houses.MinDistanceFromBuilding)
		for _, map in ipairs(maps()) do
			H.reset()
			H.seed(4242)
			local session = H.newSession(map.id)
			H.runSession(session, 500, 0.5)
			local list = session.buildingList
			for i = 1, #list do
				for j = i + 1, #list do
					local d = math.sqrt((list[i].x - list[j].x) ^ 2 + (list[i].y - list[j].y) ^ 2)
					T.ge(d, minimum - 1e-6, map.id .. ": " .. list[i].key .. " and " .. list[j].key .. " are too close")
				end
			end
			session:destroy()
		end
	end)

	T.test("a store evolves from small to large: same place and colour, bigger capacity, model replaced cleanly", function()
		local StoreConfig = H.load("StoreConfig")
		local session = H.newSession("los_angeles")
		session.budget = 500
		session.satisfaction = 1e9
		for _, house in ipairs(session.houses) do
			H.connect(session, house, session.destinations[1])
		end
		local store = session.destinations[1]
		local x, y, colorIndex = store.x, store.y, store.colorIndex
		T.eq(store.storeType, "small")
		T.eq(store.capacity, StoreConfig.Demand.SmallCapacity)
		local elapsed = 0
		while store.storeType == "small" and elapsed < 1500 do
			H.runSession(session, 10, 0.1)
			elapsed += 10
		end
		H.runSession(session, 2, 0.1)
		T.eq(store.storeType, "large", "a store that keeps being served must evolve")
		T.eq(store.capacity, StoreConfig.Demand.LargeCapacity)
		T.eq(store.x, x)
		T.eq(store.y, y)
		T.eq(store.colorIndex, colorIndex)
		T.ok(store.model.Parent, "the evolved model is in the world")
		local models = 0
		for _, child in ipairs(session.world.Buildings:GetChildren()) do
			if string.find(child.Name, "store_" .. store.id, 1, true) then
				models += 1
			end
		end
		T.eq(models, 1, "exactly one model per store after the evolution (no stale small model)")
	end)

	T.test("stores get unique colours and each store has houses of its colour", function()
		local session = H.newSession("tokyo")
		H.runSession(session, 700, 0.5)
		local seen = {}
		for _, store in ipairs(session.destinations) do
			T.falsy(seen[store.colorIndex], "two stores share colour " .. store.colorIndex)
			seen[store.colorIndex] = true
		end
		local byColor = {}
		for _, house in ipairs(session.houses) do
			byColor[house.colorIndex] = (byColor[house.colorIndex] or 0) + 1
		end
		for _, store in ipairs(session.destinations) do
			T.ge(byColor[store.colorIndex] or 0, 1, "store without a house of its colour")
		end
		T.ge(countKeys(byColor), 1)
	end)

	T.test("the grid is discreet: hair-thin lines close to the ground colour", function()
		local session = H.newSession("los_angeles")
		local function luminance(c)
			return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
		end
		local ground = session.world.folder:FindFirstChild("Ground", true)
		local lines = H.find(session.world.folder, { name = "GridH" })
		T.ok(ground and #lines > 0, "ground and grid exist")
		for _, line in ipairs(lines) do
			T.lt(math.abs(luminance(line.Color) - luminance(ground.Color)), 0.15, "grid contrast vs ground")
			T.le(math.min(line.Size.X, line.Size.Z), 0.25, "grid lines must be hair-thin")
		end
		T.eq(#H.find(session.world.folder, { name = "GridH" }), #H.find(session.world.folder, { name = "GridV" }), "same number of horizontal and vertical lines")
	end)

	T.test("grid lines are aligned with the cells (same pitch as the tile size)", function()
		local session = H.newSession("los_angeles")
		local xs = {}
		for _, line in ipairs(H.find(session.world.folder, { name = "GridV" })) do
			table.insert(xs, line.Position.X)
		end
		table.sort(xs)
		T.ge(#xs, 2)
		for i = 2, #xs do
			T.near((xs[i] - xs[i - 1]) % session.tile, 0, 1e-6, "grid pitch must be a multiple of the tile size")
		end
	end)

	-- Brief, part 7: remove the diagonal hatched band and the small vertical
	-- side texts around the terrain (WorldBuilder.addHatchedBorder /
	-- addMapLabel).
	T.todo("no hatched border and no vertical side labels around the map", function()
		local session = H.newSession("los_angeles")
		T.eq(#H.find(session.world.folder, { name = "BorderHatch" }), 0, "hatched border")
		T.eq(#H.find(session.world.folder, { name = "MapLabelStrip" }), 0, "side label strips")
	end)

	T.test("trees are small decor", function()
		local Config = H.load("Config")
		local session = H.newSession("los_angeles")
		local trees = H.find(session.world.folder, { name = "Tree" })
		T.gt(#trees, 0, "parks have trees")
		T.le(#trees, 60, "do not overload the map with decor")
		for _, tree in ipairs(trees) do
			T.le(math.max(tree.Size.X, tree.Size.Z), Config.Grid.TileSize * 1.5, "trees stay small")
		end
	end)

	-- Brief, part 6.5/6.6: trees must never be drawn on water. The park-centre
	-- clusters of WorldBuilder ignore Maps.isWater (los_angeles has one tree at
	-- cell 4:12 in the sea).
	T.todo("no tree is drawn on water, on any map", function()
		local Maps, Grid = H.load("Maps"), H.load("Grid")
		for _, map in ipairs(Maps.all()) do
			H.reset()
			local session = H.newSession(map.id)
			for _, tree in ipairs(H.find(session.world.folder, { name = "Tree" })) do
				local x, y = Grid.cellFromWorld(session.origin, tree.Position)
				T.falsy(Maps.isWater(session.map, x, y), map.id .. ": tree on water at " .. x .. ":" .. y)
			end
		end
	end)

	-- Buildings are placed without looking at the park trees: ~3.5% of the
	-- buildings (10 of 288 over 36 runs) land on a cell that holds a tree.
	T.todo("buildings never spawn on a cell that holds a tree", function()
		local Maps, Grid = H.load("Maps"), H.load("Grid")
		for _, map in ipairs(Maps.all()) do
			for seed = 1, 6 do
				H.reset()
				H.seed(seed * 31)
				local session = H.newSession(map.id)
				H.runSession(session, 500, 0.5)
				local treeCells = {}
				for _, tree in ipairs(H.find(session.world.folder, { name = "Tree" })) do
					local x, y = Grid.cellFromWorld(session.origin, tree.Position)
					treeCells[x .. ":" .. y] = true
				end
				for _, building in ipairs(session.buildingList) do
					T.falsy(treeCells[building.key], map.id .. " seed " .. seed .. ": " .. building.kind .. " on a tree at " .. building.key)
				end
				session:destroy()
			end
		end
	end)
end
