return function(T, H)
	-- Cycle de vie des visuels de route : apparitions suivies, effacement sans
	-- pièce orpheline. Garde-fous pour le renderer unique.

	-- Une ligne horizontale de `length` cases libres et sèches.
	local function freeLine(session, length)
		local Grid, Maps = H.load("Grid"), H.load("Maps")
		local function free(x, y)
			local key = Grid.key(x, y)
			return Grid.inBounds(x, y)
				and not session.buildings[key]
				and not session.roads[key]
				and not Maps.isWater(session.map, x, y)
		end
		for y = 0, session.size - 1 do
			for startX = 0, session.size - length do
				local cells, ok = {}, true
				for i = 0, length - 1 do
					if not free(startX + i, y) then
						ok = false
						break
					end
					cells[#cells + 1] = { startX + i, y }
				end
				if ok then
					return cells
				end
			end
		end
		return nil
	end

	local function countKeys(t)
		local n = 0
		for _ in pairs(t) do
			n += 1
		end
		return n
	end

	T.test("road appearance tweens are tracked and cancelled on destroy", function()
		local session = H.newSession("los_angeles")
		session.budget = 100
		local line = freeLine(session, 4)
		T.ok(line, "a free line of four dry cells")
		local tweens = session.tweens
		session:drawRoad(line)
		T.ok(countKeys(tweens) > 0, "the appearance tweens are registered in session.tweens")
		session:destroy()
		T.eq(countKeys(tweens), 0, "destroy cancels every road appearance tween")
	end)

	T.test("erasing every road leaves no road part in the world", function()
		local session = H.newSession("los_angeles")
		session.budget = 100
		local line = freeLine(session, 6)
		T.ok(line, "a free line of six dry cells")
		session:drawRoad(line)
		H.runSession(session, 1)
		T.ok(H.count(session.world.Roads, "BasePart") > 0, "the drawn line has road parts")
		local keys = {}
		for _, cell in ipairs(line) do
			keys[#keys + 1] = H.load("Grid").key(cell[1], cell[2])
		end
		session:eraseRoads(keys)
		H.runSession(session, 1)
		T.eq(H.count(session.world.Roads, "BasePart"), 0, "no orphan road part after erasing everything")
		T.eq(countKeys(session.roadParts), 0, "no road cell keeps a parts entry")
	end)
end
