-- manhattanPath et flattenPath : quatre quadrants, préférence d'axe, plafond
-- de longueur, entrées invalides, continuité et dédoublonnage des tracés.
return function(T, H)
	local function RN()
		return H.load("RoadNetwork")
	end

	-- Vérifie qu'un tracé part de (fx, fy), finit sur (tx, ty) et ne fait que des pas unitaires.
	local function checkContinuous(path, fx, fy, tx, ty)
		local px, py = fx, fy
		for _, cell in ipairs(path) do
			T.eq(math.abs(cell[1] - px) + math.abs(cell[2] - py), 1, "unit step")
			px, py = cell[1], cell[2]
		end
		T.eq(px, tx, "ends at target x")
		T.eq(py, ty, "ends at target y")
	end

	T.test("manhattanPath covers the four quadrants", function()
		local rn = RN()
		local cases = {
			{ 5, 5, 8, 7 },
			{ 5, 5, 2, 7 },
			{ 5, 5, 2, 1 },
			{ 5, 5, 8, 1 },
		}
		for _, c in ipairs(cases) do
			local path, complete = rn.manhattanPath(c[1], c[2], c[3], c[4])
			T.ok(complete)
			T.eq(#path, math.abs(c[3] - c[1]) + math.abs(c[4] - c[2]))
			checkContinuous(path, c[1], c[2], c[3], c[4])
		end
	end)

	T.test("manhattanPath on a single axis walks only that axis", function()
		local rn = RN()
		T.deepEq(rn.manhattanPath(5, 5, 5, 1), { { 5, 4 }, { 5, 3 }, { 5, 2 }, { 5, 1 } })
		T.deepEq(rn.manhattanPath(5, 5, 7, 5), { { 6, 5 }, { 7, 5 } })
		T.deepEq(rn.manhattanPath(5, 5, 3, 5), { { 4, 5 }, { 3, 5 } })
	end)

	T.test("manhattanPath preferredAxis decides the order of an L shape", function()
		local rn = RN()
		-- Trajet dominant en x, mais la préférence "y" passe en premier.
		local yFirst = rn.manhattanPath(0, 0, 4, 2, "y")
		T.deepEq(yFirst[1], { 0, 1 })
		T.deepEq(yFirst[#yFirst], { 4, 2 })
		local xFirst = rn.manhattanPath(0, 0, 4, 2, "x")
		T.deepEq(xFirst[1], { 1, 0 })
		checkContinuous(yFirst, 0, 0, 4, 2)
		checkContinuous(xFirst, 0, 0, 4, 2)
	end)

	T.test("manhattanPath ties go horizontal first without a preference", function()
		local rn = RN()
		local tie = rn.manhattanPath(0, 0, 2, 2)
		T.deepEq(tie[1], { 1, 0 })
	end)

	T.test("manhattanPath with an unknown preference behaves like no preference", function()
		local rn = RN()
		T.deepEq(rn.manhattanPath(0, 0, 4, 1, "z"), rn.manhattanPath(0, 0, 4, 1))
	end)

	T.test("manhattanPath to the same cell is empty and complete", function()
		local rn = RN()
		local path, complete = rn.manhattanPath(3, 3, 3, 3)
		T.deepEq(path, {})
		T.ok(complete)
	end)

	T.test("manhattanPath accepts a path of exactly the cap", function()
		local rn, Config = RN(), H.load("RoadConfig")
		local cap = Config.Input.MaxPathSteps
		local path, complete = rn.manhattanPath(0, 0, cap, 0)
		T.ok(complete)
		T.eq(#path, cap)
		local tooLong, tooLongComplete = rn.manhattanPath(0, 0, cap + 1, 0)
		T.falsy(tooLongComplete)
		T.deepEq(tooLong, {})
	end)

	T.test("manhattanPath refuses non-integer, NaN and infinite coordinates", function()
		local rn = RN()
		for _, bad in ipairs({
			{ 0.5, 0, 2, 0 },
			{ 0, 0, 0 / 0, 0 },
			{ 0, 0, 2, math.huge },
			{ -math.huge, 0, 2, 0 },
			{ nil, 0, 2, 0 },
			{ "1", 0, 2, 0 },
		}) do
			local path, complete = rn.manhattanPath(bad[1], bad[2], bad[3], bad[4])
			T.deepEq(path, {}, "refused " .. tostring(bad[1]) .. "," .. tostring(bad[3]))
			T.falsy(complete)
		end
	end)

	T.test("flattenPath chains segments into one continuous route", function()
		local rn = RN()
		local flat = rn.flattenPath(0, 0, { { 3, 0 }, { 3, 2 }, { 0, 2 } })
		T.eq(#flat, 3 + 2 + 3)
		checkContinuous(flat, 0, 0, 0, 2)
	end)

	T.test("flattenPath keeps every cell of a self-crossing stroke exactly once", function()
		local rn = RN()
		-- Le trajet (2,0) -> (1,1) repasse par (1,0) : la case n'est gardée qu'une fois.
		local flat = rn.flattenPath(0, 0, { { 2, 0 }, { 1, 1 } })
		T.deepEq(flat, { { 1, 0 }, { 2, 0 }, { 1, 1 } })
	end)

	T.test("flattenPath never repeats a cell and never returns the start", function()
		local rn = RN()
		local flat = rn.flattenPath(0, 0, { { 2, 0 }, { 0, 0 }, { 2, 0 } })
		local seen = {}
		for _, cell in ipairs(flat) do
			local k = cell[1] .. ":" .. cell[2]
			T.falsy(seen[k], "duplicate " .. k)
			seen[k] = true
			T.ok(not (cell[1] == 0 and cell[2] == 0), "start is not returned")
		end
		T.eq(#flat, 2)
	end)

	T.test("flattenPath skips NaN, infinite and missing targets without moving", function()
		local rn = RN()
		local flat = rn.flattenPath(0, 0, {
			{ 0 / 0, 1 },
			{ 2, math.huge },
			{ nil, 3 },
			{ 2, 0 },
		})
		T.deepEq(flat, { { 1, 0 }, { 2, 0 } })
	end)

	T.test("flattenPath floors fractional targets and fractional starts", function()
		local rn = RN()
		T.deepEq(rn.flattenPath(0.9, 0.2, { { 2.7, 0.4 } }), { { 1, 0 }, { 2, 0 } })
	end)

	T.test("flattenPath refuses a non-finite start", function()
		local rn = RN()
		T.deepEq(rn.flattenPath(0 / 0, 0, { { 2, 0 } }), {})
		T.deepEq(rn.flattenPath(0, math.huge, { { 2, 0 } }), {})
	end)

	T.test("flattenPath skips a target too far away and keeps going from the last good one", function()
		local rn, Config = RN(), H.load("RoadConfig")
		local far = Config.Input.MaxPathSteps + 10
		local flat = rn.flattenPath(0, 0, { { far, 0 }, { 2, 0 } })
		T.deepEq(flat, { { 1, 0 }, { 2, 0 } })
	end)

	T.test("flattenPath output reproduces the drag used by the input controller", function()
		local rn = RN()
		-- Un geste en biais, traité en deux morceaux comme le fait le contrôleur.
		local one = rn.manhattanPath(0, 0, 3, 2, "x")
		local two = rn.flattenPath(0, 0, { { 3, 2 } }, "x")
		T.deepEq(two, one)
	end)
end
