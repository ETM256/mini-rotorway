--[[
	InputController.luau
	Dessin des routes à la souris / au doigt.
	Le client envoie des lots de cases au serveur ; le serveur valide.
	Un seul "fantôme" carré montre la case survolée. La carte garde sa taille,
	mais le carré de visée est agrandi et la détection favorise les diagonales.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)

local InputController = {}
InputController.__index = InputController

-- Le carré de visée déborde légèrement de la case : il est plus facile à
-- repérer et à poser, sans changer la taille réelle de la carte.
local GHOST_SCALE = 1.20
local DIAGONAL_CORNER = 0.32
local DIAGONAL_REACH = 0.95

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
	self.dragging = false
	self.dragTool = nil
	self.lastCell = nil
	self.diagonalIntent = false
	self.pending = {}
	self.pendingSet = {}
	self.erasePending = {}
	self.eraseSet = {}
	self.sendClock = 0
	self.pointer = nil
	self.ghost = nil
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
	-- Un seul carré, fin et presque à plat. Il est volontairement un peu
	-- plus large que la case pour offrir une cible de visée confortable.
	local size = Vector3.new(self.tile * GHOST_SCALE, 0.04, self.tile * GHOST_SCALE)
	self.ghost = makeGhostPart("MM_Ghost", size)
end

function InputController:bind()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not self.enabled then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local pointer = pointerFrom(input)
			self.pointer = pointer
			if self.tool == "erase" then
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

			-- On mémorise si le geste est réellement en biais. La position
			-- seule ne suffit pas : une ligne horizontale tracée près du bas
			-- d'une case ne doit pas se transformer en diagonale.
			local delta = input.Delta
			local adx = math.abs(delta.X)
			local ady = math.abs(delta.Y)
			if adx < 0.01 and ady < 0.01 and previous then
				adx = math.abs(nextPointer.X - previous.X)
				ady = math.abs(nextPointer.Y - previous.Y)
			end
			local biggest = math.max(adx, ady)
			self.diagonalIntent = biggest >= 1
				and math.min(adx, ady) >= biggest * 0.45
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
		self.sendClock += dt
		if self.sendClock >= 0.05 then
			self.sendClock = 0
			if self.dragging then
				self:flush()
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
end

function InputController:setEnabled(value)
	self.enabled = value == true
	if not self.enabled then
		self.dragging = false
		self.dragTool = nil
		self.lastCell = nil
		self.diagonalIntent = false
		self.pending = {}
		self.pendingSet = {}
		self.erasePending = {}
		self.eraseSet = {}
		self.ghost.Transparency = 1
	end
end

function InputController:setTool(tool)
	self.tool = tool
	self.ghost.Color = tool == "erase" and Config.Colors.Danger or Config.Colors.Teal
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
	-- On utilise self.tile plutôt que la constante globale : la sélection
	-- reste exacte même si la carte fournit une taille de case différente.
	local u = (hit.X - self.origin.X) / self.tile
	local v = (hit.Z - self.origin.Z) / self.tile
	local cellX = math.floor(u)
	local cellY = math.floor(v)
	if not Grid.inBounds(cellX, cellY) then
		return nil
	end

	-- Détection diagonale plus tolérante : quand le curseur approche du coin
	-- partagé avec la dernière case, on privilégie la case diagonale. Un geste
	-- en biais ne fabrique donc plus un escalier en passant par la case
	-- horizontale ou verticale voisine.
	if self.dragging and self.diagonalIntent and self.lastCell then
		local lx, ly = self.lastCell[1], self.lastCell[2]
		local dx = u - (lx + 0.5)
		local dy = v - (ly + 0.5)
		local nearLast = dx * dx + dy * dy <= 1.45 * 1.45
		local leftLast = cellX ~= lx or cellY ~= ly
		if leftLast
			and nearLast
			and math.abs(dx) >= DIAGONAL_CORNER
			and math.abs(dy) >= DIAGONAL_CORNER
		then
			local sx = dx > 0 and 1 or -1
			local sy = dy > 0 and 1 or -1
			local nx, ny = lx + sx, ly + sy
			if Grid.inBounds(nx, ny) then
				local ddx = u - (nx + 0.5)
				local ddy = v - (ny + 0.5)
				if ddx * ddx + ddy * ddy <= DIAGONAL_REACH * DIAGONAL_REACH then
					return { nx, ny }
				end
			end
		end
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
	self.lastCell = cell
	self.diagonalIntent = false
	self:addBuild(cell[1], cell[2])
end

function InputController:startErase(position)
	local cell = self:cellAt(position)
	if not cell then
		return
	end
	self.dragging = true
	self.dragTool = "erase"
	self.lastCell = cell
	self.diagonalIntent = false
	self:addErase(cell[1], cell[2])
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

	local lastX, lastY = self.lastCell[1], self.lastCell[2]
	local cx, cy = lastX, lastY
	local guard = 0

	-- On avance simultanément sur X et Y : un geste en diagonale dessine
	-- donc une vraie ligne à 45°, puis termine tout droit si les deux axes
	-- n'ont pas la même longueur. Sans cela, le client fabriquait un escalier
	-- de cases horizontales/verticales et le serveur ne voyait jamais de
	-- diagonale.
	while (cx ~= x or cy ~= y) and guard < 128 do
		local stepX = 0
		local stepY = 0
		if cx ~= x then
			stepX = x > cx and 1 or -1
		end
		if cy ~= y then
			stepY = y > cy and 1 or -1
		end
		cx += stepX
		cy += stepY
		if self.dragTool == "erase" then
			self:addErase(cx, cy)
		else
			self:addBuild(cx, cy)
		end
		guard += 1
	end

	self.lastCell = { x, y }
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

function InputController:flush()
	if #self.pending > 0 then
		local batch = self.pending
		self.pending = {}
		self.pendingSet = {}
		if self.callbacks.onDraw then
			self.callbacks.onDraw(batch)
		end
	end

	if #self.erasePending > 0 then
		local batch = self.erasePending
		self.erasePending = {}
		self.eraseSet = {}
		if self.callbacks.onErase then
			for _, key in ipairs(batch) do
				self.callbacks.onErase(key)
			end
		end
	end
end

function InputController:endDrag()
	self:flush()
	self.dragging = false
	self.dragTool = nil
	self.lastCell = nil
	self.diagonalIntent = false
end

function InputController:updateGhost()
	if not self.enabled then
		self.ghost.Transparency = 1
		return
	end

	local cell = self.pointer and self:cellAt(self.pointer) or nil
	if not cell then
		self.ghost.Transparency = 1
		return
	end

	self.ghost.CFrame = CFrame.new(Grid.center(self.origin, cell[1], cell[2], 0.44))
	self.ghost.Color = self.tool == "erase" and Config.Colors.Danger or Config.Colors.Teal
	self.ghost.Transparency = 0.5
end

return InputController
