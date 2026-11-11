return function(T, H)
	-- Vérifie que la géographie d'une carte (formes) est la seule source de
	-- vérité : l'eau jouable, le rendu et l'aperçu doivent concorder.

	local function load()
		return H.load("Maps"), H.load("Config")
	end

	-- Réimplémentation indépendante, volontairement séparée de Maps.luau :
	-- le test ne doit pas partager le code qu'il vérifie.
	local function inside(shape, nx, ny)
		if shape.type == "ellipse" or shape.type == "circle" then
			local rx = shape.rx or shape.r
			local ry = shape.ry or shape.r
			local a = math.rad(shape.rotation or 0)
			local dx = nx - shape.x
			local dy = ny - shape.y
			local u = dx * math.cos(a) + dy * math.sin(a)
			local v = -dx * math.sin(a) + dy * math.cos(a)
			return (u / rx) ^ 2 + (v / ry) ^ 2 <= 1
		end
		if shape.type == "bar" then
			local dx = shape.x2 - shape.x1
			local dy = shape.y2 - shape.y1
			local raw = ((nx - shape.x1) * dx + (ny - shape.y1) * dy) / (dx * dx + dy * dy)
			if shape.flatStart and raw < 0 then
				return false
			end
			local t = math.clamp(raw, 0, 1)
			local px = shape.x1 + dx * t
			local py = shape.y1 + dy * t
			local r = shape.thickness * 0.5
			return (nx - px) ^ 2 + (ny - py) ^ 2 <= r * r
		end
		if shape.type == "rect" then
			return nx >= shape.x and nx <= shape.x + shape.w and ny >= shape.y and ny <= shape.y + shape.h
		end
		return false
	end

	local function anyInside(shapes, nx, ny)
		for _, shape in ipairs(shapes) do
			if inside(shape, nx, ny) then
				return true
			end
		end
		return false
	end

	-- Règle documentée dans Maps.luau : centre de cellule, formes d'eau moins
	-- les formes sèches.
	local function expectedWater(map, x, y, n)
		local nx, ny = (x + 0.5) / n, (y + 0.5) / n
		return anyInside(map.waterShapes, nx, ny) and not anyInside(map.dryShapes, nx, ny)
	end

	-- Ponts : deux cellules de terre sont reliées si une ligne droite ne
	-- franchit qu'au plus deux cellules d'eau (rivière de moins de 3 cases).
	local function landRegions(Maps, map, n)
		local parent = {}
		local function find(k)
			while parent[k] ~= k do
				parent[k] = parent[parent[k]]
				k = parent[k]
			end
			return k
		end
		local function union(a, b)
			parent[find(a)] = find(b)
		end
		local function key(x, y)
			return y * n + x
		end
		for y = 0, n - 1 do
			for x = 0, n - 1 do
				if not Maps.isWater(map, x, y) then
					parent[key(x, y)] = key(x, y)
				end
			end
		end
		for y = 0, n - 1 do
			for x = 0, n - 1 do
				if not Maps.isWater(map, x, y) then
					for _, d in ipairs({ { 1, 0 }, { 0, 1 } }) do
						for step = 1, 3 do
							local nx, ny = x + d[1] * step, y + d[2] * step
							if nx >= n or ny >= n then
								break
							end
							if not Maps.isWater(map, nx, ny) then
								union(key(x, y), key(nx, ny))
								break
							end
						end
					end
				end
			end
		end
		local roots = {}
		local count = 0
		for k in pairs(parent) do
			local root = find(k)
			if not roots[root] then
				roots[root] = true
				count += 1
			end
		end
		return count
	end

	local function sameColor(a, b)
		return a.R == b.R and a.G == b.G and a.B == b.B
	end

	local function saturation(c)
		local hi = math.max(c.R, c.G, c.B)
		local lo = math.min(c.R, c.G, c.B)
		if hi <= 0 then
			return 0
		end
		return (hi - lo) / hi
	end

	T.test("every map has its required fields and no side labels", function()
		local Maps = load()
		for _, map in ipairs(Maps.all()) do
			T.ne(map.name, "", map.id)
			T.ne(map.description, "", map.id)
			T.ne(map.mode, nil, map.id .. " mode")
			for _, key in ipairs({ "header", "accent", "land", "water", "waterEdge", "waterDeep", "grass" }) do
				T.isType(map[key], "Color3", map.id .. "." .. key)
			end
			T.eq(map.labels, nil, map.id .. ": the side labels were removed (brief part 7)")
			T.ge(#map.previewRoads, 1, map.id .. " previewRoads")
			for _, road in ipairs(map.previewRoads) do
				for i = 1, 4 do
					T.ok(type(road[i]) == "number" and road[i] >= 0 and road[i] <= 1, map.id .. " preview road")
				end
			end
			T.ge(#map.waterShapes, 1, map.id .. " needs water")
			T.eq(type(map.grassShapes), "table", map.id .. " grassShapes")
			T.eq(type(map.dryShapes), "table", map.id .. " dryShapes")
		end
	end)

	T.test("water is never a rectangle: rivers and coasts are organic", function()
		local Maps = load()
		for _, map in ipairs(Maps.all()) do
			for i, shape in ipairs(map.waterShapes) do
				T.ne(shape.type, "rect", map.id .. " water shape " .. i .. " is a rectangle")
			end
		end
	end)

	T.test("shapes stay in a sane normalised range", function()
		local Maps = load()
		local function inRange(v)
			return type(v) == "number" and v == v and v > -0.25 and v < 1.25
		end
		for _, map in ipairs(Maps.all()) do
			for _, list in ipairs({ map.waterShapes, map.grassShapes, map.dryShapes }) do
				for i, shape in ipairs(list) do
					local where = map.id .. " shape " .. i
					if shape.type == "bar" then
						T.ok(inRange(shape.x1) and inRange(shape.y1) and inRange(shape.x2) and inRange(shape.y2), where)
						T.ok(shape.thickness > 0 and shape.thickness <= 0.5, where .. " thickness")
					else
						T.ok(inRange(shape.x) and inRange(shape.y), where)
						local rx = shape.rx or shape.r
						T.ok(rx > 0 and rx <= 0.5, where .. " radius")
						if shape.ry then
							T.ok(shape.ry > 0 and shape.ry <= 0.5, where .. " ry")
						end
					end
				end
			end
		end
	end)

	T.test("every water and park shape covers at least one cell centre", function()
		-- Une forme plus petite que la grille disparaît : elle ne bloque pas
		-- la construction alors qu'elle se dessine.
		local Maps, Config = load()
		local n = Config.Grid.Size
		for _, map in ipairs(Maps.all()) do
			for _, list in ipairs({ map.waterShapes, map.grassShapes }) do
				for i, shape in ipairs(list) do
					local covered = 0
					for x = 0, n - 1 do
						for y = 0, n - 1 do
							if inside(shape, (x + 0.5) / n, (y + 0.5) / n) then
								covered += 1
							end
						end
					end
					T.ge(covered, 1, map.id .. " shape " .. i .. " covers no cell")
				end
			end
		end
	end)

	T.test("isWater matches the shapes on every cell", function()
		local Maps, Config = load()
		local n = Config.Grid.Size
		for _, map in ipairs(Maps.all()) do
			for x = 0, n - 1 do
				for y = 0, n - 1 do
					local where = map.id .. " cell " .. x .. ":" .. y
					T.eq(Maps.isWater(map, x, y), expectedWater(map, x, y, n), where)
					T.eq(Maps.isWaterAt(map, (x + 0.5) / n, (y + 0.5) / n), expectedWater(map, x, y, n), where .. " (isWaterAt)")
					T.eq(Maps.isGrass(map, x, y), anyInside(map.grassShapes, (x + 0.5) / n, (y + 0.5) / n), where .. " grass")
				end
			end
		end
	end)

	T.test("dry shapes are land even where a water shape covers them", function()
		local Maps, Config = load()
		local n = Config.Grid.Size
		for _, map in ipairs(Maps.all()) do
			-- Le test doit réellement exercer la priorité : au moins une case
			-- sèche tombe sous une forme d'eau.
			local covered = 0
			for x = 0, n - 1 do
				for y = 0, n - 1 do
					local nx, ny = (x + 0.5) / n, (y + 0.5) / n
					if anyInside(map.dryShapes, nx, ny) then
						T.falsy(Maps.isWater(map, x, y), map.id .. " dry cell " .. x .. ":" .. y)
						if anyInside(map.waterShapes, nx, ny) then
							covered += 1
						end
					end
				end
			end
			if #map.dryShapes > 0 then
				T.gt(covered, 0, map.id .. ": dry shapes never overlap water, the rule is untested")
			end
		end
	end)

	T.test("a flat-start bar stops square: no round cap beyond its start", function()
		-- Le bout x1 d'une presqu'île est coupé net, au rendu 3D comme dans
		-- l'aperçu : la règle de construction doit répondre pareil.
		local Maps = load()
		local water = { type = "bar", x1 = 0.5, y1 = 0.5, x2 = 0.5, y2 = 0.9, thickness = 0.2 }
		local roundDry = { type = "bar", x1 = 0.5, y1 = 0.5, x2 = 0.5, y2 = 0.9, thickness = 0.2 }
		local flatDry = { type = "bar", x1 = 0.5, y1 = 0.5, x2 = 0.5, y2 = 0.9, thickness = 0.2, flatStart = true }
		local withRound = { waterShapes = { water }, dryShapes = { roundDry }, grassShapes = {} }
		local withFlat = { waterShapes = { water }, dryShapes = { flatDry }, grassShapes = {} }
		-- Point juste avant x1, dans le rayon du capuchon rond.
		T.eq(Maps.isWaterAt(withRound, 0.5, 0.45), false, "round start dries the cap")
		T.eq(Maps.isWaterAt(withFlat, 0.5, 0.45), true, "flat start leaves the water beyond it")
		T.eq(Maps.isWaterAt(withFlat, 0.5, 0.6), false, "the dry bar itself is land")
	end)

	T.test("isWater answers for cells outside the grid too", function()
		local Maps, Config = load()
		local n = Config.Grid.Size
		for _, map in ipairs(Maps.all()) do
			T.eq(type(Maps.isWater(map, -1, 0)), "boolean")
			T.eq(Maps.isWater(map, -1, 0), Maps.isWaterAt(map, -0.5 / n, 0.5 / n))
			T.eq(Maps.isWater(map, n, n), Maps.isWaterAt(map, (n + 0.5) / n, (n + 0.5) / n))
		end
	end)

	T.test("the start area (centre of the map) is land", function()
		local Maps, Config = load()
		local n = Config.Grid.Size
		local lo = math.floor(n / 2) - 2
		local hi = math.floor(n / 2) + 1
		for _, map in ipairs(Maps.all()) do
			for x = lo, hi do
				for y = lo, hi do
					T.falsy(Maps.isWater(map, x, y), map.id .. " centre cell " .. x .. ":" .. y)
				end
			end
		end
	end)

	T.test("each map keeps at least 65% land and some water", function()
		local Maps, Config = load()
		local n = Config.Grid.Size
		for _, map in ipairs(Maps.all()) do
			local land, water = 0, 0
			for x = 0, n - 1 do
				for y = 0, n - 1 do
					if Maps.isWater(map, x, y) then
						water += 1
					else
						land += 1
					end
				end
			end
			T.ge(land / (n * n), 0.65, map.id .. ": too much water")
			T.gt(water, 0, map.id .. ": no water at all")
		end
	end)

	T.test("land is one region, or linked by bridges over rivers narrower than 3 cells", function()
		local Maps, Config = load()
		local n = Config.Grid.Size
		for _, map in ipairs(Maps.all()) do
			T.eq(landRegions(Maps, map, n), 1, map.id .. ": land is cut in several regions")
		end
	end)

	T.test("parks never touch water", function()
		local Maps, Config = load()
		local n = Config.Grid.Size
		for _, map in ipairs(Maps.all()) do
			for x = 0, n - 1 do
				for y = 0, n - 1 do
					if Maps.isGrass(map, x, y) then
						local where = map.id .. " park cell " .. x .. ":" .. y
						T.falsy(Maps.isWater(map, x, y), where .. " is water")
						for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
							T.falsy(Maps.isWater(map, x + d[1], y + d[2]), where .. " touches water")
						end
					end
				end
			end
		end
	end)

	T.test("terrain colours are the shared Config palette, light and desaturated", function()
		local Maps, Config = load()
		local C = Config.Colors
		for _, map in ipairs(Maps.all()) do
			T.ok(sameColor(map.land, C.Land), map.id .. " land is the shared sol")
			T.ok(sameColor(map.water, C.Water), map.id .. " water is the shared eau")
			T.ok(sameColor(map.grass, C.Park), map.id .. " grass is the shared parc")
			for _, key in ipairs({ "land", "water", "waterEdge", "waterDeep", "grass" }) do
				local c = map[key]
				T.le(saturation(c), 0.35, map.id .. "." .. key .. " is too saturated")
				T.ge(math.max(c.R, c.G, c.B), 0.6, map.id .. "." .. key .. " is too dark")
			end
		end
	end)
end
