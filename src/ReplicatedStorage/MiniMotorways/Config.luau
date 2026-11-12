--[[
	Config.luau
	All game settings live here.
	Change a value, rebuild (tools\build.ps1), and it is applied.
]]

local Config = {}

-- Name shown in the lobby.
-- "Mini Motorways" is a trademark of Dinosaur Polo Club.
-- Change this name (and Config.GameName) before publishing publicly.
Config.GameName = "Mini Motorways"
Config.Tagline = "Tracez. Reliez. Livrez."
Config.Version = "1.5.0"

-- Play grid: 18 x 18 tiles of 4 studs = 72 x 72 studs. La carte garde sa
-- taille ; ce sont les cases de visée des routes qui sont agrandies.
Config.Grid = {
	Size = 18,
	TileSize = 4,
}

-- Dimensions partagées : une seule source pour les tailles visibles. Les
-- routes sont plus étroites qu'un bâtiment et qu'une case, sans trou ni
-- chevauchement entre le liseré et la surface.
Config.Dimensions = {
	-- Route : coeur anthracite, liseré blanc fin (Contour puis Edge), en fraction
	-- d'une case.
	Road = { Width = 0.54, Contour = 0.57, Edge = 0.59 },
}

-- Every player gets their own city, far away from the others.
Config.World = {
	OriginSpacing = 700,
	BaseY = 0,
}

Config.Camera = {
	Height = 232,
	Back = 54,
	FOV = 20,
	Fit = 1.18,
	BackRatio = 0.035,
	-- Zoom : la molette ajoute ZoomStep par cran ; le zoom glisse vers sa cible
	-- à ZoomSmoothing (1/s), indépendamment de la fréquence d'images.
	ZoomMin = 1,
	ZoomMax = 2.8,
	ZoomStep = 0.14,
	ZoomSmoothing = 12,
	-- Déplacement : le centre de vue peut dépasser le bord de la carte de cette
	-- fraction de l'écart carte / vue (0 = la vue reste entièrement sur la carte).
	PanOverscroll = 0.5,
	-- Arrivée sur la carte : la caméra descend depuis IntroZoomOut fois plus loin.
	IntroSeconds = 0.6,
	IntroZoomOut = 1.4,
	LobbyHeight = 400,
	LobbyFOV = 60,
}

-- Budget de départ et limites. Les gains hebdomadaires réels sont décrits
-- dans Config.Rewards : +20 routes avec un outil spécial, ou +30/+40 routes.
Config.Roads = {
	StartBudget = 20,
	WeekReward = 30,
	MaxBudget = 999,
	StartBridges = 1,
	WeekBridges = 1,
	MaxBridges = 14,
	StartRoundabouts = 0,
	WeekRoundabouts = 1,
	MaxRoundabouts = 9,
}

-- Choix hebdomadaire inspiré de Mini Motorways : chaque semaine, deux
-- propositions. Les deux donnent des routes ; une seule contient un outil
-- spécial. C'est le fonctionnement réel du jeu (voir README, section 11).
Config.Rewards = {
	Roads = {
		id = "roads",
		kind = "roads",
		amount = 30,
		title = "+30 routes",
		description = "Un lot de 30 routes pour étendre votre réseau.",
	},
	RoadsLarge = {
		id = "roads_large",
		kind = "roads",
		amount = 40,
		title = "+40 routes",
		description = "Un grand lot de 40 routes pour les grands projets.",
	},
	Bridge = {
		id = "bridge",
		kind = "bridges",
		amount = 1,
		roads = 20,
		title = "+1 pont",
		description = "Un pont + 20 routes pour traverser l'eau.",
	},
	Roundabout = {
		id = "roundabout",
		kind = "roundabouts",
		amount = 1,
		roads = 20,
		title = "+1 rond-point",
		description = "Un rond-point + 20 routes pour fluidifier un carrefour.",
	},
}

-- Game pacing.
-- Le rythme des magasins et des maisons est maintenant décrit dans
-- StoreConfig.luau. Ici on garde uniquement les réglages généraux.
Config.Game = {
	WeekDuration = 60, -- seconds per week
	SpawnInterval = 8.5, -- delay between two trips from one house
	FirstSpawnDelay = 3, -- first trip from a house
	DeliveryScore = 1,
	DeliverySatisfaction = 2,
}

-- Traffic and patience.
Config.Traffic = {
	CarSpeed = 9, -- studs / second
	CarSpacing = 3.6, -- safety distance
	StuckAfter = 8, -- a car blocked for X seconds drains the gauge
	RetryPathInterval = 1.2,
	DrainPerStuckCar = 1.1, -- patience points / s / blocked car
	RegenPerSecond = 1.4, -- recovery when traffic flows
	SatisfactionStart = 100,
	SatisfactionMax = 100,
}

-- Style d'interface partagé : arrondis, contours et durées d'animation.
Config.Style = {
	-- Arrondis d'interface, en pixels.
	CornerRadius = { Small = 4, Medium = 8, Large = 12 },
	-- Contours d'interface, en pixels : jamais de gros trait sombre.
	Outline = { Thin = 1, Max = 2 },
	-- Durées d'animation de l'interface, en secondes. Hover reprend la durée
	-- réelle du survol (Theme.Motion.Duration, 0.12 s).
	Motion = { Hover = 0.12, Fast = 0.16, Standard = 0.24 },
}

-- Palette claire de la version française : papier crème, eau menthe,
-- encre charbon et boutons pastel, comme dans la vidéo de référence.
Config.Colors = {
	Background = Color3.fromHex("E6EBEA"),
	GridLine = Color3.fromHex("D9E2E0"),
	-- Ambiance du menu d'accueil : bleu-gris très clair, grille discrète,
	-- boutons menthe et accents orange, comme la capture de référence.
	LobbyBackground = Color3.fromHex("E9F0F2"),
	LobbyGrid = Color3.fromHex("D4DFE1"),
	LobbyButton = Color3.fromHex("8DBDB6"),
	LobbyButtonDark = Color3.fromHex("78A8A1"),
	LobbyOrange = Color3.fromHex("F5B84D"),
	LobbyRoad = Color3.fromHex("FFFDF8"),
	LobbyRoadShadow = Color3.fromHex("D2DDE0"),
	-- Fond du menu en dégradé, accents chauds et pastille de pont (interface).
	LobbyBackgroundTop = Color3.fromHex("F5F9F9"),
	LobbyBackgroundBottom = Color3.fromHex("DDE8EA"),
	LobbyAccent = Color3.fromHex("E7825F"),
	LobbyAccentDeep = Color3.fromHex("D49675"),
	BridgeChip = Color3.fromHex("7F8A7C"),
	Ink = Color3.fromHex("33383A"),
	InkSoft = Color3.fromHex("737D7C"),
	Teal = Color3.fromHex("7FBDB5"),
	TealDark = Color3.fromHex("5F9F97"),
	Orange = Color3.fromHex("F6C87E"),
	White = Color3.fromHex("FEFDF9"),
	Cream = Color3.fromHex("FBF3DE"),
	CardShadow = Color3.fromHex("C9D2CF"),
	Danger = Color3.fromHex("D96A5B"),
	Panel = Color3.fromHex("FEFDF9"),
	PanelSoft = Color3.fromHex("EEF3F1"),
	PanelDark = Color3.fromHex("2E3234"),
	Border = Color3.fromHex("E6DBC2"),
	BorderStripe = Color3.fromHex("F8EED4"),
	Paper = Color3.fromHex("F8EED4"),
	-- Palette reprise de l'aperçu de Los Angeles : terre crème, eau menthe
	-- plus contrastée, parcs jaune-vert et liseré de côte blanc.
	Land = Color3.fromHex("FFF8DC"),
	Grass = Color3.fromHex("EFEC8C"),
	Water = Color3.fromHex("A5DAC6"),
	WaterDeep = Color3.fromHex("7FB7A5"),
	WaterEdge = Color3.fromHex("8FC9B7"),
	Coast = Color3.fromHex("FFFFF7"),
	Ring = Color3.fromHex("88B5A7"),
	RingShadow = Color3.fromHex("D3CDB8"),
	-- Routes graphite : le ruban sombre se détache du sol crème, avec un
	-- liseré blanc fin de chaque côté comme sur une route réelle.
	Road = Color3.fromHex("262B2C"),
	RoadEdge = Color3.fromHex("FFFFFF"),
	RoadContour = Color3.fromHex("FFFFFF"),
	Bridge = Color3.fromHex("2E3334"),
	BridgeEdge = Color3.fromHex("FFFFFF"),
	-- Ombres douces et petits arbres des parcs, façon icônes vectorielles.
	BuildingShadow = Color3.fromHex("CFC5AA"),
	TreeDark = Color3.fromHex("8FA94A"),
	TreeLight = Color3.fromHex("B4C96A"),
}

-- Maisons / destinations : chaque couleur a une teinte claire pour le toit
-- et une teinte plus dense pour le socle, comme les cartes empilées de la
-- référence. Huit couleurs : un magasin unique par couleur au départ.
Config.HouseColors = {
	{ name = "Miel", color = Color3.fromHex("F4C25C"), base = Color3.fromHex("E7825F") },
	{ name = "Corail", color = Color3.fromHex("EE8A6B"), base = Color3.fromHex("D95B5B") },
	{ name = "Rose", color = Color3.fromHex("E792B4"), base = Color3.fromHex("C96A92") },
	{ name = "Bleu", color = Color3.fromHex("7DB8D8"), base = Color3.fromHex("4F8FB8") },
	{ name = "Vert", color = Color3.fromHex("91C97C"), base = Color3.fromHex("5FA36A") },
	{ name = "Violet", color = Color3.fromHex("B19BDB"), base = Color3.fromHex("8B6FBF") },
	{ name = "Turquoise", color = Color3.fromHex("62C7BC"), base = Color3.fromHex("3FA39A") },
	{ name = "Orange", color = Color3.fromHex("F2A65A"), base = Color3.fromHex("D9823F") },
}

return Config
