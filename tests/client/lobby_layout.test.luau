return function(T, H)
	-- Résolutions du cahier des charges (9.5) + téléphones debout et couché.
	-- 780x360 : téléphone couché étroit, où la colonne d'icônes gêne les cartes.
	local RESOLUTIONS = {
		{ 1920, 1080 },
		{ 1600, 900 },
		{ 1366, 768 },
		{ 1280, 720 },
		{ 844, 390 },
		{ 780, 360 },
		{ 667, 375 },
		{ 390, 844 },
	}

	-- Largeur du titre (Config.GameName) et de ses pastilles, à taille normale,
	-- telle que la mesure le faux TextService du harnais (caractères x 92 / 2),
	-- puis décalage, pas et taille des pastilles (Lobby : 22, 34 x 2, 24).
	local TITLE_WIDTH = #H.load("Config").GameName * 92 * 0.5 + 22 + 2 * 34 + 24

	local function newLobby()
		H.asClient()
		local Lobby = H.load("Lobby")
		local lobby = Lobby.new({})
		return lobby, Lobby
	end

	local function label(w, h)
		return string.format("%dx%d", w, h)
	end

	T.test("the map page stays inside the screen at every resolution", function()
		H.asClient()
		local Lobby = H.load("Lobby")
		for _, res in ipairs(RESOLUTIONS) do
			local w, h = res[1], res[2]
			local L = Lobby.layoutFor(w, h, TITLE_WIDTH)
			local name = label(w, h)
			T.le(L.playTop + L.playHeight, h, "bouton Jouer dans l'écran " .. name)
			T.ge(L.playTop, 0, "bouton Jouer au-dessus du bord " .. name)
			if L.hintVisible then
				T.le(L.hintTop + 22, h, "astuce dans l'écran " .. name)
				T.le(L.playTop + L.playHeight, L.hintTop, "astuce sous le bouton " .. name)
			end
			T.le(L.scrollerTop + L.scrollerHeight, L.playTop, "cartes au-dessus de Jouer " .. name)
			T.le(L.scrollerX + L.scrollerWidth, 1, "cartes dans la largeur " .. name)
			T.ge(L.cardScale, 0.4, "échelle minimale " .. name)
			T.le(L.cardScale, 1, "pas d'agrandissement " .. name)
			T.le(L.cardHeight, L.scrollerHeight, "une carte entière tient en hauteur " .. name)
			T.le(L.backY * h + L.backHeight, L.scrollerTop, "retour au-dessus des cartes " .. name)
			T.le(L.subtitleY * h + 0.028 * h, L.scrollerTop, "sous-titre au-dessus des cartes " .. name)
		end
	end)

	T.test("the main menu, rail and info button stay inside the screen", function()
		H.asClient()
		local Lobby = H.load("Lobby")
		for _, res in ipairs(RESOLUTIONS) do
			local w, h = res[1], res[2]
			local L = Lobby.layoutFor(w, h, TITLE_WIDTH)
			local name = label(w, h)
			T.le(L.menuY * h + L.menuHeight, h, "menu principal dans l'écran " .. name)
			T.le(L.menuX + L.menuWidth, 1, "menu principal dans la largeur " .. name)
			T.le(L.infoX * w, w, "bouton info à droite " .. name)
			T.le(L.infoY * h, h, "bouton info en bas " .. name)
			T.le(L.infoSize, math.min(w, h), "bouton info plus petit que l'écran " .. name)
			if L.railVisible then
				T.ge(L.railTop, 0, "rail au-dessus du bord " .. name)
				T.le(L.railTop + L.railHeight, h, "rail dans l'écran " .. name)
			end
			T.le(L.destinationSize, h, "destination dans l'écran " .. name)
		end
	end)

	T.test("the six menu entries fit the screen and sit under the title on short phones", function()
		local lobby, Lobby = newLobby()
		lobby:show()
		-- 568x320 : iPhone SE couché, le plus court des téléphones visés.
		local SHORT_PHONES = { { 844, 390 }, { 780, 360 }, { 740, 360 }, { 667, 375 }, { 640, 360 }, { 568, 320 } }
		for _, res in ipairs(SHORT_PHONES) do
			local w, h = res[1], res[2]
			local name = label(w, h)
			H.setViewport(w, h)
			lobby:updateResponsive()
			local L = Lobby.layoutFor(w, h, lobby.titleWidth)
			T.le(L.menuY * h + L.menuHeight, h, "menu dans l'écran " .. name)
			-- Hauteur nominale du titre : son corps (92), comme la mesure du harnais.
			T.le(L.titleY * h + L.titleScale * 92, L.menuY * h, "menu sous le titre " .. name)
			-- L'instance applique l'écart de la mise en page : les entrées et leurs écarts remplissent le menu.
			local total = (#lobby.menuItems - 1) * lobby.menuLayout.Padding.Offset
			for _, item in ipairs(lobby.menuItems) do
				total += item.button.Size.Y.Offset
			end
			T.near(total, L.menuHeight, 0.001, "entrées et écarts remplissent le menu " .. name)
		end
		lobby:destroy()
	end)

	T.test("the title and its pastilles stay on screen at every resolution", function()
		H.asClient()
		local Lobby = H.load("Lobby")
		for _, res in ipairs(RESOLUTIONS) do
			local w, h = res[1], res[2]
			local L = Lobby.layoutFor(w, h, TITLE_WIDTH)
			local name = label(w, h)
			T.ge(L.titleScale, 0.3, "titre lisible " .. name)
			T.le(L.titleScale, 1, "titre sans agrandissement " .. name)
			T.le(L.titleX * w + TITLE_WIDTH * L.titleScale, w, "titre et pastilles dans l'écran " .. name)
		end
		-- Sur téléphone debout, l'ancienne échelle (largeur / 720) faisait sortir les pastilles.
		local portrait = Lobby.layoutFor(390, 844, TITLE_WIDTH)
		T.lt(portrait.titleScale, 390 / 720, "le titre se réduit pour tenir à l'écran")
	end)

	T.test("the rail never covers the first card on narrow landscape screens", function()
		H.asClient()
		local Lobby = H.load("Lobby")
		for _, res in ipairs(RESOLUTIONS) do
			local w, h = res[1], res[2]
			local L = Lobby.layoutFor(w, h, TITLE_WIDTH)
			if L.railVisible then
				T.le(L.railX * w + L.railWidth, L.scrollerX * w, "rail à gauche des cartes " .. label(w, h))
				T.le(L.scrollerX + L.scrollerWidth, 1, "cartes dans la largeur " .. label(w, h))
			end
		end
		local narrow = Lobby.layoutFor(780, 360, TITLE_WIDTH)
		T.gt(narrow.scrollerX, 0.09, "la zone des cartes recule sur téléphone couché")
		local wide = Lobby.layoutFor(1280, 720, TITLE_WIDTH)
		T.eq(wide.scrollerX, 0.09, "pas de recul quand la place suffit")
	end)

	T.test("portrait phones hide the decoration and the rail, landscape keeps them", function()
		H.asClient()
		local Lobby = H.load("Lobby")
		local portrait = Lobby.layoutFor(390, 844, TITLE_WIDTH)
		T.ok(portrait.portrait)
		T.falsy(portrait.decorVisible)
		T.falsy(portrait.railVisible)
		local landscape = Lobby.layoutFor(1280, 720, TITLE_WIDTH)
		T.falsy(landscape.portrait)
		T.ok(landscape.decorVisible)
		T.ok(landscape.railVisible)
	end)

	T.test("a short landscape screen shrinks the cards and hides the hint", function()
		H.asClient()
		local Lobby = H.load("Lobby")
		local L = Lobby.layoutFor(844, 390, TITLE_WIDTH)
		T.falsy(L.hintVisible)
		T.lt(L.cardScale, 1, "les cartes rétrécissent au lieu de sortir de la zone")
		T.ge(L.cardScale, 0.4)
		local normal = Lobby.layoutFor(1280, 720, TITLE_WIDTH)
		T.eq(normal.cardScale, 1, "pas de réduction quand la place suffit")
	end)

	T.test("the instance layout follows the viewport at every resolution", function()
		local lobby, Lobby = newLobby()
		lobby:show()
		for _, res in ipairs(RESOLUTIONS) do
			local w, h = res[1], res[2]
			H.setViewport(w, h)
			T.eq(lobby.gui.AbsoluteSize.X, w, "largeur lue par le lobby " .. label(w, h))
			T.eq(lobby.gui.AbsoluteSize.Y, h, "hauteur lue par le lobby " .. label(w, h))
			lobby:updateResponsive()
			local L = Lobby.layoutFor(w, h, lobby.titleWidth)
			T.near(lobby.playButton.Position.Y.Offset, L.playTop, 0.001, "Jouer " .. label(w, h))
			T.near(lobby.titleScale.Scale, L.titleScale, 0.001, "titre " .. label(w, h))
			T.eq(lobby.mainPage.Visible, true)
			T.eq(lobby.decoration.Visible, L.decorVisible, "décor " .. label(w, h))
			T.eq(lobby.rail.Visible, L.railVisible, "rail " .. label(w, h))
			for _, entry in pairs(lobby.cards) do
				T.near(entry.scale.Scale, L.cardScale, 0.001, "échelle carte " .. label(w, h))
				T.near(entry.holder.Size.X.Offset, L.cardWidth, 0.001, "largeur carte " .. label(w, h))
			end
		end
		lobby:destroy()
	end)

	T.test("modal windows are scaled to fit the viewport", function()
		local lobby = newLobby()
		lobby:show()
		for _, res in ipairs(RESOLUTIONS) do
			local w, h = res[1], res[2]
			H.setViewport(w, h)
			lobby:updateResponsive()
			for _, entry in ipairs(lobby.modalScales) do
				local name = label(w, h)
				T.le(entry.width * entry.scale.Scale, w, "modale plus large que l'écran " .. name)
				T.le(entry.height * entry.scale.Scale, h, "modale plus haute que l'écran " .. name)
			end
		end
		lobby:destroy()
	end)

	T.test("the grid of squares rebuilds only when the viewport size changes", function()
		local lobby = newLobby()
		lobby:show()
		H.setViewport(1280, 720)
		lobby:updateResponsive()
		local count = H.instanceCount()
		lobby:updateResponsive()
		T.eq(H.instanceCount(), count, "même taille : aucune nouvelle case")
		lobby:destroy()
	end)
end
