--[[
	SessionRibbons.luau
	Ruban de route lissé de Session : tracé, courbes et extrémités.
	Ajoute ses méthodes à Session ; appelé une seule fois depuis Session.luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local RoadConfig = require(Shared.RoadConfig)
local SessionUtil = require(script.Parent.SessionUtil)
local makePart = SessionUtil.makePart

return function(Session)
	local function ribbonEdgeKey(a, b)
		if a < b then
			return a .. "|" .. b
		end
		return b .. "|" .. a
	end

	local function isAdjacentKey(a, b)
		local ax, ay = Grid.parse(a)
		local bx, by = Grid.parse(b)
		if not ax or not bx then
			return false
		end
		local dx, dy = bx - ax, by - ay
		return math.abs(dx) <= 1 and math.abs(dy) <= 1 and (dx ~= 0 or dy ~= 0)
	end

	local function catmullRom(p0, p1, p2, p3, t)
		local t2 = t * t
		local t3 = t2 * t
		return (p1 * 2
			+ (p2 - p0) * t
			+ (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
			+ (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
	end

	function Session:clearRoadRibbons()
		for _, part in ipairs(self.roadRibbons) do
			if part and part.Parent then
				part:Destroy()
			end
		end
		self.roadRibbons = {}
	end

	function Session:addRibbonPart(name, size, center, direction, color)
		if not direction or direction.Magnitude < 0.001 then
			return
		end
		local part = makePart({
			Name = name,
			Parent = self.world.Roads,
			Size = size,
			CFrame = CFrame.lookAt(center, center + direction.Unit),
			Color = color,
			CastShadow = false,
		})
		table.insert(self.roadRibbons, part)
	end

	function Session:addRibbonDisk(name, size, center, color)
		local part = makePart({
			Name = name,
			Parent = self.world.Roads,
			Shape = Enum.PartType.Cylinder,
			Size = size,
			CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			CastShadow = false,
		})
		table.insert(self.roadRibbons, part)
	end

	-- Extrémité ovale du ruban : un cylindre aplati dont le grand axe est
	-- perpendiculaire à la route. Il remplace le gros disque rond d'origine.
	function Session:addRibbonOval(name, height, alongDiameter, acrossDiameter, center, direction, color)
		if not direction or direction.Magnitude < 0.001 then
			return
		end
		local unit = direction.Unit
		local across = Vector3.new(unit.Z, 0, -unit.X)
		local part = makePart({
			Name = name,
			Parent = self.world.Roads,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, alongDiameter, acrossDiameter),
			CFrame = CFrame.fromMatrix(center, Vector3.new(0, 1, 0), unit, across),
			Color = color,
			CastShadow = false,
		})
		table.insert(self.roadRibbons, part)
	end

	function Session:hasOtherRoadNeighbor(key, exceptKey)
		local x, y = Grid.parse(key)
		if not x then
			return false
		end
		for _, neighbor in ipairs(Grid.neighbors8(x, y)) do
			local neighborKey = Grid.key(neighbor[1], neighbor[2])
			if neighborKey ~= exceptKey and self.roads[neighborKey] then
				return true
			end
		end
		return false
	end

	function Session:splitRibbonPath(cells)
		local result = {}
		local current = {}
		for _, key in ipairs(cells) do
			if self.roads[key] then
				if #current == 0 or isAdjacentKey(current[#current], key) then
					if #current == 0 or current[#current] ~= key then
						table.insert(current, key)
					end
				else
					if #current >= 2 then
						table.insert(result, current)
					end
					current = { key }
				end
			else
				if #current >= 2 then
					table.insert(result, current)
				end
				current = {}
			end
		end
		if #current >= 2 then
			table.insert(result, current)
		end
		return result
	end

	function Session:createRibbonForPath(path, pathIndex)
		if #path < 2 then
			return false
		end

		-- On ne redessine pas une arête déjà couverte par un ruban existant.
		local hasNewEdge = false
		for i = 1, #path - 1 do
			local edge = ribbonEdgeKey(path[i], path[i + 1])
			if not self.ribbonEdges[edge] then
				hasNewEdge = true
				break
			end
		end
		if not hasNewEdge then
			return false
		end
		for i = 1, #path - 1 do
			self.ribbonEdges[ribbonEdgeKey(path[i], path[i + 1])] = true
		end

		local points = {}
		for _, key in ipairs(path) do
			local x, y = Grid.parse(key)
			if x then
				points[#points + 1] = Grid.center(self.origin, x, y, 0)
			end
		end
		if #points < 2 then
			return false
		end

		local yOffset = (pathIndex % 10) * 0.0015
		local ribbonLift = 0.003
		local edgeWidth = self.tile * RoadConfig.Visual.RibbonEdgeWidth
		local topWidth = self.tile * RoadConfig.Visual.RibbonTopWidth
		local samplesPerSegment = 3
		local samples = {}

		for i = 1, #points - 1 do
			local p0 = points[math.max(i - 1, 1)]
			local p1 = points[i]
			local p2 = points[i + 1]
			local p3 = points[math.min(i + 2, #points)]
			local bridge = self.bridges[path[i]] == true or self.bridges[path[i + 1]] == true
			for s = 0, samplesPerSegment - 1 do
				local t = s / samplesPerSegment
				samples[#samples + 1] = {
					pos = catmullRom(p0, p1, p2, p3, t),
					bridge = bridge,
				}
			end
		end
		samples[#samples + 1] = {
			pos = points[#points],
			bridge = self.bridges[path[#path]] == true,
		}

		for i = 1, #samples - 1 do
			local a = samples[i]
			local b = samples[i + 1]
			local delta = b.pos - a.pos
			local length = delta.Magnitude
			if length > 0.001 then
				local mid = (a.pos + b.pos) * 0.5
				local direction = delta.Unit
				local bridge = a.bridge or b.bridge
				local edgeColor = bridge and Config.Colors.BridgeEdge or Config.Colors.RoadEdge
				local topColor = bridge and Config.Colors.Bridge or Config.Colors.Road
				local edgeHeight = bridge and 0.30 or 0.26
				local edgeY = bridge and 0.23 or 0.17
				local topHeight = bridge and 0.22 or 0.20
				local topY = bridge and 0.32 or 0.24
				-- Très léger décalage entre segments voisins : ils se chevauchent
				-- un peu pour éviter les trous, sans scintillement de faces.
				local segmentLift = (i % 4) * 0.0005

				self:addRibbonPart(
					"RoadRibbonEdge" .. pathIndex .. "_" .. i,
					Vector3.new(edgeWidth, edgeHeight, length + 0.06),
					mid + Vector3.new(0, edgeY + yOffset + segmentLift, 0),
					direction,
					edgeColor
				)
				self:addRibbonPart(
					"RoadRibbonTop" .. pathIndex .. "_" .. i,
					Vector3.new(topWidth, topHeight, length + 0.04),
					mid + Vector3.new(0, topY + yOffset + segmentLift, 0),
					direction,
					topColor
				)
			end
		end

		for i, point in ipairs(points) do
			local key = path[i]
			local bridge = self.bridges[key] == true
			local edgeColor = bridge and Config.Colors.BridgeEdge or Config.Colors.RoadEdge
			local topColor = bridge and Config.Colors.Bridge or Config.Colors.Road
			local edgeHeight = bridge and 0.30 or 0.26
			local edgeY = bridge and 0.23 or 0.17
			local topHeight = bridge and 0.22 or 0.20
			local topY = bridge and 0.32 or 0.24
			-- Aux vraies extrémités, le disque de jonction formerait encore un
			-- gros rond. On le saute : l'extension plate et son capuchon ovale
			-- ajoutés plus bas suffisent.
			local flatStart = i == 1
				and not self:hasOtherRoadNeighbor(path[1], path[2])
			local flatEnd = i == #points
				and not self:hasOtherRoadNeighbor(path[#path], path[#path - 1])

			if not flatStart and not flatEnd then
				self:addRibbonDisk(
					"RoadRibbonEdgeJoint" .. pathIndex .. "_" .. i,
					Vector3.new(edgeHeight - 0.02, edgeWidth, edgeWidth),
					point + Vector3.new(0, edgeY + yOffset + ribbonLift, 0),
					edgeColor
				)
				self:addRibbonDisk(
					"RoadRibbonTopJoint" .. pathIndex .. "_" .. i,
					Vector3.new(topHeight - 0.02, topWidth, topWidth),
					point + Vector3.new(0, topY + yOffset + ribbonLift, 0),
					topColor
				)
			end
		end

		-- Extrémités du ruban : on prolonge le dernier segment jusqu'au bord de
		-- la case, puis on ajoute un capuchon ovale. La boîte plate assure la
		-- continuité, l'ovale arrondit le bout sans recréer un gros disque rond.
		-- On omet cette extension quand la case est déjà reliée à une autre route.
		local function addCap(point, direction, bridge, suffix)
			if not direction or direction.Magnitude < 0.001 then
				return
			end
			local unit = direction.Unit
			-- On va jusqu'au bord de la case dans la direction de la route :
			-- 0,5 case pour un axe, ~0,707 case pour une diagonale (le coin).
			local capLength = (self.tile * 0.5) / math.max(math.abs(unit.X), math.abs(unit.Z))
			local capCenter = point + unit * (capLength * 0.5)
			local edgeColor = bridge and Config.Colors.BridgeEdge or Config.Colors.RoadEdge
			local topColor = bridge and Config.Colors.Bridge or Config.Colors.Road
			local edgeHeight = bridge and 0.30 or 0.26
			local edgeY = bridge and 0.23 or 0.17
			local topHeight = bridge and 0.22 or 0.20
			local topY = bridge and 0.32 or 0.24

			self:addRibbonPart(
				"RoadRibbonEdgeEnd" .. pathIndex .. suffix,
				Vector3.new(edgeWidth, edgeHeight, capLength),
				capCenter + Vector3.new(0, edgeY + yOffset + ribbonLift, 0),
				unit,
				edgeColor
			)
			self:addRibbonPart(
				"RoadRibbonTopEnd" .. pathIndex .. suffix,
				Vector3.new(topWidth, topHeight, capLength),
				capCenter + Vector3.new(0, topY + yOffset + ribbonLift, 0),
				unit,
				topColor
			)

			-- Capuchons ovales posés sur le bout des extensions plates. Le petit
			-- axe suit la route : la fin est arrondie mais reste une ellipse.
			local endPoint = point + unit * capLength
			self:addRibbonOval(
				"RoadRibbonEdgeOval" .. pathIndex .. suffix,
				edgeHeight,
				edgeWidth * 0.62,
				edgeWidth,
				endPoint + Vector3.new(0, edgeY + yOffset + ribbonLift + 0.004, 0),
				unit,
				edgeColor
			)
			self:addRibbonOval(
				"RoadRibbonTopOval" .. pathIndex .. suffix,
				topHeight,
				topWidth * 0.62,
				topWidth,
				endPoint + Vector3.new(0, topY + yOffset + ribbonLift + 0.004, 0),
				unit,
				topColor
			)
		end

		if not self:hasOtherRoadNeighbor(path[1], path[2]) then
			addCap(points[1], points[1] - points[2], self.bridges[path[1]] == true, "Start")
		end
		if not self:hasOtherRoadNeighbor(path[#path], path[#path - 1]) then
			addCap(points[#points], points[#points] - points[#points - 1], self.bridges[path[#path]] == true, "End")
		end

		return true
	end

	function Session:addRoadRibbons(cells)
		if type(cells) ~= "table" or not self.world or not self.world.Roads then
			return
		end
		-- Si un effacement attend sa reconstruction, on le solde d'abord pour
		-- que le nouveau tracé ne soit pas considéré comme déjà couvert.
		if self.roadRibbonsDirty then
			self.roadRibbonsDirty = false
			self:rebuildRoadRibbons()
		end
		local ordered = {}
		local firstKey = nil

		for _, cell in ipairs(cells) do
			if type(cell) == "table" then
				local x, y = tonumber(cell[1]), tonumber(cell[2])
				if x and y then
					local key = Grid.key(math.floor(x), math.floor(y))
					if self.roads[key] then
						firstKey = key
						break
					end
				end
			end
		end

		-- Le lot suivant commence souvent par la dernière case du lot précédent.
		-- On la reprend pour que le ruban soit continu d'un envoi à l'autre.
		if self.lastRibbonCell
			and self.roads[self.lastRibbonCell]
			and firstKey
			and isAdjacentKey(self.lastRibbonCell, firstKey)
		then
			table.insert(ordered, self.lastRibbonCell)
		end

		for _, cell in ipairs(cells) do
			if type(cell) == "table" then
				local x, y = tonumber(cell[1]), tonumber(cell[2])
				if x and y then
					local key = Grid.key(math.floor(x), math.floor(y))
					if self.roads[key] and (#ordered == 0 or ordered[#ordered] ~= key) then
						table.insert(ordered, key)
					end
				end
			end
		end

		for i = #cells, 1, -1 do
			local cell = cells[i]
			if type(cell) == "table" then
				local x, y = tonumber(cell[1]), tonumber(cell[2])
				if x and y then
					local key = Grid.key(math.floor(x), math.floor(y))
					if self.roads[key] then
						self.lastRibbonCell = key
						break
					end
				end
			end
		end

		if #ordered < 2 then
			return
		end

		for _, path in ipairs(self:splitRibbonPath(ordered)) do
			if self:createRibbonForPath(path, #self.roadRibbonPaths + 1) then
				table.insert(self.roadRibbonPaths, path)
			end
		end
	end

	function Session:rebuildRoadRibbons()
		if not self.world or not self.world.Roads then
			return
		end
		self:clearRoadRibbons()
		self.ribbonEdges = {}
		local newPaths = {}
		for _, path in ipairs(self.roadRibbonPaths) do
			for _, subPath in ipairs(self:splitRibbonPath(path)) do
				if self:createRibbonForPath(subPath, #newPaths + 1) then
					table.insert(newPaths, subPath)
				end
			end
		end
		self.roadRibbonPaths = newPaths
	end
end
