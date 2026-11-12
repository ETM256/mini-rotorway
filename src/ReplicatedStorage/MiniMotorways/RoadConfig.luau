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

RoadConfig.Version = "1.1.0"

-- true : autorise les cases reliées par un coin (comportement historique).
-- false : réseau orthogonal uniquement, virages à 90° et intersections
--         en T / en croix générées automatiquement.
RoadConfig.AllowDiagonals = false

-- "orthogonal" : une route doit toucher un côté du bâtiment pour le desservir.
-- "all"        : accepte aussi une route posée en diagonale du bâtiment.
RoadConfig.BuildingConnection = "orthogonal"

RoadConfig.Visual = {
	-- Largeurs en fraction d'une case, issues de Config.Dimensions.Road : une
	-- route reste plus étroite qu'une maison, sans trou ni chevauchement.
	RoadWidth = Config.Dimensions.Road.Width,
	EdgeWidth = Config.Dimensions.Road.Edge,
	-- Rayon des virages, en fraction de la largeur de route.
	CornerRadius = 0.42,

	-- Aperçu local avant construction : même emprise que le liseré de route.
	PreviewScale = Config.Dimensions.Road.Edge,
	PreviewHeight = 0.045,
	PreviewY = 0.84,
	PreviewTransparency = 0.34,
	PreviewHoverTransparency = 0.48,
	PreviewValidColor = Config.Colors.Teal,
	PreviewInvalidColor = Config.Colors.Danger,
}

-- Couches du renderer de routes (RoadRenderer), en studs au-dessus du plateau.
-- Top : hauteur du dessus ; Thickness : épaisseur de la dalle. Une couche a une
-- seule hauteur : deux couches ne sont jamais coplanaires (pas de scintillement),
-- et le liseré passe toujours sous la surface graphite. Le pont est plus haut
-- que la route pour passer au-dessus de l'eau. Le rond-point (anneau, île) est
-- posé juste au-dessus de la route.
RoadConfig.Layers = {
	Edge = { Top = 0.29, Thickness = 0.12 },
	Body = { Top = 0.31, Thickness = 0.12 },
	BridgeEdge = { Top = 0.37, Thickness = 0.16 },
	Bridge = { Top = 0.40, Thickness = 0.16 },
	RoundaboutEdge = { Top = 0.325, Thickness = 0.03 },
	RoundaboutBody = { Top = 0.335, Thickness = 0.03 },
	RoundaboutIsland = { Top = 0.355, Thickness = 0.05 },
	-- Diamètres du rond-point, en fraction de case : l'anneau reste plus large
	-- qu'une route, l'île centrale laisse une chaussée circulaire.
	RoundaboutDiameter = 0.9,
	RoundaboutIslandDiameter = 0.4,
}

RoadConfig.Input = {
	-- La construction est validée au relâchement (InputController). L'aperçu
	-- reste local : Échap peut donc annuler sans avoir consommé de route.
	MaxCellsPerRequest = 512,
	-- Garde-fou d'un seul tracé orthogonal (RoadNetwork.manhattanPath) :
	-- distinct de la taille d'un lot, qui découpe un long geste en requêtes.
	MaxPathSteps = 512,
	-- Hystérésis : en dessous de ce seuil, on conserve le dernier axe.
	DragAxisThreshold = 0.35,
	-- Mouvement minimal (pixels écran) avant de décider d'un axe dominant.
	AxisMinPixels = 4,
	-- Rafraîchissement de l'aperçu survolé (secondes), pour suivre la caméra.
	HoverRefresh = 0.12,
	-- Zoom par pincement : variation de zoom pour un doublement de l'écart.
	PinchZoomGain = 1.5,
}

-- Apparition échelonnée des cases d'un même tracé (en secondes).
RoadConfig.Construction = {
	RevealStagger = 0.022,
	RevealStaggerMax = 0.28,
	-- Au-delà de ce nombre de cases neuves dans un même lot, elles apparaissent
	-- sans animation (une case animée = 2 à 6 pièces tweenées par le serveur).
	MaxAnimatedCells = 40,
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
}

-- Autoroutes : volontairement désactivées tant que leur logique de trajet
-- dédiée n'est pas branchée. Les ponts et les ronds-points sont des cartes de
-- Config.Rewards, pas un réglage ici.
RoadConfig.Infrastructure = {
	Highways = {
		Enabled = false,
	},
}

-- Voitures : tailles et trajectoires, en fraction d'une case sauf mention.
RoadConfig.Vehicle = {
	LengthTiles = Config.Dimensions.Car.Length,
	WidthTiles = Config.Dimensions.Car.Width,
	-- Hauteur de carrosserie, en studs (et non en fraction de case).
	Height = 0.4,
	-- Voie de droite : décalage latéral par rapport à l'axe de la route. Deux
	-- voies opposées restent séparées d'une voiture entière (2 x décalage) et
	-- la voiture reste dans la chaussée (demi-route - demi-voiture = 0.145).
	LaneOffsetTiles = 0.14,
	-- Virage : l'arc commence à cette distance du centre de la case.
	CornerCutTiles = 0.45,
	-- Produit scalaire au-dessous duquel l'enchaînement est un virage.
	TurnDot = 0.98,
	-- Vitesse de rotation maximale du cap (radians par seconde).
	TurnRate = 5,
	-- Freinage pour s'arrêter avant une intersection occupée, en fraction de
	-- Traffic.Braking : plus doux qu'un arrêt net, donc sans à-coup visible.
	StopBrakeFactor = 0.5,
	CurveSamples = 8,
	-- Distance d'observation des voitures qui précèdent sur le trajet.
	LookaheadTiles = 2.5,
	-- Zone de ralentissement progressif avant la distance de sécurité (studs).
	FollowBand = 2.4,
	-- Pas de simulation maximal (secondes) : un dt de 0.3 s est découpé.
	MaxStep = 0.1,
	-- Une voiture qui attend une case depuis ce délai (secondes) cherche si
	-- l'attente forme une boucle : si oui, une seule voiture de la boucle passe.
	DeadlockCheckTime = 1,
	-- Écart de cap (radians) au-delà duquel la voiture n'avance plus : elle
	-- pivote d'abord sur sa place après un demi-tour, au lieu de balayer la route.
	AlignAngle = 0.8,
	-- Dans un virage la voiture se rapproche de l'axe de la route (fraction du
	-- décalage de voie, au milieu de l'arc) : sa queue ne déborde pas du bord.
	CurveLanePull = 0.2,
}

return RoadConfig
