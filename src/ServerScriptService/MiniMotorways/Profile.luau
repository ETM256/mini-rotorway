--[[
	Profile.luau
	Meilleurs scores par carte, sauvegardés dans un DataStore.

	Règles de sûreté des données :
	  - le cache mémoire n'est jamais jeté tant qu'une écriture n'a pas réussi ;
	  - un profil dont la lecture a échoué n'est jamais écrit : une table vide
	    écrite par-dessus les vrais scores les effacerait. Il est relu plus tard
	    et les deux copies sont fusionnées (meilleur score par carte) ;
	  - l'écriture est une fusion (UpdateAsync) : le meilleur score par carte
	    gagne entre le magasin et le cache, même si un autre serveur a écrit
	    entre-temps. Seule une réinitialisation écrase le magasin ;
	  - submit ne bloque jamais : il est appelé à la fin d'une partie, dans le
	    Heartbeat. La sauvegarde a lieu à intervalle régulier, à la sortie du
	    joueur et à la fermeture du serveur.
	En Studio sans API Services, tout fonctionne quand même : les scores restent
	en mémoire pour la session.
]]

local DataStoreService = game:GetService("DataStoreService")

local Profile = {}

-- Nom historique conservé : les scores déjà enregistrés restent lisibles.
local STORE_NAME = "MiniMotorwaysV1"
-- Schéma 2 : { schema = 2, records = { [mapId] = meilleur score } }.
-- Le schéma 1 (table plate mapId -> score) est lu puis réécrit en schéma 2.
local SCHEMA_VERSION = 2
local MAX_SCORE = 1e9
local MAX_MAP_ID_LENGTH = 64
local LOAD_ATTEMPTS = 3
local SAVE_ATTEMPTS = 4
local RETRY_BASE_SECONDS = 1
local RELOAD_SECONDS = 15
local FLUSH_TIMEOUT_SECONDS = 25
local SAVE_POLL_SECONDS = 0.1

-- Intervalle des sauvegardes régulières (utilisé par Bootstrap).
Profile.AUTOSAVE_SECONDS = 60

local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[MiniMotorways] DataStore unavailable: " .. tostring(result))
	end
end

-- cache[userId] = { userId, key, records, loaded, dirty, saving, overwrite, departed }
local cache = {}
-- Lectures en cours (userId -> true). Le profil est demandé à l'arrivée du
-- joueur et au lancement de sa première partie : sans cela, deux lectures
-- simultanées doubleraient les appels GetAsync (quota) et les tentatives.
local loading = {}

local function keyFor(userId)
	return "player_" .. tostring(userId)
end

-- Un score est un nombre fini, positif, entier et borné. Tout le reste est rejeté.
local function cleanScore(value)
	local n = tonumber(value)
	if not n or n ~= n or math.abs(n) == math.huge or n < 0 then
		return nil
	end
	return math.min(math.floor(n), MAX_SCORE)
end

local function bestOf(records, mapId)
	return cleanScore(records[mapId]) or 0
end

-- Lit une valeur stockée (schéma 2 ou ancien schéma plat) et ne garde que des
-- entrées valides. Une valeur inconnue donne un profil vide.
local function decode(value)
	local records = {}
	if type(value) ~= "table" then
		return records
	end
	local source = value
	if value.schema == SCHEMA_VERSION and type(value.records) == "table" then
		source = value.records
	end
	for mapId, raw in pairs(source) do
		local score = cleanScore(raw)
		if
			type(mapId) == "string"
			and #mapId > 0
			and #mapId <= MAX_MAP_ID_LENGTH
			and mapId ~= "schema"
			and mapId ~= "records"
			and score
		then
			records[mapId] = score
		end
	end
	return records
end

-- Lecture avec nouvelles tentatives espacées. Retourne (true, valeur), ou
-- (false) si le magasin reste injoignable : le profil est alors non chargé.
local function fetch(key)
	if not store then
		return true, nil
	end
	for attempt = 1, LOAD_ATTEMPTS do
		local ok, value = pcall(function()
			return store:GetAsync(key)
		end)
		if ok then
			return true, value
		end
		warn("[MiniMotorways] Could not load profile (essai " .. attempt .. "/" .. LOAD_ATTEMPTS .. "): " .. tostring(value))
		if attempt < LOAD_ATTEMPTS then
			task.wait(RETRY_BASE_SECONDS * 2 ^ (attempt - 1))
		end
	end
	return false, nil
end

-- Fusion sans perte : pour chaque carte, le meilleur score gagne. Le résultat
-- est réécrit au prochain passage de sauvegarde.
local function mergeStored(entry, stored)
	for mapId, score in pairs(stored) do
		if bestOf(entry.records, mapId) < score then
			entry.records[mapId] = score
		end
	end
	entry.dirty = true
end

local reloadUntilLoaded

-- Relance la lecture d'un profil resté non chargé, jusqu'à réussite ou jusqu'à
-- ce que l'entrée ne soit plus en cache (joueur parti sans rien à sauver).
reloadUntilLoaded = function(entry)
	while cache[entry.userId] == entry and not entry.loaded do
		task.wait(RELOAD_SECONDS)
		if cache[entry.userId] == entry and not entry.loaded then
			local ok, value = fetch(entry.key)
			if ok then
				mergeStored(entry, decode(value))
				entry.loaded = true
			end
		end
	end
end

-- Contenu à écrire, calculé sur la valeur stockée au moment de l'écriture
-- (UpdateAsync peut le recalculer après un conflit). Le meilleur score par carte
-- gagne entre le magasin et le cache ; après une réinitialisation, seul le cache compte.
-- Appelée dans UpdateAsync : elle n'attend jamais, ne modifie pas l'entrée et ne
-- renvoie jamais nil (ce qui annulerait l'écriture).
local function recordsToWrite(entry, old)
	local records = {}
	if not entry.overwrite then
		records = decode(old)
	end
	for mapId, score in pairs(entry.records) do
		if bestOf(records, mapId) < score then
			records[mapId] = score
		end
	end
	return records
end

-- Écrit une entrée modifiée (fusionnée avec le magasin), avec nouvelles tentatives
-- espacées. Une entrée non chargée n'est jamais écrite (voir l'en-tête). Ne doit pas
-- être appelée dans le Heartbeat : elle attend entre les essais.
local function saveEntry(entry)
	if not store then
		entry.dirty = false
		return true
	end
	-- Une écriture déjà en cours : on attend son résultat, même si `dirty` est
	-- déjà repassé à faux (il l'est pendant l'écriture), sinon la sortie du
	-- joueur libérerait une entrée dont l'écriture peut encore échouer.
	if entry.saving then
		while entry.saving do
			task.wait(SAVE_POLL_SECONDS)
		end
		return not entry.dirty
	end
	if not entry.dirty then
		return true
	end
	if not entry.loaded then
		return false
	end

	entry.saving = true
	local written = false
	local committed = nil
	for attempt = 1, SAVE_ATTEMPTS do
		-- Une modification pendant l'écriture rouvre l'entrée : elle sera réécrite.
		entry.dirty = false
		local ok, value = pcall(function()
			return store:UpdateAsync(entry.key, function(old)
				return { schema = SCHEMA_VERSION, records = recordsToWrite(entry, old) }
			end)
		end)
		if ok then
			written = true
			-- La valeur réellement écrite, quel que soit le nombre d'appels de la fonction.
			committed = value
			break
		end
		entry.dirty = true
		warn("[MiniMotorways] Could not save profile (essai " .. attempt .. "/" .. SAVE_ATTEMPTS .. "): " .. tostring(value))
		if attempt < SAVE_ATTEMPTS then
			task.wait(RETRY_BASE_SECONDS * 2 ^ (attempt - 1))
		end
	end
	entry.saving = false
	if written then
		-- Le cache reprend les meilleurs scores écrits (ceux des autres serveurs), sans jamais baisser.
		for mapId, score in pairs(decode(committed)) do
			if bestOf(entry.records, mapId) < score then
				entry.records[mapId] = score
			end
		end
		entry.overwrite = false
	end
	-- Joueur parti dont la dernière écriture vient d'aboutir : le cache peut être libéré.
	if written and entry.departed and cache[entry.userId] == entry then
		cache[entry.userId] = nil
	end
	return written
end

-- Retourne la table des records du joueur (carte -> meilleur score). Peut
-- attendre le DataStore la première fois : à appeler hors Heartbeat.
function Profile.load(player)
	local userId = player.UserId
	local cached = cache[userId]
	if cached then
		-- Joueur revenu avant l'écriture de ses données : l'entrée reste en service.
		cached.departed = nil
		return cached.records
	end

	-- Une lecture est déjà en vol pour ce joueur : on attend son résultat.
	if loading[userId] then
		while loading[userId] do
			task.wait(SAVE_POLL_SECONDS)
		end
		cached = cache[userId]
		if cached then
			cached.departed = nil
			return cached.records
		end
		-- La première lecture n'a rien mis en cache (joueur parti) : on lit à notre tour.
	end

	local key = keyFor(userId)
	loading[userId] = true
	local ok, value = fetch(key)
	loading[userId] = nil
	-- Pendant la lecture, un autre appel a pu charger le même profil : le premier gagne.
	cached = cache[userId]
	if cached then
		return cached.records
	end

	local entry = {
		userId = userId,
		key = key,
		records = decode(value),
		loaded = ok,
		-- Un profil au format plat est réécrit en schéma 2 à la prochaine sauvegarde.
		dirty = ok and type(value) == "table" and value.schema ~= SCHEMA_VERSION,
		saving = false,
		-- Vrai après une réinitialisation, jusqu'à une écriture réussie.
		overwrite = false,
	}
	if player.Parent == nil then
		-- Joueur parti pendant la lecture : rien à garder en cache.
		return entry.records
	end
	cache[userId] = entry
	if not ok then
		task.spawn(reloadUntilLoaded, entry)
	end
	return entry.records
end

-- Sauvegarde immédiate du profil du joueur (sortie). Sans effet si rien n'a changé.
function Profile.save(player)
	local entry = cache[player.UserId]
	if not entry then
		return true
	end
	return saveEntry(entry)
end

-- Sauvegarde toutes les entrées modifiées, en parallèle, avec un délai maximal
-- (la fermeture du serveur accorde une trentaine de secondes).
function Profile.flushAll()
	local pending = {}
	for _, entry in pairs(cache) do
		-- Une écriture en cours a déjà remis `dirty` à faux : on l'attend aussi, la
		-- fermeture du serveur ne doit pas la couper avant son résultat.
		if entry.dirty or entry.saving then
			table.insert(pending, entry)
		end
	end
	if #pending == 0 then
		return
	end

	local remaining = #pending
	for _, entry in ipairs(pending) do
		task.spawn(function()
			pcall(saveEntry, entry)
			remaining -= 1
		end)
	end
	local deadline = tick() + FLUSH_TIMEOUT_SECONDS
	while remaining > 0 and tick() < deadline do
		task.wait(SAVE_POLL_SECONDS)
	end
end

-- Enregistre un score et renvoie le meilleur de la carte. N'attend jamais.
-- Si le profil n'est pas encore en cache, le score est fusionné dès que la
-- lecture aboutit, et la valeur renvoyée est alors le score seul.
function Profile.submit(player, mapId, score)
	local value = cleanScore(score)
	local validMap = type(mapId) == "string" and #mapId > 0 and #mapId <= MAX_MAP_ID_LENGTH
	local entry = cache[player.UserId]

	if not entry then
		if not (validMap and value) then
			return 0
		end
		task.spawn(function()
			local records = Profile.load(player)
			if bestOf(records, mapId) < value then
				records[mapId] = value
			end
			local loaded = cache[player.UserId]
			if loaded then
				loaded.dirty = true
			end
		end)
		return value
	end

	if not (validMap and value) then
		return bestOf(entry.records, mapId)
	end
	local best = bestOf(entry.records, mapId)
	if value > best then
		entry.records[mapId] = value
		best = value
		entry.dirty = true
	end
	return best
end

-- Meilleur score d'une carte. Peut attendre le DataStore (voir Profile.load).
function Profile.getBest(player, mapId)
	return bestOf(Profile.load(player), mapId)
end

-- Remet tous les records à zéro, en mémoire puis dans le DataStore. Refusé si le
-- profil n'a pas pu être lu : effacer une copie vide ne doit pas écraser les scores.
function Profile.reset(player)
	Profile.load(player)
	local entry = cache[player.UserId]
	if not entry or not entry.loaded then
		return false
	end
	-- Une écriture en vol fusionne encore l'ancien contenu : on attend son résultat
	-- avant de vider, sinon elle rendrait ses scores au cache.
	while entry.saving do
		task.wait(SAVE_POLL_SECONDS)
	end
	for mapId in pairs(entry.records) do
		entry.records[mapId] = nil
	end
	-- Écrasement : les écritures suivantes (y compris une reprise après échec) ne fusionnent plus.
	entry.overwrite = true
	entry.dirty = true
	return saveEntry(entry)
end

-- Libère le cache d'un joueur parti, sauf une modification non encore écrite :
-- elle reste en mémoire jusqu'à une sauvegarde réussie.
function Profile.forget(player)
	local entry = cache[player.UserId]
	if not entry then
		return
	end
	if entry.dirty or entry.saving then
		-- Libérée par saveEntry dès que l'écriture aboutit.
		entry.departed = true
	else
		cache[player.UserId] = nil
	end
end

return Profile
