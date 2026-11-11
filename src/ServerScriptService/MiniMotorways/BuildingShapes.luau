--[[
	BuildingShapes.luau
	Formes plates des bâtiments, vues du dessus : rectangle, ellipse, cercle et
	rectangle à coins arrondis. Chaque forme est faite de Parts ancrées, sans
	collision ni ombre portée, posées entre bottomY et bottomY + height.
	Aucune logique de partie ici : seulement de la géométrie.
]]

local SessionUtil = require(script.Parent.SessionUtil)
local makePart = SessionUtil.makePart

local BuildingShapes = {}

-- Un Cylinder a son axe selon X : la rotation le couche debout, son disque
-- est alors dans le plan XZ, comme les cases vues d'en haut.
local CYLINDER_UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

-- Pour un angle de lacet donné, le local Z pointe vers (sin, 0, cos) : c'est
-- la convention de l'entrée des bâtiments.
local function plate(center, bottomY, height, angle)
	return CFrame.new(center.X, bottomY + height * 0.5, center.Z) * CFrame.Angles(0, angle or 0, 0)
end

function BuildingShapes.rect(parent, name, center, width, depth, bottomY, height, color, angle, transparency)
	return makePart({
		Name = name,
		Parent = parent,
		Size = Vector3.new(width, height, depth),
		CFrame = plate(center, bottomY, height, angle),
		Color = color,
		Transparency = transparency or 0,
		CastShadow = false,
	})
end

function BuildingShapes.ellipse(parent, name, center, width, depth, bottomY, height, color, angle, transparency)
	return makePart({
		Name = name,
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, width, depth),
		CFrame = plate(center, bottomY, height, angle) * CYLINDER_UPRIGHT,
		Color = color,
		Transparency = transparency or 0,
		CastShadow = false,
	})
end

function BuildingShapes.circle(parent, name, center, diameter, bottomY, height, color, transparency)
	return BuildingShapes.ellipse(parent, name, center, diameter, diameter, bottomY, height, color, 0, transparency)
end

-- Rectangle à coins arrondis : deux traverses qui se croisent et quatre
-- disques aux coins, soit six parts. Renvoie la traverse horizontale, qui
-- sert de PrimaryPart au modèle.
-- Ces parts se chevauchent : en translucide, chaque recouvrement serait
-- mélangé deux ou trois fois et dessinerait une croix plus foncée. Une forme
-- translucide (une ombre) reste donc une seule part, à coins droits.
function BuildingShapes.roundedRect(parent, name, center, width, depth, radius, bottomY, height, color, angle, transparency)
	local alpha = transparency or 0
	if alpha > 0 then
		return BuildingShapes.rect(parent, name, center, width, depth, bottomY, height, color, angle, alpha)
	end

	local r = math.min(radius, width * 0.45, depth * 0.45)
	local frame = plate(center, bottomY, height, angle)

	local first = makePart({
		Name = name,
		Parent = parent,
		Size = Vector3.new(width, height, depth - 2 * r),
		CFrame = frame,
		Color = color,
		Transparency = alpha,
		CastShadow = false,
	})
	makePart({
		Name = name,
		Parent = parent,
		Size = Vector3.new(width - 2 * r, height, depth),
		CFrame = frame,
		Color = color,
		Transparency = alpha,
		CastShadow = false,
	})
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			makePart({
				Name = name,
				Parent = parent,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(height, 2 * r, 2 * r),
				CFrame = frame * CFrame.new(sx * (width * 0.5 - r), 0, sz * (depth * 0.5 - r)) * CYLINDER_UPRIGHT,
				Color = color,
				Transparency = alpha,
				CastShadow = false,
			})
		end
	end
	return first
end

return BuildingShapes
