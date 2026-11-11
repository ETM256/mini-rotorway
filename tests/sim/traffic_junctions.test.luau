return function(T, H)
	local function stepRun(session, seconds, dt, check)
		local elapsed = 0
		while elapsed < seconds and not session.over do
			session:update(dt)
			H.flush(dt)
			elapsed += dt
			if session.awaitingChoice then
				session:chooseReward(session.choice.options[1].id)
			end
			if check then
				check(session, elapsed)
			end
		end
	end

	-- Relie chaque maison à un magasin de sa couleur, quand un chemin existe.
	local function connectAll(session)
		session.budget = 400
		for _, house in ipairs(session.houses) do
			for _, store in ipairs(session.destinations) do
				if store.colorIndex == house.colorIndex and H.connect(session, house, store) then
					break
				end
			end
		end
	end

	T.test("two car bodies never overlap, on every map, at junctions and house exits", function()
		local Maps = H.load("Maps")
		local Config = H.load("Config")
		local RoadConfig = H.load("RoadConfig")
		local bodyWidth = Config.Grid.TileSize * RoadConfig.Vehicle.WidthTiles
		local minimum = bodyWidth * 0.8
		local pairsChecked = 0
		for _, map in ipairs(Maps.all()) do
			local session = H.newSession(map.id)
			connectAll(session)
			local overlaps = 0
			local worst = math.huge
			stepRun(session, 200, 0.1, function(s)
				for a = 1, #s.cars do
					for b = a + 1, #s.cars do
						local distance = (s.cars[a].pos - s.cars[b].pos).Magnitude
						pairsChecked += 1
						worst = math.min(worst, distance)
						if distance < minimum then
							overlaps += 1
						end
					end
				end
			end)
			T.eq(overlaps, 0, map.id .. ": cars overlap (closest " .. worst .. " studs)")
		end
		T.gt(pairsChecked, 0, "the scenarios must put several cars on the road")
	end)
end
