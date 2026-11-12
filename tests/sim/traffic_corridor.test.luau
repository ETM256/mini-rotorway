-- Les voitures restent dans la chaussée (spec 8 : aucune voiture décalée de la
-- route) : les quatre coins de leur carrosserie sont échantillonnés contre la
-- surface visible des routes (RoadGeometry : chaussée et liseré blanc), case par case.
return function(T, H)
	-- Fraction de case tolérée au-delà du liseré blanc : la queue d'une voiture qui
	-- tourne déborde au plus de 0,026 case (0,1 stud) dans un virage ou un T.
	local TOLERANCE = 0.03

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

	-- Bras de raccord : pour chaque connexion route -> bâtiment, la direction de
	-- la route vers le bâtiment.
	local function connectorSet(session)
		local Grid = H.load("Grid")
		local RoadGeometry = H.load("RoadGeometry")
		local set = {}
		local buildingCells = {}
		for _, building in ipairs(session.buildingList) do
			buildingCells[Grid.key(building.x, building.y)] = building
			for _, key in ipairs(building.connections or {}) do
				local x, y = Grid.parse(key)
				local dir = nil
				if building.y < y then
					dir = "N"
				elseif building.y > y then
					dir = "S"
				elseif building.x > x then
					dir = "E"
				else
					dir = "W"
				end
				set[RoadGeometry.connectorKey(x, y, dir)] = true
			end
		end
		return set, buildingCells
	end

	-- Distance (fraction de case) entre le point et la pièce : 0 s'il est dedans.
	local function excess(piece, u, v)
		if piece.kind == "disk" then
			return math.max(0, math.sqrt((u - piece.cx) ^ 2 + (v - piece.cy) ^ 2) - piece.r)
		end
		local dx = math.max(0, math.abs(u - piece.cx) - piece.w * 0.5)
		local dy = math.max(0, math.abs(v - piece.cy) - piece.h * 0.5)
		return math.sqrt(dx * dx + dy * dy)
	end

	-- Écart du point à la chaussée de sa case (0 = dessus) et type de la case.
	local function offRoad(session, connectors, buildingCells, car, point)
		local Grid = H.load("Grid")
		local RoadGeometry = H.load("RoadGeometry")
		local tile = session.tile
		local x, y = Grid.cellFromWorld(session.origin, point)
		local key = Grid.key(x, y)
		if not session.roads[key] then
			-- Seule la case du bâtiment desservi est permise, à l'entrée et à la sortie.
			local building = buildingCells[key]
			local ends = car.index <= 1 or car.index >= #car.path
			local allowed = building ~= nil and ends and (building == car.house or building == car.dest)
			return allowed and 0 or math.huge, "building"
		end
		local u = (point.X - session.origin.X) / tile - x
		local v = (point.Z - session.origin.Z) / tile - y
		local mask = RoadGeometry.neighborMask(session.roads, x, y, session.bridges, connectors)
		local kind = RoadGeometry.classify(mask)
		local best = math.huge
		for _, piece in ipairs(RoadGeometry.cellPieces(session.roads, session.bridges, connectors, x, y)) do
			best = math.min(best, excess(piece, u, v))
		end
		return best, kind
	end

	local function sampleCorridor(mapId)
		local RoadConfig = H.load("RoadConfig")
		local session = H.newSession(mapId)
		connectAll(session)
		local halfWidth = session.tile * RoadConfig.Vehicle.WidthTiles * 0.5
		local halfLength = session.tile * RoadConfig.Vehicle.LengthTiles * 0.5
		local counts, bad, worst = {}, 0, nil
		local elapsed = 0
		while elapsed < 240 and not session.over do
			session:update(0.1)
			H.flush(0.1)
			elapsed += 0.1
			if session.awaitingChoice then
				session:chooseReward(session.choice.options[1].id)
			end
			local connectors, buildingCells = connectorSet(session)
			for _, car in ipairs(session.cars) do
				if car.seg and car.heading then
					local forward = car.heading
					local right = Vector3.new(-forward.Z, 0, forward.X)
					for _, sign in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
						local corner = car.pos + right * (halfWidth * sign[1]) + forward * (halfLength * sign[2])
						local out, kind = offRoad(session, connectors, buildingCells, car, corner)
						counts[kind] = (counts[kind] or 0) + 1
						if out > TOLERANCE then
							bad += 1
							worst = worst or (kind .. " cell, " .. out .. " tile outside, t=" .. elapsed)
						end
					end
				end
			end
		end
		return counts, bad, worst
	end

	T.test("car body corners stay on the road surface (straight, corner, T and cross cells, both maps)", function()
		local total = {}
		for _, mapId in ipairs({ "los_angeles", "tokyo" }) do
			local counts, bad, worst = sampleCorridor(mapId)
			for kind, n in pairs(counts) do
				total[kind] = (total[kind] or 0) + n
			end
			T.eq(bad, 0, mapId .. ": a car corner left the road: " .. tostring(worst))
		end
		T.gt(total.straight or 0, 0, "no sample on a straight cell")
		T.gt(total.corner or 0, 0, "no sample on a corner cell")
		T.gt((total.tee or 0) + (total.cross or 0), 0, "no sample on a T or cross cell")
	end)
end
