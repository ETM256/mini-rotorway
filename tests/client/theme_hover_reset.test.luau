return function(T, H)
	local function newGui()
		H.asClient()
		local Theme = H.load("UI/Theme")
		local gui = Theme.new("ScreenGui", { Parent = H.localPlayer.PlayerGui })
		return Theme, gui
	end

	local function touchEnd()
		return { UserInputType = Enum.UserInputType.Touch }
	end

	local function mouseEnd()
		return { UserInputType = Enum.UserInputType.MouseButton1 }
	end

	T.test("a finger lifted from a button clears its hover scale even without MouseLeave", function()
		local Theme, gui = newGui()
		local button = Theme.new("TextButton", { Parent = gui, Size = UDim2.fromOffset(120, 40) })
		Theme.motion(button)
		H.I.fire(H.I.getSignal(button, "MouseEnter"))
		H.advance(0.5)
		local scale = button:FindFirstChild("MotionScale")
		T.near(scale.Scale, Theme.Motion.Hover, 1e-6, "survol installé")

		H.I.fire(H.I.getSignal(button, "InputEnded"), touchEnd())
		H.advance(0.5)
		T.near(scale.Scale, 1, 1e-6, "le toucher relâché ramène la taille de repos")
	end)

	T.test("a mouse button release does not touch the hover state", function()
		local Theme, gui = newGui()
		local button = Theme.new("TextButton", { Parent = gui, Size = UDim2.fromOffset(120, 40) })
		Theme.motion(button)
		H.I.fire(H.I.getSignal(button, "MouseEnter"))
		H.advance(0.5)
		H.I.fire(H.I.getSignal(button, "InputEnded"), mouseEnd())
		H.advance(0.5)
		T.near(button.MotionScale.Scale, Theme.Motion.Hover, 1e-6, "la souris est toujours dessus")
	end)

	T.test("a lifted finger restores the base colour of a Theme.button", function()
		local Theme, gui = newGui()
		local button = Theme.button(gui, "Jouer", { Size = UDim2.fromOffset(120, 40) }, function() end)
		local base = button.BackgroundColor3
		H.I.fire(H.I.getSignal(button, "MouseEnter"))
		H.advance(0.5)
		T.ne(button.BackgroundColor3, base, "survol assombri")
		H.I.fire(H.I.getSignal(button, "InputEnded"), touchEnd())
		H.advance(0.5)
		T.eq(button.BackgroundColor3, base, "couleur de repos après le toucher")
	end)

	T.test("resetHover restores buttons hidden by an ancestor", function()
		local Theme, gui = newGui()
		local layer = Theme.new("Frame", { Parent = gui, Size = UDim2.fromScale(1, 1) })
		local button = Theme.button(layer, "Reprendre", { Size = UDim2.fromOffset(120, 40) }, function() end)
		Theme.motion(button)
		local base = button.BackgroundColor3
		H.I.fire(H.I.getSignal(button, "MouseEnter"))
		H.advance(0.5)
		T.near(button.MotionScale.Scale, Theme.Motion.Hover, 1e-6)
		T.ne(button.BackgroundColor3, base)

		layer.Visible = false
		Theme.resetHover(layer)
		T.near(button.MotionScale.Scale, 1, 1e-6, "échelle remise à 1 sans attendre de tween")
		T.eq(button.BackgroundColor3, base, "couleur remise sans attendre de tween")

		-- La couche rouvre sans état figé, et le survol suivant fonctionne encore.
		layer.Visible = true
		H.I.fire(H.I.getSignal(button, "MouseEnter"))
		H.advance(0.5)
		T.near(button.MotionScale.Scale, Theme.Motion.Hover, 1e-6, "le survol fonctionne après la remise")
	end)

	T.test("resetHover ignores instances without hover state and destroyed motions", function()
		local Theme, gui = newGui()
		local plain = Theme.new("Frame", { Parent = gui })
		Theme.new("TextLabel", { Parent = plain })
		T.noThrow(function()
			Theme.resetHover(plain)
		end)
		local button = Theme.new("TextButton", { Parent = gui })
		local handle = Theme.motion(button)
		handle:destroy()
		T.noThrow(function()
			Theme.resetHover(gui)
		end)
		T.falsy(button:FindFirstChild("MotionScale"), "l'échelle détruite n'est pas recréée")
	end)

	T.test("hover bookkeeping adds no lasting connection once the motion is destroyed", function()
		local Theme, gui = newGui()
		local button = Theme.new("TextButton", { Parent = gui })
		H.advance(0.2)
		local before = H.connectionCount()
		for _ = 1, 20 do
			local handle = Theme.motion(button)
			handle:destroy()
		end
		T.eq(H.connectionCount(), before, "vingt cycles installer/détruire ne laissent aucune connexion")
	end)
end
