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

	-- Paliers de progression. untilTime = temps simulé écoulé depuis le début.
	-- Le premier magasin est créé immédiatement ; ces valeurs règlent les
	-- magasins suivants. Les derniers paliers seront utiles si MaxStores est
	-- augmenté au-delà de 8.
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

StoreConfig.Demand = {
	-- Capacités demandées : petit magasin 6, grand magasin 8.
	SmallCapacity = 6,
	LargeCapacity = 8,

	-- Base de génération des demandes (secondes simulées).
	SmallInterval = 11.5,
	LargeInterval = 7.5,
	FirstDelayMin = 5,
	FirstDelayMax = 9,

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
	AnimationDuration = 0.55,
}

StoreConfig.Houses = {
	StartHouses = 3,
	HousesPerStore = 2,
	MaxHousesPerStore = 3,
	MaxHouses = 16,
	SpawnInterval = 18,
	FirstSpawnDelay = 26,

	MinDistanceFromStore = 4,
	MaxDistanceFromStore = 9,
	MinDistanceFromBuilding = 2.6,
	MinBuildableNeighbors = 2,
}

StoreConfig.Visual = {
	SmallSize = 6.4,
	LargeSize = 8.4,
	SpawnAnimationDuration = 0.4,
	EvolutionStartScale = 0.62,
	EvolutionDuration = 0.55,

	-- Pins de demande côté client (BillboardGui).
	PinRowWidth = 196,
	PinRowHeight = 64,
	PinSize = 18,
	PinGap = 4,
	-- Distance en studs au-dessus du magasin, vers le haut de l'écran
	-- (la caméra du jeu regarde vers le bas : l'axe écran-haut est world -Z).
	PinHeightSmall = 6.6,
	PinHeightLarge = 7.8,
	PinMaxDistance = 420,
	PinWarningWidth = 30,
	PinWarningHeight = 20,
}

return StoreConfig
