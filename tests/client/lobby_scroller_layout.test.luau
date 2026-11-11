return function(T, H)
	local function newLobby()
		H.asClient()
		local Lobby = H.load("Lobby")
		return Lobby.new({}), Lobby
	end

	T.test("the card row keeps a card gap of padding on both sides, counted in the canvas", function()
		local lobby = newLobby()
		lobby:show()
		lobby:showMaps()
		local padding = lobby.scroller:FindFirstChildOfClass("UIPadding")
		T.ok(padding, "marge dans la zone défilante")
		T.eq(padding.PaddingLeft, padding.PaddingRight, "symétrique")
		T.gt(padding.PaddingLeft.Offset, 0)

		-- Largeur réelle de la rangée : cartes, espaces entre elles et les deux marges.
		local maps = #H.load("Maps").all()
		local cardWidth = lobby.cards[next(lobby.cards)].holder.Size.X.Offset
		local layout = lobby.scroller:FindFirstChildOfClass("UIListLayout")
		local gap = layout.Padding.Offset
		local rowWidth = maps * cardWidth + (maps - 1) * gap + padding.PaddingLeft.Offset + padding.PaddingRight.Offset
		local viewport = lobby.scroller.AbsoluteSize.X
		T.near(lobby.scroller.CanvasSize.X.Offset, math.max(rowWidth, viewport), 1e-6, "aucune zone vide superflue")
		lobby:destroy()
	end)

	T.test("switching pages clears the hover state of the hidden page buttons", function()
		local lobby = newLobby()
		lobby:show()
		local play
		for _, found in ipairs(H.find(lobby.menu, { class = "TextButton", text = "Jouer" })) do
			play = found
		end
		T.ok(play)
		H.I.fire(H.I.getSignal(play, "MouseEnter"))
		H.advance(0.5)
		T.near(play.MotionScale.Scale, 1.03, 1e-6)
		lobby:showMaps()
		T.near(play.MotionScale.Scale, 1, 1e-6, "page cachée sans survol")
		lobby:showMain()
		T.near(play.MotionScale.Scale, 1, 1e-6, "page rouverte sans survol figé")
		lobby:destroy()
	end)

	T.test("closing a modal clears the hover state of its close button", function()
		local lobby = newLobby()
		lobby:show()
		lobby:showOptions()
		local close
		for _, found in ipairs(H.find(lobby.optionsOverlay, { class = "TextButton", text = "Fermer" })) do
			close = found
		end
		T.ok(close)
		H.I.fire(H.I.getSignal(close, "MouseEnter"))
		H.advance(0.5)
		T.near(close.MotionScale.Scale, 1.03, 1e-6)
		H.click(close)
		T.falsy(lobby.optionsOverlay.Visible, "modale fermée")
		T.near(close.MotionScale.Scale, 1, 1e-6, "bouton sans survol à la réouverture")
		lobby:destroy()
	end)
end
