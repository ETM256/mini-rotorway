return function(T, H)
	-- Part 16 of the brief: the game must stay smooth with many buildings and
	-- cars. Wall-clock limits are deliberately generous (headless, no rendering);
	-- part counts are what matters on a real client.

	local function terrainParts(session)
		local n = 0
		for _, child in ipairs(session.world.folder:GetChildren()) do
			if child.Name ~= "Buildings" and child.Name ~= "Roads" and child.Name ~= "Cars" and child.Name ~= "FX" then
				n += H.count(child, "BasePart")
				if child:IsA("BasePart") then
					n += 1
				end
			end
		end
		return n
	end

	T.test("creating a session is quick on every map", function()
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local started = H.cpuClock()
			H.newSession(map.id)
			T.lt(H.cpuClock() - started, 2, map.id .. " takes too long to build")
		end
	end)

	T.test("a busy game (3 stores, 9 houses, 6 cars) simulates 5 minutes in well under 3 s of CPU", function()
		local session = H.newSession("los_angeles")
		session.budget = 500
		for _, house in ipairs(session.houses) do
			H.connect(session, house, session.destinations[1])
		end
		local started = H.cpuClock()
		H.runSession(session, 300, 0.1)
		T.lt(H.cpuClock() - started, 3)
	end)

	T.test("memory stays bounded: part count does not grow while nothing changes", function()
		local session = H.newSession("los_angeles")
		session.budget = 500
		session.storeSystem.spawnClock = 1e9
		session.storeSystem.houseClock = 1e9
		for _, house in ipairs(session.houses) do
			H.connect(session, house, session.destinations[1])
		end
		H.runSession(session, 40, 0.1)
		local before = H.count(session.world.folder, "BasePart")
		-- Les cartes sont reconstruites à l'identique : plus de nouveaux bâtiments, seulement des voitures.
		H.runSession(session, 120, 0.1)
		T.le(H.count(session.world.folder, "BasePart"), before + 40, "cars must be pooled or cleaned up")
	end)

	T.test("terrain parts are bounded on every map (water/grass/grid)", function()
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			T.le(terrainParts(session), 1500, map.id .. " terrain: " .. terrainParts(session))
		end
	end)

	-- Today a building is ~50 BasePart (rounded cards made of two bars + four
	-- cylinders per layer) and a water map ~450 parts.
	T.todo("a building model uses at most 25 parts", function()
		local session = H.newSession("los_angeles")
		local count = H.count(session.world.Buildings, "BasePart") / #session.buildingList
		T.le(count, 25)
	end)

	T.test("static terrain uses at most 300 parts", function()
		local session = H.newSession("los_angeles")
		T.le(terrainParts(session), 300)
	end)
end
