-- Cycle de vie des magasins : cadence de diffusion en temps réel, libération
-- immédiate des réservations, destination joignable, tweens suivis et arrêtés.
return function(T, H)
	local StoreConfig = H.load("StoreConfig")

	T.test("diffusion : StoreState suit le temps réel, pas le temps simulé", function()
		local session = H.newSession("los_angeles")
		session.satisfaction = 1e9
		session.speed = 3
		local system = session.storeSystem
		local before = #H.sent("StoreState")
		-- Soixante pas de 1 s simulée = 20 s réelles à vitesse 3. Au rythme réel
		-- (1,5 s d'inactivité) : environ 13 diffusions ; si la cadence suivait
		-- le temps simulé, il y en aurait 40.
		for _ = 1, 60 do
			system.dirty = false
			system:update(1)
		end
		local sent = #H.sent("StoreState") - before
		T.le(sent, 20 / StoreConfig.Sync.IdleDelay + 8, "StoreState must be paced in real time, not in game time")
		session:destroy()
	end)

	T.test("réservations : une voiture retirée libère sa demande sur-le-champ", function()
		local session = H.newSession("los_angeles")
		session.satisfaction = 1e9
		H.runSession(session, 40, 0.1)
		local store = session.destinations[1]
		local house = store.houses[1]
		local demandId = session.storeSystem:claimDemand(store)
		T.ok(demandId ~= nil, "a demand must be available to claim")
		local reserved = store.reserved
		session:retireCar({ claim = true, dest = store, demandId = demandId, house = house, held = {} })
		T.eq(store.reserved, reserved - 1, "retiring the car releases the claim at once")
		T.falsy(store.reservedIds[demandId], "the released demand is no longer reserved")
		session:destroy()
	end)

	T.test("destination : un magasin injoignable reste le choix quand aucun autre n'existe", function()
		local session = H.newSession("los_angeles")
		local store = session.destinations[1]
		local house = store.houses[1]
		local seen = {}
		local found = session:findDestinationForHouse(house, false, function(candidate)
			table.insert(seen, candidate)
			return false
		end)
		T.eq(found, store, "the nearest same-colour store is kept so the car retries")
		T.eq(#seen, 1, "the predicate is asked about the candidate")
		T.eq(seen[1], store, "the predicate receives the store itself")
		session:destroy()
	end)

	T.test("tweens : une partie arrêtée ne laisse aucun tween suivi ni connexion", function()
		-- Les apparitions du départ sont encore en cours : rien n'a été avancé.
		local session = H.newSession("london")
		T.ok(next(session.tweens) ~= nil, "the scenario must have tweens in flight")
		session:destroy()
		T.eq(next(session.tweens), nil, "destroy leaves no tracked tween")
		T.eq(session.world, nil, "destroy removes the world")
	end)

	T.test("apparition : une maison nouvelle part transparente puis rejoint sa transparence", function()
		local session = H.newSession("los_angeles")
		session.satisfaction = 1e9
		local store = session.destinations[1]
		-- Un magasin plein n'accepte plus de maison par spawnHouse : on pose la
		-- maison directement à un emplacement valide autour de ce magasin.
		local x, y = session.storeSystem:findHouseSpot(store)
		T.ok(x ~= nil, "a house spot must exist around the store")
		local house = session.storeSystem:createHouse(store, x, y)
		local body = house.model:FindFirstChild("Body")
		T.eq(body.Transparency, 1, "a new house starts fully transparent")
		T.ok(next(session.tweens) ~= nil, "the house fade is tracked")
		H.advance(1)
		T.eq(body.Transparency, 0, "the house ends at its build transparency")
		T.eq(next(session.tweens), nil, "finished fades stop being tracked")
		session:destroy()
	end)
end
