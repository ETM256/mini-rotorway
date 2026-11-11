return function(T, H)
	-- Empreinte réelle des routes : toutes les Parts sous world.Roads sont
	-- rastérisées (boîtes et cylindres) et comparées à une règle indépendante de
	-- RoadGeometry (centre carré + bras), sur des réseaux de toutes formes.

	local Grid = H.load("Grid")
	local Maps = H.load("Maps")
	local Config = H.load("Config")
	local RoadConfig = H.load("RoadConfig")

	local ROAD_HALF = Config.Dimensions.Road.Width * 0.5
	local EDGE_HALF = Config.Dimensions.Road.Edge * 0.5
	local LAYERS = RoadConfig.Layers
	local STEP = 0.05
	local SLACK = 0.002

	local BODY = { RoadBody = true, RoadBridge = true }
	local ANY = { RoadBody = true, RoadBridge = true, RoadEdge = true, RoadBridgeEdge = true }

	local DIRS = {
		N = { 0, -1 },
		E = { 1, 0 },
		S = { 0, 1 },
		W = { -1, 0 },
	}

	-- Rectangle libre de w x h cases sèches, sans bâtiment, avec une marge d'une
	-- case libre de bâtiments tout autour.
	local function freeArea(session, w, h)
		local function dry(x, y)
			return Grid.inBounds(x, y)
				and not session.buildings[Grid.key(x, y)]
				and not Maps.isWater(session.map, x, y)
		end
		for oy = 1, session.size - h - 1 do
			for ox = 1, session.size - w - 1 do
				local ok = true
				for y = oy - 1, oy + h do
					for x = ox - 1, ox + w do
						if not dry(x, y) then
							ok = false
						end
					end
				end
				if ok then
					return ox, oy
				end
			end
		end
		return nil
	end

	local function newNetworkSession(cells)
		local w, h = 0, 0
		for _, cell in ipairs(cells) do
			w, h = math.max(w, cell[1] + 1), math.max(h, cell[2] + 1)
		end
		local session, ox, oy
		for _, mapId in ipairs({ "los_angeles", "tokyo", "beijing", "dubai", "london", "dar_es_salaam" }) do
			session = H.newSession(mapId)
			session.budget = 400
			ox, oy = freeArea(session, w, h)
			if ox then
				break
			end
		end
		T.ok(ox, "a free dry area of " .. w .. "x" .. h)
		local absolute = {}
		for _, cell in ipairs(cells) do
			absolute[#absolute + 1] = { cell[1] + ox, cell[2] + oy }
		end
		session:drawRoad(absolute)
		H.runSession(session, 1)
		return session, ox, oy, w, h
	end

	-- Parts de route sous forme de données pures.
	local function snapshot(session)
		local list = {}
		for _, part in ipairs(session.world.Roads:GetChildren()) do
			if part:IsA("BasePart") then
				local position = part.CFrame.Position
				local cylinder = part.Shape == Enum.PartType.Cylinder
				list[#list + 1] = {
					name = part.Name,
					x = position.X,
					z = position.Z,
					cylinder = cylinder,
					hx = (cylinder and part.Size.Y or part.Size.X) * 0.5,
					hz = (cylinder and part.Size.Z or part.Size.Z) * 0.5,
					top = position.Y + (cylinder and part.Size.X or part.Size.Y) * 0.5,
					bottom = position.Y - (cylinder and part.Size.X or part.Size.Y) * 0.5,
				}
			end
		end
		return list
	end

	local function covers(shape, wx, wz)
		if shape.cylinder then
			local dx, dz = wx - shape.x, wz - shape.z
			return dx * dx + dz * dz <= shape.hx * shape.hx
		end
		return math.abs(wx - shape.x) <= shape.hx and math.abs(wz - shape.z) <= shape.hz
	end

	local function coveredIn(session, shapes, names, cx, cy, u, v)
		local wx = session.origin.X + (cx + u) * session.tile
		local wz = session.origin.Z + (cy + v) * session.tile
		for _, shape in ipairs(shapes) do
			if names[shape.name] and covers(shape, wx, wz) then
				return true
			end
		end
		return false
	end

	-- Bras attendus d'une case : routes voisines et bâtiments voisins (raccords).
	local function armsOf(session, x, y)
		local arms = {}
		for name, d in pairs(DIRS) do
			local key = Grid.key(x + d[1], y + d[2])
			if session.roads[key] or session.buildings[key] then
				arms[name] = true
			end
		end
		return arms
	end

	-- Règle indépendante : le point (u, v) d'une case est-il dans le couloir
	-- (centre carré + bras) de demi-largeur `half` ?
	local function inCorridor(session, x, y, u, v, half)
		if not session.roads[Grid.key(x, y)] then
			return false
		end
		local arms = armsOf(session, x, y)
		local du, dv = math.abs(u - 0.5), math.abs(v - 0.5)
		if du <= half + SLACK and dv <= half + SLACK then
			return true
		end
		if arms.N and v <= 0.5 and du <= half + SLACK then
			return true
		end
		if arms.S and v >= 0.5 and du <= half + SLACK then
			return true
		end
		if arms.W and u <= 0.5 and dv <= half + SLACK then
			return true
		end
		if arms.E and u >= 0.5 and dv <= half + SLACK then
			return true
		end
		return false
	end

	local function eachSample(ox, oy, w, h, fn)
		local count = math.floor(1 / STEP)
		for cy = oy - 1, oy + h do
			for cx = ox - 1, ox + w do
				for i = 0, count - 1 do
					for j = 0, count - 1 do
						fn(cx, cy, STEP * 0.25 + i * STEP, STEP * 0.25 + j * STEP)
					end
				end
			end
		end
	end

	-- Largeur couverte, en fraction de case, perpendiculairement à un bras, à
	-- 0,4 case du centre : au-delà de la demi-largeur des bras qui se croisent,
	-- donc seule la largeur de ce bras est mesurée.
	local function armWidth(session, shapes, names, x, y, name)
		local d = DIRS[name]
		local covered = 0
		local steps = 400
		for i = 0, steps - 1 do
			local t = -0.5 + (i + 0.5) / steps
			local u = 0.5 + d[1] * 0.4 + (d[1] == 0 and t or 0)
			local v = 0.5 + d[2] * 0.4 + (d[2] == 0 and t or 0)
			if coveredIn(session, shapes, names, x, y, u, v) then
				covered += 1
			end
		end
		return covered / steps
	end

	-- Vérifie un réseau entier : fuites, couverture des axes, largeurs, bâtiments.
	local function checkNetwork(session, ox, oy, w, h, label)
		local shapes = snapshot(session)
		T.gt(#shapes, 0, label .. ": the network has road parts")

		-- Aucune fuite : le corps reste dans le couloir de route, le liseré dans
		-- le couloir un peu plus large ; rien dans les cases vides ni sous un
		-- bâtiment.
		local leaks = 0
		eachSample(ox, oy, w, h, function(cx, cy, u, v)
			if coveredIn(session, shapes, BODY, cx, cy, u, v) and not inCorridor(session, cx, cy, u, v, ROAD_HALF) then
				leaks += 1
			end
			if coveredIn(session, shapes, ANY, cx, cy, u, v) and not inCorridor(session, cx, cy, u, v, EDGE_HALF) then
				leaks += 1
			end
		end)
		T.eq(leaks, 0, label .. ": road surface leaks outside the corridor")

		for key in pairs(session.roads) do
			local x, y = Grid.parse(key)
			local arms = armsOf(session, x, y)
			T.ok(coveredIn(session, shapes, BODY, x, y, 0.5, 0.5), label .. ": centre of " .. key .. " uncovered")
			for name, d in pairs(DIRS) do
				if arms[name] then
					-- La ligne médiane du bras est couverte du centre jusqu'au bord.
					for k = 0, 9 do
						local t = k * 0.05
						T.ok(
							coveredIn(session, shapes, BODY, x, y, 0.5 + d[1] * t, 0.5 + d[2] * t),
							label .. ": arm " .. name .. " of " .. key .. " has a hole at " .. t
						)
					end
					T.ok(
						coveredIn(session, shapes, BODY, x, y, 0.5 + d[1] * 0.499, 0.5 + d[2] * 0.499),
						label .. ": arm " .. name .. " of " .. key .. " stops short of the border"
					)
					-- Même largeur partout : droite, virage, T, croix, raccord.
					T.near(armWidth(session, shapes, BODY, x, y, name), ROAD_HALF * 2, 0.01, label .. ": body width at " .. key .. name)
					T.near(armWidth(session, shapes, ANY, x, y, name), EDGE_HALF * 2, 0.01, label .. ": edge width at " .. key .. name)
				end
			end
		end
		return shapes
	end

	local function line(x0, y0, x1, y1)
		local cells = {}
		local dx, dy = (x1 > x0) and 1 or ((x1 < x0) and -1 or 0), (y1 > y0) and 1 or ((y1 < y0) and -1 or 0)
		local x, y = x0, y0
		while true do
			cells[#cells + 1] = { x, y }
			if x == x1 and y == y1 then
				return cells
			end
			x, y = x + dx, y + dy
		end
	end

	local function join(...)
		local all = {}
		for _, part in ipairs({ ... }) do
			for _, cell in ipairs(part) do
				all[#all + 1] = cell
			end
		end
		return all
	end

	local NETWORKS = {
		straight = line(0, 1, 4, 1),
		corner = join(line(0, 0, 2, 0), line(2, 1, 2, 2)),
		tee = join(line(0, 0, 2, 0), line(1, 1, 1, 2)),
		cross = join(line(0, 2, 4, 2), line(2, 0, 2, 1), line(2, 3, 2, 4)),
		["dead ends and isolated block"] = join(line(0, 0, 1, 0), { { 4, 4 } }),
		["2x2 block with a tail"] = { { 1, 1 }, { 2, 1 }, { 1, 2 }, { 2, 2 }, { 3, 2 }, { 4, 2 } },
		ring = join(line(1, 1, 3, 1), line(3, 2, 3, 3), line(2, 3, 1, 3), { { 1, 2 } }, line(0, 2, 0, 2)),
		staircase = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 }, { 2, 2 }, { 3, 2 }, { 3, 3 } },
	}

	local ORDER = {}
	for name in pairs(NETWORKS) do
		ORDER[#ORDER + 1] = name
	end
	table.sort(ORDER)

	for _, name in ipairs(ORDER) do
		T.test("road footprint: " .. name .. " (width, coverage, no leak)", function()
			local session, ox, oy, w, h = newNetworkSession(NETWORKS[name])
			checkNetwork(session, ox, oy, w, h, name)
		end)
	end

	T.test("road footprint: the outer corner of a turn is rounded, the inner one stays covered", function()
		local session, ox, oy = newNetworkSession(join(line(0, 0, 2, 0), line(2, 1, 2, 2)))
		local shapes = snapshot(session)
		-- Cellule (2,0) : bras W et S. Coin extérieur = NE.
		local cx, cy = ox + 2, oy
		local low, high = 0.5 - ROAD_HALF, 0.5 + ROAD_HALF
		T.falsy(coveredIn(session, shapes, ANY, cx, cy, high - 0.003, low + 0.003), "outer corner point is covered")
		-- Le centre de l'arrondi est à (half - r) du centre de la case, vers le coin.
		local radius = RoadConfig.Visual.CornerRadius * ROAD_HALF * 2
		local round = (ROAD_HALF - radius) + radius * 0.9 * 0.7071
		T.ok(coveredIn(session, shapes, BODY, cx, cy, 0.5 + round, 0.5 - round), "the rounded corner fills inside its arc")
		-- Coin intérieur (SW) couvert par les deux bras.
		T.ok(coveredIn(session, shapes, BODY, cx, cy, low + 0.003, high - 0.003), "inner corner is covered")
	end)

	T.test("road footprint: a dead end is capped by a round end and never pokes into the next cell", function()
		local session, ox, oy, w, h = newNetworkSession(line(1, 1, 3, 1))
		local shapes = checkNetwork(session, ox, oy, w, h, "dead ends")
		local cx, cy = ox + 3, oy + 1
		-- Bout est de la route : le centre est couvert, la case suivante est vide.
		T.ok(coveredIn(session, shapes, BODY, cx, cy, 0.5, 0.5), "end cell centre")
		T.falsy(coveredIn(session, shapes, ANY, cx, cy, 0.5 + EDGE_HALF + 0.01, 0.5), "end cell poking past the cap")
		T.falsy(coveredIn(session, shapes, ANY, cx + 1, cy, 0.05, 0.5), "next cell is empty")
		-- Le bout est arrondi : le coin du carré central n'est pas peint.
		T.falsy(coveredIn(session, shapes, ANY, cx, cy, 0.5 + ROAD_HALF - 0.003, 0.5 - ROAD_HALF + 0.003), "square end corner")
	end)

	T.test("road footprint: layers use distinct heights, so overlapping layers never z-fight", function()
		local session, _, _, _, _ = newNetworkSession(NETWORKS.cross)
		local shapes = snapshot(session)
		local topOf = {}
		for _, shape in ipairs(shapes) do
			local known = topOf[shape.name]
			if known then
				T.near(shape.top, known, 1e-6, shape.name .. ": one height per layer")
			end
			topOf[shape.name] = shape.top
		end
		T.near(topOf.RoadEdge, LAYERS.Edge.Top, 1e-6)
		T.near(topOf.RoadBody, LAYERS.Body.Top, 1e-6)
		T.gt(topOf.RoadBody, topOf.RoadEdge, "the edge sits under the surface")

		-- Aucune paire de couches différentes à la même hauteur avec une empreinte
		-- commune (échantillonnage des centres et des coins de chaque pièce).
		for i = 1, #shapes do
			for j = i + 1, #shapes do
				local a, b = shapes[i], shapes[j]
				if a.name ~= b.name and math.abs(a.top - b.top) < 0.005 then
					local overlap = covers(a, b.x, b.z) or covers(b, a.x, a.z)
					T.falsy(overlap, a.name .. " and " .. b.name .. " are coplanar and overlap")
				end
			end
		end
	end)

	T.test("road footprint: a bridge has its own colour, height and no body underneath", function()
		local session = H.newSession("los_angeles")
		session.budget = 100
		session.bridgesLeft = 5
		-- Ligne qui traverse de l'eau.
		local found = nil
		for y = 0, session.size - 1 do
			for startX = 0, session.size - 8 do
				local cells, water, free = {}, 0, true
				for i = 0, 7 do
					local x = startX + i
					if session.buildings[Grid.key(x, y)] then
						free = false
					end
					if Maps.isWater(session.map, x, y) then
						water += 1
					end
					cells[#cells + 1] = { x, y }
				end
				if free and water >= 1 and water <= 3 then
					found = cells
					break
				end
			end
			if found then
				break
			end
		end
		T.ok(found, "a free line of eight cells crossing a little water")
		session:drawRoad(found)
		H.runSession(session, 1)
		local bridges = 0
		for key in pairs(session.bridges) do
			bridges += 1
			local names = {}
			for _, part in ipairs(session.roadParts[key]) do
				names[part.Name] = true
				T.ne(part.Name, "RoadBody", "a bridge cell has no road body")
				T.ne(part.Name, "RoadEdge", "a bridge cell has no road edge")
			end
			T.ok(names.RoadBridge and names.RoadBridgeEdge, "bridge cell draws its own surface and edge")
		end
		T.gt(bridges, 0, "the line contains a bridge cell")
		local shapes = snapshot(session)
		for _, shape in ipairs(shapes) do
			if shape.name == "RoadBridge" then
				T.near(shape.top, LAYERS.Bridge.Top, 1e-6)
			end
		end
		T.gt(LAYERS.Bridge.Top, LAYERS.Body.Top, "the bridge deck is above the road")
	end)

	T.test("road footprint: roads stop at the border of a building, never poke under it", function()
		local session = H.newSession("los_angeles")
		session.budget = 200
		local house, store = H.houseAndStore(session)
		T.ok(house and store, "a house and a store")
		T.ok(H.connect(session, house, store), "the two buildings are connected")
		-- Une route en bordure du bâtiment, parallèle à lui, reçoit aussi un raccord.
		H.runSession(session, 1)
		local shapes = snapshot(session)
		local touching = 0
		for _, building in ipairs(session.buildingList) do
			for i = 0, 19 do
				for j = 0, 19 do
					local u, v = 0.02 + i * 0.048, 0.02 + j * 0.048
					T.falsy(
						coveredIn(session, shapes, ANY, building.x, building.y, u, v),
						"road part inside building cell " .. building.key
					)
				end
			end
			for name, d in pairs(DIRS) do
				local roadKey = Grid.key(building.x + d[1], building.y + d[2])
				if session.roads[roadKey] then
					touching += 1
					-- Côté du bâtiment : la route atteint exactement la frontière.
					local rx, ry = building.x + d[1], building.y + d[2]
					local fromBuilding = DIRS[name == "N" and "S" or name == "S" and "N" or name == "E" and "W" or "E"]
					T.ok(
						coveredIn(session, shapes, BODY, rx, ry, 0.5 + fromBuilding[1] * 0.499, 0.5 + fromBuilding[2] * 0.499),
						"the road reaches the building border at " .. roadKey
					)
				end
			end
		end
		T.gt(touching, 1, "both buildings have a road next to them")
		local ox, oy = 0, 0
		checkNetwork(session, ox, oy, session.size, session.size, "building connection")
	end)

	T.test("road footprint: a house spawning next to a road gives that road its connector without a redraw", function()
		local session = H.newSession("los_angeles")
		session.budget = 400
		local ox, oy = freeArea(session, 5, 3)
		T.ok(ox, "a free area")
		local cells = line(ox, oy + 1, ox + 4, oy + 1)
		session:drawRoad(cells)
		H.runSession(session, 0.5)
		local middle = Grid.key(ox + 2, oy + 1)
		local before = #session.roadParts[middle]
		T.eq(before, 2, "a straight cell has an edge and a body part")
		-- Un bâtiment apparaît contre la route (créé comme le fait Session).
		local house = session:createBuilding("house", ox + 2, oy, 1)
		house.timer = 1e9
		H.runSession(session, 0.2)
		T.gt(#session.roadParts[middle], before, "the road cell grew an arm toward the new building")
		local shapes = snapshot(session)
		T.ok(coveredIn(session, shapes, BODY, ox + 2, oy + 1, 0.5, 0.01), "the arm reaches the building border")
		T.falsy(coveredIn(session, shapes, ANY, ox + 2, oy, 0.5, 0.99), "and does not enter the building cell")
	end)
end
