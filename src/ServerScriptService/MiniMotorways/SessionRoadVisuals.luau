--[[
	SessionRoadVisuals.luau
	Rendu des cases de route de Session (tuiles, ponts, rond-points).
	Ajoute ses méthodes à Session ; appelé une seule fois depuis Session.luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local RoadConfig = require(Shared.RoadConfig)
local SessionUtil = require(script.Parent.SessionUtil)
local makePart = SessionUtil.makePart
local animateRoadPart = SessionUtil.animateRoadPart

return function(Session)
	function Session:createRoadVisual(key, isBridge, delay, animate)
		local x, y = Grid.parse(key)
		if not x then
			return
		end

		delay = delay or 0
		animate = animate ~= false
		local function reveal(part, size)
			if animate then
				animateRoadPart(part, size, delay)
			end
		end

		local tile = self.tile
		local color = isBridge and Config.Colors.Bridge or Config.Colors.Road
		local edgeColor = isBridge and Config.Colors.BridgeEdge or Config.Colors.RoadEdge
		local contourColor = Config.Colors.RoadContour
		local outlineHeight = isBridge and 0.32 or 0.28
		local outlineCenterY = isBridge and 0.21 or 0.15
		local contourHeight = isBridge and 0.28 or 0.24
		local contourCenterY = isBridge and 0.255 or 0.18
		local topHeight = isBridge and 0.20 or 0.18
		local topCenterY = isBridge and 0.30 or 0.22
		local jointRotation = CFrame.Angles(0, 0, math.rad(90))
		-- Le liseré blanc reste visible tout autour du ruban graphite : les
		-- couches sont légèrement décalées pour éviter toute couture.
		local layerLift = 0.01
		local diagonalLift = 0.008

		local parts = {}
		local function addBox(name, size, center, partColor)
			local part = makePart({
				Name = name,
				Parent = self.world.Roads,
				Size = size,
				CFrame = CFrame.new(center),
				Color = partColor,
			})
			reveal(part, size)
			table.insert(parts, part)
			return part
		end

		local function addCylinder(name, size, center, partColor)
			local part = makePart({
				Name = name,
				Parent = self.world.Roads,
				Shape = Enum.PartType.Cylinder,
				Size = size,
				CFrame = CFrame.new(center) * jointRotation,
				Color = partColor,
			})
			reveal(part, size)
			table.insert(parts, part)
			return part
		end

		-- Segment orienté librement, réservé aux liaisons diagonales. Il est
		-- volontairement placé très légèrement sous la forme arrondie centrale :
		-- la forme ovale recouvre le raccord et il ne reste aucun triangle.
		local function addRotatedBox(name, size, center, direction, partColor)
			local part = makePart({
				Name = name,
				Parent = self.world.Roads,
				Size = size,
				CFrame = CFrame.lookAt(center, center + direction),
				Color = partColor,
			})
			reveal(part, size)
			table.insert(parts, part)
			return part
		end

		-- Extrémité ovale : le grand axe reste perpendiculaire à la route, le
		-- petit axe suit la route. On obtient une fin arrondie sans gros disque.
		local function addOval(name, height, alongDiameter, acrossDiameter, center, direction, partColor)
			local unit = direction.Unit
			local across = Vector3.new(unit.Z, 0, -unit.X)
			local size = Vector3.new(height, alongDiameter, acrossDiameter)
			local part = makePart({
				Name = name,
				Parent = self.world.Roads,
				Shape = Enum.PartType.Cylinder,
				Size = size,
				CFrame = CFrame.fromMatrix(center, Vector3.new(0, 1, 0), unit, across),
				Color = partColor,
			})
			reveal(part, size)
			table.insert(parts, part)
			return part
		end

		local function addDiagonalSegment(name, width, height, centerY, partColor, dx, dz)
			local from = Grid.center(self.origin, x, y, 0)
			local to = Grid.center(self.origin, x + dx, y + dz, 0)
			local midpoint = (from + to) * 0.5
			local direction = (to - from).Unit
			local center = midpoint + Vector3.new(0, centerY, 0)
			addRotatedBox(
				name,
				Vector3.new(width, height, (to - from).Magnitude),
				center,
				direction,
				partColor
			)
		end

		-- Les directions orthogonales gardent exactement l'ancien rendu : cases
		-- droites, virages en arc et extrémités arrondies. Les directions
		-- diagonales sont collectées séparément et ajoutées sous ces formes.
		local neighborDirs = {}
		local diagonalDirs = {}
		for _, neighbor in ipairs(Grid.neighbors8(x, y)) do
			local nx, ny = neighbor[1], neighbor[2]
			if Grid.inBounds(nx, ny) and self.roads[Grid.key(nx, ny)] then
				local dx, dy = nx - x, ny - y
				if dx == 0 or dy == 0 then
					table.insert(neighborDirs, { dx, dy })
				else
					table.insert(diagonalDirs, { dx, dy, nx, ny })
				end
			end
		end

		-- Une diagonale droite ne doit pas avoir de tuile centrale plus large :
		-- sinon le ruban paraît bosselé à chaque case. On la laisse filer comme
		-- une route horizontale et on ne garde les formes centrales qu'aux
		-- virages, aux extrémités et aux jonctions.
		local isStraightDiagonal = false
		if #neighborDirs == 0 and #diagonalDirs == 2 then
			local a, b = diagonalDirs[1], diagonalDirs[2]
			if a[1] == -b[1] and a[2] == -b[2] then
				isStraightDiagonal = true
				local cellIsBridge = self.bridges[key] == true
				for _, diagonal in ipairs(diagonalDirs) do
					local neighborBridge = self.bridges[Grid.key(x + diagonal[1], y + diagonal[2])] == true
					if (cellIsBridge or neighborBridge) ~= cellIsBridge then
						isStraightDiagonal = false
						break
					end
				end
			end
		end

		-- Les lignes droites gardent des bords parfaitement droits. Un virage
		-- est un arc d'anneau : une suite de disques qui se chevauchent dessine
		-- l'extérieur et l'intérieur arrondis, avec une largeur constante.
		local isTurn = false
		local turnDirs = nil
		local rounded = nil
		if #neighborDirs == 0 then
			rounded = { NE = true, NW = true, SE = true, SW = true }
		elseif #neighborDirs == 2 then
			local a, b = neighborDirs[1], neighborDirs[2]
			if a[1] * b[1] + a[2] * b[2] == 0 then
				isTurn = true
				turnDirs = { a, b }
			end
		end

		local center = Grid.center(self.origin, x, y, 0)
		local function addLayer(name, width, height, centerY, radius, layerColor)
			local layerCenter = center + Vector3.new(0, centerY, 0)
			if not rounded then
				addBox(name, Vector3.new(width, height, width), layerCenter, layerColor)
				return
			end

			local r = math.min(radius, width * 0.5)
			local inner = width * 0.5 - r
			addBox(name .. "H", Vector3.new(width, height, width - 2 * r), layerCenter, layerColor)
			addBox(name .. "V", Vector3.new(width - 2 * r, height, width), layerCenter, layerColor)

			local corners = {
				{ key = "NE", sx = 1, sz = -1 },
				{ key = "NW", sx = -1, sz = -1 },
				{ key = "SE", sx = 1, sz = 1 },
				{ key = "SW", sx = -1, sz = 1 },
			}
			for _, corner in ipairs(corners) do
				if rounded[corner.key] then
					addCylinder(
						name .. corner.key,
						Vector3.new(height, 2 * r, 2 * r),
						layerCenter + Vector3.new(corner.sx * inner, 0, corner.sz * inner),
						layerColor
					)
				else
					addBox(
						name .. corner.key,
						Vector3.new(r, height, r),
						layerCenter + Vector3.new(corner.sx * (inner + r * 0.5), 0, corner.sz * (inner + r * 0.5)),
						layerColor
					)
				end
			end
		end

		local roadWidth = tile * RoadConfig.Visual.RoadWidth
		local contourWidth = tile * RoadConfig.Visual.ContourWidth
		local edgeWidth = tile * RoadConfig.Visual.EdgeWidth
		local cornerRadius = roadWidth * RoadConfig.Visual.CornerRadius

		local function addArcLayer(name, width, height, centerY, layerColor, dirs)
			local d1, d2 = dirs[1], dirs[2]
			local outer = Vector3.new(-(d1[1] + d2[1]), 0, -(d1[2] + d2[2])).Unit
			local function perpTowardOuter(dir)
				local a = Vector3.new(dir[2], 0, -dir[1])
				local b = Vector3.new(-dir[2], 0, dir[1])
				if a:Dot(outer) >= b:Dot(outer) then
					return a
				end
				return b
			end

			local p1 = perpTowardOuter(d1)
			local p2 = perpTowardOuter(d2)
			local arcCenter = center
				+ Vector3.new((d1[1] + d2[1]) * tile * 0.5, centerY, (d1[2] + d2[2]) * tile * 0.5)
			local arcRadius = tile * 0.5
			local steps = 6
			for index = 0, steps do
				local t = index / steps
				local direction = (p1 * (1 - t) + p2 * t).Unit
				local circleCenter = arcCenter + direction * arcRadius
				addCylinder(
					name .. tostring(index),
					Vector3.new(height, width, width),
					circleCenter,
					layerColor
				)
			end
		end

		local function addTileLayer(name, width, height, centerY, layerColor)
			if isTurn then
				addArcLayer(name, width, height, centerY, layerColor, turnDirs)
				return
			end

			if #neighborDirs == 0 then
				-- Une diagonale droite est déjà couverte par le ruban et son
				-- disque de jonction. Une tuile plus large ferait une bosse.
				if not isStraightDiagonal then
					local offset = (width - roadWidth) * 0.5
					addLayer(name, width, height, centerY, cornerRadius + offset, layerColor)
				end
				return
			end

			local layerCenter = center + Vector3.new(0, centerY, 0)
			-- Une case qui a une seule route orthogonale et une diagonale n'est pas
			-- une extrémité : on ne dessine que la branche utile et le disque
			-- central, au lieu du grand capuchon historique qui créerait un ergot.
			if #neighborDirs == 1 and #diagonalDirs > 0 then
				local axis = neighborDirs[1]
				if axis[1] ~= 0 then
					addBox(
						name,
						Vector3.new(tile * 0.5, height, width),
						layerCenter + Vector3.new(axis[1] * tile * 0.25, 0, 0),
						layerColor
					)
				else
					addBox(
						name,
						Vector3.new(width, height, tile * 0.5),
						layerCenter + Vector3.new(0, 0, axis[2] * tile * 0.25),
						layerColor
					)
				end
				return
			end

			if #neighborDirs <= 2 then
				local axis = neighborDirs[1]
				if axis[1] ~= 0 then
					addBox(name, Vector3.new(tile, height, width), layerCenter, layerColor)
				else
					addBox(name, Vector3.new(width, height, tile), layerCenter, layerColor)
				end
				return
			end

			-- T et croisement : une branche par voisin, depuis le centre.
			for _, dir in ipairs(neighborDirs) do
				if dir[1] ~= 0 then
					addBox(
						name .. (dir[1] > 0 and "E" or "W"),
						Vector3.new(tile * 0.5, height, width),
						layerCenter + Vector3.new(dir[1] * tile * 0.25, 0, 0),
						layerColor
					)
				else
					addBox(
						name .. (dir[2] > 0 and "S" or "N"),
						Vector3.new(width, height, tile * 0.5),
						layerCenter + Vector3.new(0, 0, dir[2] * tile * 0.25),
						layerColor
					)
				end
			end
		end

		-- Les diagonales passent d'abord, sous les formes arrondies. On ne les
		-- dessine qu'une fois par arête (clé la plus petite) pour éviter les
		-- surfaces coplanaires qui clignotent.
		local diagonalLayers = {
			{
				name = "RoadOutline",
				width = edgeWidth,
				height = outlineHeight,
				centerY = outlineCenterY,
				color = edgeColor,
				bridgeHeight = 0.32,
				bridgeCenterY = 0.21,
				bridgeColor = Config.Colors.BridgeEdge,
			},
			{
				name = "RoadContour",
				width = contourWidth,
				height = contourHeight,
				centerY = contourCenterY,
				color = contourColor,
				bridgeHeight = 0.28,
				bridgeCenterY = 0.255,
				bridgeColor = contourColor,
			},
			{
				name = "Road",
				width = roadWidth,
				height = topHeight,
				centerY = topCenterY,
				color = color,
				bridgeHeight = 0.20,
				bridgeCenterY = 0.30,
				bridgeColor = Config.Colors.Bridge,
			},
		}
		for _, layer in ipairs(diagonalLayers) do
			for _, diagonal in ipairs(diagonalDirs) do
				local nx, ny = diagonal[1], diagonal[2]
				local neighborKey = Grid.key(nx, ny)
				if key < neighborKey then
					local edgeIsBridge = self.bridges[key] == true or self.bridges[neighborKey] == true
					addDiagonalSegment(
						layer.name .. "_" .. neighborKey,
						layer.width,
						edgeIsBridge and layer.bridgeHeight or layer.height,
						(edgeIsBridge and layer.bridgeCenterY or layer.centerY) - diagonalLift,
						edgeIsBridge and layer.bridgeColor or layer.color,
						diagonal[1],
						diagonal[2]
					)
				end
			end
		end

		-- Un disque central recouvre l'extrémité carrée de chaque segment diagonal.
		-- Il est placé entre les segments et les formes orthogonales : le raccord
		-- reste rond, sans coin ni triangle qui dépasse, même sur un T ou un
		-- croisement qui n'a pas de forme centrale arrondie.
		if #diagonalDirs > 0 and not isStraightDiagonal then
			for _, layer in ipairs(diagonalLayers) do
				local capHeight = isBridge and layer.bridgeHeight or layer.height
				local capCenterY = isBridge and layer.bridgeCenterY or layer.centerY
				addCylinder(
					layer.name .. "_Center",
					Vector3.new(capHeight, layer.width, layer.width),
					center + Vector3.new(0, capCenterY - diagonalLift * 0.5, 0),
					isBridge and layer.bridgeColor or layer.color
				)
			end
		end

		addTileLayer("RoadOutline", edgeWidth, outlineHeight, outlineCenterY, edgeColor)
		addTileLayer("RoadContour", contourWidth, contourHeight, contourCenterY, contourColor)
		addTileLayer("Road", roadWidth, topHeight, topCenterY, color)

		-- Extrémité : on prolonge la route jusqu'au bord de la case avec une
		-- boîte plate, puis on ajoute un capuchon ovale. Le bout est arrondi
		-- comme dans la vidéo, sans recréer les gros disques ronds d'origine.
		if #neighborDirs == 1 and #diagonalDirs == 0 then
			local dir = neighborDirs[1]
			local direction = Vector3.new(dir[1], 0, dir[2])
			local capLength = tile * 0.5
			local capCenter = center
				+ direction * (capLength * 0.5)
			addRotatedBox(
				"RoadOutlineEnd",
				Vector3.new(edgeWidth, outlineHeight, capLength),
				capCenter + Vector3.new(0, outlineCenterY + layerLift, 0),
				direction,
				edgeColor
			)
			addRotatedBox(
				"RoadContourEnd",
				Vector3.new(contourWidth, contourHeight, capLength),
				capCenter + Vector3.new(0, contourCenterY + layerLift, 0),
				direction,
				contourColor
			)
			addRotatedBox(
				"RoadEnd",
				Vector3.new(roadWidth, topHeight, capLength),
				capCenter + Vector3.new(0, topCenterY + layerLift, 0),
				direction,
				color
			)

			-- Fin ovale : les boîtes plates assurent la continuité, ces ovales
			-- arrondissent seulement le bout. Le petit axe suit la route pour
			-- éviter l'effet « gros rond ».
			local endPoint = center + direction * capLength
			addOval(
				"RoadOutlineOval",
				outlineHeight,
				edgeWidth * 0.62,
				edgeWidth,
				endPoint + Vector3.new(0, outlineCenterY + layerLift + 0.004, 0),
				direction,
				edgeColor
			)
			addOval(
				"RoadContourOval",
				contourHeight,
				contourWidth * 0.62,
				contourWidth,
				endPoint + Vector3.new(0, contourCenterY + layerLift + 0.004, 0),
				direction,
				contourColor
			)
			addOval(
				"RoadOval",
				topHeight,
				roadWidth * 0.62,
				roadWidth,
				endPoint + Vector3.new(0, topCenterY + layerLift + 0.004, 0),
				direction,
				color
			)
		end

		self.roadParts[key] = parts
	end

	function Session:refreshRoadVisual(key)
		local parts = self.roadParts[key]
		if parts then
			for _, part in pairs(parts) do
				if part then
					part:Destroy()
				end
			end
			self.roadParts[key] = nil
		end
		if self.roads[key] then
			self:createRoadVisual(key, self.bridges[key] == true, 0, false)
		end
	end

	--[[
		Ruban de route lissé.

		La simulation reste sur la grille : les voitures suivent les centres des
		cases et le pathfinding ne change pas. Pour l'affichage, on ajoute un ruban
		noir continu au-dessus des cases, tracé avec une spline de Catmull-Rom qui
		passe par leurs centres. Les virages et les diagonales sont donc arrondis
		comme dans la vidéo, sans modifier les règles ni le budget.
	]]

	function Session:createRoundaboutVisual(key)
		local x, y = Grid.parse(key)
		if not x then
			return
		end
		local tile = self.tile
		local model = Instance.new("Model")
		model.Name = "Roundabout"

		local rotation = CFrame.Angles(0, 0, math.rad(90))
		-- Même liseré blanc fin que les routes, autour du rond-point graphite.
		makePart({
			Name = "RoundaboutContour",
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.20, tile * 1.02, tile * 1.02),
			CFrame = CFrame.new(Grid.center(self.origin, x, y, 0.32)) * rotation,
			Color = Config.Colors.RoadContour,
		})
		makePart({
			Name = "RoundaboutOuter",
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.18, tile * 0.92, tile * 0.92),
			CFrame = CFrame.new(Grid.center(self.origin, x, y, 0.34)) * rotation,
			Color = Config.Colors.Road,
		})
		makePart({
			Name = "RoundaboutInner",
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.20, tile * 0.44, tile * 0.44),
			CFrame = CFrame.new(Grid.center(self.origin, x, y, 0.36)) * rotation,
			Color = Config.Colors.White,
		})
		makePart({
			Name = "RoundaboutDot",
			Parent = model,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.22, tile * 0.16, tile * 0.16),
			CFrame = CFrame.new(Grid.center(self.origin, x, y, 0.38)) * rotation,
			Color = Config.Colors.Ink,
		})

		model.Parent = self.world.FX
		self.roundaboutParts[key] = model
	end
end
