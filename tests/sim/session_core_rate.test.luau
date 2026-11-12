-- Débit des remotes (Bootstrap) : un geste de construction normal, même rapide,
-- n'est jamais freiné ; une rafale est bornée par le seau à jetons.
return function(T, H)
	local function startAs(player)
		H.localPlayer = player
		H.fireServer("StartGame", "los_angeles")
		H.advance(0.2)
	end

	-- Compte les tracés de route réellement acceptés par Session.
	local function countDraws()
		local Session = H.load("Session")
		local calls = 0
		local original = Session.drawRoad
		Session.drawRoad = function(self, cells)
			calls += 1
			return original(self, cells)
		end
		return function()
			return calls
		end
	end

	-- Le client n'envoie DrawRoad qu'au relâchement du geste (InputController) :
	-- un geste par relâchement, pas une requête par mouvement de souris.
	T.test("a normal fast drag (four strokes a second) is never throttled", function()
		H.runScript("Bootstrap")
		startAs(H.newPlayer("Drawer", 3001))
		local calls = countDraws()
		-- Quarante gestes en dix secondes : plus que la rafale, donc le débit
		-- soutenu (8 par seconde) est bien ce qui est mesuré.
		for i = 1, 40 do
			H.fireServer("DrawRoad", { { i % 16 + 1, 2 } })
			H.advance(0.25)
		end
		T.eq(calls(), 40, "quarante gestes en dix secondes passent tous")
	end)

	T.test("a flood in one instant is capped at the DrawRoad burst", function()
		H.runScript("Bootstrap")
		startAs(H.newPlayer("Flooder", 3002))
		local calls = countDraws()
		for _ = 1, 100 do
			H.fireServer("DrawRoad", { { 1, 1 } })
		end
		T.le(calls(), 20, "la rafale est bornée au seau (burst = 20)")
		T.ge(calls(), 1, "les premières requêtes sont servies")
	end)
end
