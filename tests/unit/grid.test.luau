return function(T, H)
	local function Grid()
		return H.load("Grid")
	end

	T.test("key and parse round-trip", function()
		local g = Grid()
		for _, c in ipairs({ { 0, 0 }, { 5, 12 }, { 17, 17 }, { -3, 4 } }) do
			local x, y = g.parse(g.key(c[1], c[2]))
			T.eq(x, c[1])
			T.eq(y, c[2])
		end
	end)

	T.test("parse rejects malformed keys", function()
		local g = Grid()
		for _, bad in ipairs({ "", "1", "1:", ":2", "a:b", "1:2:3", "1.5:2" }) do
			T.eq(g.parse(bad), nil, "key " .. bad)
		end
		T.eq(g.parse(nil), nil)
		T.eq(g.parse(12), nil)
	end)

	T.test("inBounds follows Config.Grid.Size", function()
		local g, Config = Grid(), H.load("Config")
		local n = Config.Grid.Size
		T.ok(g.inBounds(0, 0))
		T.ok(g.inBounds(n - 1, n - 1))
		T.falsy(g.inBounds(-1, 0))
		T.falsy(g.inBounds(0, -1))
		T.falsy(g.inBounds(n, 0))
		T.falsy(g.inBounds(0, n))
	end)

	T.test("center and cellFromWorld are inverse", function()
		local g, Config = Grid(), H.load("Config")
		local origin = Vector3.new(700, 0, 0)
		for _, c in ipairs({ { 0, 0 }, { 3, 9 }, { Config.Grid.Size - 1, Config.Grid.Size - 1 } }) do
			local p = g.center(origin, c[1], c[2], 1.5)
			T.near(p.Y, 1.5, 1e-9)
			local x, y = g.cellFromWorld(origin, p)
			T.eq(x, c[1])
			T.eq(y, c[2])
		end
	end)

	T.test("center is the middle of the tile", function()
		local g, Config = Grid(), H.load("Config")
		local tile = Config.Grid.TileSize
		local p = g.center(Vector3.zero, 2, 3)
		T.near(p.X, 2.5 * tile, 1e-9)
		T.near(p.Z, 3.5 * tile, 1e-9)
	end)

	T.test("cellFromWorld handles tile edges consistently", function()
		local g, Config = Grid(), H.load("Config")
		local tile = Config.Grid.TileSize
		local x, y = g.cellFromWorld(Vector3.zero, Vector3.new(tile * 2 - 0.001, 0, tile * 2 + 0.001))
		T.eq(x, 1)
		T.eq(y, 2)
	end)

	T.test("neighbors are the 4 orthogonal cells", function()
		local list = Grid().neighbors(5, 5)
		T.eq(#list, 4)
		local seen = {}
		for _, n in ipairs(list) do
			T.eq(math.abs(n[1] - 5) + math.abs(n[2] - 5), 1)
			seen[n[1] .. ":" .. n[2]] = true
		end
		T.eq(#list, 4)
		local count = 0
		for _ in pairs(seen) do
			count += 1
		end
		T.eq(count, 4)
	end)

	T.test("neighbors8 adds the 4 diagonals", function()
		local list = Grid().neighbors8(5, 5)
		T.eq(#list, 8)
		local diagonals = 0
		for _, n in ipairs(list) do
			local d = math.max(math.abs(n[1] - 5), math.abs(n[2] - 5))
			T.eq(d, 1)
			if n[1] ~= 5 and n[2] ~= 5 then
				diagonals += 1
			end
		end
		T.eq(diagonals, 4)
	end)

	T.test("distance is Manhattan", function()
		T.eq(Grid().distance({ x = 1, y = 1 }, { x = 4, y = 5 }), 7)
		T.eq(Grid().distance({ x = 2, y = 2 }, { x = 2, y = 2 }), 0)
	end)
end
