--[[
	StoreConfig.luau
	Tous les réglages du système de magasins / destinations.
	Modifie ce fichier puis reconstruis avec tools\build.ps1.

	Les intervalles sont exprimés en secondes SIMULÉES. Session:update
	multiplie déjà dt par la vitesse choisie par le joueur : les magasins
	apparaissent donc plus vite en temps réel quand la simulation accélère,
	sans changer le rythme de la partie.
]]

local Config = require(script.Parent.Config)

local StoreConfig = {}

-- La palette est centralisée dans Config.HouseColors. Un magasin reçoit une
-- couleur unique ; les maisons de cette couleur ne desservent que ce magasin.
-- Pour ajouter une couleur, ajoute une entrée dans Config.HouseColors puis
-- augmente Spawn.MaxStores si nécessaire.
StoreConfig.Colors = Config.HouseColors

StoreConfig.Spawn = {
	MaxStores = 8,
	StartStores = 1,

	-- Si aucun emplacement valide n'est trouvé, on réessaie après ce délai.
	RetryDelay = 6,

	-- Distances exprimées en cases (distance euclidienne).
	MinStoreDistance = 4.4,
	MinBuildingDistance = 2.6,
	MinBuildableNeighbors = 3,
	MaxAttempts = 700,

	-- Paliers de difficulté. untilTime = temps simulé de fin du palier.
	-- Les valeurs d'un palier sont atteintes à son début ; entre deux
	-- paliers, l'intervalle glisse linéairement vers le palier suivant.
	-- Le dernier palier reste constant. Ordre croissant obligatoire.
	Tiers = {
		{ untilTime = 180, minInterval = 100, maxInterval = 120 },
		{ untilTime = 360, minInterval = 75, maxInterval = 100 },
		{ untilTime = 600, minInterval = 55, maxInterval = 75 },
		{ untilTime = 900, minInterval = 35, maxInterval = 55 },
		{ untilTime = 1200, minInterval = 25, maxInterval = 40 },
		{ untilTime = math.huge, minInterval = 15, maxInterval = 30 },
	},

	-- Zones de génération pondérées autour du centre de la carte.
	-- minRadius/maxRadius sont normalisés : 1 = demi-taille de la carte.
	Zones = {
		{ weight = 0.35, minRadius = 0.10, maxRadius = 0.35 },
		{ weight = 0.40, minRadius = 0.30, maxRadius = 0.65 },
		{ weight = 0.25, minRadius = 0.58, maxRadius = 0.84 },
	},
}

-- Diffusion vers le client (secondes réelles) : rafraîchissement rapide quand
-- l'état change (compte à rebours), sinon une mise à jour lente suffit.
StoreConfig.Sync = {
	DirtyDelay = 0.2,
	IdleDelay = 1.5,
}

StoreConfig.Demand = {
	-- Capacités demandées : petit magasin 6, grand magasin 8.
	SmallCapacity = 6,
	LargeCapacity = 8,

	-- Base de génération des demandes (secondes simulées).
	SmallInterval = 11.5,
	LargeInterval = 7.5,
	FirstDelayMin = 5,
	FirstDelayMax = 9,
	-- Variation relative aléatoire appliquée à chaque intervalle (±10 %).
	Jitter = 0.10,

	-- La difficulté augmente avec le temps : les demandes arrivent plus vite.
	RampDuration = 600,
	RampMinMultiplier = 0.70,
	MinInterval = 4,

	-- Surcharge : quand le magasin reste plein, le compte à rebours descend.
	-- À zéro, le magasin devient critique et draine la jauge de satisfaction.
	OverloadGrace = 12,
	OverloadDrainPerSecond = 1.25,

	-- Une demande réservée par une voiture ne peut pas être prise par une
	-- autre voiture. Si la voiture ne trouve aucun chemin après ce délai,
	-- elle libère sa réservation et rentre.
	ClaimTimeout = 18,
	NoDemandRetry = 2,
}

StoreConfig.Evolution = {
	MinAge = 95,
	CheckInterval = 14,
	Chance = 0.42,
	MinDeliveries = 3,
	MaxLargeStores = 6,
	AnimationDuration = Config.Style.Motion.Evolution,
	-- Variation relative de l'intervalle entre deux contrôles d'évolution.
	CheckJitter = 0.30,
}

StoreConfig.Houses = {
	StartHouses = 3,
	HousesPerStore = 2,
	MaxHousesPerStore = 3,
	-- Plafond des maisons, hors première maison de chaque magasin : celle-ci
	-- passe toujours, sinon le magasin ne serait jamais servi.
	MaxHouses = 16,
	SpawnInterval = 18,
	FirstSpawnDelay = 26,
	-- Aléa ajouté au délai de la première sortie d'une nouvelle maison.
	FirstTripJitter = 4,

	MinDistanceFromStore = 4,
	MaxDistanceFromStore = 9,
	-- Groupes : une nouvelle maison se pose près d'une maison déjà présente
	-- (même magasin) avec cette probabilité, sinon autour du magasin.
	ClusterChance = 0.6,
	ClusterMinDistance = 2.6,
	ClusterMaxDistance = 3.6,
	MaxAttempts = 500,
	MinDistanceFromBuilding = 2.6,
	MinBuildableNeighbors = 2,
}

StoreConfig.Visual = {
	-- Emprise dessinée des magasins (BuildingModels), en studs : même source que
	-- les bâtiments, pour que le décalage des pins colle au bâtiment.
	SmallSize = Config.Dimensions.Building.SmallStore * Config.Grid.TileSize,
	LargeSize = Config.Dimensions.Building.LargeStore * Config.Grid.TileSize,
	SpawnAnimationDuration = Config.Style.Motion.Spawn,
	EvolutionStartScale = 0.62,
	EvolutionDuration = Config.Style.Motion.Evolution,

	-- Pins de demande côté client (BillboardGui). Les tailles sont en pixels
	-- écran : elles restent lisibles au dézoom sans grossir au zoom avant.
	PinRowWidth = 64,
	PinRowHeight = 96,
	PinSize = Config.Dimensions.Pin.Size,
	PinGap = 4,
	PinsPerRow = 4,
	-- Décalage entre deux pins d'une même vague d'apparition (secondes).
	PinStagger = 0.05,
	PinAppearDuration = 0.24,
	PinRemoveDuration = 0.16,
	PinStrokeTransparency = 0.4,
	-- Écart en studs entre le bord du magasin et le bas des pins ; le décalage
	-- de caméra vers le haut de l'écran (world -Z) est calculé à partir de la
	-- taille du magasin, pour rester collé au bâtiment quand il évolue.
	PinLift = 1.4,
	PinEvolutionPop = 1.16,
	-- Les pins ne sont jamais masqués par la distance : la caméra reste proche.
	PinMaxDistance = 2000,
	PinWarningWidth = 28,
	PinWarningHeight = 12,
	PinWarningGap = 3,
	PinWarningTextSize = 10,
}

return StoreConfig
