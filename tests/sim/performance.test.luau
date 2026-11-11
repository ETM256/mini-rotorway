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

	-- Budget per building model: a house is ~10 BasePart, a small store ~14.
	T.test("a building model uses at most 14 parts (house) and 20 parts (store)", function()
		local session = H.newSession("los_angeles")
		T.ok(#session.houses > 0 and #session.destinations > 0, "need a house and a store")
		for _, house in ipairs(session.houses) do
			T.le(H.count(house.model, "BasePart"), 14, house.key .. " uses too many parts")
		end
		for _, store in ipairs(session.destinations) do
			T.le(H.count(store.model, "BasePart"), 20, store.key .. " uses too many parts")
		end
	end)

	T.test("static terrain uses at most 300 parts", function()
		local session = H.newSession("los_angeles")
		T.le(terrainParts(session), 300)
	end)
end
