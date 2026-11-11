return function(T, H)
	-- Rendu incrémental : budget de parts, effacement, lots, performance, suite
	-- aléatoire de constructions et d'effacements, nettoyage à la destruction.

	local Grid = H.load("Grid")
	local Maps = H.load("Maps")
	local RoadGeometry = H.load("RoadGeometry")
	local PART_BUDGET = 8

	local function countKeys(t)
		local n = 0
		for _ in pairs(t) do
			n += 1
		end
		return n
	end

	local function dryCell(session, x, y)
		local key = Grid.key(x, y)
		return Grid.inBounds(x, y) and not session.buildings[key] and not Maps.isWater(session.map, x, y)
	end

	-- Cases sans bâtiment (sèches, ou avec eau si withWater), dans l'ordre des lignes.
	local function dryCells(session, limit, withWater)
		local cells = {}
		for y = 0, session.size - 1 do
			for x = 0, session.size - 1 do
				local key = Grid.key(x, y)
				if (withWater and not session.buildings[key]) or dryCell(session, x, y) then
					cells[#cells + 1] = { x, y }
					if #cells == limit then
						return cells
					end
				end
			end
		end
		return cells
	end

	local function keysOf(cells)
		local keys = {}
		for index, cell in ipairs(cells) do
			keys[index] = Grid.key(cell[1], cell[2])
		end
		return keys
	end

	local function roadPartCount(session)
		return H.count(session.world.Roads, "BasePart")
	end

	-- Connecteurs attendus, recalculés sans passer par le renderer.
	local function expectedPieces(session, key)
		local x, y = Grid.parse(key)
		local connectors = {}
		for name, d in pairs({ N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }) do
			if session.buildings[Grid.key(x + d[1], y + d[2])] then
				connectors[RoadGeometry.connectorKey(x, y, name)] = true
			end
		end
		return RoadGeometry.cellPieces(session.roads, session.bridges, connectors, x, y)
	end

	-- Le rendu incrémental donne exactement ce que donnerait un rendu complet :
	-- mêmes cases, même nombre de parts, budget respecté, aucune part orpheline.
	local function checkConsistent(session, label)
		local listed = 0
		for key, parts in pairs(session.roadParts) do
			T.ok(session.roads[key], label .. ": parts kept for a missing road " .. key)
			T.le(#parts, PART_BUDGET, label .. ": part budget at " .. key)
			T.eq(#parts, #expectedPieces(session, key), label .. ": parts of " .. key .. " differ from its geometry")
			listed += #parts
		end
		for key in pairs(session.roads) do
			T.ok(session.roadParts[key], label .. ": road without parts " .. key)
		end
		T.eq(roadPartCount(session), listed, label .. ": orphan or missing road parts")
	end

	T.test("every road cell stays within the part budget, with no orphan part", function()
		local session = H.newSession("los_angeles")
		session.budget = 400
		local cells = dryCells(session, 120)
		session:drawRoad(cells)
		H.runSession(session, 1)
		T.gt(countKeys(session.roads), 100, "a big network")
		checkConsistent(session, "dense network")
		local worst = 0
		for _, parts in pairs(session.roadParts) do
			worst = math.max(worst, #parts)
		end
		T.le(worst, PART_BUDGET)
	end)

	T.test("erasing a middle cell re-renders both neighbours as dead ends", function()
		local session = H.newSession("los_angeles")
		local cells = dryCells(session, 3)
		local keys = keysOf(cells)
		session:drawRoad(cells)
		T.eq(#session.roadParts[keys[1]], 4, "end cell: edge and body, arm and round cap")
		T.eq(#session.roadParts[keys[2]], 2, "straight cell: edge and body")
		session:eraseRoad(keys[2])
		T.eq(session.roadParts[keys[2]], nil, "the erased cell loses its parts")
		T.eq(#session.roadParts[keys[1]], 2, "the left neighbour is now an isolated block")
		T.eq(#session.roadParts[keys[3]], 2, "the right neighbour is now an isolated block")
		T.eq(roadPartCount(session), 4)
		checkConsistent(session, "after erase")
	end)

	T.test("erasing every road returns the road parts count to zero", function()
		local session = H.newSession("los_angeles")
		session.budget = 400
		local cells = dryCells(session, 80)
		session:drawRoad(cells)
		T.gt(roadPartCount(session), 80)
		session:eraseRoads(keysOf(cells))
		T.eq(roadPartCount(session), 0, "no road part left")
		T.eq(countKeys(session.roadParts), 0)
		T.eq(countKeys(session.roads), 0)
		session:drawRoad(cells)
		T.gt(roadPartCount(session), 80, "drawing again works after a full erase")
	end)

	T.test("a batch erase re-renders each remaining cell at most once", function()
		local session = H.newSession("los_angeles")
		session.budget = 400
		local cells = dryCells(session, 40)
		session:drawRoad(cells)
		local renders = {}
		local original = session.renderRoadCell
		session.renderRoadCell = function(self, key, reveal)
			renders[key] = (renders[key] or 0) + 1
			return original(self, key, reveal)
		end
		-- Une cellule sur deux : chaque voisine est touchée par deux effacements.
		local keys = {}
		for index = 1, #cells, 2 do
			keys[#keys + 1] = Grid.key(cells[index][1], cells[index][2])
		end
		session:eraseRoads(keys)
		T.gt(countKeys(renders), 0, "some neighbours changed shape")
		for key, times in pairs(renders) do
			T.eq(times, 1, key .. " rendered once")
			T.ok(session.roads[key], key .. " is a standing road")
		end
		checkConsistent(session, "after batch erase")
	end)

	T.test("drawing a line renders each cell once, and the next frame renders nothing", function()
		local session = H.newSession("los_angeles")
		local cells = dryCells(session, 10)
		local renders = 0
		local original = session.renderRoadCell
		session.renderRoadCell = function(self, key, reveal)
			renders += 1
			return original(self, key, reveal)
		end
		session:drawRoad(cells)
		T.le(renders, #cells + 2, "new cells plus at most their two ends")
		renders = 0
		H.runSession(session, 1)
		T.eq(renders, 0, "an idle session does not re-render roads")
	end)

	T.test("an unchanged network is not redrawn when a neighbour cell changes elsewhere", function()
		local session = H.newSession("los_angeles")
		session.budget = 400
		local cells = dryCells(session, 12)
		session:drawRoad(cells)
		local keys = keysOf(cells)
		local before = session.roadParts[keys[1]]
		session:eraseRoad(keys[12])
		T.ok(session.roadParts[keys[1]] == before, "a distant cell keeps its parts")
	end)

	T.test("appearance animation is tracked, finishes on the final shape, and bulk refreshes do not animate", function()
		local session = H.newSession("los_angeles")
		local cells = dryCells(session, 4)
		session:drawRoad(cells)
		T.gt(countKeys(session.tweens), 0, "new cells animate")
		H.runSession(session, 2)
		T.eq(countKeys(session.tweens), 0, "tweens complete and unregister")
		for _, part in ipairs(session.world.Roads:GetChildren()) do
			T.eq(part.Transparency, 0, part.Name .. " fully opaque")
		end
		session:refreshRoadVisual(Grid.key(cells[2][1], cells[2][2]))
		T.eq(countKeys(session.tweens), 0, "a refresh does not animate")
		session:eraseRoad(Grid.key(cells[4][1], cells[4][2]))
		T.eq(countKeys(session.tweens), 0, "re-rendered neighbours do not animate")
	end)

	T.test("a 300-cell network builds and erases within a generous time budget", function()
		local session = H.newSession("los_angeles")
		session.budget = 400
		session.bridgesLeft = 100
		local cells = dryCells(session, 300, true)
		T.eq(#cells, 300, "enough free cells on the board")
		local start = H.cpuClock()
		session:drawRoad(cells)
		T.eq(countKeys(session.roads), 300)
		session:eraseRoads(keysOf(cells))
		local elapsed = H.cpuClock() - start
		T.lt(elapsed, 10, "build + erase of 300 cells took " .. elapsed .. " s")
		T.eq(roadPartCount(session), 0)
	end)

	-- Générateur déterministe : le test ne dépend pas du hasard global.
	local function lcg(seed)
		local state = seed
		return function(n)
			state = (state * 1103515245 + 12345) % 2147483648
			return state % n + 1
		end
	end

	T.test("300 seeded random builds, erases, roundabouts and new buildings stay consistent", function()
		local session = H.newSession("los_angeles")
		session.budget = 400
		session.roundaboutsLeft = 50
		local random = lcg(2024)
		local size = session.size
		for step = 1, 300 do
			local choice = random(10)
			if choice <= 5 then
				local cells = {}
				local x, y = random(size) - 1, random(size) - 1
				for _ = 1, random(4) do
					cells[#cells + 1] = { x, y }
					if random(2) == 1 then
						x = math.clamp(x + random(3) - 2, 0, size - 1)
					else
						y = math.clamp(y + random(3) - 2, 0, size - 1)
					end
				end
				session.budget = math.max(session.budget, 20)
				session:drawRoad(cells)
			elseif choice <= 8 then
				local keys = {}
				for key in pairs(session.roads) do
					if random(5) == 1 then
						keys[#keys + 1] = key
					end
				end
				session:eraseRoads(keys)
			elseif choice == 9 then
				for key in pairs(session.roads) do
					local x, y = Grid.parse(key)
					session:placeRoundabout(x, y)
					break
				end
			else
				H.runSession(session, 3)
			end
			if step % 30 == 0 then
				checkConsistent(session, "step " .. step)
			end
		end
		checkConsistent(session, "final")
		T.gt(session.stats.roadsBuilt, 0, "the run really built roads")
		T.gt(session.stats.roadsErased, 0, "and erased some")
	end)

	T.test("a roundabout draws three parts, is removed with its road, and gives its piece back", function()
		local session = H.newSession("los_angeles")
		local cells = dryCells(session, 3)
		session:drawRoad(cells)
		local key = Grid.key(cells[2][1], cells[2][2])
		session.roundaboutsLeft = 2
		local left = session.roundaboutsLeft
		session:placeRoundabout(cells[2][1], cells[2][2])
		local model = session.roundaboutParts[key]
		T.ok(model, "the roundabout is registered")
		T.eq(#model:GetChildren(), 3, "edge ring, body ring and island")
		T.eq(session.roundaboutsLeft, left - 1)
		local Config = H.load("Config")
		local colors = {}
		for _, part in ipairs(model:GetChildren()) do
			colors[part.Name] = part.Color
		end
		T.eq(colors.RoundaboutBody, Config.Colors.Road, "same anthracite as the roads")
		T.eq(colors.RoundaboutEdge, Config.Colors.RoadEdge, "same white edge as the roads")
		session:eraseRoad(key)
		T.eq(session.roundaboutParts[key], nil)
		T.eq(session.roundaboutsLeft, left, "the roundabout piece is given back")
		T.eq(#model:GetChildren(), 0, "its parts are destroyed")
	end)

	T.test("destroy leaves zero road parts and zero tweens", function()
		local session = H.newSession("los_angeles")
		session.budget = 400
		session:drawRoad(dryCells(session, 30))
		local roads = session.world.Roads
		T.gt(countKeys(session.tweens), 0, "tweens running")
		session:destroy()
		T.eq(countKeys(session.tweens), 0, "no tween survives")
		T.eq(countKeys(session.roadParts), 0)
		T.eq(H.count(roads, "BasePart"), 0, "the road folder holds no part")
		T.noThrow(function()
			session:update(0.1)
			session:flushRoadRender()
		end)
	end)

	T.test("restarting a session clears the road render state", function()
		local session = H.newSession("los_angeles")
		session.budget = 400
		session:drawRoad(dryCells(session, 30))
		session:start()
		T.eq(countKeys(session.roadParts), 0)
		T.eq(roadPartCount(session), 0)
		T.eq(next(session.roadDirty), nil)
		session:drawRoad(dryCells(session, 5))
		checkConsistent(session, "after restart")
	end)
end
