--[[
	RoadRenderer.luau
	Transforme les pièces de RoadGeometry en Parts. Un seul rendu de route :
	chaque case donne au plus une dizaine de parts (virage : 6), toutes
	ancrées, sans collision ni ombre. Aucune logique de partie ici ; le suivi
	des cases à redessiner est dans SessionRoadVisuals.

	Couches (RoadConfig.Layers) : liseré blanc, surface graphite ou pont. Une
	couche a une hauteur et une couleur, donc les pièces d'une même couche qui
	se chevauchent restent invisibles (ni couture, ni triangle).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local RoadConfig = require(Shared.RoadConfig)
local RoadGeometry = require(Shared.RoadGeometry)
local SessionUtil = require(script.Parent.SessionUtil)
local makePart = SessionUtil.makePart
local animateRoadPart = SessionUtil.animateRoadPart

local RoadRenderer = {}

-- Un Cylinder a son axe selon X : la rotation le couche debout, son disque
-- est alors dans le plan XZ, comme les cases vues d'en haut.
local CYLINDER_UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

local NEIGHBOR_DIRS = {
	{ name = "N", dx = 0, dy = -1 },
	{ name = "E", dx = 1, dy = 0 },
	{ name = "S", dx = 0, dy = 1 },
	{ name = "W", dx = -1, dy = 0 },
}

-- Nom de part, couleur et dalle d'une couche de RoadGeometry. Le liseré d'une
-- case de pont est plus haut que celui d'une route : le pont passe sur l'eau.
local function layerStyle(layer, isBridge)
	local layers = RoadConfig.Layers
	if layer == "edge" then
		if isBridge then
			return "RoadBridgeEdge", Config.Colors.BridgeEdge, layers.BridgeEdge
		end
		return "RoadEdge", Config.Colors.RoadEdge, layers.Edge
	end
	if layer == "bridge" then
		return "RoadBridge", Config.Colors.Bridge, layers.Bridge
	end
	return "RoadBody", Config.Colors.Road, layers.Body
end

-- Raccords de la case : un par côté orthogonal occupé par un bâtiment. Les
-- routes s'arrêtent alors exactement au bord de la case, sans entrer dessous.
local function connectorsAround(session, x, y)
	local connectors = {}
	for _, dir in ipairs(NEIGHBOR_DIRS) do
		if session.buildings[Grid.key(x + dir.dx, y + dir.dy)] then
			connectors[RoadGeometry.connectorKey(x, y, dir.name)] = true
		end
	end
	return connectors
end

-- Signature de la forme d'une case : deux cases de même signature ont
-- exactement les mêmes pièces, il est inutile de les redessiner.
function RoadRenderer.signature(session, key)
	local x, y = Grid.parse(key)
	if not x or not session.roads[key] then
		return nil
	end
	local mask = RoadGeometry.neighborMask(session.roads, x, y, session.bridges, connectorsAround(session, x, y))
	return mask * 2 + (session.bridges[key] and 1 or 0)
end

-- Crée les parts de la case `key` sous session.world.Roads et les renvoie.
-- reveal : nil (pas d'animation) ou le délai d'apparition en secondes.
function RoadRenderer.buildCell(session, key, reveal)
	local x, y = Grid.parse(key)
	if not x or not session.roads[key] then
		return {}
	end

	local tile = session.tile
	local isBridge = session.bridges[key] == true
	local pieces = RoadGeometry.cellPieces(
		session.roads,
		session.bridges,
		connectorsAround(session, x, y),
		x,
		y
	)

	local parts = {}
	for _, piece in ipairs(pieces) do
		local name, color, slab = layerStyle(piece.layer, isBridge)
		local pieceWidth, pieceDepth = piece.w, piece.h
		-- Les pièces actuelles valent toutes 0 ; un quart de tour échange les axes.
		if piece.rotation % 180 == 90 then
			pieceWidth, pieceDepth = pieceDepth, pieceWidth
		end
		local position = Vector3.new(
			session.origin.X + (x + piece.cx) * tile,
			session.origin.Y + slab.Top - slab.Thickness * 0.5,
			session.origin.Z + (y + piece.cy) * tile
		)

		local props = { Name = name, Color = color, CastShadow = false }
		local size
		if piece.kind == "disk" then
			size = Vector3.new(slab.Thickness, pieceWidth * tile, pieceWidth * tile)
			props.Shape = Enum.PartType.Cylinder
			props.CFrame = CFrame.new(position) * CYLINDER_UPRIGHT
		else
			size = Vector3.new(pieceWidth * tile, slab.Thickness, pieceDepth * tile)
			props.CFrame = CFrame.new(position)
		end
		props.Size = size
		props.Parent = session.world.Roads

		local part = makePart(props)
		if reveal then
			animateRoadPart(part, size, reveal, session.tweens)
		end
		table.insert(parts, part)
	end
	return parts
end

-- Rond-point : anneau graphite à liseré blanc et île centrale, dans le même
-- langage que les routes (mêmes couleurs, mêmes couches). Posé sur la case.
function RoadRenderer.buildRoundabout(session, key)
	local x, y = Grid.parse(key)
	if not x then
		return nil
	end
	local tile = session.tile
	local layers = RoadConfig.Layers
	local dimensions = Config.Dimensions.Road
	local outer = layers.RoundaboutDiameter
	local ringBody = outer - (dimensions.Edge - dimensions.Width)

	local model = Instance.new("Model")
	model.Name = "Roundabout"

	local function disk(name, diameter, slab, color)
		makePart({
			Name = name,
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(slab.Thickness, diameter * tile, diameter * tile),
			CFrame = CFrame.new(Grid.center(session.origin, x, y, slab.Top - slab.Thickness * 0.5))
				* CYLINDER_UPRIGHT,
			Color = color,
			CastShadow = false,
		})
	end
	disk("RoundaboutEdge", outer, layers.RoundaboutEdge, Config.Colors.RoadEdge)
	disk("RoundaboutBody", ringBody, layers.RoundaboutBody, Config.Colors.Road)
	disk("RoundaboutIsland", layers.RoundaboutIslandDiameter, layers.RoundaboutIsland, Config.Colors.White)

	model.Parent = session.world.FX
	return model
end

return RoadRenderer
