--[[
	HUDOverlays.luau
	Couches par-dessus la partie : toast en file, menu pause (avec paramètres),
	fin de partie et choix hebdomadaire. Une seule couche modale est ouverte à la
	fois : le menu pause et la fin de partie passent devant le choix, qui reste
	en attente et réapparaît à la reprise. Mixin : ajoute ses méthodes à HUD.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.HUDIcons)

-- Ordre d'empilement des couches (ZIndex) : le choix hebdomadaire passe au-dessus.
local Z_MODAL = 60
local Z_CHOICE = 70

local TOAST_DURATION = 3
-- File des toasts : au-delà, le plus ancien est abandonné pour rester à jour.
local TOAST_QUEUE_MAX = 3

-- Voile sombre léger derrière les cartes, et fondu d'apparition.
local OVERLAY_TRANSPARENCY = 0.18
local FADE_DURATION = Config.Style.Motion.Fast

-- Tailles des cartes. HUDResponsive met les cartes à l'échelle à partir des
-- mêmes valeurs : les modifier ici impose de les modifier là-bas aussi.
local PAUSE_SIZE = UDim2.fromOffset(420, 340)
local OVER_SIZE = UDim2.fromOffset(500, 430)
local CHOICE_SIZE = UDim2.fromOffset(660, 390)
local CARD_PADDING = 30
local CONTENT_Y = 108

local BUTTON_HEIGHT = 44
local MENU_ICON_SIZE = 20
-- Les voitures du circuit sont plus petites que les autres pictogrammes (cercle de 56 px).
local CARS_ICON_SIZE = 28
local BUTTON_GAP = 8
local OPTION_HEIGHT = 226
local OPTION_GAP = 16
-- Touches 1 à 3 pour choisir une amélioration (même ordre que l'affichage).
local OPTION_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }

local SWITCH_WIDTH = 44
local SWITCH_HEIGHT = 24
local KNOB_SIZE = 18
local KNOB_OFF = UDim2.new(0, 3, 0.5, 0)
local KNOB_ON = UDim2.new(0, SWITCH_WIDTH - KNOB_SIZE - 3, 0.5, 0)

-- Réglages du menu : nom transmis à onSetting, libellé affiché.
local SETTINGS_ROWS = {
	{ "grid", "Grille visible" },
	{ "hints", "Astuces" },
}

-- Statistiques principales de la fin de partie (clé de data.stats, libellé).
-- Une ligne n'est créée que si la donnée existe.
local STAT_ROWS = {
	{ "deliveries", "Trajets livrés" },
	{ "demandsServed", "Demandes servies" },
	{ "storesSpawned", "Magasins ouverts" },
	{ "housesSpawned", "Maisons apparues" },
	{ "roadsBuilt", "Routes posées" },
	{ "weeksCompleted", "Semaines terminées" },
}

-- Valeur numérique sûre : nil, NaN et infini donnent la valeur de repli.
local function numberOr(value, fallback)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function textOr(value, fallback)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

-- Entier avec espaces de milliers : 1 234 567.
local function formatNumber(value)
	local n = math.floor(numberOr(value, 0))
	local sign = ""
	if n < 0 then
		sign = "-"
		n = -n
	end
	local digits = tostring(n)
	local groups = ""
	while #digits > 3 do
		groups = " " .. string.sub(digits, -3) .. groups
		digits = string.sub(digits, 1, -4)
	end
	return sign .. digits .. groups
end

-- Durée mm:ss. Les minutes ne se bornent pas à 59 : 3600 s donnent 60:00.
local function formatDuration(seconds)
	local total = math.max(0, math.floor(numberOr(seconds, 0)))
	return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

-- Phrase lisible pour la raison de fin de partie ; nil si la raison est inconnue.
local function reasonText(data)
	local overload = type(data.overload) == "table" and data.overload or nil
	local reason = textOr(data.reason, nil)
	if reason == nil and overload then
		reason = "overload"
	end
	if reason == "overload" then
		local name = overload and textOr(overload.colorName, nil)
		if name then
			return "Le magasin " .. name .. " est resté trop longtemps surchargé."
		end
		return "Un magasin est resté trop longtemps surchargé."
	elseif reason == "traffic" then
		return "Les voitures sont restées bloquées trop longtemps."
	elseif reason == "satisfaction" then
		return "Les habitants ne sont plus satisfaits."
	end
	return nil
end

-- Garde les options exploitables : une table avec un identifiant à renvoyer.
local function sanitizeOptions(list)
	local options: { any } = {}
	if type(list) ~= "table" then
		return options
	end
	for _, option in ipairs(list) do
		if type(option) == "table" and option.id ~= nil then
			table.insert(options, option)
		end
	end
	return options
end

local function newOverlay(gui, zIndex)
	return Theme.new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = OVERLAY_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
		ZIndex = zIndex,
	})
end

-- Carte centrée ; son UIScale permet de la réduire sur petit écran.
local function newCard(overlay, size, zIndex)
	local card = Theme.new("Frame", {
		Parent = overlay,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	})
	Theme.corner(card, Theme.Radius.Large)
	Theme.stroke(card, Theme.Border, Theme.Stroke.Max, 0.1)
	local scale = Instance.new("UIScale")
	scale.Parent = card
	return card, scale
end

-- Une couche s'ouvre par un court fondu ; ouvrir une couche déjà visible ne la
-- rejoue pas.
local function openOverlay(overlay)
	if overlay.Visible then
		return
	end
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	Theme.tween(overlay, { BackgroundTransparency = OVERLAY_TRANSPARENCY }, "fade", FADE_DURATION)
end

local function closeOverlay(overlay)
	Theme.stopTweens(overlay)
	-- Les boutons cachés avec la couche ne doivent pas rouvrir en état de survol.
	Theme.resetHover(overlay)
	overlay.Visible = false
	overlay.BackgroundTransparency = OVERLAY_TRANSPARENCY
end

local function newOptionLayout(parent)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, OPTION_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

local function menuButton(parent, order, text, primary, icon, onClick)
	local button = Theme.button(parent, text, {
		Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
		LayoutOrder = order,
		BackgroundColor3 = primary and Theme.Teal or Theme.PanelSoft,
		TextColor3 = Theme.Ink,
		TextSize = 18,
		CornerRadius = Theme.Radius.Medium,
		ZIndex = 62,
	}, onClick)
	-- Pictogramme à gauche du libellé, centré verticalement.
	local canvas = icon(button, Theme.Ink, MENU_ICON_SIZE)
	canvas.AnchorPoint = Vector2.new(0, 0.5)
	canvas.Position = UDim2.new(0, 16, 0.5, 0)
	Theme.motion(button)
	return button
end

local function actionButton(parent, text, position, size, primary, onClick)
	local button = Theme.button(parent, text, {
		Position = position,
		Size = size,
		BackgroundColor3 = primary and Theme.Teal or Theme.PanelSoft,
		TextColor3 = Theme.Ink,
		TextSize = 18,
		CornerRadius = Theme.Radius.Medium,
		ZIndex = 62,
	}, onClick)
	Theme.motion(button)
	return button
end

-- Page du menu (boutons empilés) ou page des réglages : une seule est visible.
local function showPausePage(self, page)
	local onSettings = page == "settings"
	self.pauseMenuPage.Visible = not onSettings
	self.pauseSettingsPage.Visible = onSettings
	self.pauseTitle.Text = onSettings and "Paramètres" or "Pause"
	self.pauseCaption.Text = onSettings and "Réglages conservés pendant cette session." or "La partie est en pause."
end

-- Interrupteur à jour. Un changement s'anime ; l'état initial s'affiche sans fondu.
local function paintSwitch(self, name, instant)
	local view = self.switchViews[name]
	if not view then
		return
	end
	local on = self.settings[name] == true
	local color = on and Theme.Teal or Theme.Border
	local knob = on and KNOB_ON or KNOB_OFF
	if instant then
		Theme.stopTweens(view.track)
		Theme.stopTweens(view.knob)
		view.track.BackgroundColor3 = color
		view.knob.Position = knob
	else
		Theme.tween(view.track, { BackgroundColor3 = color }, "color", FADE_DURATION)
		Theme.tween(view.knob, { Position = knob }, "knob", FADE_DURATION)
	end
end

-- Un réglage changé est transmis au jeu. « Astuces » est appliqué ici : coupé,
-- l'aide disparaît tout de suite ; rallumé, elle réapparaît avec son délai
-- d'extinction (jamais figée).
local function applySetting(self, name, value)
	if name == "hints" then
		if value then
			self:flashHint()
		else
			self:cancelHintTimer()
			self:setHintShown(false)
		end
	end
	if self.callbacks.onSetting then
		self.callbacks.onSetting(name, value)
	end
end

-- Ligne cliquable entière : libellé à gauche, interrupteur à droite.
local function buildSwitchRow(self, page, index, name, label)
	local row = Theme.button(page, "", {
		Position = UDim2.fromOffset(CARD_PADDING, CONTENT_Y + (index - 1) * (BUTTON_HEIGHT + BUTTON_GAP)),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, BUTTON_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 62,
	}, function()
		self.settings[name] = not self.settings[name]
		paintSwitch(self, name, false)
		applySetting(self, name, self.settings[name])
	end)
	Theme.label(row, label, {
		Position = UDim2.fromOffset(4, 0),
		Size = UDim2.new(1, -80, 1, 0),
		Font = Theme.FontBold,
		TextSize = 16,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 63,
	})
	local track = Theme.new("Frame", {
		Parent = row,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(SWITCH_WIDTH, SWITCH_HEIGHT),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		ZIndex = 63,
	})
	Theme.corner(track, Theme.Radius.Pill)
	local knob = Theme.circle(track, KNOB_SIZE, Theme.White, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = KNOB_OFF,
		ZIndex = 64,
	})
	self.switchViews[name] = { track = track, knob = knob }
	paintSwitch(self, name, true)
end

local function resumePause(self)
	-- Une reprise ne compte qu'une fois : le menu doit être ouvert.
	if not self.pauseOverlay.Visible then
		return
	end
	self:hidePause()
	if self.callbacks.onResume then
		self.callbacks.onResume()
	end
end

local function buildPauseOverlay(self)
	local overlay = newOverlay(self.gui, Z_MODAL)
	self.pauseOverlay = overlay
	local card, scale = newCard(overlay, PAUSE_SIZE, Z_MODAL + 1)
	self.pauseCard = card
	self.pauseScale = scale

	self.pauseTitle = Theme.label(card, "Pause", {
		Position = UDim2.fromOffset(CARD_PADDING, 24),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, 42),
		Font = Theme.FontBlack,
		TextSize = 32,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})
	self.pauseCaption = Theme.label(card, "", {
		Position = UDim2.fromOffset(CARD_PADDING, 68),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, 24),
		TextSize = 14,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})

	-- Page du menu : la liste empile les boutons, un bouton masqué ne laisse pas de trou.
	local menuPage = Theme.new("Frame", {
		Parent = card,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 62,
	})
	self.pauseMenuPage = menuPage
	local list = Theme.new("Frame", {
		Parent = menuPage,
		Position = UDim2.fromOffset(CARD_PADDING, CONTENT_Y),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, 4 * BUTTON_HEIGHT + 3 * BUTTON_GAP),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 62,
	})
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, BUTTON_GAP)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	menuButton(list, 1, "Reprendre", true, Icons.play, function()
		resumePause(self)
	end)
	-- Le menu ne se ferme qu'à GameStarted : si le serveur refuse la demande (limite
	-- de débit), la partie reste en pause et le menu reste ouvert pour réessayer.
	self.restartButton = menuButton(list, 2, "Recommencer", false, Icons.reload, function()
		if self.callbacks.onRestart then
			self.callbacks.onRestart()
		end
	end)
	menuButton(list, 3, "Paramètres", false, Icons.sliders, function()
		showPausePage(self, "settings")
	end)
	menuButton(list, 4, "Menu principal", false, Icons.menu, function()
		self:hideModals()
		if self.callbacks.onMenu then
			self.callbacks.onMenu()
		end
	end)

	-- Page des réglages : un interrupteur par réglage, puis le retour.
	local settingsPage = Theme.new("Frame", {
		Parent = card,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 62,
	})
	self.pauseSettingsPage = settingsPage
	for index, row in ipairs(SETTINGS_ROWS) do
		buildSwitchRow(self, settingsPage, index, row[1], row[2])
	end
	actionButton(
		settingsPage,
		"Retour",
		UDim2.fromOffset(CARD_PADDING, CONTENT_Y + #SETTINGS_ROWS * (BUTTON_HEIGHT + BUTTON_GAP)),
		UDim2.new(1, -2 * CARD_PADDING, 0, BUTTON_HEIGHT),
		false,
		function()
			showPausePage(self, "menu")
		end
	)

	showPausePage(self, "menu")
end

-- Vide la liste des statistiques et la reconstruit avec les lignes présentes.
local function rebuildStats(self, stats)
	for _, tile in ipairs(self.statTiles) do
		tile:Destroy()
	end
	table.clear(self.statTiles)
	if type(stats) ~= "table" then
		return
	end
	for index, row in ipairs(STAT_ROWS) do
		local value = numberOr(stats[row[1]], nil)
		if value ~= nil then
			local tile = Theme.new("Frame", {
				Parent = self.statGrid,
				BackgroundColor3 = Theme.PanelSoft,
				BorderSizePixel = 0,
				LayoutOrder = index,
				ZIndex = 62,
			})
			Theme.corner(tile, Theme.Radius.Medium)
			Theme.label(tile, formatNumber(value), {
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(1, -20, 0, 24),
				Font = Theme.FontBlack,
				TextSize = 20,
				TextColor3 = Theme.Ink,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 63,
			})
			Theme.label(tile, row[2], {
				Position = UDim2.fromOffset(10, 28),
				Size = UDim2.new(1, -20, 0, 18),
				TextSize = 11,
				TextColor3 = Theme.InkSoft,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 63,
			})
			table.insert(self.statTiles, tile)
		end
	end
end

local function buildGameOverOverlay(self)
	local overlay = newOverlay(self.gui, Z_MODAL)
	self.overOverlay = overlay
	local card, scale = newCard(overlay, OVER_SIZE, Z_MODAL + 1)
	self.overCard = card
	self.overScale = scale

	Theme.label(card, "Partie terminée", {
		Position = UDim2.fromOffset(CARD_PADDING, 22),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, 40),
		Font = Theme.FontBlack,
		TextSize = 30,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})
	self.finalMap = Theme.label(card, "", {
		Position = UDim2.fromOffset(CARD_PADDING, 62),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, 22),
		TextSize = 14,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})

	Theme.label(card, "SCORE", {
		Position = UDim2.fromOffset(CARD_PADDING, 96),
		Size = UDim2.fromOffset(220, 20),
		TextSize = 11,
		Font = Theme.FontBold,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})
	self.finalScore = Theme.label(card, "0", {
		Position = UDim2.fromOffset(CARD_PADDING, 112),
		Size = UDim2.fromOffset(240, 60),
		Font = Theme.FontBlack,
		TextSize = 50,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})
	-- Un score à sept chiffres ou plus déborderait de la case : le texte se réduit.
	Theme.textScaled(self.finalScore, 50, 24)
	self.finalDuration = Theme.label(card, "", {
		Position = UDim2.fromOffset(280, 96),
		Size = UDim2.fromOffset(190, 20),
		TextSize = 14,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 62,
	})
	-- Meilleur score, ou marque « Nouveau record » sur une pastille.
	self.finalBest = Theme.label(card, "", {
		Position = UDim2.fromOffset(300, 130),
		Size = UDim2.fromOffset(170, 30),
		Font = Theme.FontBold,
		TextSize = 15,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 62,
	})
	Theme.corner(self.finalBest, Theme.Radius.Pill)

	self.finalWeek = Theme.label(card, "", {
		Position = UDim2.fromOffset(CARD_PADDING, 176),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, 20),
		TextSize = 13,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})
	self.finalReason = Theme.label(card, "", {
		Position = UDim2.fromOffset(CARD_PADDING, 198),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, 20),
		TextSize = 13,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 62,
	})

	Theme.new("Frame", {
		Parent = card,
		Position = UDim2.fromOffset(CARD_PADDING, 222),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, 1),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		ZIndex = 62,
	})

	-- Grille des statistiques : trois colonnes, les lignes absentes ne laissent pas de case.
	self.statGrid = Theme.new("Frame", {
		Parent = card,
		Position = UDim2.fromOffset(CARD_PADDING, 232),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, 110),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 62,
	})
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(140, 50)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.FillDirectionMaxCells = 3
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = self.statGrid
	self.statTiles = {}

	self.overRestart = actionButton(
		card,
		"Rejouer",
		UDim2.fromOffset(CARD_PADDING, 356),
		UDim2.fromOffset(212, BUTTON_HEIGHT + 2),
		true,
		function()
			-- Même règle que « Recommencer » : la carte reste jusqu'à GameStarted.
			if self.callbacks.onRestart then
				self.callbacks.onRestart()
			end
		end
	)
	self.overMenu = actionButton(
		card,
		"Menu principal",
		UDim2.fromOffset(OVER_SIZE.X.Offset - CARD_PADDING - 212, 356),
		UDim2.fromOffset(212, BUTTON_HEIGHT + 2),
		false,
		function()
			self:hideModals()
			if self.callbacks.onMenu then
				self.callbacks.onMenu()
			end
		end
	)
end

-- Couleur d'accent d'une amélioration : le circuit a la sienne, les autres suivent leur type.
local function optionColor(option)
	if option.trafficFactor then
		return Theme.AccentWarm
	end
	if option.kind == "roads" then
		return Theme.PanelDark
	end
	if option.kind == "bridges" then
		return Theme.Bridge
	end
	return Theme.TealDark
end

-- Pictogramme d'une amélioration, blanc sur la pastille teintée (le circuit,
-- sur fond chaud, est dessiné en encre).
local function drawOptionIcon(circle, option)
	if option.trafficFactor then
		Icons.cars(circle, Theme.Ink, CARS_ICON_SIZE)
	elseif option.kind == "roads" then
		Icons.road(circle, Theme.White)
	elseif option.kind == "bridges" then
		Icons.bridge(circle, Theme.White)
	else
		Icons.roundabout(circle, Theme.White)
	end
end

local function clearChoiceCards(self)
	for _, connection in ipairs(self.choiceConnections) do
		connection:Disconnect()
	end
	table.clear(self.choiceConnections)
	for _, child in ipairs(self.choiceOptions:GetChildren()) do
		if not child:IsA("UIListLayout") then
			-- Le survol d'une carte anime sa sélection : on coupe ces tweens avant
			-- de détruire la carte et ses descendants.
			Theme.stopTweens(child)
			for _, descendant in ipairs(child:GetDescendants()) do
				Theme.stopTweens(descendant)
			end
			child:Destroy()
		end
	end
end

-- Choisit une amélioration : une seule fois, puis la carte se ferme.
local function chooseOption(self, option)
	if not self.choiceOverlay.Visible then
		return
	end
	self.choiceDismissedWeek = self.choiceWeek
	self.choicePending = nil
	closeOverlay(self.choiceOverlay)
	if self.callbacks.onChooseReward then
		self.callbacks.onChooseReward(option.id)
	end
end

local function buildOptionCard(self, option, index, count)
	local card = Theme.new("Frame", {
		Parent = self.choiceOptions,
		Size = UDim2.new(1 / count, -math.ceil(OPTION_GAP * (count - 1) / count), 0, OPTION_HEIGHT),
		BackgroundColor3 = Theme.PanelSoft,
		BorderSizePixel = 0,
		LayoutOrder = index,
		ZIndex = 73,
	})
	Theme.corner(card, Theme.Radius.Large)
	Theme.stroke(card, Theme.Border, Theme.Stroke.Thin, Theme.Stroke.Transparency)

	-- Numéro de la touche (1, 2, 3) dans le coin.
	local badge = Theme.pill(card, tostring(index), {
		Size = UDim2.fromOffset(22, 22),
		TextSize = 12,
		TextColor3 = Theme.InkSoft,
		ZIndex = 74,
	})
	badge.AnchorPoint = Vector2.new(0, 0)
	badge.Position = UDim2.fromOffset(10, 10)

	local circle = Theme.circle(card, 56, optionColor(option), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 20),
		ZIndex = 74,
	})
	drawOptionIcon(circle, option)

	local title = Theme.label(card, textOr(option.title, "Amélioration"), {
		Position = UDim2.new(0, 12, 0, 86),
		Size = UDim2.new(1, -24, 0, 40),
		Font = Theme.FontBlack,
		TextColor3 = Theme.Ink,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 74,
	})
	Theme.textScaled(title, 18, 11)

	local description = Theme.label(card, textOr(option.description, ""), {
		Position = UDim2.new(0, 12, 0, 130),
		Size = UDim2.new(1, -24, 0, 46),
		TextSize = 12,
		TextColor3 = Theme.InkSoft,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 74,
	})
	Theme.textScaled(description, 12, 9)

	-- Montant de la ressource, en pastille sous la description.
	local amount = numberOr(option.roads, numberOr(option.amount, 0))
	local amountLabel = Theme.pill(card, "+" .. formatNumber(amount) .. " routes", {
		Size = UDim2.fromOffset(120, 24),
		TextSize = 12,
		TextColor3 = Theme.Ink,
		BackgroundColor3 = Theme.Panel,
		ZIndex = 74,
	})
	amountLabel.AnchorPoint = Vector2.new(0.5, 1)
	amountLabel.Position = UDim2.new(0.5, 0, 1, -12)

	-- Zone cliquable couvrant la carte ; le survol la met en avant.
	local hit = Theme.new("TextButton", {
		Parent = card,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Active = true,
		Selectable = true,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		ZIndex = 76,
	})
	local connections = self.choiceConnections
	table.insert(connections, hit.MouseEnter:Connect(function()
		Theme.setSelected(card, true)
	end))
	table.insert(connections, hit.MouseLeave:Connect(function()
		Theme.setSelected(card, false)
	end))
	local function choose()
		chooseOption(self, option)
	end
	-- Activated couvre souris, tactile et manette.
	table.insert(connections, hit.Activated:Connect(choose))
end

local function showChoiceNow(self)
	local pending = self.choicePending
	if not pending then
		return
	end
	self.choiceTitle.Text = type(pending.week) == "number" and ("Semaine " .. tostring(pending.week)) or "Nouvelle amélioration"
	clearChoiceCards(self)
	self.choiceOptionList = pending.options
	for index, option in ipairs(pending.options) do
		buildOptionCard(self, option, index, #pending.options)
	end
	openOverlay(self.choiceOverlay)
end

-- Rouvre le choix mis en attente quand aucune autre couche ne le recouvre.
local function restoreChoice(self)
	if self.choicePending and not self.pauseOverlay.Visible and not self.overOverlay.Visible then
		showChoiceNow(self)
	end
end

local function buildWeekChoiceOverlay(self)
	local overlay = newOverlay(self.gui, Z_CHOICE)
	self.choiceOverlay = overlay
	local card, scale = newCard(overlay, CHOICE_SIZE, Z_CHOICE + 1)
	self.choiceCard = card
	self.choiceScale = scale

	self.choiceTitle = Theme.label(card, "", {
		Position = UDim2.fromOffset(CARD_PADDING, 22),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, 38),
		Font = Theme.FontBlack,
		TextSize = 30,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 72,
	})
	Theme.label(card, "Choisissez une amélioration pour continuer.", {
		Position = UDim2.fromOffset(CARD_PADDING, 62),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, 24),
		TextSize = 14,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 72,
	})

	local options = Theme.new("Frame", {
		Parent = card,
		Position = UDim2.fromOffset(CARD_PADDING, 106),
		Size = UDim2.new(1, -2 * CARD_PADDING, 0, OPTION_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 72,
	})
	self.choiceOptions = options
	newOptionLayout(options)
end

-- Notification bref, en file : un message à la fois, chacun reste TOAST_DURATION s.
local function showNextToast(self)
	local message = table.remove(self.toastQueue, 1)
	if not message then
		self.toastShowing = false
		return
	end
	self.toastShowing = true
	self.toastLabel.Text = message
	self.toastLabel.Visible = true
	self.toastTimer = task.delay(TOAST_DURATION, function()
		self.toastTimer = nil
		self.toastLabel.Visible = false
		showNextToast(self)
	end)
end

return function(HUD)
	function HUD:buildToast()
		self.toastLabel = Theme.label(self.gui, "", {
			Position = UDim2.fromScale(0.5, 0.12),
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.new(0.7, 0, 0, 34),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.08,
			TextSize = 13,
			TextColor3 = Theme.Ink,
			Visible = false,
			ZIndex = 55,
		})
		Theme.corner(self.toastLabel, Theme.Radius.Pill)
		Theme.textScaled(self.toastLabel, 13, 8)
		Theme.maxSize(self.toastLabel, 560, 34)
		self.toastQueue = {}
		self.toastShowing = false
	end

	function HUD:buildOverlays()
		-- Réglages de la session : gardés dans l'objet HUD, pas dans le stockage du navigateur.
		-- Grille : par défaut elle suit l'outil (visible en construction) ; épinglée, elle reste visible.
		self.settings = { grid = false, hints = true }
		self.switchViews = {}
		self.statTiles = {}
		self.choiceConnections = {}
		self.choiceOptionList = {}
		self.choicePending = nil

		buildPauseOverlay(self)
		buildGameOverOverlay(self)
		buildWeekChoiceOverlay(self)

		-- Échap ferme le menu pause (ou revient du réglage) ; 1 à 3 choisissent une amélioration.
		self.overlayInput = UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.Escape then
				if self.pauseOverlay.Visible then
					if self.pauseSettingsPage.Visible then
						showPausePage(self, "menu")
					else
						resumePause(self)
					end
				end
				return
			end
			if processed or not self.choiceOverlay.Visible then
				return
			end
			for index, key in ipairs(OPTION_KEYS) do
				if input.KeyCode == key then
					local option = self.choiceOptionList[index]
					if option then
						chooseOption(self, option)
					end
					return
				end
			end
		end)
	end

	-- Menu pause : seulement si la fin de partie n'est pas affichée.
	function HUD:showPause()
		if self.pauseOverlay.Visible or self.overOverlay.Visible then
			return
		end
		-- Le choix hebdomadaire reste en attente et réapparaît à la reprise.
		closeOverlay(self.choiceOverlay)
		showPausePage(self, "menu")
		paintSwitch(self, "grid", true)
		paintSwitch(self, "hints", true)
		self.restartButton.Visible = self.callbacks.onRestart and true or false
		openOverlay(self.pauseOverlay)
		self:setPaused(true)
	end

	function HUD:hidePause()
		closeOverlay(self.pauseOverlay)
		showPausePage(self, "menu")
		self:setPaused(false)
		restoreChoice(self)
	end

	-- Libère les connexions globales et celles des cartes de choix (appelé par HUD:destroy).
	function HUD:releaseOverlays()
		if self.overlayInput then
			self.overlayInput:Disconnect()
			self.overlayInput = nil
		end
		for _, connection in ipairs(self.choiceConnections) do
			connection:Disconnect()
		end
		table.clear(self.choiceConnections)
	end

	-- Permet à la touche P de reprendre si le menu est déjà ouvert, sans rouvrir la pause.
	function HUD:isPauseOpen()
		return self.pauseOverlay.Visible
	end

	function HUD:isGameOverOpen()
		return self.overOverlay.Visible
	end

	-- Vrai si le choix hebdomadaire est affiché : les commandes de la carte restent coupées.
	function HUD:isChoiceOpen()
		return self.choiceOverlay.Visible
	end

	-- Valeur d'un réglage de la session (« grid », « hints »).
	function HUD:getSetting(name)
		return self.settings[name] == true
	end

	function HUD:showGameOver(data)
		if type(data) ~= "table" then
			data = {}
		end
		-- La fin de partie annule le choix en attente et les autres couches.
		self.choicePending = nil
		closeOverlay(self.choiceOverlay)
		closeOverlay(self.pauseOverlay)
		showPausePage(self, "menu")
		self.controls.Visible = false
		self:cancelHintTimer()
		self:setHintShown(false)

		self.finalMap.Text = self.mapName or ""
		local score = numberOr(data.score, 0)
		local best = numberOr(data.best, 0)
		self.finalScore.Text = formatNumber(score)
		if score > 0 and score >= best then
			self.finalBest.Text = "Nouveau record !"
			self.finalBest.BackgroundTransparency = 0
			self.finalBest.BackgroundColor3 = Theme.Orange
			self.finalBest.TextColor3 = Theme.Ink
		else
			self.finalBest.Text = "Meilleur : " .. formatNumber(best)
			self.finalBest.BackgroundTransparency = 1
			self.finalBest.TextColor3 = Theme.InkSoft
		end
		self.finalDuration.Text = "Durée " .. formatDuration(data.durationSeconds)

		local parts: { string } = {}
		local week = numberOr(data.week, nil)
		if week then
			table.insert(parts, "Semaine " .. formatNumber(week))
		end
		local day = numberOr(data.day, nil)
		local monthName = textOr(data.monthName, nil)
		if day then
			table.insert(parts, "Jour " .. formatNumber(day) .. (monthName and (" · " .. monthName) or ""))
		end
		self.finalWeek.Text = table.concat(parts, "  ·  ")

		local reason = reasonText(data)
		self.finalReason.Text = reason or ""
		self.finalReason.Visible = reason ~= nil

		rebuildStats(self, data.stats)
		self.overRestart.Visible = self.callbacks.onRestart and true or false
		self.overMenu.Visible = self.callbacks.onMenu and true or false
		openOverlay(self.overOverlay)
	end

	-- Choix hebdomadaire : une demande incomplète est ignorée, sans bloquer la partie.
	function HUD:showWeekChoice(data)
		if type(data) ~= "table" then
			return
		end
		local options = sanitizeOptions(data.options)
		if #options == 0 then
			return
		end
		if self.choiceOverlay.Visible and self.choiceWeek == data.week then
			return
		end
		self.choiceWeek = data.week
		self.choicePending = { week = data.week, options = options }
		-- Une autre couche est ouverte : le choix attend sa fermeture.
		if self.pauseOverlay.Visible or self.overOverlay.Visible then
			return
		end
		showChoiceNow(self)
	end

	function HUD:hideWeekChoice()
		self.choiceDismissedWeek = self.choiceWeek
		self.choicePending = nil
		closeOverlay(self.choiceOverlay)
	end

	-- Ferme toutes les couches et remet le menu pause sur sa page d'accueil.
	function HUD:hideModals()
		self.choicePending = nil
		closeOverlay(self.pauseOverlay)
		closeOverlay(self.overOverlay)
		closeOverlay(self.choiceOverlay)
		showPausePage(self, "menu")
	end

	-- Vide la file et retire le message affiché (nouvelle partie, destruction).
	function HUD:clearToasts()
		if self.toastTimer then
			task.cancel(self.toastTimer)
			self.toastTimer = nil
		end
		table.clear(self.toastQueue)
		self.toastShowing = false
		self.toastLabel.Visible = false
	end

	-- Message bref. Les messages s'enchaînent sans se superposer ; au-delà de la
	-- file, le plus ancien est abandonné.
	function HUD:toast(text)
		local message = textOr(text, nil)
		if not message or self.destroyed then
			return
		end
		if #self.toastQueue >= TOAST_QUEUE_MAX then
			table.remove(self.toastQueue, 1)
		end
		table.insert(self.toastQueue, message)
		if not self.toastShowing then
			showNextToast(self)
		end
	end
end
