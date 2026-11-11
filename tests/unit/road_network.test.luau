return function(T, H)
	local function RN()
		return H.load("RoadNetwork")
	end

	local function roadsOf(list)
		local set = {}
		for _, c in ipairs(list) do
			set[c[1] .. ":" .. c[2]] = true
		end
		return set
	end

	T.test("neighbors: 4 orthogonal, 8 with diagonals", function()
		T.eq(#RN().neighbors(3, 3), 4)
		T.eq(#RN().neighbors(3, 3, true), 8)
		for _, n in ipairs(RN().neighbors(3, 3)) do
			T.eq(math.abs(n[1] - 3) + math.abs(n[2] - 3), 1)
		end
	end)

	T.test("isAdjacent", function()
		local rn = RN()
		T.ok(rn.isAdjacent(1, 1, 2, 1))
		T.ok(rn.isAdjacent(1, 1, 1, 0))
		T.falsy(rn.isAdjacent(1, 1, 2, 2))
		T.ok(rn.isAdjacent(1, 1, 2, 2, true))
		T.falsy(rn.isAdjacent(1, 1, 1, 1), "a cell is not adjacent to itself")
		T.falsy(rn.isAdjacent(1, 1, 3, 1))
	end)

	T.test("countRoadNeighbors / isIntersection: T and cross", function()
		local rn = RN()
		local cross = roadsOf({ { 5, 5 }, { 4, 5 }, { 6, 5 }, { 5, 4 }, { 5, 6 } })
		T.eq(rn.countRoadNeighbors(cross, 5, 5), 4)
		T.ok(rn.isIntersection(cross, 5, 5))
		local tee = roadsOf({ { 5, 5 }, { 4, 5 }, { 6, 5 }, { 5, 4 } })
		T.eq(rn.countRoadNeighbors(tee, 5, 5), 3)
		T.ok(rn.isIntersection(tee, 5, 5))
		local corner = roadsOf({ { 5, 5 }, { 4, 5 }, { 5, 4 } })
		T.eq(rn.countRoadNeighbors(corner, 5, 5), 2)
		T.falsy(rn.isIntersection(corner, 5, 5))
		T.eq(rn.countRoadNeighbors(roadsOf({}), 5, 5), 0)
	end)

	T.test("diagonal neighbours only count when requested", function()
		local rn = RN()
		local roads = roadsOf({ { 4, 4 }, { 6, 6 }, { 4, 6 }, { 6, 4 } })
		T.eq(rn.countRoadNeighbors(roads, 5, 5), 0)
		T.eq(rn.countRoadNeighbors(roads, 5, 5, true), 4)
	end)

	T.test("countRoadNeighborsAtKey / isIntersectionKey", function()
		local rn = RN()
		local tee = roadsOf({ { 5, 5 }, { 4, 5 }, { 6, 5 }, { 5, 4 } })
		T.eq(rn.countRoadNeighborsAtKey(tee, "5:5"), 3)
		T.ok(rn.isIntersectionKey(tee, "5:5"))
		T.eq(rn.countRoadNeighborsAtKey(tee, "garbage"), 0)
		T.falsy(rn.isIntersectionKey(tee, "garbage"))
	end)

	T.test("manhattanPath: straight lines exclude the start", function()
		local rn = RN()
		T.deepEq(rn.manhattanPath(0, 0, 3, 0), { { 1, 0 }, { 2, 0 }, { 3, 0 } })
		T.deepEq(rn.manhattanPath(2, 5, 2, 3), { { 2, 4 }, { 2, 3 } })
		T.deepEq(rn.manhattanPath(4, 4, 4, 4), {})
	end)

	T.test("manhattanPath: L shapes follow preferredAxis", function()
		local rn = RN()
		local xFirst = rn.manhattanPath(0, 0, 2, 2, "x")
		T.deepEq(xFirst, { { 1, 0 }, { 2, 0 }, { 2, 1 }, { 2, 2 } })
		local yFirst = rn.manhattanPath(0, 0, 2, 2, "y")
		T.deepEq(yFirst, { { 0, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } })
	end)

	T.test("manhattanPath: every step is orthogonal, no diagonal, reaches the goal", function()
		local rn = RN()
		for _, c in ipairs({ { 0, 0, 7, 3 }, { 9, 9, 1, 2 }, { 3, 8, 3, 1 }, { 0, 5, 6, 5 } }) do
			local path = rn.manhattanPath(c[1], c[2], c[3], c[4])
			T.eq(#path, math.abs(c[3] - c[1]) + math.abs(c[4] - c[2]))
			local px, py = c[1], c[2]
			for _, cell in ipairs(path) do
				T.eq(math.abs(cell[1] - px) + math.abs(cell[2] - py), 1)
				px, py = cell[1], cell[2]
			end
			T.eq(px, c[3])
			T.eq(py, c[4])
		end
	end)

	T.test("manhattanPath: dominant axis goes first when no preference", function()
		local rn = RN()
		local wide = rn.manhattanPath(0, 0, 4, 1)
		T.deepEq(wide[1], { 1, 0 })
		local tall = rn.manhattanPath(0, 0, 1, 4)
		T.deepEq(tall[1], { 0, 1 })
	end)

	T.test("manhattanPath: over the cap is refused, never truncated", function()
		local rn = RN()
		local path, complete = rn.manhattanPath(0, 0, 2000, 2000)
		T.deepEq(path, {})
		T.falsy(complete)
	end)

	T.test("flattenPath: chains segments and removes duplicates", function()
		local rn = RN()
		local flat = rn.flattenPath(0, 0, { { 2, 0 }, { 2, 2 }, { 2, 0 } })
		T.deepEq(flat, { { 1, 0 }, { 2, 0 }, { 2, 1 }, { 2, 2 } })
	end)

	T.test("flattenPath: tolerates junk entries", function()
		local rn = RN()
		T.deepEq(rn.flattenPath(0, 0, nil), {})
		T.deepEq(rn.flattenPath(0, 0, { "x", 5, { 1, 0 } }), { { 1, 0 } })
		local flat = rn.flattenPath(1, 1, { { 1.9, 1.2 } })
		T.deepEq(flat, {})
	end)
end
