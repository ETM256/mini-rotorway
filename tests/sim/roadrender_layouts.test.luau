return function(T, H)
	-- Dispositions limites du renderer unique : routes le long du bord du plateau
	-- et route prise entre deux bâtiments.

	local Grid = H.load("Grid")
	local Maps = H.load("Maps")

	local EPSILON = 1e-4

	local function free(session, x, y)
		return Grid.inBounds(x, y) and not session.buildings[Grid.key(x, y)] and not Maps.isWater(session.map, x, y)
	end

	-- Première ligne de `length` cases libres le long d'un bord du plateau.
	local function edgeLine(session, length, vertical)
		local last = session.size - 1
		for fixed = 0, last, math.max(last, 1) do
			for start = 0, session.size - length do
				local cells, ok = {}, true
				for i = 0, length - 1 do
					local x, y = start + i, fixed
					if vertical then
						x, y = fixed, start + i
					end
					if not free(session, x, y) then
						ok = false
						break
					end
					cells[#cells + 1] = { x, y }
				end
				if ok then
					return cells
				end
			end
		end
		return nil
	end

	local function assertInsideBoard(session, label)
		local lowX, lowZ = session.origin.X, session.origin.Z
		local highX, highZ = lowX + session.size * session.tile, lowZ + session.size * session.tile
		for _, part in ipairs(session.world.Roads:GetChildren()) do
			local position = part.CFrame.Position
			local halfX, halfZ = part.Size.X * 0.5, part.Size.Z * 0.5
			if part.Shape == Enum.PartType.Cylinder then
				halfX, halfZ = part.Size.Y * 0.5, part.Size.Z * 0.5
			end
			T.ok(
				position.X - halfX >= lowX - EPSILON and position.X + halfX <= highX + EPSILON
					and position.Z - halfZ >= lowZ - EPSILON and position.Z + halfZ <= highZ + EPSILON,
				label .. ": " .. part.Name .. " leaves the board"
			)
		end
	end

	for _, vertical in ipairs({ false, true }) do
		local label = vertical and "left or right edge" or "top or bottom edge"
		T.test("road layout: a road along the " .. label .. " stays on the board within the part budget", function()
			local session = H.newSession("los_angeles")
			session.budget = 100
			local line = edgeLine(session, 5, vertical)
			T.ok(line, "a free dry line along the board edge")
			session:drawRoad(line)
			H.runSession(session, 1)
			for key in pairs(session.roads) do
				local parts = session.roadParts[key]
				T.ok(parts and #parts >= 1 and #parts <= 8, "cell " .. key .. " has 1 to 8 parts")
			end
			assertInsideBoard(session, label)
			session:destroy()
		end)
	end

	T.test("road layout: a road cell between two buildings keeps a full-width surface and no part inside either", function()
		local session = H.newSession("los_angeles")
		session.budget = 100
		local found = nil
		for y = 1, session.size - 2 do
			for x = 0, session.size - 5 do
				if free(session, x, y - 1) and free(session, x, y + 1) and free(session, x - 1, y) == (x > 0)
					and free(session, x + 1, y) and free(session, x + 2, y) and free(session, x, y)
					and not session.roads[Grid.key(x, y)]
				then
					found = { x, y }
					break
				end
			end
			if found then
				break
			end
		end
		T.ok(found, "a free spot")
		local x, y = found[1], found[2]
		-- Une route horizontale de trois cases ; la case du milieu reçoit une maison
		-- au nord et un magasin au sud.
		session:drawRoad({ { x, y }, { x + 1, y }, { x + 2, y } })
		local north = session:createBuilding("house", x + 1, y - 1, 1)
		local south = session:createBuilding("house", x + 1, y + 1, 2)
		T.ok(north and south, "buildings created on both sides")
		-- Pas de nouvelle demande pendant le test.
		north.timer, south.timer = 1e9, 1e9
		H.runSession(session, 0.5)
		local middle = session.roadParts[Grid.key(x + 1, y)]
		T.ok(middle, "the middle cell is rendered")
		T.eq(#middle, 4, "a cross: two bands for the edge, two for the surface")
		local spanX = 0
		for _, part in ipairs(middle) do
			if part.Name == "RoadBody" then
				spanX = math.max(spanX, part.Size.X)
			end
			-- Les raccords vers les bâtiments s'arrêtent au bord de la case.
			local z = part.CFrame.Position.Z
			T.ok(z - part.Size.Z * 0.5 >= session.origin.Z + y * session.tile - EPSILON, "no part north of the cell")
			T.ok(z + part.Size.Z * 0.5 <= session.origin.Z + (y + 1) * session.tile + EPSILON, "no part south of the cell")
		end
		T.near(spanX, session.tile, 1e-3, "the surface still spans the whole cell width")
		for _, building in ipairs({ north, south }) do
			for _, part in ipairs(session.world.Roads:GetChildren()) do
				local position = part.CFrame.Position
				local cx = session.origin.X + (building.x + 0.5) * session.tile
				local cz = session.origin.Z + (building.y + 0.5) * session.tile
				T.falsy(
					math.abs(position.X - cx) < session.tile * 0.5 - EPSILON
						and math.abs(position.Z - cz) < session.tile * 0.5 - EPSILON,
					"road part centred inside building cell " .. building.key
				)
			end
		end
		session:destroy()
	end)
end
