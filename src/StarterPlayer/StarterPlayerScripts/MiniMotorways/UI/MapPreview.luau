--[[
	MapPreview.luau
	Dessine l'aperçu circulaire d'une carte dans le menu :
	une géographie d'eau lissée + quelques routes + des points colorés.
	Aucune image nécessaire.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Theme = require(script.Parent.Theme)

local MapPreview = {}

-- Dessine une forme d'eau sans passer par une grille de gros pixels.
-- Les formes sont volontairement simples : rectangles arrondis, disques,
-- ellipses et barres. Elles se superposent pour donner une côte ou une
-- rivière continue, puis le cercle de l'aperçu les découpe.
local function drawWaterShape(circle, shape, diameter, color, padding, zIndex)
	padding = padding or 0
	zIndex = zIndex or 1
	local kind = shape.type

	if kind == "rect" then
		local frame = Theme.new("Frame", {
			Parent = circle,
			Position = UDim2.fromOffset(
				shape.x * diameter - padding,
				shape.y * diameter - padding
			),
			Size = UDim2.fromOffset(
				shape.w * diameter + padding * 2,
				shape.h * diameter + padding * 2
			),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		})
		Theme.corner(frame, (shape.radius or 0) * diameter + padding)
		return
	end

	if kind == "circle" or kind == "ellipse" then
		local baseRx = shape.rx or shape.r or 0.05
		local baseRy = shape.ry or shape.r or baseRx
		local rx = baseRx * diameter + padding
		local ry = baseRy * diameter + padding

		-- Un Frame avec UICorner donne une capsule, pas une vraie ellipse.
		-- On approche donc l'ellipse par une chaîne de cercles dont le rayon
		-- suit la largeur de l'ellipse le long de son grand axe.
		if math.abs(rx - ry) <= math.max(0.35, math.min(rx, ry) * 0.04) then
			local blob = Theme.new("Frame", {
				Parent = circle,
				Position = UDim2.fromScale(shape.x, shape.y),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(rx * 2, ry * 2),
				Rotation = shape.rotation or 0,
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = zIndex,
			})
			Theme.corner(blob, math.min(rx, ry))
			return
		end

		local baseMajor = math.max(baseRx, baseRy) * diameter
		local baseMinor = math.min(baseRx, baseRy) * diameter
		local angle = math.rad(shape.rotation or 0)
		if baseRy > baseRx then
			angle += math.pi / 2
		end
		local axisX = math.cos(angle)
		local axisY = math.sin(angle)
		local count = math.clamp(math.ceil(baseMajor / 1.6), 5, 32)
		local centerX = shape.x * diameter
		local centerY = shape.y * diameter

		for i = 0, count - 1 do
			local theta = -math.pi / 2 + math.pi * (i / (count - 1))
			local offset = baseMajor * math.sin(theta)
			local radius = baseMinor * math.cos(theta)
			if radius < 0.35 then
				radius = 0.35
			end
			local size = (radius + padding) * 2
			local dot = Theme.new("Frame", {
				Parent = circle,
				Position = UDim2.fromOffset(
					centerX + offset * axisX - size * 0.5,
					centerY + offset * axisY - size * 0.5
				),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = zIndex,
			})
			Theme.corner(dot, size * 0.5)
		end
		return
	end

	if kind == "bar" then
		local dx = (shape.x2 - shape.x1) * diameter
		local dy = (shape.y2 - shape.y1) * diameter
		local length = math.sqrt(dx * dx + dy * dy)
		local angle = math.deg(math.atan2(dy, dx))
		local thickness = (shape.thickness or 0.04) * diameter + padding * 2
		local centerX = (shape.x1 + shape.x2) * 0.5 * diameter
		local centerY = (shape.y1 + shape.y2) * 0.5 * diameter

		if shape.flatStart then
			-- Coupure nette côté terre : un rectangle jusqu'au bout, puis
			-- un seul capuchon rond côté eau. Même principe que la 3D.
			Theme.new("Frame", {
				Parent = circle,
				Position = UDim2.fromOffset(centerX, centerY),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(length, thickness),
				Rotation = angle,
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = zIndex,
			})
			local cap = Theme.new("Frame", {
				Parent = circle,
				Position = UDim2.fromOffset(shape.x2 * diameter, shape.y2 * diameter),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(thickness, thickness),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = zIndex,
			})
			Theme.corner(cap, thickness / 2)
			return
		end

		local bar = Theme.new("Frame", {
			Parent = circle,
			Position = UDim2.fromOffset(centerX, centerY),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(length + thickness * 0.5, thickness),
			Rotation = angle,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		})
		Theme.corner(bar, thickness / 2)
	end
end

function MapPreview.create(parent, map, diameter, position, anchorPoint)
	-- Le cercle est posé sur un anneau beige, avec un liseré menthe foncé :
	-- on retrouve le cadre de la référence, sans image.
	local wrapper = Theme.new("Frame", {
		Name = "PreviewFrame_" .. map.id,
		Parent = parent,
		Position = position or UDim2.fromScale(0.5, 0),
		AnchorPoint = anchorPoint or Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(diameter + 8, diameter + 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
	})
	Theme.circle(wrapper, diameter + 8, Config.Colors.RingShadow or Color3.fromHex("D3CDB8"), {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 1,
	})

	-- CanvasGroup, et non Frame : contrairement à ClipsDescendants seul, il
	-- découpe réellement les enfants selon les coins arrondis. L'eau ne peut
	-- donc plus déborder dans les angles du cercle.
	local circle = Theme.new("CanvasGroup", {
		Name = "Preview_" .. map.id,
		Parent = wrapper,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(diameter, diameter),
		BackgroundColor3 = map.land,
		BorderSizePixel = 0,
		ZIndex = 2,
	})
	Theme.corner(circle, diameter / 2)
	Theme.stroke(circle, Config.Colors.Ring or Color3.fromHex("88B5A7"), math.max(4, diameter * 0.03), 0)

	-- Zones vertes douces, comme les parcs de la vidéo.
	for _, shape in ipairs(map.grassShapes or {}) do
		drawWaterShape(circle, shape, diameter, map.grass or Config.Colors.Grass, 0, 1)
	end

	-- Eau lissée : chaque carte fournit ses formes dans Maps.luau.
	-- Ombre extérieure, liseré de côte blanc, puis remplissage menthe.
	local waterShapes = map.waterShapes
	local outline = math.max(1.8, diameter * 0.015)
	local coastColor = Config.Colors.Coast or Color3.fromHex("FFFFF7")
	if waterShapes and #waterShapes > 0 then
		local shadowColor = map.waterDeep or Config.Colors.WaterDeep
		for _, shape in ipairs(waterShapes) do
			drawWaterShape(circle, shape, diameter, shadowColor, outline * 1.8, 1)
		end
		for _, shape in ipairs(waterShapes) do
			drawWaterShape(circle, shape, diameter, coastColor, outline * 0.95, 2)
		end
		for _, shape in ipairs(waterShapes) do
			drawWaterShape(circle, shape, diameter, map.water, 0, 3)
		end
	else
		-- Filet de sécurité si une carte n'a pas encore de waterShapes.
		local cells = 24
		local cell = diameter / cells
		for gx = 0, cells - 1 do
			for gy = 0, cells - 1 do
				local nx = (gx + 0.5) / cells
				local ny = (gy + 0.5) / cells
				if map.isWater(nx, ny) then
					Theme.new("Frame", {
						Parent = circle,
						Position = UDim2.fromOffset(gx * cell, gy * cell),
						Size = UDim2.fromOffset(cell + 0.5, cell + 0.5),
						BackgroundColor3 = map.water,
						BorderSizePixel = 0,
						ZIndex = 1,
					})
				end
			end
		end
	end

	-- Presqu'îles sèches dessinées par-dessus l'eau : liseré de côte blanc,
	-- puis terre crème. Le petit raccord terre masque le liseré côté continent.
	for _, shape in ipairs(map.dryShapes or {}) do
		drawWaterShape(circle, shape, diameter, coastColor, outline * 0.95, 4)
	end
	for _, shape in ipairs(map.dryShapes or {}) do
		drawWaterShape(circle, shape, diameter, map.land, 0, 5)
	end
	for _, shape in ipairs(map.dryPatches or {}) do
		drawWaterShape(circle, shape, diameter, map.land, 0, 6)
	end

	-- Petit réseau routier et pastilles de bâtiments : l'aperçu ressemble
	-- davantage à une carte jouable, sans surcharger le cercle.
	local roads = map.previewRoads or {}
	local roadWidth = math.max(5, diameter * 0.030)
	local roadColor = Config.Colors.LobbyRoad or Config.Colors.White
	local roadShadow = Config.Colors.LobbyRoadShadow or Config.Colors.CardShadow

	local function drawPreviewRoad(road, color, width, offsetX, offsetY, zIndex)
		local ax = road[1] * diameter + offsetX
		local ay = road[2] * diameter + offsetY
		local bx = road[3] * diameter + offsetX
		local by = road[4] * diameter + offsetY
		local dx = bx - ax
		local dy = by - ay
		local length = math.sqrt(dx * dx + dy * dy)
		if length <= 0 then
			return
		end
		local bar = Theme.new("Frame", {
			Parent = circle,
			Position = UDim2.fromOffset((ax + bx) * 0.5, (ay + by) * 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(length + width * 0.5, width),
			Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		})
		Theme.corner(bar, width / 2)
	end

	for _, road in ipairs(roads) do
		drawPreviewRoad(road, roadShadow, roadWidth + 3, 1.5, 2, 6)
	end
	for _, road in ipairs(roads) do
		drawPreviewRoad(road, roadColor, roadWidth, 0, 0, 7)
	end

	local endpoints = {}
	local seen = {}
	local buildingSize = math.max(14, diameter * 0.075)
	for index, road in ipairs(roads) do
		for pointIndex = 1, 2 do
			local nx = road[pointIndex == 1 and 1 or 3]
			local ny = road[pointIndex == 1 and 2 or 4]
			local key = string.format("%.3f:%.3f", nx, ny)
			if not seen[key]
				and nx > 0.02
				and nx < 0.98
				and ny > 0.02
				and ny < 0.98
				and not (map.isWater and map.isWater(nx, ny))
			then
				seen[key] = true
				table.insert(endpoints, { x = nx, y = ny, index = index + pointIndex })
			end
		end
	end

	for _, endpoint in ipairs(endpoints) do
		local x = endpoint.x * diameter
		local y = endpoint.y * diameter
		local palette = Config.HouseColors[(endpoint.index - 1) % #Config.HouseColors + 1]
		local shadow = Theme.new("Frame", {
			Parent = circle,
			Position = UDim2.fromOffset(x - buildingSize * 0.5 + 1.5, y - buildingSize * 0.5 + 2),
			Size = UDim2.fromOffset(buildingSize, buildingSize),
			BackgroundColor3 = roadShadow,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 8,
		})
		Theme.corner(shadow, 4)
		local building = Theme.new("Frame", {
			Parent = circle,
			Position = UDim2.fromOffset(x - buildingSize * 0.5, y - buildingSize * 0.5),
			Size = UDim2.fromOffset(buildingSize, buildingSize),
			BackgroundColor3 = palette.color,
			BorderSizePixel = 0,
			ZIndex = 9,
		})
		Theme.corner(building, 4)
		Theme.stroke(building, roadColor, 1.5, 0)
	end

	return circle
end

return MapPreview
