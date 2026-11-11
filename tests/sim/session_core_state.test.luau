-- Envois de l'état au client (remote State) : au plus 5 Hz en temps réel, et
-- aucun envoi pour un état identique au précédent.
return function(T, H)
	local Config = H.load("Config")

	T.test("State is sent at most every StateInterval of real time while the game runs", function()
		local session = H.newSession("los_angeles")
		session:setSpeed(3)
		local before = #H.sent("State")
		-- 20 s réelles à vitesse 3 : 60 s simulées, mais 5 Hz en temps réel.
		H.runSession(session, 20, 0.1, { autoChoose = false })
		local sent = #H.sent("State") - before
		local ceiling = math.floor(20 / Config.Time.StateInterval) + 1
		T.le(sent, ceiling, "au plus 5 envois par seconde réelle")
		T.ge(sent, ceiling - 5, "l'interface reçoit bien son flux à 5 Hz")
	end)

	T.test("an unchanged state is not sent twice", function()
		local session = H.newSession("los_angeles")
		session:sendState()
		local before = #H.sent("State")
		session:sendState()
		session:sendState()
		T.eq(#H.sent("State") - before, 0, "deux appels sans changement : aucun envoi")
	end)

	T.test("a real change (speed) is sent at once, without waiting for the 5 Hz tick", function()
		local session = H.newSession("los_angeles")
		local before = #H.sent("State")
		session:setSpeed(2)
		local last = H.lastSent("State")
		T.eq(#H.sent("State") - before, 1, "un envoi immédiat")
		T.eq(last.speed, 2, "la vitesse annoncée est la nouvelle")
	end)
end
