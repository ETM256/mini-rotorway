return function(T, H)
	-- Theme.button et la carte lisent os.clock pour le anti double-clic : le
	-- harnais virtualise os.clock, on avance donc l'horloge entre deux clics.
	local function realWait(seconds)
		H.flush(seconds)
	end

	local function newLobby(calls)
		H.asClient()
		local Lobby = H.load("Lobby")
		calls = calls or {}
		local lobby = Lobby.new({
			onPlay = function()
				table.insert(calls, "play")
			end,
			onQuit = function()
				table.insert(calls, "quit")
			end,
			onStartMap = function(mapId)
				table.insert(calls, "start:" .. tostring(mapId))
			end,
			onResetRecords = function()
				table.insert(calls, "reset")
			end,
		})
		return lobby, calls
	end

	local function buttonWithText(root, text)
		for _, button in ipairs(H.find(root, { class = "GuiButton" })) do
			if button.Text == text then
				return button
			end
		end
		return nil
	end

	T.test("the decoration animates while the menu is visible and pauses when hidden", function()
		local lobby = newLobby()
		lobby:show()
		T.ok(lobby.frameConnection, "boucle d'animation active sur le menu")
		local first = lobby.decorCars[1].body.Position
		H.advance(1)
		T.ne(lobby.decorCars[1].body.Position, first, "la voiture avance")

		lobby:hide()
		T.falsy(lobby.frameConnection, "boucle coupée quand le lobby est caché")
		local frozen = lobby.decorCars[1].body.Position
		H.advance(1)
		T.eq(lobby.decorCars[1].body.Position, frozen, "aucune animation quand le lobby est caché")

		lobby:show()
		T.ok(lobby.frameConnection, "boucle reprise à l'affichage")
		lobby:destroy()
	end)

	T.test("the animation loop is never connected twice and stops in portrait", function()
		local lobby = newLobby()
		lobby:show()
		local connection = lobby.frameConnection
		lobby:show()
		lobby:showMain()
		T.eq(lobby.frameConnection, connection, "une seule connexion RenderStepped")
		H.setViewport(390, 844)
		lobby:updateResponsive()
		T.falsy(lobby.frameConnection, "décor masqué en portrait : pas d'animation")
		H.setViewport(1280, 720)
		lobby:updateResponsive()
		T.ok(lobby.frameConnection, "décor de retour en paysage")
		lobby:destroy()
	end)

	T.test("repeated show, hide and page switches create no instance", function()
		local lobby = newLobby()
		lobby:show()
		lobby:showMaps()
		lobby:showMain()
		local count = H.instanceCount()
		for _ = 1, 12 do
			lobby:show()
			lobby:showMaps()
			lobby:showMain()
			lobby:showOptions()
			lobby:showRecords()
			lobby:hide()
			lobby:show()
			lobby:toast("Records réinitialisés")
			lobby:setProfile({ los_angeles = 10 })
		end
		T.eq(H.instanceCount(), count, "aucune instance créée ou perdue en boucle")
		lobby:destroy()
	end)

	T.test("destroy disconnects every connection and leaves no instance behind", function()
		H.asClient()
		local Lobby = H.load("Lobby")
		local connectionsBefore = H.connectionCount()
		local instancesBefore = H.instanceCount()
		local lobby = Lobby.new({})
		lobby:show()
		lobby:showMaps()
		H.advance(1)
		T.gt(H.connectionCount(), connectionsBefore, "le lobby crée des connexions")
		lobby:destroy()
		T.eq(H.connectionCount(), connectionsBefore, "aucune connexion ne survit à destroy")
		T.eq(H.instanceCount(), instancesBefore, "l'interface est entièrement retirée")
		T.falsy(lobby.frameConnection)
	end)

	T.test("calls on a destroyed lobby are harmless", function()
		local lobby = newLobby()
		lobby:show()
		lobby:destroy()
		T.noThrow(function()
			lobby:destroy()
			lobby:show()
			lobby:hide()
			lobby:showMaps()
			lobby:toast("trop tard")
			lobby:setProfile({ los_angeles = 3 })
			lobby:updateResponsive()
			H.advance(3)
		end)
		T.eq(#H.handlerErrors, 0, "aucune erreur après destroy")
	end)

	T.test("the reset button needs a second click and disarms by itself", function()
		local calls = {}
		local lobby = newLobby(calls)
		lobby:showOptions()
		local reset = buttonWithText(lobby.optionsOverlay, "Réinitialiser mes records")
		T.ok(reset, "bouton de réinitialisation présent")

		H.click(reset)
		T.eq(reset.Text, "Confirmer ?", "le premier clic arme le bouton")
		T.eq(#calls, 0, "rien n'est effacé au premier clic")

		realWait(0.13)
		H.click(reset)
		T.eq(calls[#calls], "reset", "le second clic efface les records")
		T.eq(reset.Text, "Réinitialiser mes records", "le bouton revient à son état normal")

		realWait(0.13)
		H.click(reset)
		T.eq(reset.Text, "Confirmer ?", "un nouveau premier clic réarme")
		H.advance(4)
		T.eq(reset.Text, "Réinitialiser mes records", "l'armement expire seul")
		local resets = 0
		for _, call in ipairs(calls) do
			if call == "reset" then
				resets += 1
			end
		end
		T.eq(resets, 1, "un seul effacement pour deux clics confirmés")
		lobby:destroy()
	end)

	T.test("the main menu opens records and statistics directly", function()
		local lobby = newLobby()
		lobby:show()
		local records = buttonWithText(lobby.menu, "Palmarès")
		local stats = buttonWithText(lobby.menu, "Statistiques")
		T.ok(records, "entrée Palmarès dans le menu principal")
		T.ok(stats, "entrée Statistiques dans le menu principal")
		H.click(records)
		T.ok(lobby.recordsOverlay.Visible, "le palmarès s'ouvre")
		lobby:hide()
		lobby:show()
		H.click(stats)
		T.ok(lobby.statsOverlay.Visible, "les statistiques s'ouvrent")
		lobby:destroy()
	end)

	T.test("the garage opens from the main menu, phones included", function()
		-- Le rail (seule autre entrée vers le garage) est caché en portrait et sur
		-- les écrans étroits : le menu principal doit donc offrir le garage partout.
		local resolutions = {
			{ 1920, 1080 },
			{ 1366, 768 },
			{ 844, 390 },
			{ 780, 360 },
			{ 740, 360 },
			{ 667, 375 },
			{ 568, 320 },
			{ 390, 844 },
		}
		for _, res in ipairs(resolutions) do
			local name = string.format("%dx%d", res[1], res[2])
			H.reset()
			local lobby = newLobby()
			H.setViewport(res[1], res[2])
			lobby:show()
			local garage = buttonWithText(lobby.menu, "Garage")
			T.ok(garage, "entrée Garage dans le menu principal " .. name)
			-- H.click ignore Visible : le bouton doit aussi être affiché, dans une page affichée.
			T.ok(lobby.mainPage.Visible and lobby.menu.Visible and garage.Visible, "entrée Garage affichée " .. name)
			T.falsy(lobby.garageOverlay.Visible, "le garage est fermé avant le clic " .. name)
			H.click(garage)
			T.ok(lobby.garageOverlay.Visible, "le garage s'ouvre " .. name)
			lobby:destroy()
		end
	end)

	T.test("a full profile fills every card, record and statistic", function()
		local Maps = H.load("Maps")
		local lobby = newLobby()
		local profile = {}
		local total = 0
		for index, map in ipairs(Maps.all()) do
			profile[map.id] = index * 10
			total += index * 10
		end
		lobby:setProfile(profile)
		local first = Maps.all()[1]
		T.contains(lobby.cards[first.id].bestLabel.Text, tostring(profile[first.id]))
		T.eq(lobby.statsLabels.total.Text, tostring(total))
		T.eq(lobby.statsLabels.played.Text, tostring(#Maps.all()))
		local last = Maps.all()[#Maps.all()]
		T.eq(lobby.statsLabels.bestMap.Text, last.name)
		T.eq(lobby.recordLabels[last.id].Text, tostring(profile[last.id]))
		lobby:destroy()
	end)

	T.test("an empty profile shows dashes and zero", function()
		local lobby = newLobby()
		lobby:setProfile({})
		for _, entry in pairs(lobby.cards) do
			T.eq(entry.bestLabel.Text, "Meilleur : -")
		end
		T.eq(lobby.statsLabels.total.Text, "0")
		T.eq(lobby.statsLabels.played.Text, "0")
		T.eq(lobby.statsLabels.bestMap.Text, "-")
		T.eq(lobby.statsLabels.average.Text, "-")
		lobby:destroy()
	end)

	T.test("malformed profile payloads never throw and count as zero", function()
		local Maps = H.load("Maps")
		local lobby = newLobby()
		local all = Maps.all()
		-- table.pack : un nil dans une liste ipairs couperait la boucle en silence.
		local payloads = table.pack(
			nil,
			"oops",
			42,
			true,
			{
				[all[1].id] = "bad",
				[all[2].id] = -5,
				[all[3].id] = 0 / 0,
				[all[4].id] = math.huge,
				[all[5].id] = {},
			}
		)
		T.eq(payloads.n, 5, "tous les cas mal formés sont testés")
		for index = 1, payloads.n do
			local payload = payloads[index]
			T.noThrow(function()
				lobby:setProfile(payload)
			end, "profil mal formé n°" .. index)
			T.eq(lobby.statsLabels.total.Text, "0", "total à zéro pour le cas n°" .. index)
			T.eq(lobby.statsLabels.played.Text, "0", "aucune ville jouée pour le cas n°" .. index)
			T.eq(lobby.recordLabels[all[1].id].Text, "-", "aucun record affiché pour le cas n°" .. index)
		end
		lobby:destroy()
	end)

	T.test("the rail icons are drawn from shapes, not from text glyphs", function()
		local lobby = newLobby()
		lobby:show()
		local rail = lobby.rail
		local buttons = H.find(rail, { class = "TextButton" })
		T.eq(#buttons, 4, "quatre entrées dans la colonne latérale")
		for _, button in ipairs(buttons) do
			T.eq(button.Text, "", "pas de caractère à afficher")
			local icon = H.find(button, { name = "Icon" })[1]
			T.ok(icon, "chaque entrée a une icône dessinée")
			T.ok(H.count(icon, "Frame") >= 2, "l'icône est faite de plusieurs formes")
		end
		lobby:destroy()
	end)

	T.test("a fractional score is shown as its whole part", function()
		local Maps = H.load("Maps")
		local lobby = newLobby()
		local map = Maps.all()[1]
		lobby:setProfile({ [map.id] = 12.7 })
		T.eq(lobby.recordLabels[map.id].Text, "12")
		lobby:destroy()
	end)

	T.test("a tie for best map keeps the map order, not the table order", function()
		local Maps = H.load("Maps")
		local lobby = newLobby()
		local first = Maps.all()[1]
		local second = Maps.all()[2]
		lobby:setProfile({ [second.id] = 9, [first.id] = 9 })
		T.eq(lobby.statsLabels.bestMap.Text, first.name)
		lobby:destroy()
	end)

	T.test("a second click on the selected card starts the map", function()
		local calls = {}
		local lobby = newLobby(calls)
		lobby:show()
		lobby:showMaps()
		local Maps = H.load("Maps")
		local target = Maps.all()[2]
		local hit = H.find(lobby.cards[target.id].card, { class = "TextButton" })[1]
		H.click(hit)
		T.eq(lobby.selectedId, target.id, "le premier clic sélectionne")
		T.eq(#calls, 0, "rien ne démarre au premier clic")
		realWait(0.13)
		H.click(hit)
		T.contains(calls, "start:" .. target.id, "le second clic rapide lance la ville")
		lobby:destroy()
	end)
end
