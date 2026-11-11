-- Clés de case, bornes et conversions monde / case de Grid.
return function(T, H)
	local function Grid()
		return H.load("Grid")
	end

	T.test("key of negative zero is the key of zero", function()
		local g = Grid()
		T.eq(g.key(-0, 0), "0:0")
		T.eq(g.key(0, -0), "0:0")
		T.eq(g.key(-0, -0), g.key(0, 0))
	end)

	T.test("parse of a negative zero gives a plain zero", function()
		local x, y = Grid().parse("-0:-0")
		T.eq(x, 0)
		T.eq(y, 0)
		T.eq(tostring(x), "0")
		T.eq(tostring(y), "0")
	end)

	T.test("key and parse round-trip on the whole small grid", function()
		local g = Grid()
		for x = -2, 20 do
			for y = -2, 20 do
				local px, py = g.parse(g.key(x, y))
				T.eq(px, x)
				T.eq(py, y)
			end
		end
	end)

	T.test("key floors fractional coordinates to their cell", function()
		local g = Grid()
		T.eq(g.key(1.9, 2.2), "1:2")
		T.eq(g.key(-0.5, 0), "-1:0")
		local x, y = g.parse(g.key(1.9, 2.2))
		T.eq(x, 1)
		T.eq(y, 2)
	end)

	T.test("parse rejects fractional, signed-garbage and spaced keys", function()
		local g = Grid()
		for _, bad in ipairs({ "1.0:2", "1:2.5", "--1:2", "1:-", "+1:2", " 1:2", "1:2 ", "1e3:2", "0x1:2" }) do
			T.eq(g.parse(bad), nil, "key " .. bad)
		end
	end)

	T.test("parse accepts only strings", function()
		local g = Grid()
		T.eq(g.parse(nil), nil)
		T.eq(g.parse(12), nil)
		T.eq(g.parse({ "1:2" }), nil)
	end)

	T.test("inRange checks integer cells inside a square grid", function()
		local g = Grid()
		T.ok(g.inRange(0, 0, 4))
		T.ok(g.inRange(3, 3, 4))
		T.falsy(g.inRange(4, 0, 4))
		T.falsy(g.inRange(0, 4, 4))
		T.falsy(g.inRange(-1, 0, 4))
		T.falsy(g.inRange(1.5, 1, 4))
		T.falsy(g.inRange(0 / 0, 1, 4), "NaN is never in range")
		T.falsy(g.inRange(math.huge, 1, 4), "infinity is never in range")
		T.falsy(g.inRange(nil, 1, 4))
	end)

	T.test("inBounds follows Config.Grid.Size and rejects non-cells", function()
		local g, Config = Grid(), H.load("Config")
		local n = Config.Grid.Size
		T.ok(g.inBounds(0, 0))
		T.ok(g.inBounds(n - 1, n - 1))
		T.falsy(g.inBounds(n, 0))
		T.falsy(g.inBounds(0, n))
		T.falsy(g.inBounds(-1, 0))
		T.falsy(g.inBounds(0.5, 0))
		T.falsy(g.inBounds(0 / 0, 0))
		T.falsy(g.inBounds(nil, 0))
	end)

	T.test("cellFromWorld: a point exactly on a tile border belongs to the cell that starts there", function()
		local g, Config = Grid(), H.load("Config")
		local tile = Config.Grid.TileSize
		local origin = Vector3.new(700, 0, -300)
		for cell = 0, 5 do
			local x, y = g.cellFromWorld(origin, Vector3.new(origin.X + cell * tile, 0, origin.Z + cell * tile))
			T.eq(x, cell, "x border " .. cell)
			T.eq(y, cell, "y border " .. cell)
		end
	end)

	T.test("cellFromWorld: float noise just under a border stays in the next cell", function()
		local g, Config = Grid(), H.load("Config")
		local tile = Config.Grid.TileSize
		-- Erreur d'arrondi typique d'un raycast : quelques 1e-12 studs sous la frontière.
		local x, y = g.cellFromWorld(Vector3.zero, Vector3.new(tile * 3 - 1e-12, 0, tile * 3 - 1e-12))
		T.eq(x, 3)
		T.eq(y, 3)
	end)

	T.test("cellFromWorld: a point well inside a tile keeps its cell", function()
		local g, Config = Grid(), H.load("Config")
		local tile = Config.Grid.TileSize
		local x, y = g.cellFromWorld(Vector3.zero, Vector3.new(tile * 3.9, 0, tile * 0.1))
		T.eq(x, 3)
		T.eq(y, 0)
	end)

	T.test("cellFromWorld: points before the origin map to negative cells", function()
		local g, Config = Grid(), H.load("Config")
		local tile = Config.Grid.TileSize
		local x, y = g.cellFromWorld(Vector3.zero, Vector3.new(-tile * 0.5, 0, -tile * 1.5))
		T.eq(x, -1)
		T.eq(y, -2)
	end)

	T.test("center then cellFromWorld gives back every cell of the grid", function()
		local g, Config = Grid(), H.load("Config")
		local origin = Vector3.new(1400, 0, 700)
		local n = Config.Grid.Size
		for x = 0, n - 1 do
			for y = 0, n - 1 do
				local px, py = g.cellFromWorld(origin, g.center(origin, x, y, 0.5))
				T.eq(px, x)
				T.eq(py, y)
			end
		end
	end)

	T.test("neighbours: 4 orthogonal and 8 with diagonals, all distinct", function()
		local g = Grid()
		local function distinct(list)
			local seen, count = {}, 0
			for _, n in ipairs(list) do
				local k = n[1] .. ":" .. n[2]
				if not seen[k] then
					seen[k] = true
					count += 1
				end
			end
			return count
		end
		T.eq(distinct(g.neighbors(0, 0)), 4)
		T.eq(distinct(g.neighbors8(0, 0)), 8)
	end)

	T.test("shared offset constants describe the same neighbourhood as neighbors8", function()
		local g = Grid()
		T.eq(#g.ORTHOGONAL_OFFSETS, 4)
		T.eq(#g.DIAGONAL_OFFSETS, 4)
		local fromConstants = {}
		for _, o in ipairs(g.ORTHOGONAL_OFFSETS) do
			fromConstants[(5 + o[1]) .. ":" .. (5 + o[2])] = true
		end
		for _, o in ipairs(g.DIAGONAL_OFFSETS) do
			fromConstants[(5 + o[1]) .. ":" .. (5 + o[2])] = true
		end
		for _, n in ipairs(g.neighbors8(5, 5)) do
			T.ok(fromConstants[n[1] .. ":" .. n[2]], "neighbour " .. n[1] .. ":" .. n[2])
		end
	end)

	T.test("distance is Manhattan and symmetric", function()
		local g = Grid()
		T.eq(g.distance({ x = 1, y = 1 }, { x = 4, y = 5 }), 7)
		T.eq(g.distance({ x = 4, y = 5 }, { x = 1, y = 1 }), 7)
		T.eq(g.distance({ x = 2, y = 2 }, { x = 2, y = 2 }), 0)
	end)
end
