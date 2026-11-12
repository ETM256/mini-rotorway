-- Parties longues et déterministes (un robot construit, des routes sont effacées
-- au hasard) : à chaque image, le trafic respecte ses invariants. Un interblocage,
-- une demande jamais rendue, une réservation orpheline ou une voiture qui quitte
-- la route y apparaissent.
return function(T, H)
	local STUCK_LIMIT = 35 -- attente continue au-delà de laquelle c'est un interblocage (mesuré : 25 s au plus en jeu normal)
	local ERASE_EVERY = 150 -- images entre deux effacements

	-- Congruentiel linéaire : déterministe et indépendant du harnais.
	local function randomIndex(state, n)
		state.value = (state.value * 1103515245 + 12345) % 2147483648
		return state.value % n + 1
	end

	local function botBuild(session, attempted)
		for _, house in ipairs(session.houses) do
			if not attempted[house] then
				local store = nil
				for _, candidate in ipairs(session.destinations) do
					if candidate.colorIndex == house.colorIndex then
						store = candidate
						break
					end
				end
				local cells = store and H.pathCells(session, house, store)
				if not cells then
					attempted[house] = true
				elseif session.budget >= #cells then
					H.connect(session, house, store)
					attempted[house] = true
				end
			end
		end
	end

	local function eraseOne(session, state)
		local keys = {}
		for key in pairs(session.roads) do
			keys[#keys + 1] = key
		end
		table.sort(keys)
		if #keys > 0 then
			session:eraseRoad(keys[randomIndex(state, #keys)])
		end
	end

	-- Première violation d'invariant, ou nil.
	local function violation(session, previousCenters, stepSeconds)
		local Config = H.load("Config")
		local Grid = H.load("Grid")
		local alive = {}
		local claims = {}
		for _, car in ipairs(session.cars) do
			alive[car] = true
			if car.claim and car.demandId and car.dest then
				claims[car.dest] = (claims[car.dest] or 0) + 1
			end
		end
		for _, store in ipairs(session.destinations) do
			if (claims[store] or 0) ~= store.reserved then
				return "demandes réservées " .. store.reserved .. " pour " .. (claims[store] or 0) .. " voitures"
			end
		end
		for key, holder in pairs(session.intersectionReservations) do
			if not alive[holder] then
				return "réservation orpheline sur " .. key
			end
		end
		for _, house in ipairs(session.houses) do
			if house.car and not alive[house.car] then
				return "une maison garde une voiture retirée"
			end
		end
		for _, car in ipairs(session.cars) do
			for _, other in ipairs(car.lane or {}) do
				if not alive[other] then
					return "voie qui liste une voiture retirée"
				end
			end
			if (car.waitTime or 0) > STUCK_LIMIT then
				return "voiture bloquée " .. math.floor(car.waitTime) .. " s (nœud " .. tostring(car.index) .. ")"
			end
			if car.center and car.seg then
				local before = previousCenters[car]
				if before and (car.center - before).Magnitude > Config.Traffic.CarSpeed * stepSeconds + 0.05 then
					return "voiture téléportée de " .. (car.center - before).Magnitude .. " studs"
				end
				previousCenters[car] = car.center
				local x, y = Grid.cellFromWorld(session.origin, car.center)
				local onBuilding = false
				for _, building in ipairs(session.buildingList) do
					onBuilding = onBuilding or (building.x == x and building.y == y)
				end
				if not session.roads[Grid.key(x, y)] and not onBuilding then
					return "voiture hors de la route en " .. Grid.key(x, y)
				end
			end
		end
		return nil
	end

	local function play(mapId, seed, speed, erase, seconds)
		H.seed(seed)
		local session = H.newSession(mapId)
		session:setSpeed(speed)
		local state = { value = seed * 7 + speed }
		local attempted = {}
		local previousCenters = {}
		local frame = 0
		while not session.over and session.elapsed < seconds do
			if session.awaitingChoice then
				session:chooseReward(session.choice.options[1].id)
			end
			frame += 1
			if frame % 10 == 0 then
				botBuild(session, attempted)
			end
			if erase and frame % ERASE_EVERY == 0 then
				eraseOne(session, state)
			end
			session:update(0.1)
			H.flush(0.1)
			local found = violation(session, previousCenters, 0.1 * speed)
			if found then
				return found .. " à t=" .. math.floor(session.elapsed) .. " s"
			end
		end
		T.eq(#H.handlerErrors, 0)
		return nil, session
	end

	-- Tokyo, graine 3, vitesse 1 : une voiture de retour bloquait pour toujours
	-- celle qui la précède (elle avait pris la case avant elle).
	T.test("a long game never deadlocks (tokyo, seed 3, speed 1)", function()
		local found, session = play("tokyo", 3, 1, false, 360)
		T.eq(found, nil)
		T.gt(session.stats.deliveries, 60, "le trafic doit rester fluide")
	end)

	T.test("a long game with roads erased at random keeps every invariant (tokyo, speed 3)", function()
		T.eq((play("tokyo", 1, 3, true, 300)), nil)
	end)

	T.test("a long game with roads erased at random keeps every invariant (los_angeles, speed 3)", function()
		T.eq((play("los_angeles", 2, 3, true, 300)), nil)
	end)
end
