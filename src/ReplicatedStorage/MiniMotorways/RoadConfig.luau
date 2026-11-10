--[[
	RoadConfig.luau
	Réglages centralisés du système de routes.

	Les routes sont orthogonales par défaut : chaque déplacement va d'une case
	vers une case voisine en haut, en bas, à gauche ou à droite. Un geste en
	biais est transformé en chemin horizontal puis vertical (ou l'inverse).
	Les diagonales restent disponibles en option pour les anciens réseaux.
]]

local Config = require(script.Parent.Config)

local RoadConfig = {}

RoadConfig.Version = "1.0.0"

-- true : autorise les cases reliées par un coin (comportement historique).
-- false : réseau orthogonal uniquement, virages à 90° et intersections
--         en T / en croix générées automatiquement.
RoadConfig.AllowDiagonals = false

-- "orthogonal" : une route doit toucher un côté du bâtiment pour le desservir.
-- "all"        : accepte aussi une route posée en diagonale du bâtiment.
RoadConfig.BuildingConnection = "orthogonal"

RoadConfig.Visual = {
	-- Largeurs exprimées en fraction d'une case.
	RoadWidth = 0.72,
	ContourWidth = 0.78,
	EdgeWidth = 0.84,
	RibbonEdgeWidth = 0.86,
	RibbonTopWidth = 0.74,
	CornerRadius = 0.42,

	-- Aperçu local avant construction.
	PreviewScale = 0.74,
	PreviewHeight = 0.045,
	PreviewY = 0.84,
	PreviewTransparency = 0.34,
	PreviewHoverTransparency = 0.48,
	PreviewValidColor = Config.Colors.Teal,
	PreviewInvalidColor = Config.Colors.Danger,
}

RoadConfig.Input = {
	-- La construction est validée au relâchement. L'aperçu reste local :
	-- Échap peut donc annuler sans avoir consommé de route.
	CommitOnRelease = true,
	MaxCellsPerRequest = 512,
	-- Hystérésis : en dessous de ce seuil, on conserve le dernier axe.
	DragAxisThreshold = 0.35,
}

RoadConfig.Traffic = {
	-- Ralentissement visuel dans les virages et les intersections.
	TurnSpeedFactor = 0.62,
	IntersectionApproachSlow = 0.76,
	-- La direction visuelle rejoint la direction réelle sans rotation sèche.
	HeadingLerp = 9,
	-- Redémarrage progressif après un arrêt.
	Acceleration = 2.2,
	Braking = 6,
	-- Une intersection (3 ou 4 voisins) est réservée à une voiture à la fois.
	IntersectionReservation = true,
	ReservationReleaseTime = 8,
}

-- Emplacements prévus pour les futures infrastructures. Les ponts existent
-- déjà ; les autoroutes sont volontairement désactivées tant que leur
-- logique de trajet dédiée n'est pas branchée.
RoadConfig.Infrastructure = {
	Bridges = {
		Enabled = true,
		CostsRoadPiece = true,
		SpecialResource = "bridges",
	},
	Highways = {
		Enabled = false,
		CostsRoadPiece = false,
		MaxEntrances = 2,
		SpeedMultiplier = 1.8,
	},
}

return RoadConfig
