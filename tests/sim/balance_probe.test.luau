-- Équilibrage avec un bot (spec 11, 12, 13) : parties déterministes à vitesse 3.
-- Le bot relie chaque maison à un magasin de sa couleur par le plus court
-- chemin de cases libres, tant que le budget le permet, et prend toujours la
-- première proposition de semaine. Mesures de la vague 4 (graines 1 à 3,
-- 900 s max, relevées par une exécution réelle de ce fichier) :
--   sans route : 137 à 141 s sur les deux cartes (surcharge, semaine 3) ;
--   bot los_angeles : 336 à 435 s ; bot tokyo : 460 à 563 s ;
--   les six parties du bot finissent par surcharge, aucune par embouteillage ;
--   voitures bloquées : 179 s au total (143 s pour tokyo graine 1 seule).
-- Avant la correction du trafic (réservations par paires de cases : deux
-- voitures de sens opposés sur deux cases voisines se bloquaient pour de bon),
-- 6 parties sur 12 étaient perdues par embouteillage. Depuis (réservation par
-- suites entières de cases, arrêt avant la case occupée, boucle d'attente
-- cassée) il n'y en a plus.
-- Une seule graine ne suffit pas : la durée varie beaucoup d'une graine à
-- l'autre. Aucun réglage d'équilibrage n'a été modifié : la défaite vient
-- désormais de la surcharge des magasins, pas du trafic.
return function(T, H)
	local Config = H.load("Config")
	local Roads = Config.Roads
	local Progression = Config.Progression

	local SEEDS = { 1, 2, 3 }
	local GAME_LIMIT = 900 -- 15 minutes simulées
	local SAMPLE_SECONDS = 30
	local DT = 0.1 -- secondes réelles par frame ; à vitesse 3 : 0,3 s simulées
	local BOT_RATIO = 1.25 -- le bot dure au moins 25 % de plus que sans route, graine par graine
	local MIN_BOT_SECONDS = 150

	-- Chaque partie est jouée une seule fois : les tests la relisent.
	local cache = {}

	local function chooseFirst(session)
		if session.awaitingChoice then
			session:chooseReward(session.choice.options[1].id)
		end
	end

	-- Ne construit qu'avec le budget réel : H.connect élargirait le budget.
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

	-- Joue une partie et renvoie seulement des données simples : échantillons
	-- toutes les SAMPLE_SECONDS, première violation d'invariant, bilan de fin.
	local function play(mapId, seed, useBot)
		local key = mapId .. "/" .. seed .. "/" .. tostring(useBot)
		if cache[key] then
			return cache[key]
		end

		H.reset()
		H.seed(seed)
		local session = H.newSession(mapId)
		session:setSpeed(3)
		local attempted = {}
		local samples = {}
		local violation = nil
		local frame = 0
		local nextSample = 0

		local function sample()
			samples[#samples + 1] = {
				t = session.elapsed,
				score = session.score,
				houses = #session.houses,
				stores = #session.destinations,
				demands = session.stats.demandsCreated,
			}
		end

		while not session.over and session.elapsed < GAME_LIMIT do
			chooseFirst(session)
			frame += 1
			if useBot and frame % 10 == 0 then
				botBuild(session, attempted)
			end
			session:update(DT)
			H.flush(DT)

			if not violation then
				if session.budget < 0 or session.budget > Roads.MaxBudget then
					violation = "budget hors bornes : " .. session.budget
				elseif session.bridgesLeft < 0 or session.bridgesLeft > Roads.MaxBridges then
					violation = "ponts hors bornes : " .. session.bridgesLeft
				elseif session.roundaboutsLeft < 0 or session.roundaboutsLeft > Roads.MaxRoundabouts then
					violation = "ronds-points hors bornes : " .. session.roundaboutsLeft
				elseif session.satisfaction < 0 or session.satisfaction > Config.Traffic.SatisfactionMax then
					violation = "satisfaction hors bornes : " .. session.satisfaction
				end
			end

			if session.elapsed >= nextSample then
				sample()
				nextSample += SAMPLE_SECONDS
			end
		end
		sample()

		local result = {
			elapsed = session.elapsed,
			over = session.over,
			reason = session.gameOverReason and session.gameOverReason.kind,
			samples = samples,
			violation = violation,
			mapId = session.mapId,
			score = session.score,
			payload = H.lastSent("GameOver"),
		}
		cache[key] = result
		return result
	end

	-- Payload de fin : mêmes champs que lit l'écran de fin (HUDOverlays).
	local function checkPayload(T, run, label)
		local payload = run.payload
		T.ok(payload ~= nil, label .. " : GameOver envoyé")
		if not payload then
			return
		end
		T.eq(payload.mapId, run.mapId, label .. " : mapId")
		T.eq(payload.reason, run.reason, label .. " : reason")
		T.eq(payload.durationSeconds, math.floor(run.elapsed), label .. " : durationSeconds entier")
		T.eq(payload.score, run.score, label .. " : score")
		T.ok(type(payload.best) == "number", label .. " : best")
		T.ok(type(payload.stats) == "table" and type(payload.stats.deliveries) == "number", label .. " : stats")
		T.ok(type(payload.overload) == "table", label .. " : overload est une table simple")
		if payload.reason == "overload" then
			T.ok(type(payload.overload.storeId) == "number" or type(payload.overload.storeId) == "string", label .. " : overload.storeId")
			T.ok(type(payload.overload.colorName) == "string", label .. " : overload.colorName")
		end
	end

	T.test("bot outlives the no-road game on every tested seed, on both maps", function()
		for _, mapId in ipairs({ "los_angeles", "tokyo" }) do
			for _, seed in ipairs(SEEDS) do
				local without = play(mapId, seed, false)
				local bot = play(mapId, seed, true)
				local label = mapId .. " graine " .. seed
				T.ok(bot.elapsed >= MIN_BOT_SECONDS, label .. " : le bot tient au moins " .. MIN_BOT_SECONDS .. " s (atteint " .. math.floor(bot.elapsed) .. " s)")
				T.ge(bot.elapsed, without.elapsed * BOT_RATIO, label .. " : nettement plus longtemps que sans route")
			end
		end
	end)

	T.test("bot: the end payload is well-formed (los_angeles, seed 1)", function()
		local bot = play("los_angeles", 1, true)
		T.ok(bot.over or bot.elapsed >= GAME_LIMIT, "la partie finit ou atteint la limite")
		if bot.over then
			T.ok(bot.reason == "traffic" or bot.reason == "overload", "cause de fin connue : " .. tostring(bot.reason))
			checkPayload(T, bot, "bot los_angeles")
		end
	end)

	T.test("bot: invariants hold every frame and the score never decreases", function()
		for _, mapId in ipairs({ "los_angeles", "tokyo" }) do
			for _, seed in ipairs(SEEDS) do
				local bot = play(mapId, seed, true)
				local label = mapId .. " graine " .. seed
				T.eq(bot.violation, nil, label .. " : budget, ponts, ronds-points et satisfaction bornés")
				local previous = -1
				for _, s in ipairs(bot.samples) do
					T.ge(s.score, previous, label .. " : score croissant à t=" .. math.floor(s.t))
					previous = s.score
				end
				T.gt(previous, 0, label .. " : le bot marque des points")
			end
		end
	end)

	-- Difficulté progressive (spec 13 : « ne pas augmenter la difficulté de
	-- manière brutale ») : pas de bond de magasins ni de maisons d'une minute à
	-- l'autre. Mesuré : au plus +1 magasin et +3 maisons par minute.
	T.test("bot: stores grow by at most 2 and houses by at most 4 per simulated minute", function()
		for _, mapId in ipairs({ "los_angeles", "tokyo" }) do
			for _, seed in ipairs(SEEDS) do
				local bot = play(mapId, seed, true)
				local byMinute = {}
				for _, s in ipairs(bot.samples) do
					if s.t >= 60 * #byMinute then
						byMinute[#byMinute + 1] = s
					end
				end
				local label = mapId .. " graine " .. seed
				for i = 2, #byMinute do
					local a, b = byMinute[i - 1], byMinute[i]
					T.le(b.stores - a.stores, 2, label .. " : magasins en plus à t=" .. math.floor(b.t))
					T.le(b.houses - a.houses, 4, label .. " : maisons en plus à t=" .. math.floor(b.t))
				end
			end
		end
	end)

	-- Demandes : chaque minute en crée au plus 2,5 fois plus que la précédente
	-- (plus 2) ; la courbe monte sans palier brutal.
	T.test("bot: demand windows ramp smoothly (each minute at most 2.5x the previous one, plus 2)", function()
		for _, mapId in ipairs({ "los_angeles", "tokyo" }) do
			for _, seed in ipairs(SEEDS) do
				local bot = play(mapId, seed, true)
				local perMinute = {}
				local last = 0
				for _, s in ipairs(bot.samples) do
					if s.t >= 60 * (#perMinute + 1) then
						perMinute[#perMinute + 1] = s.demands - last
						last = s.demands
					end
				end
				local label = mapId .. " graine " .. seed
				for i = 2, #perMinute do
					T.le(perMinute[i], 2.5 * perMinute[i - 1] + 2, label .. " : demandes minute " .. i)
				end
			end
		end
	end)

	-- Les mesures valent pour ces réglages : tout retuning doit relancer la
	-- sonde et mettre à jour l'en-tête.
	T.test("probe assumptions: start budget and overload cap are the measured values", function()
		T.eq(Roads.StartBudget, 20, "budget de départ mesuré")
		T.eq(Progression.OverloadMaxExtra, 1, "pression de surcharge mesurée")
	end)
end
