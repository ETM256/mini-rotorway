--[[
	InputController.luau
	Dessin des routes à la souris / au doigt.

	Le client construit un aperçu local, case par case. Un geste en biais est
	résolu en chemin orthogonal : horizontal puis vertical, ou l'inverse.
	La validation définitive et les ressources restent au serveur.
	Échap annule le tracé en cours sans rien consommer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Maps = require(Shared.Maps)
local RoadConfig = require(Shared.RoadConfig)
local RoadNetwork = require(Shared.RoadNetwork)

local RoadPreview = require(script.Parent.RoadPreview)

local InputController = {}
InputController.__index = InputController

local GHOST_SCALE = 1.10

local function isMouseInput(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
end

-- GetMouseLocation est la référence écran pour ViewportPointToRay. Pour le
-- tactile, on garde la position de l'InputObject.
local function pointerFrom(input)
	if isMouseInput(input) then
		local location = UserInputService:GetMouseLocation()
		return Vector2.new(location.X, location.Y)
	end
	return Vector2.new(input.Position.X, input.Position.Y)
end

function InputController.new(callbacks)
	local self = setmetatable({}, InputController)
	self.callbacks = callbacks or {}
	self.enabled = false
	self.tool = "build"
	self.origin = Vector3.zero
	self.size = Config.Grid.Size
	self.tile = Config.Grid.TileSize
	self.map = nil

	self.roads = {}
	self.bridges = {}
	self.buildingSet = {}
	self.budget = Config.Roads.StartBudget
	self.bridgesLeft = Config.Roads.StartBridges

	self.dragging = false
	self.dragTool = nil
	self.dragStart = nil
	self.dragAxis = nil
	self.dragScreenDX = 0
	self.dragScreenDY = 0
	self.lastCell = nil
	self.pending = {}
	self.pendingSet = {}
	self.erasePending = {}
	self.eraseSet = {}
	self.pointer = nil
	self.hoverClock = 0

	self.ghost = nil
	self.preview = RoadPreview.new()
	self:createGhost()
	self:bind()
	return self
end

local function makeGhostPart(name, size)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Config.Colors.Teal
	part.Transparency = 1
	part.Size = size
	part.Parent = Workspace
	return part
end

function InputController:createGhost()
	-- Le fantôme ne sert plus qu'au rond-point : les routes ont leur aperçu.
	local size = Vector3.new(self.tile * GHOST_SCALE, 0.04, self.tile * GHOST_SCALE)
	self.ghost = makeGhostPart("MM_Ghost", size)
end

function InputController:bind()
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape and self.dragging then
			self:cancelDrag()
			return
		end
		if processed or not self.enabled then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local pointer = pointerFrom(input)
			self.pointer = pointer
			if self.tool == "camera" then
				self:startCamera()
			elseif self.tool == "erase" then
				self:startErase(pointer)
			elseif self.tool == "roundabout" then
				self:startRoundabout(pointer)
			else
				self:startBuild(pointer)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			local pointer = pointerFrom(input)
			self.pointer = pointer
			self:startErase(pointer)
		elseif input.KeyCode == Enum.KeyCode.One then
			self:setTool("build")
			if self.callbacks.onToolChanged then
				self.callbacks.onToolChanged("build")
			end
		elseif input.KeyCode == Enum.KeyCode.Two then
			self:setTool("erase")
			if self.callbacks.onToolChanged then
				self.callbacks.onToolChanged("erase")
			end
		elseif input.KeyCode == Enum.KeyCode.Three then
			self:setTool("roundabout")
			if self.callbacks.onToolChanged then
				self.callbacks.onToolChanged("roundabout")
			end
		elseif input.KeyCode == Enum.KeyCode.Four then
			self:setTool("camera")
			if self.callbacks.onToolChanged then
				self.callbacks.onToolChanged("camera")
			end
		elseif input.KeyCode == Enum.KeyCode.P then
			if self.callbacks.onPauseRequest then
				self.callbacks.onPauseRequest()
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local previous = self.pointer
			local nextPointer = pointerFrom(input)
			self.pointer = nextPointer

			if previous and self.enabled and self.dragging then
				if self.dragTool == "camera" then
					if self.callbacks.onPan then
						self.callbacks.onPan(nextPointer.X - previous.X, nextPointer.Y - previous.Y)
					end
					return
				end
				-- Axe dominant à l'écran : il choisit l'ordre horizontal /
				-- vertical du prochain petit segment, même quand la souris
				-- traverse exactement une diagonale de case.
				self.dragScreenDX += nextPointer.X - previous.X
				self.dragScreenDY += nextPointer.Y - previous.Y
				local adx = math.abs(self.dragScreenDX)
				local ady = math.abs(self.dragScreenDY)
				if math.max(adx, ady) >= 4 then
					if adx >= ady * 1.15 then
						self.dragAxis = "x"
					elseif ady >= adx * 1.15 then
						self.dragAxis = "y"
					end
				end
			end
		end

		if processed or not self.enabled or not self.dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local cell = self:cellAt(pointerFrom(input))
			if cell then
				self:handleCell(cell[1], cell[2])
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not self.dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.Touch
		then
			self:endDrag()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		self.hoverClock += dt
		if self.hoverClock >= 0.12 then
			self.hoverClock = 0
			if not self.dragging then
				self:refreshPreview()
			end
		end
		self:updateGhost()
	end)
end

function InputController:setWorld(origin, size, tile)
	self.origin = origin
	self.size = size or Config.Grid.Size
	self.tile = tile or Config.Grid.TileSize
	self.ghost.Size = Vector3.new(self.tile * GHOST_SCALE, 0.04, self.tile * GHOST_SCALE)
	self.preview:setWorld(self.origin, self.tile)
end

function InputController:setMapId(mapId)
	self.map = Maps.getById(mapId)
	self:refreshPreview()
end

function InputController:setEnabled(value)
	self.enabled = value == true
	if not self.enabled then
		self:cancelDrag()
		self.roads = {}
		self.bridges = {}
		self.buildingSet = {}
		self.preview:clear()
		self.ghost.Transparency = 1
	end
end

function InputController:setTool(tool)
	if self.dragging then
		self:cancelDrag()
	end
	self.tool = tool
	self.ghost.Color = tool == "erase" and Config.Colors.Danger or Config.Colors.Teal
	if tool == "build" or tool == "erase" then
		self.ghost.Transparency = 1
	end
	self:refreshPreview()
end

-- Le serveur envoie l'état réel du réseau après chaque modification.
function InputController:applyRoadState(data)
	if type(data) ~= "table" then
		return
	end

	local roads = {}
	for _, key in ipairs(data.roads or {}) do
		roads[key] = true
	end
	local bridges = {}
	for _, key in ipairs(data.bridges or {}) do
		bridges[key] = true
	end
	local buildings = {}
	for _, key in ipairs(data.buildings or {}) do
		buildings[key] = true
	end

	self.roads = roads
	self.bridges = bridges
	self.buildingSet = buildings
	self.budget = tonumber(data.budget) or self.budget
	self.bridgesLeft = tonumber(data.bridgesLeft) or self.bridgesLeft
	self:refreshPreview()
end

function InputController:cellAt(position)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	local x2, y2
	if typeof(position) == "Vector3" then
		x2, y2 = position.X, position.Y
	elseif typeof(position) == "Vector2" then
		x2, y2 = position.X, position.Y
	else
		local mouse = UserInputService:GetMouseLocation()
		x2, y2 = mouse.X, mouse.Y
	end

	local ray = camera:ViewportPointToRay(x2, y2)
	if math.abs(ray.Direction.Y) < 0.0001 then
		return nil
	end

	local distance = (self.origin.Y - ray.Origin.Y) / ray.Direction.Y
	if distance <= 0 then
		return nil
	end

	local hit = ray.Origin + ray.Direction * distance
	local u = (hit.X - self.origin.X) / self.tile
	local v = (hit.Z - self.origin.Z) / self.tile
	local cellX = math.floor(u)
	local cellY = math.floor(v)
	if not Grid.inBounds(cellX, cellY) then
		return nil
	end
	return { cellX, cellY }
end

function InputController:startBuild(position)
	local cell = self:cellAt(position)
	if not cell then
		return
	end
	self.dragging = true
	self.dragTool = "build"
	self.dragStart = cell
	self.dragAxis = nil
	self.dragScreenDX = 0
	self.dragScreenDY = 0
	self.lastCell = cell
	self:addBuild(cell[1], cell[2])
	self:refreshPreview()
end

function InputController:startErase(position)
	local cell = self:cellAt(position)
	if not cell then
		return
	end
	self.dragging = true
	self.dragTool = "erase"
	self.dragStart = cell
	self.dragAxis = nil
	self.dragScreenDX = 0
	self.dragScreenDY = 0
	self.lastCell = cell
	self:addErase(cell[1], cell[2])
	self:refreshPreview()
end

function InputController:startCamera()
	self.dragging = true
	self.dragTool = "camera"
	self.dragStart = nil
	self.dragAxis = nil
	self.lastCell = nil
	self.preview:clear()
end

function InputController:startRoundabout(position)
	local cell = self:cellAt(position)
	if not cell then
		return
	end
	self.dragging = false
	self.dragTool = nil
	self.lastCell = nil
	if self.callbacks.onRoundabout then
		self.callbacks.onRoundabout(cell[1], cell[2])
	end
end

function InputController:handleCell(x, y)
	if not self.lastCell then
		self.lastCell = { x, y }
	end

	-- On conserve l'axe dominant du geste pour éviter les zigzags : un léger
	-- mouvement latéral ne fait pas changer l'ordre horizontal / vertical.
	if self.dragStart then
		local ax = x - self.dragStart[1]
		local ay = y - self.dragStart[2]
		local threshold = RoadConfig.Input.DragAxisThreshold
		if math.abs(ax) >= math.abs(ay) + threshold then
			self.dragAxis = "x"
		elseif math.abs(ay) >= math.abs(ax) + threshold then
			self.dragAxis = "y"
		end
	end

	local lastX, lastY = self.lastCell[1], self.lastCell[2]
	local path = RoadNetwork.manhattanPath(lastX, lastY, x, y, self.dragAxis)
	for _, step in ipairs(path) do
		if self.dragTool == "erase" then
			self:addErase(step[1], step[2])
		else
			self:addBuild(step[1], step[2])
		end
	end
	self.lastCell = { x, y }
	self:refreshPreview()
end

function InputController:addBuild(x, y)
	local key = Grid.key(x, y)
	if self.pendingSet[key] then
		return
	end
	self.pendingSet[key] = true
	table.insert(self.pending, { x, y })
end

function InputController:addErase(x, y)
	local key = Grid.key(x, y)
	if self.eraseSet[key] then
		return
	end
	self.eraseSet[key] = true
	table.insert(self.erasePending, key)
end

function InputController:isWater(x, y)
	if not self.map then
		return false
	end
	return Maps.isWater(self.map, x, y)
end

-- Recalcule les cases d'aperçu et leur validité locale. Le serveur reste
-- l'autorité finale, mais le joueur voit immédiatement les refus évidents.
function InputController:refreshPreview()
	if not self.enabled then
		self.preview:clear()
		return
	end

	if self.dragging and self.dragTool == "build" then
		local cells = {}
		local budgetLeft = self.budget
		local bridgesLeft = self.bridgesLeft
		for _, cell in ipairs(self.pending) do
			local x, y = cell[1], cell[2]
			local key = Grid.key(x, y)
			local valid = Grid.inBounds(x, y)
				and not self.roads[key]
				and not self.buildingSet[key]
			if valid and self:isWater(x, y) then
				if bridgesLeft > 0 then
					bridgesLeft -= 1
				else
					valid = false
				end
			end
			if valid then
				if budgetLeft > 0 then
					budgetLeft -= 1
				else
					valid = false
				end
			end
			cells[#cells + 1] = { x = x, y = y, valid = valid }
		end
		self.preview:setCells(cells)
		return
	end

	if self.dragging and self.dragTool == "erase" then
		local cells = {}
		for _, key in ipairs(self.erasePending) do
			local x, y = Grid.parse(key)
			if x then
				cells[#cells + 1] = { x = x, y = y, valid = self.roads[key] == true }
			end
		end
		self.preview:setCells(cells)
		return
	end

	if self.dragging and self.dragTool == "camera" then
		self.preview:clear()
		return
	end

	if self.tool ~= "build" and self.tool ~= "erase" then
		self.preview:clear()
		return
	end

	local cell = self.pointer and self:cellAt(self.pointer) or nil
	if not cell then
		self.preview:clear()
		return
	end

	local x, y = cell[1], cell[2]
	local key = Grid.key(x, y)
	local valid
	if self.tool == "erase" then
		valid = self.roads[key] == true
	else
		valid = Grid.inBounds(x, y)
			and not self.roads[key]
			and not self.buildingSet[key]
		if valid and self:isWater(x, y) then
			valid = self.bridgesLeft > 0
		end
		if valid then
			valid = self.budget > 0
		end
	end
	self.preview:setCells({ { x = x, y = y, valid = valid, hover = true } })
end

function InputController:commit()
	if self.dragTool == "build" then
		local batch = self.pending
		self.pending = {}
		self.pendingSet = {}
		if #batch > 0 and self.callbacks.onDraw then
			local maxCells = RoadConfig.Input.MaxCellsPerRequest
			for index = 1, #batch, maxCells do
				local chunk = {}
				local last = math.min(index + maxCells - 1, #batch)
				for i = index, last do
					chunk[#chunk + 1] = batch[i]
				end
				self.callbacks.onDraw(chunk)
			end
		end
	elseif self.dragTool == "erase" then
		local batch = self.erasePending
		self.erasePending = {}
		self.eraseSet = {}
		if #batch > 0 then
			if self.callbacks.onEraseMany then
				self.callbacks.onEraseMany(batch)
			elseif self.callbacks.onErase then
				for _, key in ipairs(batch) do
					self.callbacks.onErase(key)
				end
			end
		end
	end
end

function InputController:resetDrag()
	self.dragging = false
	self.dragTool = nil
	self.dragStart = nil
	self.dragAxis = nil
	self.dragScreenDX = 0
	self.dragScreenDY = 0
	self.lastCell = nil
end

function InputController:cancelDrag()
	self.pending = {}
	self.pendingSet = {}
	self.erasePending = {}
	self.eraseSet = {}
	self:resetDrag()
	if self.preview then
		self.preview:clear()
	end
end

function InputController:endDrag()
	if self.dragging and (self.dragTool == "build" or self.dragTool == "erase") then
		self:commit()
	end
	self:resetDrag()
	self:refreshPreview()
end

function InputController:updateGhost()
	if not self.enabled or self.tool ~= "roundabout" then
		self.ghost.Transparency = 1
		return
	end

	local cell = self.pointer and self:cellAt(self.pointer) or nil
	if not cell then
		self.ghost.Transparency = 1
		return
	end

	self.ghost.CFrame = CFrame.new(Grid.center(self.origin, cell[1], cell[2], 0.52))
	self.ghost.Color = Config.Colors.Teal
	self.ghost.Transparency = 0.45
end

return InputController
