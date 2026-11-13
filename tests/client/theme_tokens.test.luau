return function(T, H)
	local function sameColor(a, b)
		return a.R == b.R and a.G == b.G and a.B == b.B
	end

	local function inPalette(color)
		local Config = H.load("Config")
		for _, value in pairs(Config.Colors) do
			if typeof(value) == "Color3" and sameColor(value, color) then
				return true
			end
		end
		return false
	end

	local function newGui()
		H.asClient()
		local Theme = H.load("UI/Theme")
		local gui = Theme.new("ScreenGui", { Parent = H.localPlayer.PlayerGui })
		return Theme, gui
	end

	T.test("every colour token of Theme comes from Config.Colors", function()
		local Theme = newGui()
		local count = 0
		for name, value in pairs(Theme) do
			if typeof(value) == "Color3" then
				count += 1
				T.ok(inPalette(value), "Theme." .. name .. " is not in Config.Colors")
			end
		end
		T.ok(count > 10, "the palette exposes tokens")
	end)

	T.test("the scales are ordered and motion never exceeds 1.04", function()
		local Theme = newGui()
		T.lt(Theme.Radius.Small, Theme.Radius.Medium)
		T.lt(Theme.Radius.Medium, Theme.Radius.Large)
		T.lt(Theme.Space.XS, Theme.Space.M)
		T.le(Theme.Motion.Max, 1.04)
		T.le(Theme.Motion.Hover, Theme.Motion.Max)
		T.le(Theme.Motion.Press, Theme.Motion.Max)
		T.eq(Theme.Stroke.Max, 2)
	end)

	T.test("corner builds a UICorner with the requested radius", function()
		local Theme, gui = newGui()
		local frame = Theme.new("Frame", { Parent = gui })
		Theme.corner(frame, Theme.Radius.Medium)
		local corner = H.find(frame, { class = "UICorner" })[1]
		T.ok(corner, "UICorner created")
		T.eq(corner.CornerRadius.Offset, Theme.Radius.Medium)
		T.eq(corner.CornerRadius.Scale, 0)
	end)

	T.test("stroke caps the thickness at 2 and defaults to the light border", function()
		local Theme, gui = newGui()
		local frame = Theme.new("Frame", { Parent = gui })
		local thick = Theme.stroke(frame, nil, 9)
		T.eq(thick.Thickness, 2, "a thick request is capped")
		local default = Theme.stroke(frame)
		T.eq(default.Thickness, Theme.Stroke.Thin)
		T.ok(sameColor(default.Color, Theme.Border), "default colour is the light border")
	end)

	T.test("numberLabel is anchored and centred in its parent", function()
		local Theme, gui = newGui()
		local box = Theme.new("Frame", { Parent = gui, Size = UDim2.fromOffset(80, 30) })
		local label = Theme.numberLabel(box, "12", { TextSize = 14 })
		T.eq(label.AnchorPoint.X, 0.5)
		T.eq(label.AnchorPoint.Y, 0.5)
		T.eq(label.Position.X.Scale, 0.5)
		T.eq(label.Position.Y.Scale, 0.5)
		T.eq(label.Size.X.Scale, 1)
		T.eq(label.Size.Y.Scale, 1)
		T.eq(label.TextXAlignment, Enum.TextXAlignment.Center)
		T.eq(label.TextYAlignment, Enum.TextYAlignment.Center)
		T.eq(label.Text, "12")
	end)

	T.test("pill is a fully rounded label", function()
		local Theme, gui = newGui()
		local pill = Theme.pill(gui, "3 routes", { Size = UDim2.fromOffset(90, 26) })
		local corner = H.find(pill, { class = "UICorner" })[1]
		T.eq(corner.CornerRadius.Offset, Theme.Radius.Pill)
		T.eq(pill.TextXAlignment, Enum.TextXAlignment.Center)
	end)

	T.test("panel uses the panel colour and rounds with Large", function()
		local Theme, gui = newGui()
		local panel = Theme.panel(gui, { Size = UDim2.fromOffset(160, 80) })
		T.ok(sameColor(panel.BackgroundColor3, Theme.Panel))
		local corner = H.find(panel, { class = "UICorner" })[1]
		T.eq(corner.CornerRadius.Offset, Theme.Radius.Large)
		T.eq(#H.find(panel, { class = "UIStroke" }), 0, "a panel has no outline by default")
	end)

	T.test("shadow is a low-alpha sibling placed behind its target", function()
		local Theme, gui = newGui()
		local panel = Theme.panel(gui, {
			Size = UDim2.fromOffset(100, 50),
			Position = UDim2.fromOffset(10, 20),
			ZIndex = 5,
			Shadow = true,
		})
		local shadow = gui:FindFirstChild("Shadow")
		T.ok(shadow, "shadow sibling created")
		T.eq(shadow.ZIndex, panel.ZIndex - 1, "drawn under the panel")
		T.near(shadow.BackgroundTransparency, Theme.Shadow.Transparency, 1e-6)
		T.eq(shadow.Position.Y.Offset, 20 + Theme.Shadow.Offset)
		T.eq(shadow.Size.X.Offset, 100)
		T.eq(#H.find(shadow, { class = "UIStroke" }), 0, "shadow is stroke-free")
	end)

	T.test("shadow disappears with its target", function()
		local Theme, gui = newGui()
		local panel = Theme.panel(gui, { Shadow = true, Size = UDim2.fromOffset(40, 40) })
		local shadow = gui:FindFirstChild("Shadow")
		T.ok(shadow)
		panel:Destroy()
		T.falsy(shadow.Parent, "shadow removed with its target")
	end)

	T.test("tween replaces the pending tween on the same slot", function()
		local Theme, gui = newGui()
		local frame = Theme.new("Frame", { Parent = gui })
		local first = Theme.tween(frame, { BackgroundTransparency = 0.5 }, "fade")
		local second = Theme.tween(frame, { BackgroundTransparency = 0.2 }, "fade")
		T.eq(first.PlaybackState, Enum.PlaybackState.Cancelled, "the old tween is cancelled")
		H.advance(1)
		T.near(frame.BackgroundTransparency, 0.2, 1e-6)
		T.eq(second.PlaybackState, Enum.PlaybackState.Completed)
	end)

	T.test("hover and press scale stay within the limit and clean up", function()
		local Theme, gui = newGui()
		local button = Theme.new("TextButton", { Parent = gui, Size = UDim2.fromOffset(120, 40) })
		H.advance(0.5)
		local before = H.connectionCount()

		local handle = Theme.motion(button)
		T.eq(H.connectionCount() - before, 9, "enter, leave, press, release, visible, ancestry, destroying, touch end and hover reset")
		T.eq(Theme.motion(button), handle, "one engine per target")
		T.eq(H.connectionCount() - before, 9, "no duplicate connections")

		H.I.fire(H.I.getSignal(button, "MouseEnter"))
		H.advance(0.5)
		local scale = button:FindFirstChild("MotionScale")
		T.ok(scale, "scale child created")
		T.near(scale.Scale, Theme.Motion.Hover, 1e-6)
		T.le(scale.Scale, 1.04)

		H.I.fire(H.I.getSignal(button, "MouseButton1Down"))
		H.advance(0.5)
		T.near(scale.Scale, Theme.Motion.Press, 1e-6)
		T.le(scale.Scale, 1.04)

		H.I.fire(H.I.getSignal(button, "MouseButton1Up"))
		H.I.fire(H.I.getSignal(button, "MouseLeave"))
		H.advance(0.5)
		T.near(scale.Scale, 1, 1e-6, "back to rest")
		T.eq(H.connectionCount() - before, 9, "finished tweens drop their connections")

		handle:destroy()
		handle:destroy()
		T.eq(H.connectionCount(), before, "destroy drops every connection")
		T.falsy(button:FindFirstChild("MotionScale"), "scale removed")
		T.ok(Theme.motion(button) ~= handle, "a new engine can be attached afterwards")
	end)

	T.test("destroy cancels a tween still running", function()
		local Theme, gui = newGui()
		local button = Theme.new("TextButton", { Parent = gui })
		local handle = Theme.motion(button)
		H.I.fire(H.I.getSignal(button, "MouseEnter"))
		local scale = button:FindFirstChild("MotionScale")
		handle:destroy()
		H.advance(1)
		T.near(scale.Scale, 1, 1e-6, "the cancelled tween never moved the scale")
	end)

	T.test("destroying the target releases its motion engine", function()
		local Theme, gui = newGui()
		local button = Theme.new("TextButton", { Parent = gui })
		H.advance(0.5)
		local before = H.connectionCount()
		local handle = Theme.motion(button)
		button:Destroy()
		T.eq(H.connectionCount(), before, "no connection left on the destroyed target")
		handle:destroy()
		T.eq(H.connectionCount(), before, "a late destroy is harmless")
	end)

	T.test("setSelected recolours and shows the ring, then restores", function()
		local Theme, gui = newGui()
		local button = Theme.button(gui, "Outil", { BackgroundColor3 = Theme.Panel })
		Theme.setSelected(button, true)
		H.advance(0.5)
		T.ok(sameColor(button.BackgroundColor3, Theme.Selected), "selected colour")
		local ring = button:FindFirstChild("SelectionRing")
		T.ok(ring, "selection ring")
		T.near(ring.Transparency, 0, 1e-6)
		T.le(ring.Thickness, 2)

		Theme.setSelected(button, false)
		H.advance(0.5)
		T.ok(sameColor(button.BackgroundColor3, Theme.Panel), "idle colour restored")
		T.near(ring.Transparency, 1, 1e-6)
	end)

	T.test("button keeps its API and rounds with Medium by default", function()
		local Theme, gui = newGui()
		local clicks = 0
		local button = Theme.button(gui, "Jouer", {}, function()
			clicks += 1
		end)
		T.eq(button.Text, "Jouer")
		T.eq(H.find(button, { class = "UICorner" })[1].CornerRadius.Offset, Theme.Radius.Medium)
		H.click(button)
		T.eq(clicks, 1)
	end)

	T.test("label defaults keep the palette and the typography token", function()
		local Theme, gui = newGui()
		local label = Theme.label(gui, "Bonjour", { TextSize = 12 })
		T.eq(label.TextSize, 12)
		T.ok(sameColor(label.TextColor3, Theme.Ink))
		T.eq(label.Text, "Bonjour")
		T.eq(label.Font, Theme.Font, "default font is the body token")
	end)

	T.test("motion never exceeds the limit, whatever the options ask", function()
		local Theme, gui = newGui()
		local button = Theme.new("TextButton", { Parent = gui })
		Theme.motion(button, { hover = 1.2, press = 1.2 })
		H.I.fire(H.I.getSignal(button, "MouseEnter"))
		H.advance(0.5)
		T.near(button:FindFirstChild("MotionScale").Scale, Theme.Motion.Max, 1e-6, "hover is capped")
		H.I.fire(H.I.getSignal(button, "MouseButton1Down"))
		H.advance(0.5)
		T.near(button:FindFirstChild("MotionScale").Scale, Theme.Motion.Max, 1e-6, "press is capped")
	end)

	T.test("tween without a slot still replaces the previous tween", function()
		local Theme, gui = newGui()
		local frame = Theme.new("Frame", { Parent = gui })
		local first = Theme.tween(frame, { BackgroundTransparency = 0.5 })
		local second = Theme.tween(frame, { BackgroundTransparency = 0.1 })
		T.eq(first.PlaybackState, Enum.PlaybackState.Cancelled)
		H.advance(1)
		T.near(frame.BackgroundTransparency, 0.1, 1e-6)
		T.eq(second.PlaybackState, Enum.PlaybackState.Completed)
	end)

	T.test("formatNumber groups thousands with spaces and falls back to 0", function()
		local Theme = newGui()
		T.eq(Theme.formatNumber(0), "0")
		T.eq(Theme.formatNumber(999), "999")
		T.eq(Theme.formatNumber(1000), "1 000")
		T.eq(Theme.formatNumber(1234567), "1 234 567")
		T.eq(Theme.formatNumber(-1234), "-1 234", "a negative keeps its sign")
		T.eq(Theme.formatNumber(12.9), "12", "rounded down")
		T.eq(Theme.formatNumber(nil), "0")
		T.eq(Theme.formatNumber("5"), "0", "a string is not a number")
		T.eq(Theme.formatNumber(0 / 0), "0", "NaN")
		T.eq(Theme.formatNumber(math.huge), "0", "infinity")
		T.eq(Theme.formatNumber(-math.huge), "0", "negative infinity")
	end)

	T.test("numberOr keeps finite numbers and returns the fallback otherwise", function()
		local Theme = newGui()
		T.eq(Theme.numberOr(3, 7), 3)
		T.eq(Theme.numberOr(-2.5, 7), -2.5)
		T.eq(Theme.numberOr(nil, 7), 7)
		T.eq(Theme.numberOr("3", 7), 7)
		T.eq(Theme.numberOr(0 / 0, 7), 7)
		T.eq(Theme.numberOr(math.huge, 7), 7)
		T.eq(Theme.numberOr(-math.huge, 7), 7)
	end)

	T.test("no UIStroke thicker than 2 in the built lobby", function()
		H.asClient()
		local Lobby = H.load("UI/Lobby")
		local lobby = Lobby.new({
			onPlay = function() end,
			onQuit = function() end,
			onStartMap = function() end,
			onResetRecords = function() end,
		})
		lobby:show()
		local gui = H.localPlayer.PlayerGui:FindFirstChild("MM_Lobby")
		T.ok(gui, "lobby gui")
		for _, stroke in ipairs(H.find(gui, { class = "UIStroke" })) do
			T.le(stroke.Thickness, 2, "a UIStroke is at most 2 px thick")
		end
	end)
end
