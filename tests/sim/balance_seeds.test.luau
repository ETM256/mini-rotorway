-- Équilibrage sans route (spec 11, 12, 13) : une partie sans aucune route doit
-- finir par surcharge, à la même échelle quelle que soit la graine. Mesures
-- (vitesse 3) : 135 à 142 s sur les 6 graines et les 2 cartes testées, en
-- semaine 3. Une partie sans route coûte peu : on balaie plusieurs graines.
return function(T, H)
	local MIN_SECONDS = 60
	local MAX_SECONDS = 300
	local SEEDS = { 1, 2, 3, 4, 5, 6 }
	local MAPS = { "los_angeles", "tokyo" }

	local function playWithoutRoads(mapId, seed)
		H.reset()
		H.seed(seed)
		local session = H.newSession(mapId)
		session:setSpeed(3)
		while not session.over and session.elapsed < 900 do
			if session.awaitingChoice then
				session:chooseReward(session.choice.options[1].id)
			end
			session:update(0.1)
			H.flush(0.1)
		end
		return session
	end

	T.test("no roads: every seed on every map ends by overload within 60 to 300 simulated seconds", function()
		for _, mapId in ipairs(MAPS) do
			for _, seed in ipairs(SEEDS) do
				local session = playWithoutRoads(mapId, seed)
				local label = mapId .. " graine " .. seed
				T.ok(session.over, label .. " : la partie se termine")
				T.eq(session.gameOverReason and session.gameOverReason.kind, "overload", label .. " : cause")
				T.ge(session.elapsed, MIN_SECONDS, label .. " : pas trop dur")
				T.le(session.elapsed, MAX_SECONDS, label .. " : pas trop facile")
			end
		end
	end)

	T.test("no roads: the GameOver payload is well-formed for the overload end", function()
		local session = playWithoutRoads("los_angeles", 1)
		local payload = H.lastSent("GameOver")
		T.ok(payload ~= nil, "GameOver envoyé")
		if not payload then
			return
		end
		T.eq(payload.mapId, "los_angeles", "mapId")
		T.eq(payload.reason, "overload", "reason")
		T.eq(payload.durationSeconds, math.floor(session.elapsed), "durationSeconds est un entier")
		T.eq(payload.score, 0, "aucune livraison sans route")
		T.eq(payload.stats.deliveries, 0, "stats.deliveries")
		T.ok(type(payload.overload) == "table", "overload est une table simple")
		T.ok(type(payload.overload.colorName) == "string", "overload.colorName")
		T.ok(type(payload.overload.seconds) == "number", "overload.seconds")
	end)
end
