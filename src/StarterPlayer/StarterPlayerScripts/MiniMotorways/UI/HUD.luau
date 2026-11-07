--[[
	HUD.luau
	Interface de jeu claire et minimaliste, inspirée de la vidéo :
	flèche retour, score / jour / horloge, pause / lecture / avance rapide,
	outils à droite, compteurs rond-point / routes / ponts, choix hebdomadaire.
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)

local HUD = {}
HUD.__index = HUD

local DAYS = { "LUN", "MAR", "MER", "JEU", "VEN", "SAM", "DIM" }
local BRIDGE_CHIP = Color3.fromHex("7F8A7C")

local function clamp01(value)
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

function HUD.new(callbacks)
	local self = setmetatable({}, HUD)
	self.callbacks = callbacks or {}
	self.tool = "build"
	self.toolButtons = {}
	self.mapName = ""
	self.toastToken = 0
	self.hintToken = 0
	self.speed = 1
	self.roundabouts = 0
	self.choiceWeek = nil
	self.choiceDismissedWeek = nil
	self:build()
	return self
end

function HUD:iconPen(parent)
	local holder = Theme.new("Frame", {
		Parent = parent,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	Theme.new("Frame", {
		Parent = holder,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(22, 6),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Rotation = 45,
	})
	Theme.circle(holder, 7, Theme.White, {
		Position = UDim2.fromScale(0.30, 0.68),
		AnchorPoint = Vector2.new(0.5, 0.5),
	})
	return holder
end

function HUD:iconTrash(parent)
	local holder = Theme.new("Frame", {
		Parent = parent,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	Theme.new("Frame", {
		Parent = holder,
		Position = UDim2.fromScale(0.5, 0.27),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(20, 4),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
	})
	Theme.new("Frame", {
		Parent = holder,
		Position = UDim2.fromScale(0.5, 0.60),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(15, 17),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
	})
	for index = 1, 2 do
		Theme.new("Frame", {
			Parent = holder,
			Position = UDim2.fromScale(0.42 + (index - 1) * 0.16, 0.60),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(2, 10),
			BackgroundColor3 = Theme.PanelDark,
			BorderSizePixel = 0,
		})
	end
	return holder
end

function HUD:iconRoundabout(parent)
	local holder = Theme.new("Frame", {
		Parent = parent,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	local outer = Theme.circle(holder, 22, Theme.White, {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
	})
	Theme.circle(outer, 13, Theme.Teal, {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
	})
	for _, offset in ipairs({
		{ 0.5, 0.14 },
		{ 0.5, 0.86 },
		{ 0.14, 0.5 },
		{ 0.86, 0.5 },
	}) do
		Theme.new("Frame", {
			Parent = holder,
			Position = UDim2.fromScale(offset[1], offset[2]),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(4, 10),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			Rotation = (offset[1] == 0.5) and 0 or 90,
		})
	end
	return holder
end

function HUD:iconRoad(parent)
	local holder = Theme.new("Frame", {
		Parent = parent,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	for index = 1, 3 do
		Theme.new("Frame", {
			Parent = holder,
			Position = UDim2.fromOffset(9, 12 + (index - 1) * 7),
			Size = UDim2.fromOffset(24, 4),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			Rotation = -18,
		})
	end
	return holder
end

function HUD:iconBridge(parent)
	local holder = Theme.new("Frame", {
		Parent = parent,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	Theme.circle(holder, 8, Theme.White, {
		Position = UDim2.fromScale(0.28, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
	})
	Theme.circle(holder, 8, Theme.White, {
		Position = UDim2.fromScale(0.72, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
	})
	Theme.new("Frame", {
		Parent = holder,
		Position = UDim2.fromScale(0.5, 0.56),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(26, 3),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
	})
	return holder
end

function HUD:build()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "MM_HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui
	self.gui = gui

	-- Barre de progression de semaine, très discrète (masquée par défaut).
	local weekBg = Theme.new("Frame", {
		Parent = gui,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		ZIndex = 41,
		Visible = false,
	})
	self.weekFill = Theme.new("Frame", {
		Parent = weekBg,
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Teal,
		BorderSizePixel = 0,
		ZIndex = 42,
	})

	-- Flèche retour, en haut à gauche.
	self.backButton = Theme.new("TextButton", {
		Parent = gui,
		Position = UDim2.fromScale(0.018, 0.020),
		Size = UDim2.fromOffset(52, 52),
		BackgroundTransparency = 1,
		Text = "←",
		Font = Theme.FontBlack,
		TextSize = 34,
		TextColor3 = Theme.Ink,
		Active = true,
		Selectable = true,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		ZIndex = 48,
	})
	self.backButton.MouseEnter:Connect(function()
		self.backButton.TextColor3 = Theme.TealDark
	end)
	self.backButton.MouseLeave:Connect(function()
		self.backButton.TextColor3 = Theme.Ink
	end)
	self.backButton.Activated:Connect(function()
		if self.callbacks.onMenu then
			self.callbacks.onMenu()
		end
	end)

	-- Jauge de trafic : discrète, visible seulement quand le trafic se dégrade.
	local circulation = Theme.new("Frame", {
		Parent = gui,
		Position = UDim2.fromScale(0.022, 0.082),
		Size = UDim2.fromOffset(176, 38),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 42,
	})
	self.circulation = circulation
	Theme.label(circulation, "TRAFIC", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(90, 14),
		TextSize = 9,
		Font = Theme.FontBold,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 43,
	})
	self.satisfactionText = Theme.label(circulation, "100%", {
		Position = UDim2.fromOffset(100, 0),
		Size = UDim2.fromOffset(76, 14),
		TextSize = 9,
		Font = Theme.FontBold,
		TextColor3 = Theme.TealDark,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 43,
	})
	local barBg = Theme.new("Frame", {
		Parent = circulation,
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.fromOffset(176, 8),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		ZIndex = 43,
	})
	Theme.corner(barBg, 4)
	self.satisfactionFill = Theme.new("Frame", {
		Parent = barBg,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Teal,
		BorderSizePixel = 0,
		ZIndex = 44,
	})
	Theme.corner(self.satisfactionFill, 4)

	-- Score, jour et horloge, en haut à droite.
	local scorePanel = Theme.new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.975, 0.020),
		Size = UDim2.fromOffset(286, 62),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 42,
	})
	self.scorePanel = scorePanel
	self.scoreValue = Theme.label(scorePanel, "0", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(126, 56),
		TextSize = 42,
		Font = Theme.FontBlack,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 43,
	})
	Theme.textScaled(self.scoreValue, 42, 18)

	local pin = Theme.circle(scorePanel, 20, Theme.PanelDark, {
		Position = UDim2.fromOffset(136, 14),
		ZIndex = 43,
	})
	Theme.circle(pin, 7, Theme.White, {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 44,
	})

	self.dayLabel = Theme.label(scorePanel, "LUN", {
		Position = UDim2.fromOffset(164, 12),
		Size = UDim2.fromOffset(54, 24),
		TextSize = 15,
		Font = Theme.FontBold,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 43,
	})
	Theme.textScaled(self.dayLabel, 15, 9)

	local clock = Theme.circle(scorePanel, 42, Theme.PanelDark, {
		Position = UDim2.fromOffset(224, 2),
		ZIndex = 43,
	})
	self.clock = clock

	-- Les aiguilles tournent autour d'un pivot placé au centre de l'horloge :
	-- Rotation pivote toujours autour du centre d'un GuiObject, pas de son
	-- AnchorPoint. Un pivot vide au centre évite donc une horloge bancale.
	local function makeClockHand(length, thickness)
		local pivot = Theme.new("Frame", {
			Parent = clock,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 44,
		})
		local hand = Theme.new("Frame", {
			Parent = pivot,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(thickness, length),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 44,
		})
		return pivot, hand
	end

	self.clockHourPivot, self.clockHour = makeClockHand(10, 2)
	self.clockMinutePivot, self.clockMinute = makeClockHand(14, 2)
	Theme.circle(clock, 5, Theme.White, {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 45,
	})

	-- L'horloge ouvre les contrôles de temps ; ils restent cachés autrement.
	self.clockButton = Theme.new("TextButton", {
		Parent = scorePanel,
		Position = UDim2.fromOffset(224, 2),
		Size = UDim2.fromOffset(42, 42),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		Active = true,
		Selectable = true,
		AutoButtonColor = false,
		ZIndex = 46,
	})
	self.clockButton.Activated:Connect(function()
		self.controls.Visible = not self.controls.Visible
	end)
	self.clockButton.MouseEnter:Connect(function()
		clock.BackgroundColor3 = Theme.TealDark
	end)
	self.clockButton.MouseLeave:Connect(function()
		clock.BackgroundColor3 = Theme.PanelDark
	end)

	self.weekLabel = Theme.label(scorePanel, "SEMAINE 1", {
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.fromOffset(274, 18),
		TextSize = 10,
		Font = Theme.FontBold,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		ZIndex = 43,
	})

	-- Pause / lecture / avance rapide, sous l'horloge.
	local controls = Theme.new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.982, 0.105),
		Size = UDim2.fromOffset(46, 160),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 42,
	})
	self.controls = controls
	controls.Visible = false
	local controlLayout = Instance.new("UIListLayout")
	controlLayout.FillDirection = Enum.FillDirection.Vertical
	controlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	controlLayout.Padding = UDim.new(0, 6)
	controlLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlLayout.Parent = controls

	local function makeControl(text, order, onClick)
		local button = Theme.new("TextButton", {
			Parent = controls,
			Size = UDim2.fromOffset(38, 38),
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Text = text,
			Font = Theme.FontBlack,
			TextSize = 18,
			TextColor3 = Theme.Ink,
			Active = true,
			Selectable = true,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			ZIndex = 43,
		})
		button.MouseEnter:Connect(function()
			button.TextColor3 = Theme.TealDark
		end)
		button.MouseLeave:Connect(function()
			if button == self.speedButton and self.speed > 1 then
				button.TextColor3 = Theme.TealDark
			else
				button.TextColor3 = Theme.Ink
			end
		end)
		button.Activated:Connect(onClick)
		return button
	end

	self.pauseButton = makeControl("II", 1, function()
		if self.callbacks.onPause then
			self.callbacks.onPause()
		end
	end)
	self.playButton = makeControl("▶", 2, function()
		if self.callbacks.onResume then
			self.callbacks.onResume()
		end
	end)
	self.speedButton = makeControl("▶▶", 3, function()
		local nextSpeed = 1
		if self.speed == 1 then
			nextSpeed = 2
		elseif self.speed == 2 then
			nextSpeed = 3
		end
		self:setSpeed(nextSpeed)
		if self.callbacks.onSpeed then
			self.callbacks.onSpeed(nextSpeed)
		end
	end)
	self.speedLabel = Theme.label(controls, "x1", {
		LayoutOrder = 4,
		Size = UDim2.fromOffset(40, 14),
		TextSize = 10,
		Font = Theme.FontBold,
		TextColor3 = Theme.InkSoft,
		ZIndex = 43,
	})

	-- Compteurs de ressources, en bas au centre.
	local resources = Theme.new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.975),
		Size = UDim2.fromOffset(330, 58),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 42,
	})
	self.resources = resources
	local resLayout = Instance.new("UIListLayout")
	resLayout.FillDirection = Enum.FillDirection.Horizontal
	resLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	resLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	resLayout.Padding = UDim.new(0, 7)
	resLayout.SortOrder = Enum.SortOrder.LayoutOrder
	resLayout.Parent = resources

	local roundaboutChip = Theme.new("Frame", {
		Parent = resources,
		Size = UDim2.fromOffset(58, 52),
		BackgroundColor3 = Theme.Teal,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		ZIndex = 43,
	})
	Theme.corner(roundaboutChip, 12)
	self.iconRoundabout(roundaboutChip)
	self.roundaboutValue = Theme.label(roundaboutChip, "0", {
		Position = UDim2.fromOffset(36, 28),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0,
		TextSize = 11,
		Font = Theme.FontBlack,
		TextColor3 = Theme.PanelDark,
		ZIndex = 45,
	})
	Theme.corner(self.roundaboutValue, 10)
	self.roundaboutChip = roundaboutChip

	local roadChip = Theme.new("Frame", {
		Parent = resources,
		Size = UDim2.fromOffset(82, 52),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		ZIndex = 43,
	})
	Theme.corner(roadChip, 10)
	self.iconRoad(roadChip)
	self.budgetValue = Theme.label(roadChip, "20", {
		Position = UDim2.fromOffset(48, 24),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0,
		TextSize = 13,
		Font = Theme.FontBlack,
		TextColor3 = Theme.PanelDark,
		ZIndex = 45,
	})
	Theme.corner(self.budgetValue, 13)

	local bridgeChip = Theme.new("Frame", {
		Parent = resources,
		Size = UDim2.fromOffset(82, 52),
		BackgroundColor3 = BRIDGE_CHIP,
		BorderSizePixel = 0,
		LayoutOrder = 3,
		ZIndex = 43,
	})
	Theme.corner(bridgeChip, 26)
	self.iconBridge(bridgeChip)
	self.bridgeValue = Theme.label(bridgeChip, "1", {
		Position = UDim2.fromOffset(48, 12),
		Size = UDim2.fromOffset(28, 28),
		TextSize = 16,
		Font = Theme.FontBlack,
		TextColor3 = Theme.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 45,
	})

	-- Toast.
	self.toastLabel = Theme.label(gui, "", {
		Position = UDim2.fromScale(0.5, 0.12),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0.7, 0, 0, 34),
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.05,
		TextSize = 13,
		TextColor3 = Theme.White,
		Visible = false,
		ZIndex = 55,
	})
	Theme.corner(self.toastLabel, 6)
	Theme.textScaled(self.toastLabel, 13, 8)
	Theme.maxSize(self.toastLabel, 560, 34)

	-- Aide en bas.
	self.hint = Theme.label(
		gui,
		"Glissez pour tracer  ·  clic droit pour effacer  ·  molette pour zoomer  ·  clic milieu pour déplacer",
		{
			Position = UDim2.fromScale(0.5, 0.895),
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.new(0.9, 0, 0, 18),
			TextSize = 12,
			TextColor3 = Theme.InkSoft,
			ZIndex = 42,
		}
	)
	Theme.textScaled(self.hint, 12, 7)
	Theme.maxSize(self.hint, 760, 18)

	-- Outils, dans une pastille verticale à droite.
	local toolPill = Theme.new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.982, 0.53),
		Size = UDim2.fromOffset(58, 132),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		ZIndex = 46,
	})
	self.toolPill = toolPill
	Theme.corner(toolPill, 29)
	local toolLayout = Instance.new("UIListLayout")
	toolLayout.FillDirection = Enum.FillDirection.Vertical
	toolLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	toolLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	toolLayout.Padding = UDim.new(0, 6)
	toolLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toolLayout.Parent = toolPill

	local function makeToolButton(tool, order, icon)
		local button = Theme.new("TextButton", {
			Parent = toolPill,
			Size = UDim2.fromOffset(46, 46),
			LayoutOrder = order,
			BackgroundColor3 = Theme.TealDark,
			BackgroundTransparency = 1,
			Text = "",
			Active = true,
			Selectable = true,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			ZIndex = 47,
		})
		Theme.corner(button, 23)
		icon(button)
		button.MouseEnter:Connect(function()
			if self.tool ~= tool then
				button.BackgroundTransparency = 0.75
			end
		end)
		button.MouseLeave:Connect(function()
			if self.tool ~= tool then
				button.BackgroundTransparency = 1
			end
		end)
		local function activate()
			self:setTool(tool)
			if self.callbacks.onToolChange then
				self.callbacks.onToolChange(tool)
			end
		end
		button.Activated:Connect(activate)
		return button
	end

	self.toolButtons.build = makeToolButton("build", 1, function(button)
		self:iconPen(button)
	end)
	self.toolButtons.erase = makeToolButton("erase", 2, function(button)
		self:iconTrash(button)
	end)
	self.toolButtons.roundabout = makeToolButton("roundabout", 3, function(button)
		self:iconRoundabout(button)
	end)
	self.toolButtons.roundabout.Visible = false
	self:setTool("build")

	self:buildPauseOverlay()
	self:buildGameOverOverlay()
	self:buildWeekChoiceOverlay()
	self:applyResponsive()
	self.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:applyResponsive()
	end)
end

function HUD:buildPauseOverlay()
	local overlay = Theme.new("Frame", {
		Parent = self.gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
		ZIndex = 60,
	})
	self.pauseOverlay = overlay

	local card = Theme.new("Frame", {
		Parent = overlay,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 340),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ZIndex = 61,
	})
	Theme.corner(card, 12)
	Theme.stroke(card, Theme.Border, 2, 0.1)
	self.pauseCard = card
	local pauseScale = Instance.new("UIScale")
	pauseScale.Parent = card
	self.pauseScale = pauseScale

	Theme.label(card, "Pause", {
		Position = UDim2.fromOffset(30, 24),
		Size = UDim2.new(1, -60, 0, 42),
		Font = Theme.FontBlack,
		TextSize = 32,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})
	Theme.label(card, "La partie est en pause.", {
		Position = UDim2.fromOffset(30, 68),
		Size = UDim2.new(1, -60, 0, 24),
		TextSize = 14,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})

	Theme.button(card, "Reprendre", {
		Position = UDim2.fromOffset(30, 112),
		Size = UDim2.fromOffset(360, 50),
		BackgroundColor3 = Theme.Teal,
		TextColor3 = Theme.White,
		TextSize = 18,
		CornerRadius = 4,
		ZIndex = 62,
	}, function()
		self:hidePause()
		if self.callbacks.onResume then
			self.callbacks.onResume()
		end
	end)

	Theme.button(card, "Recommencer", {
		Position = UDim2.fromOffset(30, 174),
		Size = UDim2.fromOffset(360, 50),
		BackgroundColor3 = Theme.PanelSoft,
		TextColor3 = Theme.Ink,
		TextSize = 18,
		CornerRadius = 4,
		ZIndex = 62,
	}, function()
		self:hidePause()
		if self.callbacks.onRestart then
			self.callbacks.onRestart()
		end
	end)

	Theme.button(card, "Menu", {
		Position = UDim2.fromOffset(30, 236),
		Size = UDim2.fromOffset(360, 50),
		BackgroundColor3 = Theme.PanelSoft,
		TextColor3 = Theme.Ink,
		TextSize = 18,
		CornerRadius = 4,
		ZIndex = 62,
	}, function()
		self:hidePause()
		if self.callbacks.onMenu then
			self.callbacks.onMenu()
		end
	end)
end

function HUD:buildGameOverOverlay()
	local overlay = Theme.new("Frame", {
		Parent = self.gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
		ZIndex = 60,
	})
	self.overOverlay = overlay

	local card = Theme.new("Frame", {
		Parent = overlay,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(500, 430),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ZIndex = 61,
	})
	Theme.corner(card, 12)
	Theme.stroke(card, Theme.Border, 2, 0.1)
	self.overCard = card
	local overScale = Instance.new("UIScale")
	overScale.Parent = card
	self.overScale = overScale

	Theme.label(card, "Partie terminée", {
		Position = UDim2.fromOffset(30, 22),
		Size = UDim2.new(1, -60, 0, 40),
		Font = Theme.FontBlack,
		TextSize = 30,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})

	self.finalMap = Theme.label(card, "", {
		Position = UDim2.fromOffset(30, 64),
		Size = UDim2.new(1, -60, 0, 22),
		TextSize = 14,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})

	Theme.label(card, "SCORE", {
		Position = UDim2.fromOffset(30, 104),
		Size = UDim2.fromOffset(220, 20),
		TextSize = 11,
		Font = Theme.FontBold,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})
	self.finalScore = Theme.label(card, "0", {
		Position = UDim2.fromOffset(30, 120),
		Size = UDim2.fromOffset(240, 72),
		Font = Theme.FontBlack,
		TextSize = 54,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})
	self.finalBest = Theme.label(card, "Meilleur : 0", {
		Position = UDim2.fromOffset(280, 140),
		Size = UDim2.fromOffset(190, 40),
		TextSize = 17,
		Font = Theme.FontBold,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 62,
	})
	self.finalWeek = Theme.label(card, "", {
		Position = UDim2.fromOffset(30, 204),
		Size = UDim2.new(1, -60, 0, 24),
		TextSize = 14,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})

	Theme.new("Frame", {
		Parent = card,
		Position = UDim2.fromOffset(30, 250),
		Size = UDim2.new(1, -60, 0, 1),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		ZIndex = 62,
	})

	Theme.button(card, "Rejouer", {
		Position = UDim2.fromOffset(30, 276),
		Size = UDim2.fromOffset(440, 50),
		BackgroundColor3 = Theme.Teal,
		TextColor3 = Theme.White,
		TextSize = 18,
		CornerRadius = 4,
		ZIndex = 62,
	}, function()
		self:hideModals()
		if self.callbacks.onRestart then
			self.callbacks.onRestart()
		end
	end)

	Theme.button(card, "Changer de ville", {
		Position = UDim2.fromOffset(30, 338),
		Size = UDim2.fromOffset(440, 50),
		BackgroundColor3 = Theme.PanelSoft,
		TextColor3 = Theme.Ink,
		TextSize = 18,
		CornerRadius = 4,
		ZIndex = 62,
	}, function()
		self:hideModals()
		if self.callbacks.onMenu then
			self.callbacks.onMenu()
		end
	end)
end

function HUD:buildWeekChoiceOverlay()
	local overlay = Theme.new("Frame", {
		Parent = self.gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
		ZIndex = 70,
	})
	self.choiceOverlay = overlay

	local card = Theme.new("Frame", {
		Parent = overlay,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(660, 390),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ZIndex = 71,
	})
	Theme.corner(card, 12)
	Theme.stroke(card, Theme.Border, 2, 0.1)
	self.choiceCard = card
	local choiceScale = Instance.new("UIScale")
	choiceScale.Parent = card
	self.choiceScale = choiceScale

	self.choiceTitle = Theme.label(card, "Semaine 2", {
		Position = UDim2.fromOffset(30, 22),
		Size = UDim2.new(1, -60, 0, 38),
		Font = Theme.FontBlack,
		TextSize = 30,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 72,
	})
	Theme.label(card, "Choisissez une amélioration pour continuer.", {
		Position = UDim2.fromOffset(30, 62),
		Size = UDim2.new(1, -60, 0, 24),
		TextSize = 14,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 72,
	})

	local options = Theme.new("Frame", {
		Parent = card,
		Position = UDim2.fromOffset(30, 106),
		Size = UDim2.new(1, -60, 0, 226),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 72,
	})
	self.choiceOptions = options
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 16)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = options
end

function HUD:applyResponsive()
	local viewport = self.gui.AbsoluteSize
	local width = viewport.X
	local height = viewport.Y
	if width < 2 or height < 2 then
		return
	end

	local portrait = width < 760 or width < height * 0.9
	local short = height < 700

	self.backButton.Position = UDim2.fromScale(0.018, portrait and 0.012 or 0.020)
	self.backButton.Size = UDim2.fromOffset(portrait and 42 or 52, portrait and 42 or 52)
	self.backButton.TextSize = portrait and 28 or 34

	self.scorePanel.Position = UDim2.new(0.975, 0, 0, portrait and 52 or 18)
	self.scorePanel.Size = UDim2.fromOffset(portrait and 238 or 286, 62)
	self.clock.Position = UDim2.fromOffset(portrait and 190 or 224, 2)
	self.clockButton.Position = self.clock.Position
	if portrait then
		self.scoreValue.Size = UDim2.fromOffset(104, 52)
		self.dayLabel.Position = UDim2.fromOffset(140, 12)
		self.dayLabel.Size = UDim2.fromOffset(44, 24)
		self.clockHour.Size = UDim2.fromOffset(2, 8)
		self.clockMinute.Size = UDim2.fromOffset(2, 12)
	else
		self.scoreValue.Size = UDim2.fromOffset(126, 56)
		self.dayLabel.Position = UDim2.fromOffset(164, 12)
		self.dayLabel.Size = UDim2.fromOffset(54, 24)
		self.clockHour.Size = UDim2.fromOffset(2, 10)
		self.clockMinute.Size = UDim2.fromOffset(2, 14)
	end

	self.controls.Position = UDim2.new(0.982, 0, 0, portrait and 122 or 78)
	self.resources.Position = UDim2.fromScale(0.5, short and 0.955 or 0.975)
	self.hint.Position = UDim2.fromScale(0.5, short and 0.835 or 0.895)
	self.hint.Visible = not short

	self.toolPill.Position = UDim2.fromScale(0.982, portrait and 0.58 or 0.53)
	self.toolPill.Size = UDim2.fromOffset(portrait and 52 or 58, self.roundabouts > 0 and 190 or 132)

	self.circulation.Position = UDim2.fromScale(0.022, portrait and 0.075 or 0.082)
	self.circulation.Size = UDim2.fromOffset(portrait and 150 or 176, 38)

	self.pauseScale.Scale = math.max(
		0.35,
		math.min(1, (width * 0.92) / 420, (height * 0.9) / 340)
	)
	self.overScale.Scale = math.max(
		0.35,
		math.min(1, (width * 0.92) / 500, (height * 0.9) / 430)
	)
	self.choiceScale.Scale = math.max(
		0.35,
		math.min(1, (width * 0.92) / 660, (height * 0.9) / 390)
	)
end

function HUD:setTool(tool)
	if tool == "roundabout" and self.roundabouts <= 0 then
		tool = "build"
	end
	self.tool = tool
	for name, button in pairs(self.toolButtons) do
		local active = name == tool
		button.BackgroundTransparency = active and 0 or 1
		button.BackgroundColor3 = Theme.TealDark
	end
end

function HUD:setRoundabouts(value)
	self.roundabouts = tonumber(value) or 0
	self.roundaboutValue.Text = tostring(self.roundabouts)
	self.toolButtons.roundabout.Visible = self.roundabouts > 0
	self.toolPill.Size = UDim2.fromOffset(
		self.gui.AbsoluteSize.X < 760 and 52 or 58,
		self.roundabouts > 0 and 190 or 132
	)
	if self.tool == "roundabout" and self.roundabouts <= 0 then
		self:setTool("build")
		if self.callbacks.onToolChange then
			self.callbacks.onToolChange("build")
		end
	end
end

function HUD:setSpeed(value)
	self.speed = tonumber(value) or 1
	if self.speed >= 3 then
		self.speed = 3
	elseif self.speed <= 1 then
		self.speed = 1
	end
	self.speedLabel.Text = "x" .. tostring(self.speed)
	self.speedButton.TextColor3 = self.speed > 1 and Theme.TealDark or Theme.Ink
end

function HUD:showGame(data, map)
	self.gui.Enabled = true
	self.controls.Visible = false
	self.pauseOverlay.Visible = false
	self.overOverlay.Visible = false
	self.choiceOverlay.Visible = false
	self.choiceWeek = nil
	self.choiceDismissedWeek = nil
	self.hint.Visible = true
	self.scoreValue.Text = "0"
	self.weekLabel.Text = "SEMAINE 1"
	self.dayLabel.Text = "LUN"
	self.budgetValue.Text = "—"
	self.bridgeValue.Text = "—"
	self.roundaboutValue.Text = "0"
	self.mapName = map and map.name or tostring(data.mapId)
	self:setTool("build")
	self:setSatisfaction(100)
	self:setSpeed(1)
	self:setRoundabouts(data.roundabouts or 0)

	self.hintToken += 1
	local token = self.hintToken
	task.delay(22, function()
		if self.hintToken == token then
			self.hint.Visible = false
		end
	end)
end

function HUD:hide()
	self.gui.Enabled = false
end

function HUD:setSatisfaction(value)
	local ratio = clamp01(value / 100)
	TweenService:Create(self.satisfactionFill, TweenInfo.new(0.22), {
		Size = UDim2.fromScale(ratio, 1),
	}):Play()

	local color = Theme.Teal
	if ratio <= 0.3 then
		color = Theme.Danger
	elseif ratio <= 0.6 then
		color = Theme.Orange
	end
	self.satisfactionFill.BackgroundColor3 = color
	self.satisfactionText.Text = tostring(math.floor(value + 0.5)) .. "%"
	self.satisfactionText.TextColor3 = color
	self.circulation.Visible = value < 99.5
end

function HUD:setState(state)
	if not state then
		return
	end
	self.scoreValue.Text = tostring(state.score or 0)
	self.weekLabel.Text = "SEMAINE " .. tostring(state.week or 1)
	self.dayLabel.Text = DAYS[(((state.week or 1) - 1) % #DAYS) + 1]
	self.budgetValue.Text = tostring(state.budget or 0)
	self.bridgeValue.Text = tostring(state.bridges or 0)
	self:setRoundabouts(state.roundabouts or 0)
	local progress = clamp01(state.weekProgress or 0)
	self.clockMinutePivot.Rotation = progress * 360
	self.clockHourPivot.Rotation = ((((state.week or 1) - 1) * 30) + progress * 30) % 360
	self:setSatisfaction(state.satisfaction or 0)
	self:setSpeed(state.speed or 1)

	TweenService:Create(self.weekFill, TweenInfo.new(0.22), {
		Size = UDim2.fromScale(clamp01(state.weekProgress or 0), 1),
	}):Play()

	if state.over then
		self.hint.Visible = false
	end
	if state.choice
		and state.choice.options
		and state.choice.week ~= self.choiceDismissedWeek
		and not self.choiceOverlay.Visible
	then
		self:showWeekChoice(state.choice)
	end
end

function HUD:showPause()
	self.pauseOverlay.Visible = true
end

function HUD:hidePause()
	self.pauseOverlay.Visible = false
end

function HUD:showGameOver(data)
	self.controls.Visible = false
	self.choiceOverlay.Visible = false
	self.pauseOverlay.Visible = false
	self.overOverlay.Visible = true
	self.hint.Visible = false
	self.finalMap.Text = self.mapName
	self.finalScore.Text = tostring(data.score)
	self.finalWeek.Text = "Semaine " .. tostring(data.week)
	if data.score >= (data.best or 0) and data.score > 0 then
		self.finalBest.Text = "Nouveau record !"
		self.finalBest.TextColor3 = Theme.Orange
	else
		self.finalBest.Text = "Meilleur : " .. tostring(data.best or 0)
		self.finalBest.TextColor3 = Theme.InkSoft
	end
end

function HUD:showWeekChoice(data)
	if self.choiceOverlay.Visible and self.choiceWeek == data.week then
		return
	end
	self.choiceWeek = data.week
	self.controls.Visible = false
	self.pauseOverlay.Visible = false
	self.overOverlay.Visible = false
	self.choiceOverlay.Visible = true
	self.choiceTitle.Text = "Semaine " .. tostring(data.week or "")
	self.choiceOptions:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 16)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = self.choiceOptions

	local options = data.options or {}
	for index, option in ipairs(options) do
		local color = Theme.Teal
		if option.kind == "roads" then
			color = Theme.PanelDark
		elseif option.kind == "bridges" then
			color = BRIDGE_CHIP
		elseif option.kind == "roundabouts" then
			color = Theme.Teal
		end
		local optionCard = Theme.new("Frame", {
			Parent = self.choiceOptions,
			Size = UDim2.fromOffset(270, 208),
			BackgroundColor3 = Theme.PanelSoft,
			BorderSizePixel = 0,
			LayoutOrder = index,
			ZIndex = 73,
		})
		Theme.corner(optionCard, 10)
		Theme.stroke(optionCard, Theme.Border, 1, 0.1)

		local iconCircle = Theme.circle(optionCard, 58, color, {
			Position = UDim2.fromScale(0.5, 0.18),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 74,
		})
		if option.kind == "roads" then
			self.iconRoad(iconCircle)
		elseif option.kind == "bridges" then
			self.iconBridge(iconCircle)
		else
			self.iconRoundabout(iconCircle)
		end

		Theme.label(optionCard, option.title or "Amélioration", {
			Position = UDim2.fromOffset(16, 104),
			Size = UDim2.new(1, -32, 0, 28),
			TextSize = 20,
			Font = Theme.FontBlack,
			TextColor3 = Theme.Ink,
			ZIndex = 74,
		})
		Theme.label(optionCard, option.description or "", {
			Position = UDim2.fromOffset(16, 136),
			Size = UDim2.new(1, -32, 0, 48),
			TextSize = 12,
			TextColor3 = Theme.InkSoft,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 74,
		})

		local hit = Theme.new("TextButton", {
			Parent = optionCard,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			Active = true,
			Selectable = true,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			ZIndex = 75,
		})
		hit.MouseEnter:Connect(function()
			optionCard.BackgroundColor3 = Theme.Cream
		end)
		hit.MouseLeave:Connect(function()
			optionCard.BackgroundColor3 = Theme.PanelSoft
		end)
		local lastChoose = 0
		local function chooseOption()
			local now = os.clock()
			if now - lastChoose < 0.15 then
				return
			end
			lastChoose = now
			self.choiceDismissedWeek = self.choiceWeek
			self.choiceOverlay.Visible = false
			if self.callbacks.onChooseReward then
				self.callbacks.onChooseReward(option.id)
			end
		end
		hit.Activated:Connect(chooseOption)
		hit.MouseButton1Click:Connect(chooseOption)
	end
end

function HUD:hideWeekChoice()
	self.choiceDismissedWeek = self.choiceWeek
	self.choiceOverlay.Visible = false
end

function HUD:hideModals()
	self.pauseOverlay.Visible = false
	self.overOverlay.Visible = false
	self.choiceOverlay.Visible = false
end

function HUD:toast(text)
	self.toastToken += 1
	local token = self.toastToken
	self.toastLabel.Text = text
	self.toastLabel.Visible = true
	task.delay(3, function()
		if self.toastToken == token then
			self.toastLabel.Visible = false
		end
	end)
end

return HUD
