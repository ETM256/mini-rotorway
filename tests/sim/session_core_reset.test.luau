-- Remise à zéro d'une partie : chaque champ écrit par un module Session* doit
-- être réinitialisé dans resetGameState (appelé à la création, au start() et au
-- destroy()). Sinon une partie garde des restes de la précédente.
return function(T, H)
	-- Champs posés une fois par Session.new (identité, monde, tweens) : hors reset.
	local CREATED_ONCE = {
		player = true,
		mapId = true,
		map = true,
		worldIndex = true,
		origin = true,
		size = true,
		tile = true,
		tweens = true,
		destroyed = true,
		world = true,
		storeSystem = true,
	}

	-- Texte de `from` jusqu'à `to` (exclu) : le corps d'une fonction du module.
	local function between(source, from, to)
		local first = string.find(source, from, 1, true)
		local last = string.find(source, to, first or 1, true)
		return first and last and string.sub(source, first, last - 1) or ""
	end

	-- resetGameState écrit aussi les champs de l'horloge, via updateClock().
	local function resetBody(source)
		return between(source, "local function resetGameState", "local function teardownGame")
			.. between(source, "function Session:updateClock", "function Session:recordStat")
	end

	local function assignedFields(source)
		local fields = {}
		for name, nextChar in string.gmatch(source, "self%.([%a_][%w_]*)%s*[%+%-]?=(.?)") do
			if nextChar ~= "=" then
				fields[name] = true
			end
		end
		return fields
	end

	T.test("every field written by a Session module is reset by resetGameState (or set once in Session.new)", function()
		local sessionSource, written = nil, {}
		for _, info in ipairs(H.sources()) do
			if info.name == "Session" then
				sessionSource = H.stripComments(info.source)
			elseif string.sub(info.name, 1, 7) == "Session" and info.name ~= "SessionUtil" then
				for name in pairs(assignedFields(H.stripComments(info.source))) do
					written[name] = info.name
				end
			end
		end
		T.ok(sessionSource ~= nil, "Session.luau est chargé")
		for name in pairs(assignedFields(sessionSource)) do
			written[name] = written[name] or "Session"
		end

		local reset = resetBody(sessionSource)
		T.ok(#reset > 0, "resetGameState est trouvé")
		local missing = {}
		for name, owner in pairs(written) do
			if not CREATED_ONCE[name] and not string.find(reset, "self." .. name .. "%s*=") then
				missing[#missing + 1] = name .. " (" .. owner .. ")"
			end
		end
		table.sort(missing)
		T.eq(#missing, 0, "champs non réinitialisés : " .. table.concat(missing, ", "))
	end)

	T.test("a restarted game starts from a clean state: no road, score or cache survives start()", function()
		local Config = H.load("Config")
		local session = H.newSession("los_angeles")
		local house, store = H.houseAndStore(session)
		H.connect(session, house, store)
		H.runSession(session, 30, 0.1, { autoChoose = false })
		T.ok(session.roadVersion > 0, "une route a été construite")

		session:start()
		T.eq(session.score, 0, "score remis à zéro")
		T.eq(session.budget, Config.Roads.StartBudget, "budget de départ")
		T.eq(next(session.roads), nil, "aucune route de la partie précédente")
		T.eq(session.roadVersion, 0, "version de route repart de zéro")
		-- Un cache rempli pendant la nouvelle partie porte sa version (0) ; un
		-- cache hérité de l'ancienne partie serait resté à une autre valeur.
		T.ok(session.holdCellVersion == nil or session.holdCellVersion == 0, "cache des cases tenues : pas d'héritage")
		T.ok(type(session.holdCells) == "table", "table des cases tenues présente")
	end)
end
