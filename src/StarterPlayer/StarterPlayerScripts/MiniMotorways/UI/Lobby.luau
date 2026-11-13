--[[
	Lobby.luau
	Menu principal, choix de la ville, options, palmarès, garage et statistiques.
	Style clair de la capture : fond quadrillé, titre, boutons menthe et cartes
	avec aperçu circulaire. Couleurs : Config.Colors, relayées par Theme.
	Le décor animé ne tourne que lorsque le menu principal est visible.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Theme = require(script.Parent.Theme)
local MapPreview = require(script.Parent.MapPreview)

local COLORS = Config.Colors

local Lobby = {}
Lobby.__index = Lobby

local DEFAULT_MAP_ID = "los_angeles"

-- Cartes des villes : taille de référence, mise à l'échelle sur petit écran.
local CARD_WIDTH = 320
local CARD_HEIGHT = 470
local CARD_GAP = Theme.Space.XL
local MIN_CARD_SCALE = 0.4

-- Seuils d'écran : portrait (téléphone debout) et hauteur courte (paysage).
local PORTRAIT_MIN_WIDTH = 760
local SHORT_HEIGHT = 700

-- Espaces : tous viennent de Theme.Space.
local SECTION_GAP = Theme.Space.M
local HEADER_GAP = Theme.Space.S
local EDGE_MARGIN = Theme.Space.L

local MENU_GAP = Theme.Space.M
local MENU_ITEM_COUNT = 5
local TITLE_SIZE = 92
-- Le titre se réduit pour rester à l'écran, sans descendre sous ce facteur.
local TITLE_MIN_SCALE = 0.3
-- Trois pastilles orange après le titre : décalage, taille et pas entre elles.
local DOT_COUNT = 3
local DOT_SIZE = 24
local DOT_OFFSET = 22
local DOT_STEP = 34
local PLAY_HEIGHT = 64
local PLAY_HEIGHT_SHORT = 48
local HINT_HEIGHT = 22
local HINT_MARGIN = 12
local RAIL_LEFT = 0.024
local RAIL_WIDTH = 58
local RAIL_ITEM = 56
local RAIL_GAP = 10
local RAIL_HEIGHT = 4 * RAIL_ITEM + 3 * RAIL_GAP
local RAIL_ICON_SIZE = 26

local RADIUS_BUTTON = Theme.Radius.Medium
local RADIUS_CARD = Theme.Radius.Large
local RADIUS_MODAL = Theme.Radius.Large

-- Texte d'une valeur absente (pas de record). Un tiret ASCII : le tiret long
-- n'est pas garanti dans la police Roblox.
local NO_SCORE = "-"

-- Anti double-clic : un clic reçu deux fois (Activated + MouseButton1Click)
-- ne compte qu'une fois ; deux clics rapprochés sur une carte lancent la ville.
local CLICK_DEBOUNCE = 0.12
local DOUBLE_CLICK_WINDOW = 0.45

local TOAST_DURATION = 2.4
local RESET_ARM_DURATION = 3

-- Décor : proportions relatives à la largeur de la zone de décor.
local ROAD_RATIO = 0.030
local CAR_RATIO = 0.0105
local CAR_SHADOW_OFFSET = Vector2.new(3, 4)

-- Couleurs propres au lobby, lues dans Config.Colors.
local TOKENS = {
	BackgroundTop = COLORS.LobbyBackgroundTop,
	BackgroundBottom = COLORS.LobbyBackgroundBottom,
	Accent = COLORS.LobbyAccent,
	AccentDeep = COLORS.LobbyAccentDeep,
}

-- Score d'une carte : seul un nombre fini et positif compte, le reste vaut 0.
local function bestOf(value)
	if typeof(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
		return 0
	end
	return math.floor(value)
end

-- Forme plate arrondie (décor, cartes). Le rayon est un UDim : UDim.new(1, 0)
-- donne une pastille parfaite quelle que soit la taille.
local function plate(parent, props, radius)
	props.Parent = parent
	props.BorderSizePixel = 0
	local frame = Theme.new("Frame", props)
	if radius then
		Theme.corner(frame, radius)
	end
	return frame
end

-- Affiche ou cache une page ou une couche. Cachée, ses boutons repartent sans
-- survol : une cible masquée sous le curseur ne signale pas toujours MouseLeave.
local function setShown(frame, visible)
	if not visible then
		Theme.resetHover(frame)
	end
	frame.Visible = visible
end

-- Icônes de la colonne latérale, en formes plates (pas de caractère Unicode :
-- la police Roblox ne garantit pas leurs glyphes). Une pièce vaut
-- { x, y, largeur, hauteur, rayon, rôle } dans une boîte RAIL_ICON_SIZE ;
-- le rôle « bg » prend la couleur du fond du bouton, pour creuser une forme.
local RAIL_ICONS = {
	map = {
		{ 5, 3, 16, 16, 8, "fg" },
		{ 10, 8, 6, 6, 3, "bg" },
	},
	garage = {
		{ 2, 9, 22, 10, 4, "fg" },
		{ 6, 3, 14, 9, 4, "fg" },
		{ 5, 15, 6, 6, 3, "fg" },
		{ 15, 15, 6, 6, 3, "fg" },
	},
	records = {
		{ 3, 2, 18, 18, 9, "fg" },
		{ 7, 6, 10, 10, 5, "bg" },
		{ 6, 17, 5, 7, 1, "fg" },
		{ 13, 17, 5, 7, 1, "fg" },
	},
	stats = {
		{ 2, 14, 5, 8, 1, "fg" },
		{ 9, 8, 5, 14, 1, "fg" },
		{ 16, 3, 5, 19, 1, "fg" },
	},
}

local function drawRailIcon(button, kind, color)
	local box = Theme.new("Frame", {
		Name = "Icon",
		Parent = button,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RAIL_ICON_SIZE, RAIL_ICON_SIZE),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	for _, piece in ipairs(RAIL_ICONS[kind]) do
		plate(box, {
			Position = UDim2.fromOffset(piece[1], piece[2]),
			Size = UDim2.fromOffset(piece[3], piece[4]),
			BackgroundColor3 = piece[6] == "bg" and button.BackgroundColor3 or color,
		}, UDim.new(0, piece[5]))
	end
end

-- Flèche « retour » en deux barres fines, sans caractère « ‹ » de la police.
-- La pointe est en (x, centre vertical) ; chaque barre fait CHEVRON_ARM px.
local CHEVRON_ARM = 10
local CHEVRON_HALF = 3.5
local CHEVRON_THICKNESS = 2

local function drawChevron(button, x, color)
	for _, arm in ipairs({ { -45, -CHEVRON_HALF }, { 45, CHEVRON_HALF } }) do
		plate(button, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, x + CHEVRON_HALF, 0.5, arm[2]),
			Size = UDim2.fromOffset(CHEVRON_ARM, CHEVRON_THICKNESS),
			Rotation = arm[1],
			BackgroundColor3 = color,
		}, UDim.new(0, CHEVRON_THICKNESS / 2))
	end
end

-- Point d'une spline de Catmull-Rom : sert à dessiner une route douce avec
-- des segments arrondis, sans image ni mesh.
local function catmullRomPoint(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return (p1 * 2
			+ (p2 - p0) * t
			+ (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
			+ (p1 * 3 - p0 - p2 * 3 + p3) * t3)
		* 0.5
end

local function samplePath(controls, stepsPerSegment)
	local points = {}
	for i = 1, #controls - 1 do
		local p0 = controls[math.max(1, i - 1)]
		local p1 = controls[i]
		local p2 = controls[i + 1]
		local p3 = controls[math.min(#controls, i + 2)]
		for step = 0, stepsPerSegment - 1 do
			table.insert(points, catmullRomPoint(p0, p1, p2, p3, step / stepsPerSegment))
		end
	end
	table.insert(points, controls[#controls])
	return points
end

--[[
	Mise en page responsive. Fonction pure : les tests vérifient qu'aucun
	élément ne sort de l'écran sans avoir besoin de rendu. Les positions en
	fraction (0..1) sont relatives à l'écran ; les tailles sont en pixels.
	titleWidth : largeur du titre et de ses pastilles, à taille normale, mesurée
	par TextService (la police n'est connue qu'à l'exécution).
]]
function Lobby.layoutFor(width, height, titleWidth)
	local portrait = width < PORTRAIT_MIN_WIDTH or width < height * 0.9
	local short = height < SHORT_HEIGHT
	local titleX = portrait and 0.08 or 0.21
	-- Le titre se réduit s'il ne tient pas entre son bord gauche et l'écran.
	local titleFit = (width * (1 - titleX) - EDGE_MARGIN) / titleWidth
	local titleScale = math.clamp(
		math.min(portrait and width / 720 or width / 1600, titleFit),
		TITLE_MIN_SCALE,
		1
	)

	-- Sur un écran étroit en paysage, la colonne d'icônes recule la zone des cartes.
	local scrollerX = portrait and 0.05 or 0.09
	local scrollerWidth = portrait and 0.9 or 0.86
	if not portrait then
		local railClear = RAIL_LEFT + (RAIL_WIDTH + SECTION_GAP) / width
		if railClear > scrollerX then
			scrollerX = railClear
			scrollerWidth = 1 - 2 * railClear
		end
	end

	local hintVisible = not short
	local playHeight = short and PLAY_HEIGHT_SHORT or PLAY_HEIGHT
	local hintTop = height - HINT_MARGIN - HINT_HEIGHT
	local playTop = hintVisible and (hintTop - SECTION_GAP - playHeight)
		or (height - EDGE_MARGIN - playHeight)

	-- La zone des cartes va du sous-titre jusqu'au bouton Jouer. Les cartes
	-- rétrécissent si la hauteur ne suffit pas (paysage téléphone).
	-- Le bouton Retour et le sous-titre restent au-dessus de la zone des cartes,
	-- même sur un écran très bas.
	local backY = portrait and 0.028 or 0.048
	local backHeight = portrait and 34 or 42
	local subtitleY = portrait and 0.15 or 0.103
	local subtitleBottom = height * (subtitleY + 0.028)
	local scrollerTop = math.max(
		height * (portrait and 0.19 or 0.145),
		height * backY + backHeight + HEADER_GAP,
		subtitleBottom + HEADER_GAP
	)
	local scrollerHeight = math.max(0, playTop - SECTION_GAP - scrollerTop)
	local cardScale = math.clamp((scrollerHeight - EDGE_MARGIN) / CARD_HEIGHT, MIN_CARD_SCALE, 1)

	local buttonHeight = math.clamp(height * 0.075, 30, 52)
	local infoSize = portrait and 60 or math.clamp(height * 0.068, 52, 74)
	local railTop = math.max(12, math.min(height * 0.34, height - RAIL_HEIGHT - 12))

	return {
		portrait = portrait,
		decorVisible = not portrait,
		railVisible = not portrait,
		railX = RAIL_LEFT,
		railWidth = RAIL_WIDTH,
		railTop = railTop,
		railHeight = RAIL_HEIGHT,
		hintVisible = hintVisible,
		hintTop = hintTop,
		titleX = titleX,
		titleY = portrait and 0.115 or 0.165,
		titleScale = titleScale,
		menuX = portrait and 0.08 or 0.21,
		menuY = portrait and 0.36 or 0.43,
		menuWidth = portrait and 0.84 or 0.19,
		menuHeight = MENU_ITEM_COUNT * buttonHeight + (MENU_ITEM_COUNT - 1) * MENU_GAP,
		buttonHeight = buttonHeight,
		infoSize = infoSize,
		infoX = portrait and 0.94 or 0.955,
		infoY = portrait and 0.94 or 0.925,
		destinationSize = math.clamp(height * 0.16, 100, 190),
		houseSize = math.clamp(height * 0.095, 66, 112),
		mapTitleY = portrait and 0.09 or 0.04,
		mapTitleWidth = portrait and 0.72 or 0.5,
		subtitleY = subtitleY,
		subtitleWidth = portrait and 0.8 or 0.62,
		backY = backY,
		backWidth = portrait and math.min(96, width * 0.28) or 118,
		backHeight = backHeight,
		scrollerX = scrollerX,
		scrollerWidth = scrollerWidth,
		scrollerTop = scrollerTop,
		scrollerHeight = scrollerHeight,
		cardScale = cardScale,
		cardWidth = CARD_WIDTH * cardScale,
		cardHeight = CARD_HEIGHT * cardScale,
		playTop = playTop,
		playHeight = playHeight,
	}
end

function Lobby.new(callbacks)
	local self = setmetatable({}, Lobby)
	self.callbacks = callbacks or {}
	self.cards = {}
	self.recordLabels = {}
	self.menuItems = {}
	self.modalScales = {}
	self.overlays = {}
	self.connections = {}
	self.frameConnection = nil
	self.decorRoads = {}
	self.decorRoutes = {}
	self.decorCars = {}
	self.decorTime = 0
	self.selectedId = (Maps.getById(DEFAULT_MAP_ID) or Maps.all()[1]).id
	self.lastClickId = nil
	self.lastClickAt = 0
	self.toastToken = 0
	self.resetToken = 0
	self.cardScale = 1
	self.destroyed = false
	self:build()
	self:track(self.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:updateResponsive()
	end))
	self:updateResponsive()
	return self
end

-- Garde une connexion persistante pour la libérer dans destroy().
function Lobby:track(connection)
	table.insert(self.connections, connection)
	return connection
end

-- Bouton du lobby : Theme.button (couleur au survol) plus Theme.motion (échelle
-- au survol et au clic, bornée par Theme.Motion). Aucun UIScale n'est ajouté ici
-- à la main : seul Theme.motion en pose un, donc jamais deux échelles par bouton.
-- Les connexions de Theme.button ne sont pas suivies ici : elles sont libérées
-- avec le ScreenGui, car Destroy coupe les événements de l'instance et de ses
-- descendants (le harnais de test reproduit ce comportement).
function Lobby:button(parent, text, props, onClick)
	local button = Theme.button(parent, text, props, onClick)
	Theme.motion(button)
	return button
end

function Lobby:build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "MM_Lobby"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	self.gui = gui

	local background = Theme.new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.LobbyBackground,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 0,
	})
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(TOKENS.BackgroundTop, TOKENS.BackgroundBottom)
	gradient.Parent = background

	-- La grille est construite à part pour garder des cases carrées, même
	-- sur un écran large, comme sur la capture de référence.
	self.lobbyGrid = Theme.new("Frame", {
		Name = "LobbyGrid",
		Parent = background,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 0,
	})

	local main = Theme.new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 1,
	})
	self.mainPage = main

	local mapPage = Theme.new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		Active = false,
		ZIndex = 2,
	})
	self.mapPage = mapPage

	self:buildDecoration(main)
	self:buildMain(main)
	self:buildMapPage(mapPage)
	self:buildOptions()
	self:buildRecords()
	self:buildGarage()
	self:buildStats()
	self:buildAbout()
	self:buildToast()
	self:select(self.selectedId)
end

function Lobby:buildDecoration(page)
	local decoration = Theme.new("Frame", {
		Parent = page,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 1,
	})
	self.decoration = decoration

	-- Tracés de la route : une grande courbe qui descend à droite, puis une
	-- branche qui rejoint la petite maison du bas. Les points sont normalisés
	-- et échantillonnés en spline pour obtenir des virages doux.
	local mainControls = {
		Vector2.new(0.735, -0.06),
		Vector2.new(0.735, 0.25),
		Vector2.new(0.735, 0.38),
		Vector2.new(0.760, 0.465),
		Vector2.new(0.795, 0.525),
		Vector2.new(0.805, 0.610),
		Vector2.new(0.803, 0.690),
		Vector2.new(0.780, 0.755),
		Vector2.new(0.720, 0.815),
		Vector2.new(0.650, 0.875),
		Vector2.new(0.570, 0.940),
		Vector2.new(0.470, 1.045),
	}
	local branchControls = {
		Vector2.new(0.797, 0.665),
		Vector2.new(0.790, 0.725),
		Vector2.new(0.760, 0.780),
		Vector2.new(0.720, 0.835),
		Vector2.new(0.700, 0.880),
		Vector2.new(0.700, 0.945),
	}
	self.decorRoutes = {
		{ samples = samplePath(mainControls, 5) },
		{ samples = samplePath(branchControls, 6) },
	}

	local function addRoadPath(samples, factor)
		for i = 1, #samples - 1 do
			local a = samples[i]
			local b = samples[i + 1]
			local shadow = plate(decoration, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(0, 0),
				BackgroundColor3 = Theme.LobbyRoadShadow,
				BackgroundTransparency = 0.38,
				ZIndex = 1,
			}, UDim.new(1, 0))
			table.insert(self.decorRoads, {
				frame = shadow,
				a = a,
				b = b,
				factor = factor * 1.04,
				offset = Vector2.new(5, 7),
			})

			local road = plate(decoration, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(0, 0),
				BackgroundColor3 = Theme.LobbyRoad,
				ZIndex = 2,
			}, UDim.new(1, 0))
			table.insert(self.decorRoads, {
				frame = road,
				a = a,
				b = b,
				factor = factor,
				offset = Vector2.new(0, 0),
			})
		end
	end

	addRoadPath(self.decorRoutes[1].samples, 1)
	addRoadPath(self.decorRoutes[2].samples, 0.82)

	-- Grande destination orange avec épingle, comme sur la capture.
	local destination = Theme.new("Frame", {
		Parent = decoration,
		Position = UDim2.fromScale(0.790, 0.155),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(170, 170),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10,
	})
	self.decorDestination = destination

	plate(destination, {
		Position = UDim2.fromScale(0.10, 0.12),
		Size = UDim2.fromScale(0.84, 0.84),
		BackgroundColor3 = Theme.CardShadow,
		BackgroundTransparency = 0.25,
		ZIndex = 11,
	}, UDim.new(0, 22))
	plate(destination, {
		Position = UDim2.fromScale(0.04, 0.02),
		Size = UDim2.fromScale(0.88, 0.88),
		BackgroundColor3 = Theme.LobbyRoad,
		ZIndex = 12,
	}, UDim.new(0, 22))
	plate(destination, {
		Position = UDim2.fromScale(0.10, 0.10),
		Size = UDim2.fromScale(0.76, 0.76),
		BackgroundColor3 = TOKENS.AccentDeep,
		ZIndex = 13,
	}, UDim.new(0, 14))
	plate(destination, {
		Position = UDim2.fromScale(0.10, 0.06),
		Size = UDim2.fromScale(0.76, 0.76),
		BackgroundColor3 = Theme.LobbyOrange,
		ZIndex = 14,
	}, UDim.new(0, 14))

	-- Épingle : cercle, pointe en losange et petit trou sombre.
	Theme.circle(destination, 42, Theme.CardShadow, {
		Position = UDim2.fromScale(0.5, 0.43),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 13,
	})
	plate(destination, {
		Position = UDim2.fromScale(0.5, 0.54),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(36, 36),
		Rotation = 45,
		BackgroundColor3 = Theme.InkSoft,
		ZIndex = 14,
	}, UDim.new(0, 5))
	plate(destination, {
		Position = UDim2.fromScale(0.5, 0.532),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(28, 28),
		Rotation = 45,
		BackgroundColor3 = Theme.LobbyRoad,
		ZIndex = 15,
	}, UDim.new(0, 4))
	Theme.circle(destination, 38, Theme.InkSoft, {
		Position = UDim2.fromScale(0.5, 0.43),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 16,
	})
	Theme.circle(destination, 31, Theme.LobbyRoad, {
		Position = UDim2.fromScale(0.5, 0.43),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 17,
	})
	Theme.circle(destination, 12, Theme.InkSoft, {
		Position = UDim2.fromScale(0.5, 0.43),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 18,
	})

	-- Petite maison corail/jaune au bout de la branche.
	local house = Theme.new("Frame", {
		Parent = decoration,
		Position = UDim2.fromScale(0.700, 0.885),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(96, 96),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10,
	})
	self.decorHouse = house

	plate(house, {
		Position = UDim2.fromScale(0.10, 0.12),
		Size = UDim2.fromScale(0.84, 0.84),
		BackgroundColor3 = Theme.CardShadow,
		BackgroundTransparency = 0.28,
		ZIndex = 11,
	}, UDim.new(0, 12))
	plate(house, {
		Position = UDim2.fromScale(0.04, 0.02),
		Size = UDim2.fromScale(0.88, 0.88),
		BackgroundColor3 = Theme.LobbyRoad,
		ZIndex = 12,
	}, UDim.new(0, 12))
	plate(house, {
		Position = UDim2.fromScale(0.09, 0.09),
		Size = UDim2.fromScale(0.78, 0.78),
		BackgroundColor3 = TOKENS.Accent,
		ZIndex = 13,
	}, UDim.new(0, 8))
	plate(house, {
		Position = UDim2.fromScale(0.08, 0.06),
		Size = UDim2.fromScale(0.76, 0.62),
		BackgroundColor3 = TOKENS.AccentDeep,
		ZIndex = 13,
	}, UDim.new(0, 8))
	plate(house, {
		Position = UDim2.fromScale(0.11, 0.03),
		Size = UDim2.fromScale(0.70, 0.58),
		BackgroundColor3 = Theme.LobbyOrange,
		ZIndex = 14,
	}, UDim.new(0, 7))
	for i = -1, 1 do
		plate(house, {
			Position = UDim2.fromScale(0.5 + i * 0.19, 0.065),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(10, 11),
			BackgroundColor3 = Theme.LobbyOrange,
			ZIndex = 15,
		}, UDim.new(0, 2))
	end

	-- Deux voitures : une sur le grand trajet, une sur la branche. Elles
	-- suivent réellement la courbe et sont orientées dans le sens du trajet.
	local carSettings = {
		{ path = 1, offset = 0.10, speed = 0.072, hiddenEnds = false, color = Theme.LobbyOrange },
		{ path = 2, offset = 0.12, speed = 0.115, hiddenEnds = true, color = Theme.Orange },
	}
	for _, setting in ipairs(carSettings) do
		local shadow = plate(decoration, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = Theme.CardShadow,
			BackgroundTransparency = 0.35,
			Visible = false,
			ZIndex = 3,
		}, UDim.new(1, 0))

		local body = plate(decoration, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = setting.color,
			Visible = false,
			ZIndex = 4,
		}, UDim.new(1, 0))
		Theme.stroke(body, Theme.LobbyRoad, 1.2, 0.08)

		plate(body, {
			Position = UDim2.fromScale(0.64, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0.32, 0.62),
			BackgroundColor3 = Theme.LobbyRoad,
			ZIndex = 1,
		}, UDim.new(0, 3))

		table.insert(self.decorCars, {
			body = body,
			shadow = shadow,
			path = setting.path,
			offset = setting.offset,
			speed = setting.speed,
			hiddenEnds = setting.hiddenEnds,
		})
	end

	self:track(decoration:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:updateDecorationLayout()
	end))
	task.defer(function()
		if not self.destroyed then
			self:updateDecorationLayout()
		end
	end)
end

-- Recalcule les segments de route, les longueurs cumulées des trajets et la
-- taille des voitures. Appelé seulement quand la zone de décor change de taille.
function Lobby:updateDecorationLayout()
	local decoration = self.decoration
	if not decoration then
		return
	end
	local size = decoration.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		return
	end

	local roadThickness = math.clamp(size.X * ROAD_RATIO, 18, 64)
	for _, segment in ipairs(self.decorRoads) do
		local ax = segment.a.X * size.X
		local ay = segment.a.Y * size.Y
		local bx = segment.b.X * size.X
		local by = segment.b.Y * size.Y
		local dx = bx - ax
		local dy = by - ay
		local length = math.sqrt(dx * dx + dy * dy)
		segment.frame.Visible = length > 0.1
		if length > 0.1 then
			segment.frame.Position = UDim2.fromOffset(
				(ax + bx) * 0.5 + segment.offset.X,
				(ay + by) * 0.5 + segment.offset.Y
			)
			segment.frame.Size = UDim2.fromOffset(
				length + roadThickness * 1.15,
				roadThickness * segment.factor
			)
			segment.frame.Rotation = math.deg(math.atan2(dy, dx))
		end
	end

	for _, route in ipairs(self.decorRoutes) do
		local points = {}
		local cumulative = { 0 }
		for i, sample in ipairs(route.samples) do
			points[i] = Vector2.new(sample.X * size.X, sample.Y * size.Y)
		end
		for i = 2, #points do
			cumulative[i] = cumulative[i - 1] + (points[i] - points[i - 1]).Magnitude
		end
		route.points = points
		route.cumulative = cumulative
		route.total = cumulative[#cumulative]
	end

	local carThickness = math.clamp(size.X * CAR_RATIO, 7, 13)
	local carSize = UDim2.fromOffset(carThickness * 2.05, carThickness)
	for _, car in ipairs(self.decorCars) do
		car.body.Size = carSize
		car.shadow.Size = carSize
	end

	self:updateDecorationCars()
end

-- Place les voitures d'après le temps écoulé : appelé à chaque frame tant que
-- le décor est visible, sans aucune allocation de table.
function Lobby:updateDecorationCars()
	for _, car in ipairs(self.decorCars) do
		local route = self.decorRoutes[car.path]
		if route and route.total and route.total > 0 then
			local progress = (self.decorTime * car.speed + car.offset) % 1
			local distance = progress * route.total
			local cumulative = route.cumulative
			local points = route.points
			local last = #points - 1

			local index = 1
			while index < last and cumulative[index + 1] < distance do
				index += 1
			end
			local segmentLength = cumulative[index + 1] - cumulative[index]
			local fraction = segmentLength > 0
				and math.clamp((distance - cumulative[index]) / segmentLength, 0, 1)
				or 0

			local a = points[index]
			local b = points[index + 1]
			local x = a.X + (b.X - a.X) * fraction
			local y = a.Y + (b.Y - a.Y) * fraction
			local angle = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
			local visible = not (car.hiddenEnds and (progress < 0.045 or progress > 0.93))

			car.body.Position = UDim2.fromOffset(x, y)
			car.body.Rotation = angle
			car.body.Visible = visible
			car.shadow.Position = UDim2.fromOffset(x + CAR_SHADOW_OFFSET.X, y + CAR_SHADOW_OFFSET.Y)
			car.shadow.Rotation = angle
			car.shadow.Visible = visible
		end
	end
end

-- Le décor n'est animé que si le menu principal est affiché : aucune
-- connexion à RenderStepped quand le lobby est caché ou en portrait.
function Lobby:syncFrameLoop()
	local active = not self.destroyed
		and self.gui.Enabled
		and self.mainPage.Visible
		and self.decoration.Visible
	if active and not self.frameConnection then
		self.frameConnection = RunService.RenderStepped:Connect(function(dt)
			self.decorTime += dt
			self:updateDecorationCars()
		end)
	elseif not active then
		self:stopFrameLoop()
	end
end

function Lobby:stopFrameLoop()
	if self.frameConnection then
		self.frameConnection:Disconnect()
		self.frameConnection = nil
	end
end

function Lobby:buildMain(page)
	local titleHolder = Theme.new("Frame", {
		Parent = page,
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
	})
	self.titleHolder = titleHolder

	local titleScale = Instance.new("UIScale")
	titleScale.Parent = titleHolder
	self.titleScale = titleScale

	Theme.label(titleHolder, Config.GameName, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Font = Theme.FontBlack,
		TextSize = TITLE_SIZE,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})

	-- Largeur réelle du titre : sert à le réduire pour qu'il tienne à l'écran.
	local bounds = TextService:GetTextSize(
		Config.GameName,
		TITLE_SIZE,
		Theme.FontBlack,
		Vector2.new(3000, 300)
	)
	self.titleWidth = bounds.X + DOT_OFFSET + (DOT_COUNT - 1) * DOT_STEP + DOT_SIZE

	-- Pastilles orange après le titre, comme sur la capture.
	for index = 1, DOT_COUNT do
		Theme.circle(titleHolder, DOT_SIZE, Theme.LobbyOrange, {
			Position = UDim2.fromOffset(bounds.X + DOT_OFFSET + (index - 1) * DOT_STEP, 52),
			ZIndex = 4,
		})
	end

	local menu = Theme.new("Frame", {
		Parent = page,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 3,
	})
	self.menu = menu
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, MENU_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Parent = menu

	-- Entrées du menu (9.2) : jouer, palmarès, statistiques, réglages, quitter.
	-- Les largeurs décalées reprennent le rythme de la capture de référence.
	self:addMenuItem(menu, "Jouer", 0.72, 1, function()
		if self.callbacks.onPlay then
			self.callbacks.onPlay()
		end
	end)
	self:addMenuItem(menu, "Palmarès", 0.80, 2, function()
		self:showRecords()
	end)
	self:addMenuItem(menu, "Statistiques", 0.92, 3, function()
		self:showStats()
	end)
	self:addMenuItem(menu, "Options", 0.84, 4, function()
		self:showOptions()
	end)
	self:addMenuItem(menu, "Sortir", 0.68, 5, function()
		if self.callbacks.onQuit then
			self.callbacks.onQuit()
		end
	end)

	-- Bouton info circulaire, avec une petite icône de document en blanc.
	-- Rayon « pilule » : le bouton reste un cercle à toute taille.
	local info = self:button(page, "", {
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = Theme.LobbyButton,
		CornerRadius = Theme.Radius.Pill,
		ZIndex = 10,
	}, function()
		self:showAbout()
	end)
	self.infoButton = info

	local document = plate(info, {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(30, 36),
		BackgroundColor3 = Theme.White,
		ZIndex = 11,
	}, UDim.new(0, 4))
	for index = 1, 3 do
		plate(document, {
			Position = UDim2.fromScale(0.5, 0.16 + (index - 1) * 0.18),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(17, 3),
			BackgroundColor3 = Theme.LobbyButton,
			ZIndex = 12,
		})
	end

	-- Pastille d'alerte posée sur le coin du bouton info.
	Theme.circle(info, 16, TOKENS.Accent, {
		Position = UDim2.fromOffset(-4, -4),
		ZIndex = 11,
	})
end

function Lobby:addMenuItem(menu, text, widthFraction, order, onClick)
	local button = self:button(menu, text, {
		LayoutOrder = order,
		BackgroundColor3 = Theme.LobbyButton,
		TextColor3 = Theme.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 30,
		CornerRadius = RADIUS_BUTTON,
	}, onClick)
	Theme.padding(button, 0, 8, 0, 22)
	table.insert(self.menuItems, { button = button, width = widthFraction })
	return button
end

function Lobby:buildMapPage(page)
	self.mapTitle = Theme.label(page, "Choisissez une ville", {
		Position = UDim2.fromScale(0.5, 0.040),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.5, 0.06),
		Font = Theme.FontBlack,
		TextSize = 38,
		TextColor3 = Theme.Ink,
		ZIndex = 3,
	})
	Theme.textScaled(self.mapTitle, 38, 16)

	self.mapSubtitle = Theme.label(page, "Six villes à explorer  ·  choisissez votre prochaine destination", {
		Position = UDim2.fromScale(0.5, 0.103),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.62, 0.028),
		TextSize = 15,
		TextColor3 = Theme.InkSoft,
		ZIndex = 3,
	})
	Theme.textScaled(self.mapSubtitle, 15, 8)

	self.backButton = self:button(page, "Retour", {
		Size = UDim2.fromOffset(118, 42),
		BackgroundColor3 = Theme.Panel,
		TextColor3 = Theme.Ink,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		CornerRadius = RADIUS_BUTTON,
		ZIndex = 4,
	}, function()
		self:showMain()
	end)
	-- Le texte laisse la place à la flèche dessinée à gauche.
	Theme.padding(self.backButton, 0, 8, 0, 32)
	drawChevron(self.backButton, 12, Theme.Ink)
	Theme.stroke(self.backButton, Theme.LobbyGrid, 1, 0.1)

	local scroller = Theme.new("ScrollingFrame", {
		Parent = page,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.LobbyButton,
		ClipsDescendants = true,
		ZIndex = 5,
	})
	self.scroller = scroller
	-- Marge de chaque côté de la rangée : le liseré de sélection et l'ombre de la
	-- première et de la dernière carte ne sont pas coupés par ClipsDescendants.
	-- updateCanvas compte ces deux marges dans la largeur de la zone défilante.
	Theme.padding(scroller, 0, CARD_GAP, 0, CARD_GAP)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroller
	self.cardLayout = layout

	for index, map in ipairs(Maps.all()) do
		self:buildCard(scroller, map, index)
	end
	self:track(scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:updateCanvas()
	end))
	self:updateCanvas()

	-- Rail d'icônes à gauche, pour retrouver garage, records et statistiques.
	local rail = Theme.new("Frame", {
		Parent = page,
		Size = UDim2.fromOffset(RAIL_WIDTH, RAIL_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 20,
	})
	self.rail = rail
	local railLayout = Instance.new("UIListLayout")
	railLayout.FillDirection = Enum.FillDirection.Vertical
	railLayout.Padding = UDim.new(0, RAIL_GAP)
	railLayout.SortOrder = Enum.SortOrder.LayoutOrder
	railLayout.Parent = rail

	local railItems = {
		{ kind = "map", active = true, action = nil },
		{ kind = "garage", active = false, action = function()
			self:showGarage()
		end },
		{ kind = "records", active = false, action = function()
			self:showRecords()
		end },
		{ kind = "stats", active = false, action = function()
			self:showStats()
		end },
	}
	for index, item in ipairs(railItems) do
		local button = self:button(rail, "", {
			Size = UDim2.fromOffset(RAIL_ITEM, RAIL_ITEM),
			LayoutOrder = index,
			BackgroundColor3 = item.active and Theme.LobbyButton or Theme.Panel,
			CornerRadius = RADIUS_BUTTON,
			ZIndex = 21,
		}, item.action)
		drawRailIcon(button, item.kind, item.active and Theme.White or Theme.InkSoft)
		if not item.active then
			Theme.stroke(button, Theme.LobbyGrid, 1, 0.1)
		end
	end

	self.playButton = self:button(page, "Jouer", {
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0.8, 0, 0, PLAY_HEIGHT),
		BackgroundColor3 = Theme.LobbyButton,
		TextColor3 = Theme.White,
		TextSize = 24,
		CornerRadius = RADIUS_BUTTON,
		ZIndex = 20,
	}, function()
		self:startSelected()
	end)
	Theme.maxSize(self.playButton, 340, PLAY_HEIGHT)

	self.mapHint = Theme.label(page, "Cliquez sur une ville pour la sélectionner  ·  double-cliquez pour jouer", {
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0.8, 0, 0, HINT_HEIGHT),
		TextSize = 13,
		TextColor3 = Theme.InkSoft,
		ZIndex = 20,
	})
	Theme.textScaled(self.mapHint, 13, 8)
	Theme.maxSize(self.mapHint, 560, HINT_HEIGHT)
end

function Lobby:buildCard(parent, map, order)
	local holder = Theme.new("Frame", {
		Name = "Card_" .. map.id,
		Parent = parent,
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = order,
		ZIndex = 2,
	})

	-- Toute la carte est dessinée à taille de référence puis mise à l'échelle
	-- par UIScale : textes et aperçu restent proportionnés sur petit écran.
	local inner = Theme.new("Frame", {
		Parent = holder,
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = inner

	local shadow = plate(inner, {
		Position = UDim2.fromOffset(7, 9),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.CardShadow,
		BackgroundTransparency = 0.05,
		ZIndex = 1,
	}, UDim.new(0, RADIUS_CARD))

	local card = plate(inner, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Panel,
		ClipsDescendants = true,
		ZIndex = 2,
	}, UDim.new(0, RADIUS_CARD))

	local header = Theme.new("Frame", {
		Parent = card,
		Size = UDim2.new(1, 0, 0.45, 0),
		BackgroundColor3 = map.header,
		BorderSizePixel = 0,
		ZIndex = 2,
	})
	local headerGradient = Instance.new("UIGradient")
	headerGradient.Rotation = 90
	headerGradient.Color = ColorSequence.new(map.header:Lerp(Theme.White, 0.16), map.header)
	headerGradient.Parent = header

	MapPreview.create(header, map, 178, UDim2.fromScale(0.5, 0.035), Vector2.new(0.5, 0))

	local modeBadge = Theme.label(card, string.upper(map.mode), {
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(96, 22),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.12,
		TextSize = 11,
		Font = Theme.FontBold,
		TextColor3 = map.header:Lerp(Theme.Ink, 0.55),
		ZIndex = 12,
	})
	Theme.corner(modeBadge, Theme.Radius.Pill)

	Theme.label(card, map.name, {
		Position = UDim2.fromScale(0.5, 0.475),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0.9, 0, 0.07, 0),
		Font = Theme.FontBlack,
		TextSize = 24,
		TextColor3 = Theme.Ink,
		ZIndex = 4,
	})

	local bestLabel = Theme.label(card, "Meilleur : " .. NO_SCORE, {
		Position = UDim2.fromScale(0.5, 0.548),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0.9, 0, 0.04, 0),
		TextSize = 15,
		TextColor3 = Theme.InkSoft,
		ZIndex = 4,
	})

	plate(card, {
		Position = UDim2.fromScale(0.1, 0.605),
		Size = UDim2.new(0.8, 0, 0, 2),
		BackgroundColor3 = Theme.Border,
		ZIndex = 4,
	})

	Theme.label(card, map.description, {
		Position = UDim2.fromScale(0.1, 0.635),
		Size = UDim2.new(0.8, 0, 0.24, 0),
		TextSize = 14,
		TextColor3 = Theme.InkSoft,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})

	local selectedBadge = Theme.label(card, "SÉLECTIONNÉE", {
		Position = UDim2.fromScale(0.5, 0.905),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(146, 26),
		BackgroundColor3 = Theme.LobbyOrange,
		BackgroundTransparency = 0,
		TextSize = 11,
		Font = Theme.FontBold,
		TextColor3 = Theme.Ink,
		Visible = false,
		ZIndex = 4,
	})
	Theme.corner(selectedBadge, Theme.Radius.Pill)

	-- Contour de sélection : fin et menthe, jamais noir et épais.
	local stroke = Theme.stroke(card, Theme.LobbyButton, 2, 1)

	local hit = Theme.new("TextButton", {
		Parent = card,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Active = true,
		Selectable = true,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		ZIndex = 20,
	})
	local lastHit = 0
	local function activateCard()
		local now = os.clock()
		if now - lastHit < CLICK_DEBOUNCE then
			return
		end
		lastHit = now
		if self.selectedId == map.id
			and self.lastClickId == map.id
			and now - self.lastClickAt < DOUBLE_CLICK_WINDOW
		then
			self.lastClickId = nil
			self:startSelected()
		else
			self:select(map.id)
			self.lastClickId = map.id
			self.lastClickAt = now
		end
	end
	self:track(hit.Activated:Connect(activateCard))
	self:track(hit.MouseButton1Click:Connect(activateCard))

	self.cards[map.id] = {
		holder = holder,
		scale = scale,
		card = card,
		header = header,
		stroke = stroke,
		shadow = shadow,
		bestLabel = bestLabel,
		selectedBadge = selectedBadge,
		map = map,
	}
end

-- Ajuste la zone défilante à la largeur réelle des cartes (échelle comprise).
function Lobby:updateCanvas()
	local scroller = self.scroller
	if not scroller then
		return
	end
	local cardWidth = CARD_WIDTH * self.cardScale
	local contentWidth = #Maps.all() * (cardWidth + CARD_GAP) + CARD_GAP
	local viewportWidth = scroller.AbsoluteSize.X
	scroller.CanvasSize = UDim2.fromOffset(
		math.max(contentWidth, viewportWidth),
		scroller.AbsoluteSize.Y
	)
	self.cardLayout.HorizontalAlignment = contentWidth <= viewportWidth
			and Enum.HorizontalAlignment.Center
		or Enum.HorizontalAlignment.Left
end

-- Modale : fond voilé, carte centrée et mise à l'échelle par updateResponsive.
function Lobby:makeModal(titleText, width, height)
	local overlay = Theme.new("Frame", {
		Parent = self.gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
		ZIndex = 50,
	})
	table.insert(self.overlays, overlay)

	local card = Theme.new("Frame", {
		Parent = overlay,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ZIndex = 51,
	})
	Theme.corner(card, RADIUS_MODAL)
	Theme.stroke(card, Theme.Border, 2, 0.1)

	local scale = Instance.new("UIScale")
	scale.Parent = card
	table.insert(self.modalScales, { scale = scale, width = width, height = height })

	local title = Theme.label(card, titleText, {
		Position = UDim2.fromOffset(30, 22),
		Size = UDim2.new(1, -60, 0, 42),
		Font = Theme.FontBlack,
		TextSize = 30,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 52,
	})
	Theme.textScaled(title, 30, 14)

	return overlay, card
end

-- Bouton « Fermer » standard de toutes les modales.
function Lobby:addCloseButton(card, overlay, y, width)
	return self:button(card, "Fermer", {
		Position = UDim2.fromOffset(30, y),
		Size = UDim2.fromOffset(width, 48),
		BackgroundColor3 = Theme.LobbyButton,
		TextColor3 = Theme.White,
		TextSize = 18,
		CornerRadius = RADIUS_BUTTON,
		ZIndex = 52,
	}, function()
		setShown(overlay, false)
	end)
end

function Lobby:buildOptions()
	local overlay, card = self:makeModal("Options", 500, 430)
	self.optionsOverlay = overlay

	Theme.label(card, "Commandes", {
		Position = UDim2.fromOffset(30, 78),
		Size = UDim2.fromOffset(440, 30),
		TextSize = 17,
		Font = Theme.FontBold,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 52,
	})

	Theme.label(
		card,
		"Glissez avec la souris (ou le doigt) pour tracer une route.\n"
			.. "Clic droit pour effacer.  ·  Touches 1 / 2 : route / gomme.\n"
			.. "P : pause.  ·  Chaque semaine, choisissez une amélioration.\n\n"
			.. "Les voitures livrent aux bâtiments de la même couleur.\n"
			.. "Si la jauge de trafic atteint zéro, la partie se termine.",
		{
			Position = UDim2.fromOffset(30, 112),
			Size = UDim2.fromOffset(440, 150),
			TextSize = 14,
			TextColor3 = Theme.InkSoft,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 52,
		}
	)

	-- Réinitialisation en deux temps : le premier clic arme le bouton, le
	-- second efface. Une armure non confirmée retombe toute seule.
	local armed = false
	local reset
	local function setArmed(value)
		armed = value
		local color = value and Theme.Danger or Theme.PanelSoft
		reset.Text = value and "Confirmer ?" or "Réinitialiser mes records"
		reset.BackgroundColor3 = color
		reset.TextColor3 = value and Theme.White or Theme.Danger
		reset:SetAttribute("BaseColor", color)
	end
	reset = self:button(card, "Réinitialiser mes records", {
		Position = UDim2.fromOffset(30, 285),
		Size = UDim2.fromOffset(440, 50),
		BackgroundColor3 = Theme.PanelSoft,
		TextColor3 = Theme.Danger,
		TextSize = 17,
		CornerRadius = RADIUS_BUTTON,
		ZIndex = 52,
	}, function()
		self.resetToken += 1
		if armed then
			setArmed(false)
			if self.callbacks.onResetRecords then
				self.callbacks.onResetRecords()
			end
		else
			setArmed(true)
			local token = self.resetToken
			task.delay(RESET_ARM_DURATION, function()
				if not self.destroyed and token == self.resetToken then
					setArmed(false)
				end
			end)
		end
	end)
	Theme.stroke(reset, Theme.Danger, 2, 0.4)

	self:addCloseButton(card, overlay, 350, 440)
end

function Lobby:buildRecords()
	local overlay, card = self:makeModal("Palmarès", 470, 500)
	self.recordsOverlay = overlay

	for index, map in ipairs(Maps.all()) do
		local y = 82 + (index - 1) * 54
		Theme.circle(card, 14, map.header, {
			Position = UDim2.fromOffset(30, y + 10),
			ZIndex = 52,
		})
		Theme.label(card, map.name, {
			Position = UDim2.fromOffset(56, y),
			Size = UDim2.fromOffset(220, 34),
			TextSize = 17,
			TextColor3 = Theme.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 52,
		})
		self.recordLabels[map.id] = Theme.label(card, NO_SCORE, {
			Position = UDim2.fromOffset(280, y),
			Size = UDim2.fromOffset(160, 34),
			TextSize = 17,
			Font = Theme.FontBold,
			TextColor3 = Theme.Ink,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 52,
		})

		Theme.new("Frame", {
			Parent = card,
			Position = UDim2.fromOffset(30, y + 42),
			Size = UDim2.fromOffset(410, 1),
			BackgroundColor3 = Theme.Border,
			BorderSizePixel = 0,
			ZIndex = 52,
		})
	end

	self:addCloseButton(card, overlay, 430, 410)
end

function Lobby:buildGarage()
	local overlay, card = self:makeModal("Garage", 520, 430)
	self.garageOverlay = overlay

	Theme.label(card, "Votre collection de voitures", {
		Position = UDim2.fromOffset(30, 82),
		Size = UDim2.fromOffset(460, 26),
		TextSize = 16,
		Font = Theme.FontBold,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 52,
	})

	local colors = Config.HouseColors
	for index = 1, #colors do
		local col = (index - 1) % 4
		local row = math.floor((index - 1) / 4)
		local slot = plate(card, {
			Position = UDim2.fromOffset(38 + col * 115, 128 + row * 96),
			Size = UDim2.fromOffset(96, 76),
			BackgroundColor3 = Theme.PanelSoft,
			ZIndex = 52,
		}, UDim.new(0, 8))
		local body = plate(slot, {
			Position = UDim2.fromScale(0.5, 0.42),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(42, 24),
			BackgroundColor3 = colors[index].color,
			ZIndex = 53,
		}, UDim.new(0, 5))
		plate(body, {
			Position = UDim2.fromScale(0.5, 0.36),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0.62, 0.42),
			BackgroundColor3 = Theme.White,
			ZIndex = 54,
		})
		Theme.label(slot, colors[index].name, {
			Position = UDim2.fromScale(0, 0.78),
			Size = UDim2.fromScale(1, 0.18),
			TextSize = 10,
			Font = Theme.FontBold,
			TextColor3 = Theme.InkSoft,
			ZIndex = 53,
		})
	end

	self:addCloseButton(card, overlay, 360, 460)
end

function Lobby:buildStats()
	local overlay, card = self:makeModal("Statistiques", 500, 430)
	self.statsOverlay = overlay

	local rows = {
		{ key = "total", label = "Meilleur score total", value = "0" },
		{ key = "played", label = "Villes jouées", value = "0" },
		{ key = "bestMap", label = "Meilleure ville", value = NO_SCORE },
		{ key = "average", label = "Moyenne des records", value = NO_SCORE },
	}
	self.statsLabels = {}
	for index, row in ipairs(rows) do
		local y = 88 + (index - 1) * 64
		Theme.label(card, row.label, {
			Position = UDim2.fromOffset(30, y),
			Size = UDim2.fromOffset(250, 26),
			TextSize = 15,
			TextColor3 = Theme.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 52,
		})
		self.statsLabels[row.key] = Theme.label(card, row.value, {
			Position = UDim2.fromOffset(280, y - 4),
			Size = UDim2.fromOffset(190, 34),
			TextSize = 22,
			Font = Theme.FontBlack,
			TextColor3 = Theme.Ink,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 52,
		})
		Theme.new("Frame", {
			Parent = card,
			Position = UDim2.fromOffset(30, y + 38),
			Size = UDim2.fromOffset(440, 1),
			BackgroundColor3 = Theme.Border,
			BorderSizePixel = 0,
			ZIndex = 52,
		})
	end

	self:addCloseButton(card, overlay, 360, 440)
end

function Lobby:buildAbout()
	local overlay, card = self:makeModal("À propos", 520, 380)
	self.aboutOverlay = overlay

	Theme.label(
		card,
		Config.GameName .. " (prototype Roblox)\n\n"
			.. "Inspiré du jeu de gestion de trafic Mini Motorways.\n"
			.. "Tous les visuels (villes, routes, voitures, interface)\n"
			.. "sont générés en code dans Roblox Studio : aucune image importée.\n\n"
			.. "Tracez des routes entre les maisons et les bâtiments de la même couleur.\n"
			.. "Livrez le plus de trajets possible, semaine après semaine, sans\n"
			.. "laisser le trafic s'effondrer.",
		{
			Position = UDim2.fromOffset(30, 82),
			Size = UDim2.fromOffset(460, 210),
			TextSize = 15,
			TextColor3 = Theme.InkSoft,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 52,
		}
	)

	self:addCloseButton(card, overlay, 310, 460)
end

function Lobby:buildToast()
	self.toastLabel = Theme.label(self.gui, "", {
		Position = UDim2.fromScale(0.5, 0.025),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0.8, 0, 0, 38),
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.08,
		TextSize = 14,
		TextColor3 = Theme.White,
		Visible = false,
		ZIndex = 60,
	})
	Theme.corner(self.toastLabel, Theme.Radius.Pill)
	Theme.textScaled(self.toastLabel, 14, 8)
	Theme.maxSize(self.toastLabel, 420, 38)
end

function Lobby:refreshLobbyGrid(width, height)
	local grid = self.lobbyGrid
	if not grid then
		return
	end
	local key = tostring(math.floor(width)) .. ":" .. tostring(math.floor(height))
	if self.lobbyGridKey == key then
		return
	end
	self.lobbyGridKey = key
	grid:ClearAllChildren()

	-- Cases carrées : la grille reste identique à la capture, même quand
	-- la fenêtre change de proportions.
	local step = math.max(90, width / 10)
	for x = step, width, step do
		Theme.new("Frame", {
			Parent = grid,
			Position = UDim2.fromOffset(math.floor(x), 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = Theme.LobbyGrid,
			BackgroundTransparency = 0.58,
			BorderSizePixel = 0,
			ZIndex = 0,
		})
	end
	for y = step, height, step do
		Theme.new("Frame", {
			Parent = grid,
			Position = UDim2.fromOffset(0, math.floor(y)),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.LobbyGrid,
			BackgroundTransparency = 0.58,
			BorderSizePixel = 0,
			ZIndex = 0,
		})
	end
end

function Lobby:updateResponsive()
	if self.destroyed then
		return
	end
	local viewport = self.gui.AbsoluteSize
	local width = viewport.X
	local height = viewport.Y
	if width < 2 or height < 2 then
		return
	end

	local layout = Lobby.layoutFor(width, height, self.titleWidth)
	self.cardScale = layout.cardScale
	self:refreshLobbyGrid(width, height)

	self.decoration.Visible = layout.decorVisible
	if layout.decorVisible then
		self:updateDecorationLayout()
	end
	self.rail.Visible = layout.railVisible
	self.rail.Position = UDim2.new(layout.railX, 0, 0, layout.railTop)

	self.titleHolder.Position = UDim2.fromScale(layout.titleX, layout.titleY)
	self.titleScale.Scale = layout.titleScale

	self.menu.Position = UDim2.fromScale(layout.menuX, layout.menuY)
	self.menu.Size = UDim2.new(layout.menuWidth, 0, 0, layout.menuHeight)
	for _, item in ipairs(self.menuItems) do
		item.button.Size = UDim2.new(item.width, 0, 0, layout.buttonHeight)
	end

	self.decorDestination.Size = UDim2.fromOffset(layout.destinationSize, layout.destinationSize)
	self.decorHouse.Size = UDim2.fromOffset(layout.houseSize, layout.houseSize)

	self.infoButton.Size = UDim2.fromOffset(layout.infoSize, layout.infoSize)
	self.infoButton.Position = UDim2.fromScale(layout.infoX, layout.infoY)

	self.mapTitle.Position = UDim2.fromScale(0.5, layout.mapTitleY)
	self.mapTitle.Size = UDim2.fromScale(layout.mapTitleWidth, 0.06)
	self.mapSubtitle.Position = UDim2.fromScale(0.5, layout.subtitleY)
	self.mapSubtitle.Size = UDim2.fromScale(layout.subtitleWidth, 0.028)

	self.backButton.Position = UDim2.fromScale(0.03, layout.backY)
	self.backButton.Size = UDim2.fromOffset(layout.backWidth, layout.backHeight)

	self.scroller.Position = UDim2.new(layout.scrollerX, 0, 0, layout.scrollerTop)
	self.scroller.Size = UDim2.new(layout.scrollerWidth, 0, 0, layout.scrollerHeight)
	for _, entry in pairs(self.cards) do
		entry.holder.Size = UDim2.fromOffset(layout.cardWidth, layout.cardHeight)
		entry.scale.Scale = layout.cardScale
	end
	self:updateCanvas()

	self.playButton.Position = UDim2.new(0.5, 0, 0, layout.playTop)
	self.playButton.Size = UDim2.new(0.8, 0, 0, layout.playHeight)
	self.mapHint.Visible = layout.hintVisible
	self.mapHint.Position = UDim2.new(0.5, 0, 0, layout.hintTop)

	for _, entry in ipairs(self.modalScales) do
		local fit = math.min(1, (width * 0.92) / entry.width, (height * 0.9) / entry.height)
		entry.scale.Scale = math.max(0.35, fit)
	end

	self:syncFrameLoop()
end

function Lobby:select(mapId)
	if not mapId or not self.cards[mapId] then
		return
	end
	self.selectedId = mapId

	for id, entry in pairs(self.cards) do
		local selected = id == mapId
		entry.stroke.Transparency = selected and 0 or 1
		entry.shadow.BackgroundTransparency = selected and 0.02 or 0.08
		entry.selectedBadge.Visible = selected
	end

	local map = Maps.getById(mapId)
	if map and self.playButton then
		self.playButton.Text = "Jouer  ·  " .. map.name
	end
end

function Lobby:startSelected()
	if self.callbacks.onStartMap then
		self.callbacks.onStartMap(self.selectedId)
	end
end

function Lobby:show()
	if self.destroyed then
		return
	end
	self.gui.Enabled = true
	setShown(self.mainPage, true)
	setShown(self.mapPage, false)
	for _, overlay in ipairs(self.overlays) do
		setShown(overlay, false)
	end
	self:updateResponsive()
	self:syncFrameLoop()
end

function Lobby:hide()
	if self.destroyed then
		return
	end
	self.gui.Enabled = false
	self:syncFrameLoop()
end

function Lobby:showMaps()
	setShown(self.mainPage, false)
	setShown(self.mapPage, true)
	self:select(self.selectedId)
	self:updateResponsive()
	self:syncFrameLoop()
end

function Lobby:showMain()
	setShown(self.mapPage, false)
	setShown(self.mainPage, true)
	self:syncFrameLoop()
end

function Lobby:showOptions()
	self.optionsOverlay.Visible = true
end

function Lobby:showRecords()
	self.recordsOverlay.Visible = true
end

function Lobby:showGarage()
	self.garageOverlay.Visible = true
end

function Lobby:showStats()
	self.statsOverlay.Visible = true
end

function Lobby:showAbout()
	self.aboutOverlay.Visible = true
end

-- Profil : tableau « identifiant de carte -> meilleur score ». Une valeur
-- absente ou invalide compte pour 0 ; un profil mal formé vide l'affichage.
function Lobby:setProfile(profile)
	local scores = typeof(profile) == "table" and profile or {}

	local total = 0
	local played = 0
	local bestMap = nil
	local bestScore = 0
	for _, map in ipairs(Maps.all()) do
		local best = bestOf(scores[map.id])
		total += best
		if best > 0 then
			played += 1
		end
		if best > bestScore then
			bestScore = best
			bestMap = map
		end
		local text = best > 0 and Theme.formatNumber(best) or NO_SCORE
		local entry = self.cards[map.id]
		if entry then
			entry.bestLabel.Text = "Meilleur : " .. text
		end
		local record = self.recordLabels[map.id]
		if record then
			record.Text = text
		end
	end

	local stats = self.statsLabels
	if stats then
		stats.total.Text = Theme.formatNumber(total)
		stats.played.Text = tostring(played)
		stats.bestMap.Text = bestMap and bestMap.name or NO_SCORE
		stats.average.Text = played > 0 and string.format("%.1f", total / played) or NO_SCORE
	end
end

function Lobby:toast(text)
	if self.destroyed or not self.toastLabel then
		return
	end
	self.toastToken += 1
	local token = self.toastToken
	self.toastLabel.Text = text
	self.toastLabel.Visible = true
	task.delay(TOAST_DURATION, function()
		if not self.destroyed and self.toastToken == token then
			self.toastLabel.Visible = false
		end
	end)
end

-- Libère toutes les connexions et l'interface. L'instance ne doit plus servir.
function Lobby:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:stopFrameLoop()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
	self.callbacks = {}
	self.gui:Destroy()
end

return Lobby
