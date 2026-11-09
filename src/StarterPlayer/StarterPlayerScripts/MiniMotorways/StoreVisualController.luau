--[[
	StoreVisualController.luau
	Affichage client des demandes (pins) au-dessus des magasins.

	Le serveur reste autoritaire : il envoie l'état des magasins via
	StoreState. Ce module ne crée que des BillboardGui locaux, anime les pins
	et affiche le compte à rebours de surcharge. Il ne modifie jamais la
	logique de jeu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local StoreConfig = require(Shared.StoreConfig)

local StoreVisualController = {}
StoreVisualController.__index = StoreVisualController

local function paletteFor(colorIndex)
	return Config.HouseColors[colorIndex] or Config.HouseColors[1]
end

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = parent
	return corner
end

function StoreVisualController.new()
	local self = setmetatable({}, StoreVisualController)
	self.origin = nil
	self.tile = Config.Grid.TileSize
	self.stores = {}
	self.pending = nil

	self.folder = Instance.new("Folder")
	self.folder.Name = "MMStorePins"
	self.folder.Parent = Workspace

	return self
end

function StoreVisualController:setWorld(origin, tile)
	self.origin = origin
	self.tile = tile or Config.Grid.TileSize

	local pending = self.pending
	self.pending = nil
	self:clear()
	if pending then
		self:apply(pending)
	end
end

function StoreVisualController:createPin(entry, colorIndex, demandId)
	local palette = paletteFor(colorIndex)
	local size = StoreConfig.Visual.PinSize

	local frame = Instance.new("Frame")
	frame.Name = "DemandPin"
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = Config.Colors.White
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.LayoutOrder = entry.nextPinOrder
	entry.nextPinOrder += 1
	addCorner(frame, 0.5)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Colors.Ink
	stroke.Thickness = 1
	stroke.Transparency = 0.55
	stroke.Parent = frame

	local inner = Instance.new("Frame")
	inner.Name = "Fill"
	inner.Position = UDim2.fromOffset(2, 2)
	inner.Size = UDim2.new(1, -4, 1, -4)
	inner.BackgroundColor3 = palette.color
	inner.BorderSizePixel = 0
	inner.Parent = frame
	addCorner(inner, 0.5)

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(5, 5)
	dot.BackgroundColor3 = Config.Colors.White
	dot.BorderSizePixel = 0
	dot.Parent = frame
	addCorner(dot, 0.5)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.1
	scale.Parent = frame

	frame.Parent = entry.container
	TweenService:Create(
		scale,
		TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	return {
		demandId = demandId,
		frame = frame,
		inner = inner,
		dot = dot,
		scale = scale,
		colorIndex = colorIndex,
	}
end

function StoreVisualController:removePin(pin)
	local frame = pin.frame
	TweenService:Create(
		pin.scale,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0 }
	):Play()
	TweenService:Create(
		frame,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	):Play()
	TweenService:Create(
		pin.inner,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	):Play()
	TweenService:Create(
		pin.dot,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	):Play()
	task.delay(0.18, function()
		if frame.Parent then
			frame:Destroy()
		end
	end)
end

function StoreVisualController:createEntry(state)
	local anchor = Instance.new("Part")
	anchor.Name = "StorePinAnchor_" .. tostring(state.id)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(Grid.center(self.origin, state.x, state.y, 0.5))
	anchor.Parent = self.folder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DemandPins"
	billboard.Adornee = anchor
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = StoreConfig.Visual.PinMaxDistance
	billboard.Size = UDim2.fromOffset(
		StoreConfig.Visual.PinRowWidth,
		StoreConfig.Visual.PinRowHeight
	)
	-- La caméra est vue de dessus : world -Z correspond à « haut de l'écran ».
	-- On décale donc les pins vers le nord de la carte, au-dessus du magasin.
	billboard.StudsOffsetWorldSpace = Vector3.new(
		0,
		0,
		-(state.storeType == "large" and StoreConfig.Visual.PinHeightLarge
			or StoreConfig.Visual.PinHeightSmall)
	)
	billboard.Parent = anchor

	local container = Instance.new("Frame")
	container.Name = "Pins"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1)
	container.Parent = billboard

	local containerScale = Instance.new("UIScale")
	containerScale.Scale = 1
	containerScale.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, StoreConfig.Visual.PinGap)
	layout.Parent = container

	local warning = Instance.new("TextLabel")
	warning.Name = "Overload"
	warning.AnchorPoint = Vector2.new(0.5, 0)
	warning.Position = UDim2.new(0.5, 0, 0, 1)
	warning.Size = UDim2.fromOffset(
		StoreConfig.Visual.PinWarningWidth,
		StoreConfig.Visual.PinWarningHeight
	)
	warning.BackgroundColor3 = Config.Colors.LobbyOrange
	warning.BorderSizePixel = 0
	warning.Font = Enum.Font.GothamBold
	warning.Text = "!"
	warning.TextColor3 = Config.Colors.White
	warning.TextSize = 12
	warning.Visible = false
	warning.ZIndex = 3
	warning.Parent = billboard
	addCorner(warning, 0.5)

	return {
		id = state.id,
		anchor = anchor,
		billboard = billboard,
		container = container,
		containerScale = containerScale,
		warning = warning,
		pins = {},
		nextPinOrder = 1,
		colorIndex = state.colorIndex,
		storeType = state.storeType,
		x = state.x,
		y = state.y,
	}
end

function StoreVisualController:updateEntry(entry, state)
	local position = Grid.center(self.origin, state.x, state.y, 0.5)
	if entry.x ~= state.x or entry.y ~= state.y then
		entry.x = state.x
		entry.y = state.y
		entry.anchor.CFrame = CFrame.new(position)
	end

	local targetOffset = state.storeType == "large"
			and StoreConfig.Visual.PinHeightLarge
		or StoreConfig.Visual.PinHeightSmall
	if entry.storeType ~= state.storeType then
		TweenService:Create(
			entry.billboard,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ StudsOffsetWorldSpace = Vector3.new(0, 0, -targetOffset) }
		):Play()
		entry.containerScale.Scale = 1.16
		TweenService:Create(
			entry.containerScale,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
		entry.storeType = state.storeType
	else
		entry.billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, -targetOffset)
	end

	if entry.colorIndex ~= state.colorIndex then
		entry.colorIndex = state.colorIndex
		local palette = paletteFor(state.colorIndex)
		for _, pin in pairs(entry.pins) do
			pin.inner.BackgroundColor3 = palette.color
		end
	end

	-- Chaque demande possède un identifiant serveur. Le client supprime donc
	-- exactement le pin qui a été servi, même si plusieurs demandes changent
	-- entre deux snapshots.
	local targetIds = state.demandIds
	if type(targetIds) ~= "table" then
		targetIds = {}
		local fallbackCount = math.clamp(state.demands or 0, 0, state.capacity or 0)
		for index = 1, fallbackCount do
			targetIds[index] = "slot_" .. tostring(index)
		end
	end

	local targetSet = {}
	for _, demandId in ipairs(targetIds) do
		targetSet[tostring(demandId)] = true
	end

	for demandId, pin in pairs(entry.pins) do
		if not targetSet[demandId] then
			entry.pins[demandId] = nil
			self:removePin(pin)
		end
	end
	for _, rawId in ipairs(targetIds) do
		local demandId = tostring(rawId)
		if not entry.pins[demandId] then
			entry.pins[demandId] = self:createPin(entry, state.colorIndex, demandId)
		end
	end

	local overloaded = state.overloaded == true
	local critical = state.critical == true
	entry.warning.Visible = overloaded or critical
	if entry.warning.Visible then
		if critical then
			entry.warning.Text = "!!"
			entry.warning.BackgroundColor3 = Config.Colors.Danger
			entry.warning.TextColor3 = Config.Colors.White
		else
			entry.warning.Text = tostring(math.max(0, math.ceil(state.overloadClock or 0))) .. "s"
			entry.warning.BackgroundColor3 = Config.Colors.LobbyOrange
			entry.warning.TextColor3 = Config.Colors.Ink
		end
	end
end

function StoreVisualController:apply(data)
	if not self.origin then
		self.pending = data
		return
	end
	if type(data) ~= "table" then
		return
	end

	local incoming = {}
	for _, state in ipairs(data.stores or {}) do
		if type(state) == "table" and type(state.id) == "number" then
			incoming[state.id] = state
		end
	end

	for id, entry in pairs(self.stores) do
		if not incoming[id] then
			entry.anchor:Destroy()
			self.stores[id] = nil
		end
	end

	for id, state in pairs(incoming) do
		local entry = self.stores[id]
		if not entry then
			entry = self:createEntry(state)
			self.stores[id] = entry
		end
		self:updateEntry(entry, state)
	end
end

function StoreVisualController:clear()
	for _, entry in pairs(self.stores) do
		if entry.anchor then
			entry.anchor:Destroy()
		end
	end
	self.stores = {}
	self.pending = nil
	if self.folder then
		self.folder:ClearAllChildren()
	end
end

function StoreVisualController:destroy()
	self:clear()
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
end

return StoreVisualController
