return function(T, H)
	local function build(cells)
		local roads = {}
		for _, c in ipairs(cells) do
			roads[c[1] .. ":" .. c[2]] = true
		end
		return roads
	end

	local function line(x1, y1, x2, y2)
		local cells = { { x1, y1 } }
		local x, y = x1, y1
		while x ~= x2 do
			x += x2 > x and 1 or -1
			table.insert(cells, { x, y })
		end
		while y ~= y2 do
			y += y2 > y and 1 or -1
			table.insert(cells, { x, y })
		end
		return cells
	end

	T.test("finds the straight path", function()
		local P = H.load("Pathfinding")
		local roads = build(line(0, 0, 5, 0))
		local path = P.find(roads, 18, "0:0", { ["5:0"] = true })
		T.deepEq(path, { "0:0", "1:0", "2:0", "3:0", "4:0", "5:0" })
	end)

	T.test("start == goal returns a single node", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 2, 2 } })
		T.deepEq(P.find(roads, 18, "2:2", { ["2:2"] = true }), { "2:2" })
	end)

	T.test("unreachable goal returns nil", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 0, 0 }, { 1, 0 }, { 5, 5 }, { 6, 5 } })
		T.eq(P.find(roads, 18, "0:0", { ["6:5"] = true }), nil)
	end)

	T.test("invalid start returns nil", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 0, 0 } })
		T.eq(P.find(roads, 18, "9:9", { ["0:0"] = true }), nil)
		T.eq(P.find(roads, 18, nil, { ["0:0"] = true }), nil)
		T.eq(P.find(roads, 18, 5, { ["0:0"] = true }), nil)
	end)

	T.test("empty or malformed goal set returns nil", function()
		local P = H.load("Pathfinding")
		local roads = build(line(0, 0, 3, 0))
		T.eq(P.find(roads, 18, "0:0", {}), nil)
		T.eq(P.find(roads, 18, "0:0", { ["nonsense"] = true }), nil)
	end)

	T.test("chooses the nearest of several goals", function()
		local P = H.load("Pathfinding")
		local roads = build(line(0, 0, 8, 0))
		local path = P.find(roads, 18, "4:0", { ["0:0"] = true, ["6:0"] = true })
		T.eq(path[#path], "6:0")
		T.eq(#path, 3)
	end)

	T.test("orthogonal mode never cuts corners", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 0, 0 }, { 1, 1 }, { 1, 0 }, { 0, 1 } })
		local path = P.find(roads, 18, "0:0", { ["1:1"] = true })
		T.eq(#path, 3)
		local roadsOnlyDiagonal = build({ { 0, 0 }, { 1, 1 } })
		T.eq(P.find(roadsOnlyDiagonal, 18, "0:0", { ["1:1"] = true }), nil)
	end)

	T.test("diagonal mode may cut corners", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 0, 0 }, { 1, 1 } })
		local path = P.find(roads, 18, "0:0", { ["1:1"] = true }, true)
		T.deepEq(path, { "0:0", "1:1" })
	end)

	T.test("path steps are adjacent road cells", function()
		local P = H.load("Pathfinding")
		local cells = {}
		for _, c in ipairs(line(0, 0, 6, 0)) do
			table.insert(cells, c)
		end
		for _, c in ipairs(line(6, 0, 6, 6)) do
			table.insert(cells, c)
		end
		local roads = build(cells)
		local path = P.find(roads, 18, "0:0", { ["6:6"] = true })
		T.eq(#path, 13)
		for i = 2, #path do
			local ax, ay = path[i - 1]:match("(%d+):(%d+)")
			local bx, by = path[i]:match("(%d+):(%d+)")
			T.eq(math.abs(ax - bx) + math.abs(ay - by), 1)
			T.ok(roads[path[i]])
		end
	end)

	T.test("ignores road cells outside the grid size", function()
		local P = H.load("Pathfinding")
		local roads = build(line(0, 0, 6, 0))
		T.eq(P.find(roads, 4, "0:0", { ["6:0"] = true }), nil)
	end)

	T.test("goes around a hole", function()
		local P = H.load("Pathfinding")
		local cells = line(0, 0, 4, 0)
		for _, c in ipairs(line(0, 1, 4, 1)) do
			table.insert(cells, c)
		end
		local roads = build(cells)
		roads["2:0"] = nil
		local path = P.find(roads, 18, "0:0", { ["4:0"] = true })
		T.ok(path)
		for _, key in ipairs(path) do
			T.ne(key, "2:0")
		end
	end)
end
