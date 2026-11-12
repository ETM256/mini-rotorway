return function(T, H)
	-- Profil : DataStore indisponible, schéma, bornes des scores et sauvegardes.

	local STORE = "MiniMotorwaysV1"

	-- Le magasin est créé au chargement du module Profile.
	local function storeData()
		H.load("Profile")
		return H.W.dataStores[STORE]._data
	end

	T.test("without a DataStore the game runs and scores stay in memory", function()
		H.W.dataStoreError = "API Services indisponible"
		H.runScript("Bootstrap")
		H.localPlayer = H.asClient()
		H.fireServer("StartGame", "los_angeles")
		H.advance(5)
		T.ok(H.lastSent("GameStarted"), "the game starts")
		T.eq(#H.handlerErrors, 0)

		local Profile = H.load("Profile")
		local player = H.localPlayer
		T.eq(Profile.submit(player, "los_angeles", 250), 250)
		T.eq(Profile.submit(player, "los_angeles", 100), 250, "the best score is kept")
		T.eq(Profile.getBest(player, "los_angeles"), 250)
		T.ok(#H.warnings > 0, "the outage is reported")
	end)

	T.test("the in-memory best is written once the DataStore comes back", function()
		H.W.dataStoreError = "down"
		H.runScript("Bootstrap")
		local player = H.asClient()
		H.fireServer("StartGame", "los_angeles")
		H.advance(5)
		H.load("Profile").submit(player, "los_angeles", 250)

		H.W.dataStoreError = nil
		H.advance(H.load("Profile").AUTOSAVE_SECONDS + 20, { frames = false })
		local saved = storeData()["player_" .. player.UserId]
		T.ok(saved, "the profile is written")
		T.eq(saved.records.los_angeles, 250)
	end)

	T.test("a profile that failed to load is never overwritten by an empty copy", function()
		local Profile = H.load("Profile")
		storeData()["player_1001"] = { schema = 2, records = { los_angeles = 500 } }
		H.W.dataStoreError = "down"
		H.runScript("Bootstrap")
		local player = H.asClient()
		H.fireServer("StartGame", "los_angeles")
		H.advance(5)

		T.eq(Profile.submit(player, "los_angeles", 100), 100, "a lower score while unloaded")
		T.eq(Profile.save(player), false, "a save is refused while the profile is not loaded")
		T.eq(storeData()["player_1001"].records.los_angeles, 500, "the stored record is untouched")

		H.W.dataStoreError = nil
		H.advance(H.load("Profile").AUTOSAVE_SECONDS + 20, { frames = false })
		T.eq(storeData()["player_1001"].records.los_angeles, 500, "the merge keeps the stored best")
	end)

	T.test("the legacy flat format is read, sanitised and rewritten as schema 2", function()
		storeData()["player_1001"] = { los_angeles = 300, junk = "x", bad = -5 }
		local Profile = H.load("Profile")
		local player = H.asClient()
		local records = Profile.load(player)
		T.eq(records.los_angeles, 300)
		T.eq(records.junk, nil, "a non-numeric value is dropped")
		T.eq(records.bad, nil, "a negative score is dropped")
		T.eq(Profile.submit(player, "los_angeles", 200), 300, "a lower score does not replace the best")
		T.eq(Profile.save(player), true)
		local saved = storeData()["player_1001"]
		T.eq(saved.schema, 2)
		T.eq(saved.records.los_angeles, 300)
	end)

	T.test("scores are clamped and invalid input never changes the record", function()
		local Profile = H.load("Profile")
		local player = H.asClient()
		T.eq(Profile.submit(player, "los_angeles", 1e20), 1e9, "clamped to the maximum")
		T.eq(Profile.submit(player, "los_angeles", 0 / 0), 1e9, "NaN is ignored")
		T.eq(Profile.submit(player, "los_angeles", -5), 1e9, "a negative score is ignored")
		T.eq(Profile.submit(player, "los_angeles", math.huge), 1e9, "infinity is ignored")
		T.eq(Profile.submit(player, 42, 10), 0, "a non-string map id is rejected")
		T.eq(Profile.submit(player, string.rep("m", 100), 10), 0, "an overlong map id is rejected")
		T.eq(Profile.getBest(player, "los_angeles"), 1e9)
	end)

	T.test("reset empties the profile in memory and in the DataStore", function()
		local Profile = H.load("Profile")
		local player = H.asClient()
		Profile.submit(player, "los_angeles", 300)
		T.eq(Profile.reset(player), true)
		T.eq(Profile.getBest(player, "los_angeles"), 0)
		T.eq(next(storeData()["player_1001"].records), nil, "the stored records are cleared")
	end)

	T.test("a submit on an unloaded player does not yield and is merged later", function()
		H.W.dataStoreError = "down"
		local Profile = H.load("Profile")
		local player = H.asClient()
		T.eq(Profile.submit(player, "tokyo", 80), 80, "returns the score without waiting")
		H.W.dataStoreError = nil
		H.advance(H.load("Profile").AUTOSAVE_SECONDS + 20, { frames = false })
		T.eq(Profile.getBest(player, "tokyo"), 80, "the score is kept once the profile loads")
	end)

	T.test("a player who leaves during a failing save keeps the score until the store is back", function()
		H.runScript("Bootstrap")
		local Profile = H.load("Profile")
		local player = H.newPlayer("Saver", 6003)
		H.localPlayer = player
		H.fireServer("RequestProfile")
		H.advance(0.1)
		Profile.submit(player, "los_angeles", 250)

		-- Une écriture lente échoue à chaque tentative ; le joueur part pendant qu'elle est en vol.
		local store = H.W.dataStores.MiniMotorwaysV1
		local real = store.SetAsync
		store.SetAsync = function(self, key, value)
			task.wait(0.5)
			return real(self, key, value)
		end
		H.W.dataStoreError = "down"
		task.spawn(Profile.save, player)
		H.advance(0.2)
		H.I.fire(H.I.getSignal(game.Players, "PlayerRemoving"), player)
		H.advance(15)
		H.W.dataStoreError = nil
		H.advance(Profile.AUTOSAVE_SECONDS + 20, { frames = false })

		local saved = storeData()["player_6003"]
		T.ok(saved, "the profile is written once the store is back")
		T.eq(saved.records.los_angeles, 250, "the score was not dropped with the cache entry")
	end)
end
