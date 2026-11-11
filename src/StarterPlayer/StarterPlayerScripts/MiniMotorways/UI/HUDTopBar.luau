--[[
	HUDTopBar.luau
	Barre du haut, discrète : flèche retour et jauge de circulation à gauche ;
	à droite un panneau (score, « Jour N », mois avec sa ligne de progression,
	horloge du jour) et, dessous, les contrôles du temps (pause, x1, x2, x3).
	La mise en page est identique sur tous les formats (gabarit Theme.Layout).
	Mixin : ajoute ses méthodes à HUD (voir HUD.luau).
]]

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.HUDIcons)

local L = Theme.Layout

-- Vitesses proposées, dans l'ordre d'affichage des boutons.
local SPEEDS = { 1, 2, 3 }
local DAYS_PER_WEEK = 7
-- Cases du panneau (colonnes du score, du texte et de l'horloge).
local PANEL_PADDING = 12
local SCORE_WIDTH = 72
local TEXT_X = PANEL_PADDING + SCORE_WIDTH + 2 * Theme.Space.S + 1 + 4
local TEXT_WIDTH = 108
local CLOCK_SIZE = 30
local PROGRESS_HEIGHT = 3
local CONTROL_BUTTON = Vector2.new(32, 28)

local function clamp01(value)
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

-- Fond clair arrondi des boutons ronds de la barre.
local function softButton(parent, props)
	props.Parent = parent
	props.BackgroundColor3 = Theme.Panel
	props.BackgroundTransparency = 0
	props.Active = true
	props.Selectable = true
	props.AutoButtonColor = false
	props.BorderSizePixel = 0
	local button = Theme.new("TextButton", props)
	Theme.corner(button, Theme.Radius.Pill)
	Theme.motion(button)
	return button
end

return function(HUD)
	local function buildBackButton(self)
		-- Flèche retour : à droite des icônes de Roblox, en haut à gauche.
		local button = softButton(self.gui, {
			Position = UDim2.fromOffset(L.TopLeftInset, L.Margin),
			Size = UDim2.fromOffset(L.BackSize, L.BackSize),
			Text = "",
			ZIndex = 48,
		})
		Icons.back(button, Theme.Ink, 22)
		Theme.stroke(button, Theme.Border, Theme.Stroke.Thin, Theme.Stroke.Transparency)
		button.Activated:Connect(function()
			if self.callbacks.onMenu then
				self.callbacks.onMenu()
			end
		end)
		self.backButton = button
	end

	local function buildTrafficGauge(self)
		-- Jauge de circulation : visible seulement quand la satisfaction baisse.
		local gauge = Theme.new("Frame", {
			Parent = self.gui,
			Position = UDim2.fromOffset(L.TopLeftInset, L.Margin + L.PanelHeight + L.Gap),
			Size = UDim2.fromOffset(L.GaugeWidth, L.GaugeHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 42,
		})
		self.circulation = gauge
		Theme.label(gauge, "TRAFIC", {
			Size = UDim2.new(0.5, 0, 0, 14),
			TextSize = 10,
			Font = Theme.FontBold,
			TextColor3 = Theme.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
		})
		self.satisfactionText = Theme.label(gauge, "100%", {
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0.5, 0, 0, 14),
			TextSize = 10,
			Font = Theme.FontBold,
			TextColor3 = Theme.TealDark,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 43,
		})
		local track = Theme.new("Frame", {
			Parent = gauge,
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 6),
			BackgroundColor3 = Theme.Border,
			BorderSizePixel = 0,
			ZIndex = 43,
		})
		Theme.corner(track, Theme.Radius.Pill)
		self.satisfactionFill = Theme.new("Frame", {
			Parent = track,
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Teal,
			BorderSizePixel = 0,
			ZIndex = 44,
		})
		Theme.corner(self.satisfactionFill, Theme.Radius.Pill)
	end

	-- Horloge du jour : une aiguille des minutes qui suit la progression du jour,
	-- une aiguille des heures qui suit le jour de la semaine. Les aiguilles
	-- tournent autour d'un pivot vide au centre (Rotation pivote toujours autour
	-- du centre d'un GuiObject, pas de son AnchorPoint).
	local function buildClock(self, panel)
		local clock = Theme.circle(panel, CLOCK_SIZE, Theme.PanelSoft, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -PANEL_PADDING, 0.5, 0),
			ZIndex = 43,
		})
		self.clock = clock

		local function makeHand(length)
			local pivot = Theme.new("Frame", {
				Parent = clock,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 44,
			})
			Theme.new("Frame", {
				Parent = pivot,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(2, length),
				BackgroundColor3 = Theme.Ink,
				BorderSizePixel = 0,
				ZIndex = 44,
			})
			return pivot
		end
		self.clockHourPivot = makeHand(7)
		self.clockMinutePivot = makeHand(11)
		Theme.circle(clock, 4, Theme.Ink, {
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 45,
		})
	end

	local function buildScorePanel(self)
		local panel = Theme.panel(self.gui, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -L.Margin, 0, L.Margin),
			Size = UDim2.fromOffset(L.PanelWidth, L.PanelHeight),
			CornerRadius = Theme.Radius.Large,
			-- Active : un clic sur le panneau est absorbé par l'interface, il ne trace
			-- pas de route et ne déplace pas la vue derrière lui.
			Active = true,
			ZIndex = 42,
		})
		Theme.stroke(panel, Theme.Border, Theme.Stroke.Thin, Theme.Stroke.Transparency)
		self.scorePanel = panel

		self.scoreValue = Theme.label(panel, "0", {
			Position = UDim2.fromOffset(PANEL_PADDING, 0),
			Size = UDim2.new(0, SCORE_WIDTH, 1, 0),
			TextSize = 28,
			Font = Theme.FontBlack,
			TextColor3 = Theme.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
		})
		Theme.textScaled(self.scoreValue, 28, 14)

		Theme.new("Frame", {
			Parent = panel,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, PANEL_PADDING + SCORE_WIDTH + Theme.Space.S, 0.5, 0),
			Size = UDim2.new(0, 1, 0, L.PanelHeight - 2 * PANEL_PADDING),
			BackgroundColor3 = Theme.Border,
			BorderSizePixel = 0,
			ZIndex = 43,
		})

		-- Colonne de texte : « Jour N » au-dessus, mois et semaine dessous, puis la
		-- fine ligne de progression du mois.
		self.dayLabel = Theme.label(panel, "Jour 1", {
			Position = UDim2.fromOffset(TEXT_X, 7),
			Size = UDim2.fromOffset(TEXT_WIDTH, 20),
			TextSize = 15,
			Font = Theme.FontBold,
			TextColor3 = Theme.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
		})
		Theme.textScaled(self.dayLabel, 15, 10)
		self.monthLabel = Theme.label(panel, "", {
			Position = UDim2.fromOffset(TEXT_X, 26),
			Size = UDim2.fromOffset(TEXT_WIDTH * 0.6, 14),
			TextSize = 11,
			TextColor3 = Theme.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
		})
		Theme.textScaled(self.monthLabel, 11, 8)
		self.weekLabel = Theme.label(panel, "Sem. 1", {
			Position = UDim2.fromOffset(TEXT_X + TEXT_WIDTH * 0.6, 26),
			Size = UDim2.fromOffset(TEXT_WIDTH * 0.4, 14),
			TextSize = 11,
			TextColor3 = Theme.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 43,
		})
		Theme.textScaled(self.weekLabel, 11, 8)

		local track = Theme.new("Frame", {
			Parent = panel,
			Position = UDim2.fromOffset(TEXT_X, L.PanelHeight - PROGRESS_HEIGHT - 6),
			Size = UDim2.fromOffset(TEXT_WIDTH, PROGRESS_HEIGHT),
			BackgroundColor3 = Theme.Border,
			BorderSizePixel = 0,
			ZIndex = 43,
		})
		Theme.corner(track, Theme.Radius.Pill)
		self.monthFill = Theme.new("Frame", {
			Parent = track,
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Theme.Teal,
			BorderSizePixel = 0,
			ZIndex = 44,
		})
		Theme.corner(self.monthFill, Theme.Radius.Pill)

		buildClock(self, panel)
	end

	-- Contrôles du temps : pause puis les trois vitesses, dans un petit panneau
	-- sous le score. Le bouton actif prend la couleur de sélection des outils.
	local function buildControls(self)
		local controls = Theme.panel(self.gui, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -L.Margin, 0, L.Margin + L.PanelHeight + L.Gap),
			Size = UDim2.fromOffset(L.ControlsWidth, L.ControlsHeight),
			CornerRadius = Theme.Radius.Large,
			Active = true,
			ZIndex = 42,
		})
		Theme.stroke(controls, Theme.Border, Theme.Stroke.Thin, Theme.Stroke.Transparency)
		self.controls = controls
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 2)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = controls

		local function makeControl(name, order, text, onClick)
			local button = softButton(controls, {
				Name = name,
				Size = UDim2.fromOffset(CONTROL_BUTTON.X, CONTROL_BUTTON.Y),
				LayoutOrder = order,
				Text = text,
				Font = Theme.FontBold,
				TextSize = 13,
				TextColor3 = Theme.Ink,
				ZIndex = 43,
			})
			button.Activated:Connect(onClick)
			return button
		end

		self.pauseButton = makeControl("pause", 1, "", function()
			if self.callbacks.onPause then
				self.callbacks.onPause()
			end
		end)
		Icons.pause(self.pauseButton, Theme.Ink, 16)
		self.speedButtons = {}
		for index, value in ipairs(SPEEDS) do
			self.speedButtons[value] = makeControl("speed" .. value, index + 1, "x" .. value, function()
				self:setSpeed(value)
				if self.callbacks.onSpeed then
					self.callbacks.onSpeed(value)
				end
			end)
		end
	end

	function HUD:buildTopBar()
		buildBackButton(self)
		buildTrafficGauge(self)
		buildScorePanel(self)
		buildControls(self)
		self.paused = false
		self:setPaused(false)
		self:setSpeed(1)
	end

	-- Remet la barre à zéro au lancement d'une partie ; le prochain état serveur
	-- recale le calendrier et l'horloge.
	function HUD:resetTopBar()
		self.controls.Visible = true
		self.scoreValue.Text = "0"
		self.dayLabel.Text = "Jour 1"
		self.monthLabel.Text = ""
		self.weekLabel.Text = "Sem. 1"
		-- Un tween de la partie précédente ne doit pas ramener la barre en arrière.
		Theme.stopTweens(self.monthFill)
		self.monthFill.Size = UDim2.fromScale(0, 1)
		self.clockMinutePivot.Rotation = 0
		self.clockHourPivot.Rotation = 0
		self:setPaused(false)
	end

	function HUD:setSatisfaction(value)
		local ratio = clamp01(value / 100)
		Theme.tween(self.satisfactionFill, { Size = UDim2.fromScale(ratio, 1) }, "size", Theme.Motion.Fast)

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

	function HUD:setSpeed(value)
		local speed = math.floor(tonumber(value) or 1)
		self.speed = math.clamp(speed, SPEEDS[1], SPEEDS[#SPEEDS])
		for _, option in ipairs(SPEEDS) do
			Theme.setSelected(self.speedButtons[option], option == self.speed)
		end
	end

	-- Indicateur de pause : le bouton de pause prend la couleur de sélection et
	-- le cadran de l'horloge se teinte.
	function HUD:setPaused(paused)
		self.paused = paused == true
		Theme.setSelected(self.pauseButton, self.paused)
		Theme.tween(
			self.clock,
			{ BackgroundColor3 = self.paused and Theme.Orange or Theme.PanelSoft },
			"tint",
			Theme.Motion.Fast
		)
	end

	-- Jour, mois, semaine et horloge d'après l'état serveur. Les champs absents
	-- (état ancien, test) sont déduits de la semaine.
	function HUD:setCalendar(state)
		local week = state.week or 1
		local dayOfWeek = tonumber(state.dayOfWeek)
		if not dayOfWeek or dayOfWeek < 1 or dayOfWeek > DAYS_PER_WEEK then
			dayOfWeek = ((week - 1) % DAYS_PER_WEEK) + 1
		end
		dayOfWeek = math.floor(dayOfWeek)
		local day = tonumber(state.day) or ((week - 1) * DAYS_PER_WEEK + dayOfWeek)
		local weekProgress = clamp01(state.weekProgress or 0)
		local dayProgress = clamp01(tonumber(state.dayProgress) or (weekProgress * DAYS_PER_WEEK) % 1)
		local monthProgress = clamp01(tonumber(state.monthProgress) or weekProgress)

		self.dayLabel.Text = "Jour " .. tostring(math.floor(day))
		self.monthLabel.Text = type(state.monthName) == "string" and state.monthName or ""
		self.weekLabel.Text = "Sem. " .. tostring(week)
		self.clockMinutePivot.Rotation = dayProgress * 360
		self.clockHourPivot.Rotation = ((dayOfWeek - 1 + dayProgress) / DAYS_PER_WEEK) * 360
		Theme.tween(self.monthFill, { Size = UDim2.fromScale(monthProgress, 1) }, "size", Theme.Motion.Fast)
	end
end
