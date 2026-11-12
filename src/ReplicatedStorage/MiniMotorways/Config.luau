--[[
	Config.luau
	All game settings live here.
	Change a value, rebuild (tools\build.ps1), and it is applied.
]]

local Config = {}

-- Nom affiché dans le menu. « Mini Motorways » est une marque de Dinosaur Polo
-- Club : ce jeu s'en inspire (règles, ambiance) sans reprendre aucun asset
-- d'origine. Vérifier ce point avant toute publication.
Config.GameName = "Mini Rotorway"
Config.Tagline = "Tracez. Reliez. Livrez."
Config.Version = "1.7.0"

-- Play grid: 18 x 18 tiles of 4 studs = 72 x 72 studs. La carte garde sa
-- taille ; ce sont les cases de visée des routes qui sont agrandies.
Config.Grid = {
	Size = 18,
	TileSize = 4,
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
	MaxBridges = 14,
	StartRoundabouts = 0,
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
	-- Amélioration de circulation : un lot plus petit qui raccourcit la
	-- distance de sécurité des voitures (multiplicateur trafic, voir
	-- Config.Progression.TrafficMinFactor).
	Traffic = {
		id = "traffic",
		kind = "roads",
		amount = 20,
		trafficFactor = 0.93,
		title = "+20 routes, trafic fluide",
		description = "Un lot de 20 routes : les voitures se suivent de plus près.",
	},
}

-- Progression douce : mise à l'échelle des lots de routes avec la semaine,
-- plancher de l'amélioration de circulation et pression de surcharge.
-- Voir SessionProgress.luau pour les formules.
Config.Progression = {
	-- Tous les RoadsWeeksPerStep, chaque lot gagne RoadsPerStep routes,
	-- plafonné à RoadsMaxBonus.
	RoadsWeeksPerStep = 3,
	RoadsPerStep = 2,
	RoadsMaxBonus = 10,
	-- Distance de sécurité minimale, en fraction de Config.Traffic.CarSpacing.
	TrafficMinFactor = 0.8,
	-- Surcharge : le drain croît linéairement pendant OverloadRampSeconds de
	-- surcharge critique, puis plafonne à 1 + OverloadMaxExtra.
	OverloadRampSeconds = 120,
	OverloadMaxExtra = 1,
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
	-- Score : bonus de la première livraison vers chaque magasin, et bonus
	-- d'un trajet long (distance en cases, entre maison et magasin).
	NewStoreBonus = 2,
	LongTripCells = 10,
	LongTripBonus = 1,
}

-- Horloge de jeu. Les jours et les mois se déduisent du temps simulé
-- (Session.elapsed) : une semaine = Config.Game.WeekDuration, un mois = quatre
-- semaines. Les vitesses sont les multiplicateurs autorisés par setSpeed.
Config.Time = {
	DaysPerWeek = 7,
	WeeksPerMonth = 4,
	MonthNames = {
		"Janvier",
		"Février",
		"Mars",
		"Avril",
		"Mai",
		"Juin",
		"Juillet",
		"Août",
		"Septembre",
		"Octobre",
		"Novembre",
		"Décembre",
	},
	MinSpeed = 1,
	MaxSpeed = 3,
	-- Pas de simulation maximal (secondes simulées). Une grosse frame est
	-- découpée : les voitures ne sautent pas de plusieurs cases à vitesse 3.
	MaxSimStep = 0.1,
	-- Durée réelle maximale prise en compte pour une frame : au-delà (onglet
	-- caché, à-coup), le temps simulé n'avance que de cette valeur.
	MaxFrameDt = 0.1,
	-- Intervalle réel entre deux envois de l'état au client (5 Hz).
	StateInterval = 0.2,
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

-- Dimensions partagées : une seule source pour les tailles visibles. Les
-- bâtiments et les voitures sont en fraction d'une case (Grid.TileSize).
-- Ordre à respecter (vérifié par les tests) : route < emprise d'une maison
-- < case, ce qui laisse toujours une route se poser à côté d'un bâtiment.
Config.Dimensions = {
	Building = { House = 0.62, SmallStore = 0.80, LargeStore = 0.90 },
	Car = { Length = 0.45, Width = 0.25 },
	-- Route : coeur anthracite, liseré blanc fin (Contour puis Edge), tous
	-- plus étroits qu'une maison. L'aperçu de construction reprend Edge.
	Road = { Width = 0.54, Contour = 0.57, Edge = 0.59 },
	-- Pastilles de demande, en pixels écran (lisibles au dézoom).
	Pin = { Size = 10 },
	-- Lignes de la grille de construction, en studs.
	Grid = { LineWidth = 0.04 },
}

-- Style commun : arrondis, ombres, contours et durées. Les animations restent
-- courtes : la fluidité compte plus que l'effet.
Config.Style = {
	-- Arrondis d'interface, en pixels.
	CornerRadius = { Small = 4, Medium = 8, Large = 12 },
	-- Arrondi des coins de bâtiment, en fraction du plus petit côté.
	BuildingCornerRatio = 0.2,
	-- Ombre douce des bâtiments et voitures, en studs : décalée vers le
	-- bas-droite et très transparente pour ne jamais paraître noire.
	Shadow = { Transparency = 0.76, Offset = 0.10, Grow = 0.12 },
	-- Contours d'interface, en pixels : jamais de gros trait sombre.
	Outline = { Thin = 1, Max = 2 },
	-- Durées d'animation, en secondes. Hover reprend la durée réelle du survol
	-- de l'interface (Theme.Motion.Duration, 0.12 s).
	Motion = { Hover = 0.12, Fast = 0.16, Standard = 0.24, Spawn = 0.4, Evolution = 0.55 },
}

-- Palette centrale : toutes les couleurs du jeu viennent d'ici. Saturation
-- modérée partout (pastel, rien de fluorescent), neutres légèrement teintés
-- pour rester doux sur le papier crème. Les alias (même couleur sous deux
-- noms) sont voulus : ils gardent les anciens noms utilisés par le code.
local White = Color3.fromHex("FDFCF8")
local Paper = Color3.fromHex("F3EFE3")
local Road = Color3.fromHex("2B3133")

Config.Colors = {
	-- Terrain : blanc cassé, gris très clair, beige très léger.
	Background = Color3.fromHex("E9ECEB"),
	GridLine = Color3.fromHex("E0E6E4"),
	Land = Color3.fromHex("F4F1E6"),
	Paper = Paper,
	BorderStripe = Paper,
	Cream = Color3.fromHex("F8F5EC"),
	Coast = Color3.fromHex("FBFAF6"),
	-- Grille du sol : même famille que le terrain, presque invisible.
	GridTerrain = Color3.fromHex("EEEBDF"),

	-- Routes : anthracite légèrement désaturé, uniforme sur toute la carte.
	Road = Road,
	Bridge = Road,
	-- Liserés blancs fins de chaque côté, comme sur une route réelle.
	RoadEdge = White,
	RoadContour = White,
	BridgeEdge = White,

	-- Eau : turquoise pastel et bleu très clair.
	Water = Color3.fromHex("A6D9D0"),
	WaterDeep = Color3.fromHex("7FC0B5"),
	WaterEdge = Color3.fromHex("96CEC4"),
	WaterPale = Color3.fromHex("D8EEF2"),
	Ring = Color3.fromHex("8CB9AE"),
	RingShadow = Color3.fromHex("D8D5CA"),

	-- Végétation : vert doux, vert sauge, vert pastel.
	Grass = Color3.fromHex("DDE6C8"),
	Park = Color3.fromHex("C6D8B6"),
	TreeDark = Color3.fromHex("9CB67E"),
	TreeLight = Color3.fromHex("BDD29C"),

	-- Bâtiments et ombres : ombre tiède et discrète.
	BuildingShadow = Color3.fromHex("C9C6BA"),
	CardShadow = Color3.fromHex("C8CFCC"),

	-- Interface : gris clair, blanc cassé, anthracite et quelques accents.
	White = White,
	Panel = White,
	PanelSoft = Color3.fromHex("EEF2F0"),
	PanelDark = Color3.fromHex("2E3436"),
	Border = Color3.fromHex("E3DFD3"),
	Ink = Color3.fromHex("33383A"),
	InkSoft = Color3.fromHex("6F7877"),
	Teal = Color3.fromHex("7FBDB5"),
	TealDark = Color3.fromHex("5F9F97"),
	Orange = Color3.fromHex("F6C87E"),
	Danger = Color3.fromHex("D8786A"),
	-- Pastille « pont » de l'interface (compteur, choix hebdomadaire) : gris-vert doux.
	BridgeChip = Color3.fromHex("7F8A7C"),

	-- Menu d'accueil : bleu-gris très clair, grille discrète, boutons menthe
	-- et accents orange, comme la capture de référence.
	LobbyBackground = Color3.fromHex("E9F0F2"),
	LobbyGrid = Color3.fromHex("D4DFE1"),
	LobbyButton = Color3.fromHex("8DBDB6"),
	LobbyButtonDark = Color3.fromHex("78A8A1"),
	LobbyOrange = Color3.fromHex("F3BC62"),
	LobbyRoad = White,
	LobbyRoadShadow = Color3.fromHex("D2DDE0"),
	-- Dégradé de fond du menu, et accents corail du décor (maison, destination).
	LobbyBackgroundTop = Color3.fromHex("F5F9F9"),
	LobbyBackgroundBottom = Color3.fromHex("DDE8EA"),
	LobbyAccent = Color3.fromHex("E7825F"),
	-- Accent corail plus doux (saturation HSV 0.45, l'ancien C56F42 était à 0.66).
	LobbyAccentDeep = Color3.fromHex("D49675"),
}

-- Maisons / destinations : huit couleurs pastel à teintes séparées d'au moins
-- 25 degrés, pour rester reconnaissables de loin. Chaque couleur a une teinte
-- claire pour le toit et une teinte plus dense pour le socle. Un magasin
-- unique par couleur au départ : l'ordre de la liste est celui des magasins.
Config.HouseColors = {
	{ name = "Miel", color = Color3.fromHex("F7ED94"), base = Color3.fromHex("D9CE6C") },
	{ name = "Corail", color = Color3.fromHex("E67386"), base = Color3.fromHex("C76374") },
	{ name = "Rose", color = Color3.fromHex("EDA8D2"), base = Color3.fromHex("CF7AAD") },
	{ name = "Bleu", color = Color3.fromHex("8DBFEB"), base = Color3.fromHex("669CCC") },
	{ name = "Vert", color = Color3.fromHex("A3E6A1"), base = Color3.fromHex("76C773") },
	{ name = "Violet", color = Color3.fromHex("BB8EF5"), base = Color3.fromHex("9A6BD6") },
	{ name = "Turquoise", color = Color3.fromHex("AEF2E7"), base = Color3.fromHex("7FD4C6") },
	{ name = "Orange", color = Color3.fromHex("F2AF83"), base = Color3.fromHex("D4946A") },
}

-- Décor du plateau (WorldBuilder) : épaisseurs en studs et probabilités.
Config.Terrain = {
	-- Grille : lignes plus fines qu'une route, visibles surtout en construction.
	GridLineWidth = Config.Dimensions.Grid.LineWidth,
	GridBaseTransparency = 0.72,
	GridActiveTransparency = 0.35,
	-- Liseré clair autour de l'eau et des presqu'îles.
	Shoreline = 0.3,
	-- Ombre de bord du plateau : deux couches très transparentes.
	BoardShadow = {
		{ grow = 1.2, transparency = 0.9 },
		{ grow = 0.5, transparency = 0.75 },
	},
	BackdropMargin = 120,
	-- Part des cases de parc qui reçoivent un petit groupe d'arbres.
	TreeClusterChance = 0.4,
	TreeShadowTransparency = 0.82,
	-- Arbres et ombres, en studs : diamètre, étalement autour du centre de la
	-- case, espacement minimal, et ombre décalée vers le bas-droite.
	TreeDiameter = 1.3,
	TreeSpread = 2.2,
	TreeMinSpacing = 1.6,
	TreeShadowScale = 1.15,
	TreeShadowOffset = 0.15,
}

return Config
