-- Contrat de Pathfinding.find / findFromAny : cas limites, buts hors route,
-- départs multiples, budget d'expansions, déterminisme et temps de calcul.
return function(T, H)
	local function build(cells)
		local roads = {}
		for _, c in ipairs(cells) do
			roads[c[1] .. ":" .. c[2]] = true
		end
		return roads
	end

	local function rect(x1, y1, x2, y2)
		local cells = {}
		for x = x1, x2 do
			for y = y1, y2 do
				cells[#cells + 1] = { x, y }
			end
		end
		return cells
	end

	T.test("start equal to a goal returns a single node", function()
		local P = H.load("Pathfinding")
		T.deepEq(P.find(build({ { 2, 2 } }), 18, "2:2", { ["2:2"] = true }), { "2:2" })
	end)

	T.test("a start that is not a road returns nil", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 1, 0 }, { 2, 0 } })
		T.eq(P.find(roads, 18, "0:0", { ["2:0"] = true }), nil)
	end)

	T.test("invalid start (not a key, outside the grid, fractional) returns nil", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 0, 0 }, { 1, 0 } })
		T.eq(P.find(roads, 18, "19:0", { ["1:0"] = true }), nil)
		T.eq(P.find(roads, 18, "-1:0", { ["1:0"] = true }), nil)
		T.eq(P.find(roads, 18, "0.5:0", { ["1:0"] = true }), nil)
		T.eq(P.find(roads, 18, nil, { ["1:0"] = true }), nil)
		T.eq(P.find(roads, 18, 5, { ["1:0"] = true }), nil)
	end)

	T.test("goals off the roads or outside the grid never match", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 0, 0 }, { 1, 0 } })
		T.eq(P.find(roads, 18, "0:0", { ["5:5"] = true }), nil)
		T.eq(P.find(roads, 18, "0:0", { ["25:0"] = true }), nil)
		T.eq(P.find(roads, 18, "0:0", { ["-1:0"] = true }), nil)
		-- Un but hors route ne fait pas échouer un but valide présent dans le même ensemble.
		T.deepEq(P.find(roads, 18, "0:0", { ["5:5"] = true, ["1:0"] = true }), { "0:0", "1:0" })
	end)

	T.test("goal flags must be truthy", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 0, 0 }, { 1, 0 } })
		T.eq(P.find(roads, 18, "0:0", { ["1:0"] = false }), nil)
	end)

	T.test("missing or malformed arguments return nil instead of raising", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 0, 0 } })
		T.eq(P.find(nil, 18, "0:0", { ["0:0"] = true }), nil)
		T.eq(P.find(roads, 18, "0:0", nil), nil)
		T.eq(P.find(roads, 0, "0:0", { ["0:0"] = true }), nil)
		T.eq(P.find(roads, 2.5, "0:0", { ["0:0"] = true }), nil)
		T.eq(P.findFromAny(roads, 18, nil, { ["0:0"] = true }), nil)
	end)

	T.test("non-canonical goal keys still match, paths use canonical keys", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 0, 0 }, { 0, 1 } })
		T.deepEq(P.find(roads, 18, "0:0", { ["00:01"] = true }), { "0:0", "0:1" })
	end)

	T.test("negative zero in the start key is the same cell as 0", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 0, 0 }, { 1, 0 } })
		T.deepEq(P.find(roads, 18, "-0:0", { ["1:0"] = true }), { "0:0", "1:0" })
	end)

	T.test("the grid size limits the search, roads beyond it are ignored", function()
		local P = H.load("Pathfinding")
		local roads = build(rect(0, 0, 6, 0))
		T.eq(P.find(roads, 4, "0:0", { ["6:0"] = true }), nil)
		T.ok(P.find(roads, 7, "0:0", { ["6:0"] = true }))
	end)

	T.test("diagonal option is off by default", function()
		local P = H.load("Pathfinding")
		local roads = build({ { 0, 0 }, { 1, 1 } })
		T.eq(P.find(roads, 18, "0:0", { ["1:1"] = true }), nil)
		T.deepEq(P.find(roads, 18, "0:0", { ["1:1"] = true }, true), { "0:0", "1:1" })
	end)

	T.test("paths are deterministic across runs", function()
		local P = H.load("Pathfinding")
		-- Deux routes de même longueur : le tracé doit toujours être le même.
		local roads = build(rect(0, 0, 2, 2))
		local first = P.find(roads, 18, "0:0", { ["2:2"] = true })
		for _ = 1, 5 do
			T.deepEq(P.find(roads, 18, "0:0", { ["2:2"] = true }), first)
		end
		T.eq(#first, 5)
	end)

	T.test("goes around a wall without leaving the grid", function()
		local P = H.load("Pathfinding")
		local roads = build(rect(0, 0, 4, 4))
		for y = 0, 4 do
			roads["2:" .. y] = nil
		end
		T.eq(P.find(roads, 5, "0:0", { ["4:0"] = true }), nil)
		-- Une seule ouverture en haut du mur : le trajet la contourne, 12 pas.
		roads["2:4"] = true
		local path = P.find(roads, 5, "0:0", { ["4:0"] = true })
		T.ok(path)
		T.eq(path[#path], "4:0")
		T.eq(#path, 13)
	end)

	T.test("findFromAny picks the shortest of several starts", function()
		local P = H.load("Pathfinding")
		local roads = build(rect(0, 0, 9, 0))
		local goals = { ["9:0"] = true }
		local path = P.findFromAny(roads, 18, { "0:0", "6:0", "3:0" }, goals)
		T.deepEq(path, { "6:0", "7:0", "8:0", "9:0" })
	end)

	T.test("findFromAny equals the best of single-start searches", function()
		local P = H.load("Pathfinding")
		local roads = build(rect(0, 0, 5, 5))
		local goals = { ["5:5"] = true, ["0:5"] = true }
		local starts = { "2:2", "4:0", "0:1" }
		local best = nil
		for _, s in ipairs(starts) do
			local p = P.find(roads, 18, s, goals)
			if p and (not best or #p < #best) then
				best = p
			end
		end
		local multi = P.findFromAny(roads, 18, starts, goals)
		T.eq(#multi, #best)
	end)

	T.test("findFromAny with a start on a goal returns that single node", function()
		local P = H.load("Pathfinding")
		local roads = build(rect(0, 0, 3, 0))
		T.deepEq(P.findFromAny(roads, 18, { "0:0", "2:0" }, { ["2:0"] = true }), { "2:0" })
	end)

	T.test("maxExpansions bounds the work and returns nil when exceeded", function()
		local P = H.load("Pathfinding")
		local roads = build(rect(0, 0, 9, 9))
		T.eq(P.find(roads, 18, "0:0", { ["9:9"] = true }, false, 3), nil)
		local path = P.find(roads, 18, "0:0", { ["9:9"] = true }, false, 10000)
		T.ok(path)
		T.eq(#path, 19)
	end)

	T.test("a huge open grid is solved quickly", function()
		local P = H.load("Pathfinding")
		local size = 120
		local roads = build(rect(0, 0, size - 1, size - 1))
		local started = H.cpuClock()
		local path = P.find(roads, size, "0:0", { [(size - 1) .. ":" .. (size - 1)] = true })
		local elapsed = H.cpuClock() - started
		T.ok(path)
		T.eq(#path, 2 * (size - 1) + 1)
		T.lt(elapsed, 5, "open grid search takes too long")
	end)

	T.test("an unreachable goal in a huge open grid is proven quickly", function()
		local P = H.load("Pathfinding")
		local size = 120
		local roads = build(rect(0, 0, size - 1, size - 1))
		-- Le but est entouré de vide : toute la grille est explorée avant l'échec.
		roads[(size - 2) .. ":" .. (size - 1)] = nil
		roads[(size - 1) .. ":" .. (size - 2)] = nil
		local started = H.cpuClock()
		local path = P.find(roads, size, "0:0", { [(size - 1) .. ":" .. (size - 1)] = true })
		local elapsed = H.cpuClock() - started
		T.eq(path, nil)
		T.lt(elapsed, 5, "exhaustive search takes too long")
	end)
end
