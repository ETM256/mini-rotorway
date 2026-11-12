--[[
	CarModel.luau
	Voiture vue du dessus : une carrosserie en capsule (un bloc et deux disques
	d'extrémité), une petite vitre claire à l'avant et une ombre très douce.
	Cinq pièces au maximum par voiture, sans contour.
	Le modèle est construit à l'origine et la pièce Body lui sert de pivot :
	Session le place et l'oriente avec PivotTo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RoadConfig = require(Shared.RoadConfig)
local SessionUtil = require(script.Parent.SessionUtil)
local makePart = SessionUtil.makePart

local CarModel = {}

-- Hauteur (studs) du centre de la voiture : le bas de la carrosserie touche le
-- dessus de la route. Session s'en sert pour poser et déplacer la voiture.
CarModel.CenterY = 0.5

local SHADOW = Config.Style.Shadow
-- Dessus le plus haut d'une chaussée au sol : la route ou l'anneau d'un
-- rond-point (sur un pont, l'ombre reste cachée sous le tablier).
local ROAD_TOP = math.max(RoadConfig.Layers.Body.Top, RoadConfig.Layers.RoundaboutBody.Top)

-- Un cylindre a son axe sur X ; cette rotation le couche sur l'axe Y pour
-- en faire un disque vu du dessus.
local DISK_ROTATION = CFrame.Angles(0, 0, math.rad(90))

-- L'avant de la voiture est sur -Z, comme pour CFrame.lookAt.
function CarModel.create(color, tile)
	local vehicle = RoadConfig.Vehicle
	local length = tile * vehicle.LengthTiles
	local width = tile * vehicle.WidthTiles
	local height = vehicle.Height
	-- Les deux disques d'extrémité complètent la longueur du bloc central.
	local bodyLength = length - width

	local model = Instance.new("Model")
	model.Name = "Car"

	local body = makePart({
		Name = "Body",
		Parent = model,
		Size = Vector3.new(width, height, bodyLength),
		Color = color,
		CastShadow = false,
	})
	model.PrimaryPart = body

	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = "Cap",
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, width, width),
			CFrame = CFrame.new(0, 0, side * bodyLength * 0.5) * DISK_ROTATION,
			Color = color,
			CastShadow = false,
		})
	end

	-- Vitre claire à l'avant : elle montre le sens de la voiture.
	makePart({
		Name = "Window",
		Parent = model,
		Size = Vector3.new(width * 0.6, 0.02, length * 0.24),
		CFrame = CFrame.new(0, height * 0.5 + 0.01, -length * 0.2),
		Color = Config.Colors.White,
		CastShadow = false,
	})

	-- Ombre douce (Config.Style.Shadow), décalée vers le bas-droit, posée juste
	-- au-dessus de la route et de l'anneau des ronds-points : en dessous elle
	-- serait invisible.
	makePart({
		Name = "Shadow",
		Parent = model,
		Size = Vector3.new(width + SHADOW.Grow, 0.02, length + SHADOW.Grow),
		CFrame = CFrame.new(SHADOW.Offset, ROAD_TOP + 0.015 - CarModel.CenterY, SHADOW.Offset),
		Color = Config.Colors.BuildingShadow,
		Transparency = SHADOW.Transparency,
		CastShadow = false,
	})

	return model
end

return CarModel
