return function(T, H)
	-- Formes de routes, ponts, budget, remboursements et statistiques.

	local function countKeys(t)
		local n = 0
		for _ in pairs(t) do
			n += 1
		end
		return n
	end

	-- Case constructible au sens du serveur : dans la carte, sans bâtiment ni route.
	local function open(session, x, y)
		local Grid = H.load("Grid")
		return Grid.inBounds(x, y) and not session.buildings[Grid.key(x, y)] and not session.roads[Grid.key(x, y)]
	end

	-- Cherche une origine où chaque décalage de `offsets` est constructible.
	-- Si waterCenter, le premier décalage doit être de l'eau et les autres de la terre.
	local function findSpot(session, offsets, waterCenter)
		local Maps = H.load("Maps")
		for x = 0, session.size - 1 do
			for y = 0, session.size - 1 do
				local ok = true
				for index, d in ipairs(offsets) do
					local cx, cy = x + d[1], y + d[2]
					local wantWater = waterCenter == true and index == 1
					if not open(session, cx, cy) or Maps.isWater(session.map, cx, cy) ~= wantWater then
						ok = false
						break
					end
				end
				if ok then
					return x, y
				end
			end
		end
		return nil
	end

	local function line(x, y, dx, dy, length)
		local cells = {}
		for i = 0, length - 1 do
			table.insert(cells, { x + dx * i, y + dy * i })
		end
		return cells
	end

	T.test("an L-shaped drag makes a corner that is not an intersection", function()
		local session = H.newSession("los_angeles")
		local x, y = findSpot(session, { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 2, 1 }, { 2, 2 } })
		T.ok(x, "free L-shaped area on the map")
		local Grid = H.load("Grid")
		H.drawRoadBetween(session, { x, y }, { x + 2, y + 2 }, { axis = "x" })
		T.eq(countKeys(session.roads), 5)
		local corner = Grid.key(x + 2, y)
		T.ok(session.roads[corner], "corner is a road")
		T.falsy(session.intersections[corner], "a bend has two neighbours, not an intersection")
	end)

	T.test("a T junction is an intersection at its centre, the arm end is not", function()
		local session = H.newSession("los_angeles")
		local x, y = findSpot(session, { { -1, 0 }, { 0, 0 }, { 1, 0 }, { 0, 1 } })
		T.ok(x, "free T-shaped area on the map")
		local Grid = H.load("Grid")
		session:drawRoad({ { x - 1, y }, { x, y }, { x + 1, y } })
		session:drawRoad({ { x, y + 1 } })
		T.ok(session.intersections[Grid.key(x, y)], "centre of the T is an intersection")
		T.falsy(session.intersections[Grid.key(x, y + 1)], "arm end is not an intersection")
	end)

	T.test("a cross is an intersection; removing arms turns it back into a bend, then a line", function()
		local session = H.newSession("los_angeles")
		local x, y = findSpot(session, { { -1, 0 }, { 0, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } })
		T.ok(x, "free cross-shaped area on the map")
		local Grid = H.load("Grid")
		local center = Grid.key(x, y)
		session:drawRoad({ { x - 1, y }, { x, y }, { x + 1, y } })
		session:drawRoad({ { x, y - 1 }, { x, y + 1 } })
		T.ok(session.intersections[center], "four neighbours: cross")
		session:eraseRoad(Grid.key(x, y - 1))
		T.ok(session.intersections[center], "three neighbours: still a T")
		session:eraseRoad(Grid.key(x, y + 1))
		T.falsy(session.intersections[center], "two neighbours: no longer an intersection")
		T.ok(session.roads[center], "the centre itself stays")
	end)

	T.test("a bridge costs a piece and a bridge, and erasing it gives both back", function()
		local session = H.newSession("los_angeles")
		local x, y = findSpot(session, { { 0, 0 }, { -1, 0 }, { 1, 0 } }, true)
		T.ok(x, "water cell with dry land on both sides")
		local Grid = H.load("Grid")
		session.bridgesLeft = 1
		local budget = session.budget
		session:drawRoad({ { x - 1, y }, { x, y }, { x + 1, y } })
		T.eq(countKeys(session.roads), 3)
		T.eq(countKeys(session.bridges), 1)
		T.ok(session.bridges[Grid.key(x, y)], "the water cell is the bridge")
		T.eq(session.bridgesLeft, 0)
		T.eq(session.budget, budget - 3, "two land pieces and one bridge piece")
		T.ok(session:eraseRoad(Grid.key(x, y)))
		T.eq(session.bridgesLeft, 1, "bridge given back")
		T.eq(session.budget, budget - 2, "only the land pieces stay spent")
	end)

	T.test("without a bridge the water cell is refused but the dry cells are still built", function()
		local session = H.newSession("los_angeles")
		local x, y = findSpot(session, { { 0, 0 }, { -1, 0 }, { 1, 0 } }, true)
		T.ok(x, "water cell with dry land on both sides")
		local Grid = H.load("Grid")
		session.bridgesLeft = 0
		local budget = session.budget
		session:drawRoad({ { x - 1, y }, { x, y }, { x + 1, y } })
		T.falsy(session.roads[Grid.key(x, y)], "no road on water without a bridge")
		T.ok(session.roads[Grid.key(x - 1, y)] and session.roads[Grid.key(x + 1, y)], "dry cells built")
		T.eq(session.budget, budget - 2, "only the two dry cells are charged")
		T.eq(H.lastSent("Toast"), "Plus de ponts disponibles", "the player is told why")
	end)

	T.test("budget exhaustion stops the batch cleanly and never goes negative", function()
		local session = H.newSession("los_angeles")
		local x, y = findSpot(session, { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 }, { 4, 0 } })
		T.ok(x, "free run of five cells")
		session.budget = 2
		session:drawRoad(line(x, y, 1, 0, 5))
		T.eq(countKeys(session.roads), 2, "only the two affordable cells are built")
		T.eq(session.budget, 0)
		T.eq(H.lastSent("Toast"), "Plus de routes disponibles")
		local sentBefore = #H.sent("RoadState")
		session:drawRoad(line(x, y + 2, 1, 0, 3))
		T.eq(session.budget, 0, "no construction without budget")
		T.eq(#H.sent("RoadState"), sentBefore, "nothing changed, nothing sent")
	end)

	T.test("erasing refunds exactly the pieces that were spent", function()
		local session = H.newSession("los_angeles")
		local x, y = findSpot(session, { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 } })
		T.ok(x, "free run of four cells")
		local Grid = H.load("Grid")
		local budget = session.budget
		session:drawRoad(line(x, y, 1, 0, 4))
		T.eq(session.budget, budget - 4)
		session:eraseRoads({ Grid.key(x, y), Grid.key(x + 1, y), "junk", 5, Grid.key(x + 9, y) })
		T.eq(session.budget, budget - 2, "two erased, two refunded; junk and absent cells refund nothing")
		T.eq(countKeys(session.roads), 2)
		T.falsy(session:eraseRoad(Grid.key(x, y)), "a cell without road refunds nothing")
		T.eq(session.budget, budget - 2)
	end)

	T.test("erasing a roundabout refunds the roundabout and one road piece", function()
		local session = H.newSession("los_angeles")
		local x, y = findSpot(session, { { 0, 0 }, { 1, 0 }, { 2, 0 } })
		T.ok(x, "free run of three cells")
		local Grid = H.load("Grid")
		session:drawRoad(line(x, y, 1, 0, 3))
		session.roundaboutsLeft = 1
		local budget = session.budget
		session:placeRoundabout(x + 1, y)
		T.eq(session.roundaboutsLeft, 0)
		T.eq(session.budget, budget, "a roundabout uses no road piece")
		T.ok(session:eraseRoad(Grid.key(x + 1, y)))
		T.eq(session.roundaboutsLeft, 1)
		T.eq(session.budget, budget + 1, "exactly one road piece back")
		T.eq(countKeys(session.roundaboutParts), 0)
	end)

	T.test("a roundabout cannot be placed on a bridge nor on a bare cell", function()
		local session = H.newSession("los_angeles")
		local x, y = findSpot(session, { { 0, 0 }, { -1, 0 }, { 1, 0 } }, true)
		T.ok(x, "water cell with dry land on both sides")
		session.bridgesLeft = 1
		session:drawRoad({ { x - 1, y }, { x, y }, { x + 1, y } })
		session.roundaboutsLeft = 2
		session:placeRoundabout(x, y)
		T.eq(session.roundaboutsLeft, 2, "no roundabout on a bridge")
		session:placeRoundabout(x + 5, y + 5)
		T.eq(session.roundaboutsLeft, 2, "no roundabout on a bare cell")
	end)

	T.test("recordStat receives roadsBuilt and roadsErased with the exact counts", function()
		local session = H.newSession("los_angeles")
		local log = {}
		session.recordStat = function(_, name, amount)
			table.insert(log, { name, amount })
		end
		local x, y = findSpot(session, { { 0, 0 }, { 1, 0 }, { 2, 0 } })
		T.ok(x, "free run of three cells")
		local Grid = H.load("Grid")
		session:drawRoad(line(x, y, 1, 0, 3))
		T.eq(#log, 1)
		T.eq(log[1][1], "roadsBuilt")
		T.eq(log[1][2], 3)
		session:eraseRoads({ Grid.key(x, y), Grid.key(x + 2, y) })
		T.eq(#log, 2)
		T.eq(log[2][1], "roadsErased")
		T.eq(log[2][2], 2)
		session:eraseRoads({ "nothing" })
		T.eq(#log, 2, "a refused batch records nothing")
	end)
end
