return function(T, H)
	local function newGui()
		H.asClient()
		local Theme = H.load("UI/Theme")
		local gui = Theme.new("ScreenGui", { Parent = H.localPlayer.PlayerGui })
		return Theme, gui
	end

	T.test("radius, outline and durations are read from Config.Style", function()
		local Theme = newGui()
		local style = H.load("Config").Style
		T.eq(Theme.Radius.Small, style.CornerRadius.Small)
		T.eq(Theme.Radius.Medium, style.CornerRadius.Medium)
		T.eq(Theme.Radius.Large, style.CornerRadius.Large)
		T.eq(Theme.Radius.Pill, 999, "pill is the only radius Theme adds itself")
		T.eq(Theme.Stroke.Thin, style.Outline.Thin)
		T.eq(Theme.Stroke.Max, style.Outline.Max)
		T.eq(Theme.Motion.Duration, style.Motion.Hover, "the hover duration is the UI hover duration")
		T.eq(Theme.Motion.Fast, style.Motion.Fast)
		T.eq(Theme.Motion.Standard, style.Motion.Standard)
	end)

	T.test("corner and stroke defaults come from the scales", function()
		local Theme, gui = newGui()
		local frame = Theme.new("Frame", { Parent = gui })
		local corner = Theme.corner(frame)
		T.eq(corner.CornerRadius.Offset, Theme.Radius.Medium)
		local stroke = Theme.stroke(frame)
		T.eq(stroke.Thickness, Theme.Stroke.Thin)
	end)

	T.test("a hovered button that gets hidden drops back to rest", function()
		local Theme, gui = newGui()
		local button = Theme.new("TextButton", { Parent = gui })
		Theme.motion(button)
		H.I.fire(H.I.getSignal(button, "MouseEnter"))
		H.advance(0.5)
		local scale = button:FindFirstChild("MotionScale")
		T.near(scale.Scale, Theme.Motion.Hover, 1e-6, "hovered")

		-- Caché pendant le survol : aucun MouseLeave ne viendra.
		button.Visible = false
		H.advance(0.5)
		T.near(scale.Scale, 1, 1e-6, "hidden: no stuck hover")

		button.Visible = true
		H.advance(0.5)
		T.near(scale.Scale, 1, 1e-6, "shown again without a pointer enter: still at rest")
	end)

	T.test("a hovered frame removed from the tree drops back to rest", function()
		local Theme, gui = newGui()
		local frame = Theme.new("Frame", { Parent = gui })
		Theme.motion(frame)
		H.I.fire(H.I.getSignal(frame, "MouseEnter"))
		H.advance(0.5)
		local scale = frame:FindFirstChild("MotionScale")
		T.near(scale.Scale, Theme.Motion.Hover, 1e-6)

		frame.Parent = nil
		H.advance(0.5)
		T.near(scale.Scale, 1, 1e-6, "detached: no stuck hover")
	end)

	T.test("a pressed button that gets hidden is not left shrunk", function()
		local Theme, gui = newGui()
		local button = Theme.new("TextButton", { Parent = gui })
		Theme.motion(button)
		H.I.fire(H.I.getSignal(button, "MouseButton1Down"))
		H.advance(0.5)
		local scale = button:FindFirstChild("MotionScale")
		T.near(scale.Scale, Theme.Motion.Press, 1e-6)
		button.Visible = false
		H.advance(0.5)
		T.near(scale.Scale, 1, 1e-6, "the press state is cleared too")
	end)

	T.test("the shadow follows size, position, anchor, visibility and layer", function()
		local Theme, gui = newGui()
		local panel = Theme.panel(gui, {
			Size = UDim2.fromOffset(100, 50),
			Position = UDim2.fromOffset(10, 20),
			ZIndex = 5,
			Shadow = true,
		})
		local shadow = gui:FindFirstChild("Shadow")
		T.ok(shadow, "shadow created")

		panel.Size = UDim2.fromOffset(150, 70)
		T.eq(shadow.Size.X.Offset, 150, "width follows")
		T.eq(shadow.Size.Y.Offset, 70, "height follows")

		panel.Position = UDim2.fromOffset(30, 40)
		T.eq(shadow.Position.X.Offset, 30, "x follows")
		T.eq(shadow.Position.Y.Offset, 40 + Theme.Shadow.Offset, "y follows with the offset")

		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		T.eq(shadow.AnchorPoint.X, 0.5, "anchor follows")

		panel.ZIndex = 9
		T.eq(shadow.ZIndex, 8, "the shadow stays one layer below")

		panel.Visible = false
		T.falsy(shadow.Visible, "hidden with its target")
		panel.Visible = true
		T.ok(shadow.Visible, "shown with its target")
	end)

	T.test("a shadow releases its listeners with its target", function()
		local Theme, gui = newGui()
		H.advance(0.5)
		local before = H.connectionCount()
		local panel = Theme.panel(gui, { Size = UDim2.fromOffset(40, 40), Shadow = true })
		T.ok(H.connectionCount() > before, "the shadow listens to its target")
		panel:Destroy()
		T.eq(H.connectionCount(), before, "no listener left after the target is destroyed")
		T.falsy(gui:FindFirstChild("Shadow"), "no orphan shadow")
	end)

	T.test("a corner takes a pixel radius or a relative UDim as given", function()
		local Theme, gui = newGui()
		local pixel = Theme.corner(Theme.new("Frame", { Parent = gui }), 6)
		T.eq(pixel.CornerRadius.Offset, 6)
		T.eq(pixel.CornerRadius.Scale, 0)
		local pill = Theme.corner(Theme.new("Frame", { Parent = gui }), UDim.new(1, 0))
		T.eq(pill.CornerRadius.Scale, 1, "a pill is a relative radius")
		T.eq(pill.CornerRadius.Offset, 0)
	end)

	T.test("a hovered button that gets hidden returns to its base colour", function()
		local Theme, gui = newGui()
		local base = Color3.fromRGB(200, 100, 50)
		local button = Theme.button(gui, "Jouer", { BackgroundColor3 = base })
		H.I.fire(H.I.getSignal(button, "MouseEnter"))
		H.advance(0.5)
		T.ok(button.BackgroundColor3.R < base.R, "hover darkens the button")
		-- Caché pendant le survol : aucun MouseLeave ne viendra.
		button.Visible = false
		H.advance(0.5)
		T.near(button.BackgroundColor3.R, base.R, 1e-6, "hidden: the base colour is back")
		T.near(button.BackgroundColor3.G, base.G, 1e-6)
	end)
end
