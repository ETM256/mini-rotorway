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

	T.test("a save merges the stored best of other servers instead of overwriting it", function()
		storeData()["player_1001"] = { schema = 2, records = { tokyo = 300, los_angeles = 100 } }
		local Profile = H.load("Profile")
		local player = H.asClient()
		Profile.load(player)
		-- Un autre serveur écrit de meilleurs scores pendant que ce cache est en mémoire.
		storeData()["player_1001"] = { schema = 2, records = { tokyo = 500, los_angeles = 900 } }

		T.eq(Profile.submit(player, "tokyo", 320), 320)
		T.eq(Profile.submit(player, "kyoto", 40), 40)
		T.eq(Profile.save(player), true)
		local saved = storeData()["player_1001"].records
		T.eq(saved.tokyo, 500, "the record written elsewhere is kept")
		T.eq(saved.los_angeles, 900, "a stale lower copy never lowers a record")
		T.eq(saved.kyoto, 40, "the local score is written")
		T.eq(Profile.getBest(player, "tokyo"), 500, "the cache takes the merged best")
		T.eq(Profile.getBest(player, "los_angeles"), 900)
	end)

	T.test("reset wipes the records another server wrote since the load", function()
		storeData()["player_1001"] = { schema = 2, records = { tokyo = 300 } }
		local Profile = H.load("Profile")
		local player = H.asClient()
		Profile.load(player)
		storeData()["player_1001"] = { schema = 2, records = { tokyo = 500 } }

		T.eq(Profile.reset(player), true)
		T.eq(Profile.getBest(player, "tokyo"), 0)
		T.eq(next(storeData()["player_1001"].records), nil, "nothing is merged back")
	end)

	T.test("a save in flight when reset is called cannot bring the old records back", function()
		storeData()["player_1001"] = { schema = 2, records = { tokyo = 300 } }
		local Profile = H.load("Profile")
		local player = H.asClient()
		Profile.load(player)
		Profile.submit(player, "tokyo", 350)
		-- Écriture lente : la fusion est calculée au départ (avec les scores d'avant la
		-- réinitialisation), la réponse n'arrive qu'après : elle est encore en vol quand
		-- la réinitialisation arrive.
		local store = H.W.dataStores.MiniMotorwaysV1
		local real = store.UpdateAsync
		store.UpdateAsync = function(self, key, fn)
			local result = real(self, key, fn)
			task.wait(1)
			return result
		end
		task.spawn(Profile.save, player)
		H.advance(0.2, { frames = false })

		local resetOk = nil
		task.spawn(function()
			resetOk = Profile.reset(player)
		end)
		H.advance(5, { frames = false })
		T.eq(resetOk, true, "the reset is written")
		T.eq(Profile.getBest(player, "tokyo"), 0, "the in-flight write does not refill the cache")
		T.eq(next(storeData()["player_1001"].records), nil, "the stored records are cleared")
	end)

	T.test("a score submitted while a save is in flight is neither lowered nor lost", function()
		local Profile = H.load("Profile")
		local player = H.asClient()
		Profile.load(player)
		T.eq(Profile.submit(player, "tokyo", 350), 350)
		local store = H.W.dataStores.MiniMotorwaysV1
		local real = store.UpdateAsync
		store.UpdateAsync = function(self, key, fn)
			local result = real(self, key, fn)
			task.wait(1)
			return result
		end
		task.spawn(Profile.save, player)
		H.advance(0.2, { frames = false })
		T.eq(Profile.submit(player, "tokyo", 400), 400, "a better score arrives mid-write")
		H.advance(2, { frames = false })
		T.eq(Profile.getBest(player, "tokyo"), 400, "the answer of the write does not lower the cache")

		store.UpdateAsync = real
		T.eq(Profile.save(player), true)
		T.eq(storeData()["player_1001"].records.tokyo, 400, "the entry was reopened and the score is written")
	end)

	T.test("a reset that could not be written is retried as an overwrite", function()
		storeData()["player_1001"] = { schema = 2, records = { tokyo = 300 } }
		local Profile = H.load("Profile")
		local player = H.asClient()
		Profile.load(player)

		H.W.dataStoreError = "down"
		local resetOk = nil
		task.spawn(function()
			resetOk = Profile.reset(player)
		end)
		H.advance(20, { frames = false })
		T.eq(resetOk, false, "the reset fails while the store is down")
		T.eq(storeData()["player_1001"].records.tokyo, 300, "the store is untouched meanwhile")

		H.W.dataStoreError = nil
		T.eq(Profile.submit(player, "kyoto", 40), 40)
		T.eq(Profile.save(player), true)
		local saved = storeData()["player_1001"].records
		T.eq(saved.tokyo, nil, "the record erased by the reset does not come back from the store")
		T.eq(saved.kyoto, 40, "the score submitted since is written")
	end)

	T.test("once a reset is written, the next saves merge with the store again", function()
		storeData()["player_1001"] = { schema = 2, records = { tokyo = 300 } }
		local Profile = H.load("Profile")
		local player = H.asClient()
		Profile.load(player)
		T.eq(Profile.reset(player), true)
		storeData()["player_1001"] = { schema = 2, records = { tokyo = 500 } }

		T.eq(Profile.submit(player, "kyoto", 40), 40)
		T.eq(Profile.save(player), true)
		local saved = storeData()["player_1001"].records
		T.eq(saved.tokyo, 500, "the record written elsewhere after the reset is kept")
		T.eq(saved.kyoto, 40)
		T.eq(Profile.getBest(player, "tokyo"), 500)
	end)

	T.test("a save whose function is called again after a conflict writes only the last result", function()
		storeData()["player_1001"] = { schema = 2, records = { tokyo = 300 } }
		local Profile = H.load("Profile")
		local player = H.asClient()
		Profile.load(player)
		T.eq(Profile.submit(player, "kyoto", 40), 40)

		-- Comme Roblox après un conflit : la fonction voit d'abord une valeur périmée,
		-- son résultat est jeté, puis elle est rappelée sur la valeur courante.
		local store = H.W.dataStores.MiniMotorwaysV1
		local real = store.UpdateAsync
		local calls = 0
		store.UpdateAsync = function(self, key, fn)
			local function counted(value)
				calls += 1
				return fn(value)
			end
			return real(self, key, function(current)
				counted({ schema = 2, records = { osaka = 999 } })
				return counted(current)
			end)
		end

		T.eq(Profile.save(player), true)
		T.eq(calls, 2, "the function ran twice")
		local saved = storeData()["player_1001"].records
		T.eq(saved.osaka, nil, "the discarded call leaves nothing in the store")
		T.eq(saved.tokyo, 300)
		T.eq(saved.kyoto, 40)
		T.eq(Profile.getBest(player, "osaka"), 0, "nor in the cache")
	end)

	T.test("a save over unusable stored data does not fail and keeps the valid records", function()
		local Profile = H.load("Profile")
		local player = H.asClient()
		Profile.load(player)
		T.eq(Profile.submit(player, "tokyo", 10), 10)

		storeData()["player_1001"] = {
			schema = 2,
			records = { tokyo = -5, kyoto = 0 / 0, osaka = "x", paris = 200, [7] = 3 },
			extra = "ignored",
		}
		T.eq(Profile.save(player), true, "invalid entries do not abort the write")
		local saved = storeData()["player_1001"].records
		T.eq(saved.tokyo, 10, "a negative stored score never beats a valid one")
		T.eq(saved.paris, 200, "a valid stored record is kept")
		T.eq(saved.kyoto, nil)
		T.eq(saved.osaka, nil)
		T.eq(saved[7], nil)

		storeData()["player_1001"] = "garbage"
		T.eq(Profile.submit(player, "tokyo", 20), 20)
		T.eq(Profile.save(player), true, "a non-table stored value does not abort the write")
		saved = storeData()["player_1001"].records
		T.eq(saved.tokyo, 20)
		T.eq(saved.paris, 200, "the cache already holds the earlier merge")
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
		local real = store.UpdateAsync
		store.UpdateAsync = function(self, key, fn)
			task.wait(0.5)
			return real(self, key, fn)
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
