return function(T, H)
	local function newLobby()
		H.asClient()
		local Lobby = H.load("Lobby")
		return Lobby.new({})
	end

	local function buttonWithText(root, text)
		for _, button in ipairs(H.find(root, { class = "GuiButton" })) do
			if button.Text == text then
				return button
			end
		end
		return nil
	end

	local function uiScaleChildren(button)
		local count = 0
		for _, child in ipairs(button:GetChildren()) do
			if child:IsA("UIScale") then
				count += 1
			end
		end
		return count
	end

	-- Source du lobby sans commentaires : les tests de texte ne voient que ce
	-- qui sera réellement exécuté.
	local function lobbySource()
		for _, module in ipairs(H.sources()) do
			if string.find(module.file, "UI/Lobby.luau", 1, true) then
				return H.stripComments(module.source)
			end
		end
		return ""
	end

	T.test("every lobby button has at most one UIScale: no double scaling", function()
		local lobby = newLobby()
		lobby:show()
		lobby:showMaps()
		lobby:showMain()
		local buttons = H.find(lobby.gui, { class = "GuiButton" })
		T.gt(#buttons, 10, "le lobby contient plusieurs boutons")
		for _, button in ipairs(buttons) do
			T.le(uiScaleChildren(button), 1, "un seul UIScale par bouton : " .. button.Name)
		end
		lobby:destroy()
	end)

	T.test("hover and press use Theme.motion limits on menu buttons", function()
		local Theme = H.load("UI/Theme")
		local lobby = newLobby()
		lobby:show()
		local play = buttonWithText(lobby.menu, "Jouer")
		T.ok(play, "bouton Jouer présent")

		H.I.fire(H.I.getSignal(play, "MouseEnter"))
		H.advance(0.3)
		local scale = play:FindFirstChild("MotionScale")
		T.ok(scale, "le survol crée l'échelle de mouvement")
		T.near(scale.Scale, Theme.Motion.Hover, 1e-6, "survol à l'échelle du thème")
		T.le(scale.Scale, 1.04, "survol borné à 1.04")

		H.I.fire(H.I.getSignal(play, "MouseButton1Down"))
		H.advance(0.3)
		T.near(scale.Scale, Theme.Motion.Press, 1e-6, "clic à l'échelle du thème")

		H.I.fire(H.I.getSignal(play, "MouseButton1Up"))
		H.advance(0.3)
		T.near(scale.Scale, Theme.Motion.Hover, 1e-6, "relâché : retour au survol")

		H.I.fire(H.I.getSignal(play, "MouseLeave"))
		H.advance(0.3)
		T.near(scale.Scale, 1, 1e-6, "sorti : taille de repos")
		lobby:destroy()
	end)

	T.test("repeated hover and press cycles create no instance", function()
		local lobby = newLobby()
		lobby:show()
		local play = buttonWithText(lobby.menu, "Jouer")
		H.I.fire(H.I.getSignal(play, "MouseEnter"))
		H.advance(0.3)
		local count = H.instanceCount()
		for _ = 1, 20 do
			H.I.fire(H.I.getSignal(play, "MouseButton1Down"))
			H.advance(0.2)
			H.I.fire(H.I.getSignal(play, "MouseButton1Up"))
			H.I.fire(H.I.getSignal(play, "MouseLeave"))
			H.advance(0.2)
			H.I.fire(H.I.getSignal(play, "MouseEnter"))
			H.advance(0.2)
		end
		T.eq(H.instanceCount(), count, "survol et clic répétés ne créent aucune instance")
		T.eq(uiScaleChildren(play), 1, "toujours un seul UIScale")
		lobby:destroy()
	end)

	T.test("destroying the lobby releases the hover connections of its buttons", function()
		H.asClient()
		local Lobby = H.load("Lobby")
		local before = H.connectionCount()
		local lobby = Lobby.new({})
		lobby:show()
		lobby:showMaps()
		local buttons = H.find(lobby.gui, { class = "GuiButton" })
		T.gt(H.connectionCount(), before, "le lobby crée des connexions")
		lobby:destroy()
		T.eq(H.connectionCount(), before, "aucune connexion de survol ne survit à destroy")
		for _, button in ipairs(buttons) do
			T.falsy(button:FindFirstChild("MotionScale"), "échelle retirée avec le bouton")
		end
	end)

	T.test("the title and the about text show Config.GameName", function()
		local Config = H.load("Config")
		local lobby = newLobby()
		local titles = {}
		for _, label in ipairs(H.find(lobby.titleHolder, { class = "TextLabel" })) do
			table.insert(titles, label.Text)
		end
		T.contains(titles, Config.GameName, "le titre vient de Config.GameName")

		local aboutText = {}
		for _, label in ipairs(H.find(lobby.aboutOverlay, { class = "TextLabel" })) do
			table.insert(aboutText, label.Text)
		end
		local found = false
		for _, text in ipairs(aboutText) do
			if string.find(text, Config.GameName, 1, true) then
				found = true
			end
		end
		T.ok(found, "le texte À propos cite Config.GameName")
		lobby:destroy()
	end)

	T.test("the lobby source never hard-codes the game name", function()
		local Config = H.load("Config")
		local source = lobbySource()
		T.ok(#source > 1000, "source du lobby lue")
		T.falsy(string.find(source, "Mini Rotorway", 1, true), "pas de nom de jeu en dur")
		if Config.GameName ~= "Mini Motorways" then
			T.falsy(string.find(source, '"' .. Config.GameName .. '"', 1, true), "nom du jeu lu dans Config")
		end
	end)

	T.test("no risky Unicode glyph and no inline colour in the lobby code", function()
		local source = lobbySource()
		-- Tiret long (U+2014), « ‹ » (U+2039) : pas garantis dans la police Roblox.
		T.falsy(string.find(source, "\226\128\148", 1, true), "pas de tiret long")
		T.falsy(string.find(source, "\226\128\185", 1, true), "pas de chevron Unicode")
		T.falsy(string.find(source, "Color3.new", 1, true), "pas de couleur écrite en dur")
		T.falsy(string.find(source, "Color3.fromRGB", 1, true), "pas de couleur écrite en dur")
		T.falsy(string.find(source, "Color3.fromHex", 1, true), "pas de couleur écrite en dur")
	end)

	T.test("the back button draws its arrow and keeps the label plain", function()
		local lobby = newLobby()
		lobby:show()
		lobby:showMaps()
		T.eq(lobby.backButton.Text, "Retour", "texte simple, sans glyphe")
		T.ok(H.count(lobby.backButton, "Frame") >= 2, "la flèche est faite de deux barres")
		lobby:destroy()
	end)

	T.test("the info button is a true circle at any size", function()
		local Theme = H.load("UI/Theme")
		local lobby = newLobby()
		lobby:show()
		local corner = lobby.infoButton:FindFirstChildOfClass("UICorner")
		T.ok(corner, "le bouton info a un coin arrondi")
		T.eq(corner.CornerRadius.Offset, Theme.Radius.Pill, "rayon pilule du thème")
		T.eq(corner.CornerRadius.Scale, 0)
		lobby:destroy()
	end)
end
