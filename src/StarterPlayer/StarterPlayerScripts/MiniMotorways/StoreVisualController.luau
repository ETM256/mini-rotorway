--[[
	StoreVisualController.luau
	Affichage client des demandes (pins) au-dessus des magasins.

	Le serveur reste autoritaire : il envoie l'état des magasins via
	StoreState. Ce module ne crée que des BillboardGui locaux, anime les pins
	et affiche le compte à rebours de surcharge. Il ne modifie jamais la
	logique de jeu.

	Les mises à jour sont différentielles : un pin n'est créé ou retiré que si
	sa demande (identifiant serveur) apparaît ou est servie. Les GUI ne sont
	jamais reconstruits entre deux snapshots.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local StoreConfig = require(Shared.StoreConfig)

local VISUAL = StoreConfig.Visual
local DEMAND = StoreConfig.Demand
local COLORS = Config.Colors

-- Les pins sont rangés en lignes de PinsPerRow ; la première ligne est au
-- contact du magasin, les suivantes s'empilent vers le haut de l'écran.
local MAX_ROWS = math.ceil(DEMAND.LargeCapacity / VISUAL.PinsPerRow)

local StoreVisualController = {}
StoreVisualController.__index = StoreVisualController

local function paletteFor(colorIndex)
	return Config.HouseColors[colorIndex] or Config.HouseColors[1]
end

local function roundCorners(parent)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = parent
end

local function startTween(instance, duration, style, direction, goal)
	local tween = TweenService:Create(instance, TweenInfo.new(duration, style, direction), goal)
	tween:Play()
	return tween
end

local function cancelTween(tween)
	if tween then
		tween:Cancel()
	end
end

-- Hauteur occupée par n lignes de pins, séparées par PinGap.
local function stackHeight(rows)
	if rows <= 0 then
		return 0
	end
	return rows * VISUAL.PinSize + (rows - 1) * VISUAL.PinGap
end

local function rowOfSlot(slot)
	return math.ceil(slot / VISUAL.PinsPerRow)
end

-- Premier emplacement libre de la grille. Un pin en cours de retrait garde sa
-- place jusqu'à sa destruction, pour qu'un nouveau pin ne se superpose pas à
-- lui. Si la grille est pleine, la place d'un pin qui part est reprise.
local function firstFreeSlot(entry)
	local limit = MAX_ROWS * VISUAL.PinsPerRow
	local leaving = nil
	for slot = 1, limit do
		local owner = entry.slots[slot]
		if not owner then
			return slot
		end
		if owner.removed and not leaving then
			leaving = slot
		end
	end
	return leaving or limit
end

-- Décalage (studs) du centre du BillboardGui vers le haut de l'écran. Le bas
-- des pins est posé à PinLift du bord du bâtiment : la taille du magasin est
-- lue dans la config pour que les pins suivent son évolution.
local function offsetFor(storeType)
	local size = if storeType == "large" then VISUAL.LargeSize else VISUAL.SmallSize
	return size * 0.5 + VISUAL.PinLift
end

-- Fond de l'alerte. Le texte reste anthracite : il est plus lisible que le
-- blanc sur le corail, à petite taille.
local function warningColor(level)
	if level == "critical" then
		return COLORS.Danger
	end
	return COLORS.LobbyOrange
end

-- Valide un magasin reçu du serveur. Un élément partiel ou malformé est
-- ignoré, sans toucher aux pins déjà affichés.
local function normalizeState(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local id, x, y = raw.id, raw.x, raw.y
	if type(id) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end

	local storeType = if raw.storeType == "large" then "large" else "small"
	local capacity = if storeType == "large" then DEMAND.LargeCapacity else DEMAND.SmallCapacity
	if type(raw.capacity) == "number" then
		capacity = math.clamp(math.floor(raw.capacity), 1, DEMAND.LargeCapacity)
	end

	-- nil = le payload ne dit rien sur les demandes : les pins actuels sont gardés.
	local demandIds = nil
	if type(raw.demandIds) == "table" then
		demandIds = {}
		for _, rawId in ipairs(raw.demandIds) do
			if #demandIds >= capacity then
				break
			end
			table.insert(demandIds, tostring(rawId))
		end
	elseif type(raw.demands) == "number" then
		-- Payload sans identifiants : des emplacements stables évitent de
		-- recréer tous les pins quand le compteur change.
		demandIds = {}
		for index = 1, math.clamp(math.floor(raw.demands), 0, capacity) do
			demandIds[index] = "slot_" .. tostring(index)
		end
	end

	local overloadClock = if type(raw.overloadClock) == "number" then raw.overloadClock else 0
	return {
		id = id,
		x = x,
		y = y,
		colorIndex = if type(raw.colorIndex) == "number" then raw.colorIndex else 1,
		storeType = storeType,
		capacity = capacity,
		demandIds = demandIds,
		overloaded = raw.overloaded == true,
		critical = raw.critical == true,
		overloadClock = math.max(0, math.ceil(overloadClock)),
	}
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

function StoreVisualController:cellCenter(x, y)
	return self.origin + Vector3.new((x + 0.5) * self.tile, 0.5, (y + 0.5) * self.tile)
end

-- Crée un pin. Le délai échelonne l'apparition d'une vague de nouvelles demandes.
function StoreVisualController:createPin(entry, demandId, delay)
	local palette = paletteFor(entry.colorIndex)
	local slot = firstFreeSlot(entry)
	local owner = entry.slots[slot]
	if owner and owner.removed then
		-- Grille pleine : le pin qui quitte cette place disparaît tout de suite.
		owner.frame:Destroy()
	end

	local frame = Instance.new("Frame")
	frame.Name = "DemandPin"
	frame.Size = UDim2.fromOffset(VISUAL.PinSize, VISUAL.PinSize)
	frame.BackgroundColor3 = palette.color
	frame.BorderSizePixel = 0
	frame.LayoutOrder = (slot - 1) % VISUAL.PinsPerRow + 1
	roundCorners(frame)

	-- Liseré fin et doux : il sépare le pin du fond sans contour épais.
	local stroke = Instance.new("UIStroke")
	stroke.Color = palette.base
	stroke.Thickness = 1
	stroke.Transparency = VISUAL.PinStrokeTransparency
	stroke.Parent = frame

	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = frame

	local pin = {
		slot = slot,
		frame = frame,
		stroke = stroke,
		scale = scale,
		removed = false,
		appear = nil,
	}
	entry.pins[demandId] = pin
	entry.slots[slot] = pin
	frame.Parent = entry.rows[rowOfSlot(slot)]

	local function appear()
		if not pin.removed then
			pin.appear = startTween(
				scale,
				VISUAL.PinAppearDuration,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out,
				{ Scale = 1 }
			)
		end
	end
	if delay > 0 then
		task.delay(delay, appear)
	else
		appear()
	end
	return pin
end

-- Retire un pin servi : il rétrécit puis disparaît à sa place. L'appelant le
-- sort de entry.pins tout de suite ; sa place reste occupée jusqu'à destruction.
function StoreVisualController:removePin(entry, pin)
	if pin.removed then
		return
	end
	pin.removed = true
	cancelTween(pin.appear)

	local duration = VISUAL.PinRemoveDuration
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(pin.scale, info, { Scale = 0 }):Play()
	TweenService:Create(pin.frame, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(pin.stroke, info, { Transparency = 1 }):Play()

	local frame = pin.frame
	task.delay(duration, function()
		if entry.slots[pin.slot] == pin then
			entry.slots[pin.slot] = nil
		end
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
	anchor.CFrame = CFrame.new(self:cellCenter(state.x, state.y))

	local offset = offsetFor(state.storeType)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DemandPins"
	billboard.Adornee = anchor
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = VISUAL.PinMaxDistance
	billboard.Size = UDim2.fromOffset(VISUAL.PinRowWidth, VISUAL.PinRowHeight)
	-- La caméra est vue de dessus : world -Z correspond à « haut de l'écran ».
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, -offset)

	-- Le bloc des pins est ancré par son bas : il grandit vers le haut, sans
	-- jamais descendre sur le magasin quand une deuxième ligne apparaît.
	local container = Instance.new("Frame")
	container.Name = "Pins"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.Size = UDim2.fromOffset(
		VISUAL.PinsPerRow * VISUAL.PinSize + (VISUAL.PinsPerRow - 1) * VISUAL.PinGap,
		stackHeight(MAX_ROWS)
	)
	container.BackgroundTransparency = 1
	container.Parent = billboard

	local containerScale = Instance.new("UIScale")
	containerScale.Scale = 1
	containerScale.Parent = container

	local stack = Instance.new("UIListLayout")
	stack.FillDirection = Enum.FillDirection.Vertical
	stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stack.VerticalAlignment = Enum.VerticalAlignment.Bottom
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Padding = UDim.new(0, VISUAL.PinGap)
	stack.Parent = container

	local rows = {}
	for row = 1, MAX_ROWS do
		local rowFrame = Instance.new("Frame")
		rowFrame.Name = "Row" .. tostring(row)
		rowFrame.BackgroundTransparency = 1
		rowFrame.BorderSizePixel = 0
		rowFrame.Size = UDim2.new(1, 0, 0, VISUAL.PinSize)
		-- LayoutOrder décroissant : la rangée 1 est la plus basse.
		rowFrame.LayoutOrder = MAX_ROWS + 1 - row

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Padding = UDim.new(0, VISUAL.PinGap)
		rowLayout.Parent = rowFrame

		rowFrame.Parent = container
		rows[row] = rowFrame
	end

	local warning = Instance.new("TextLabel")
	warning.Name = "Overload"
	warning.AnchorPoint = Vector2.new(0.5, 1)
	warning.Position = UDim2.new(0.5, 0, 0.5, -VISUAL.PinWarningGap)
	warning.Size = UDim2.fromOffset(VISUAL.PinWarningWidth, VISUAL.PinWarningHeight)
	warning.BackgroundColor3 = COLORS.LobbyOrange
	warning.BorderSizePixel = 0
	warning.Font = Enum.Font.GothamBold
	warning.Text = ""
	warning.TextColor3 = COLORS.Ink
	warning.TextSize = VISUAL.PinWarningTextSize
	warning.Visible = false
	roundCorners(warning)
	warning.Parent = billboard

	local entry = {
		id = state.id,
		anchor = anchor,
		billboard = billboard,
		containerScale = containerScale,
		rows = rows,
		warning = warning,
		pins = {},
		slots = {},
		colorIndex = state.colorIndex,
		storeType = state.storeType,
		offset = offset,
		offsetTween = nil,
		popTween = nil,
		x = state.x,
		y = state.y,
		warningLevel = nil,
		warningRows = 0,
	}

	billboard.Parent = anchor
	anchor.Parent = self.folder
	return entry
end

function StoreVisualController:updateEntry(entry, state)
	if entry.x ~= state.x or entry.y ~= state.y then
		entry.x = state.x
		entry.y = state.y
		entry.anchor.CFrame = CFrame.new(self:cellCenter(state.x, state.y))
	end

	-- Évolution petite -> grand : le décalage glisse vers la nouvelle silhouette
	-- et le bloc de pins rebondit légèrement. La tween n'est relancée que si la
	-- cible change, sinon chaque snapshot couperait l'animation en cours.
	local offset = offsetFor(state.storeType)
	if entry.offset ~= offset then
		entry.offset = offset
		cancelTween(entry.offsetTween)
		entry.offsetTween = startTween(
			entry.billboard,
			VISUAL.EvolutionDuration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out,
			{ StudsOffsetWorldSpace = Vector3.new(0, 0, -offset) }
		)
	end
	if entry.storeType ~= state.storeType then
		entry.storeType = state.storeType
		cancelTween(entry.popTween)
		entry.containerScale.Scale = VISUAL.PinEvolutionPop
		entry.popTween = startTween(
			entry.containerScale,
			VISUAL.EvolutionDuration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out,
			{ Scale = 1 }
		)
	end

	if entry.colorIndex ~= state.colorIndex then
		entry.colorIndex = state.colorIndex
		local palette = paletteFor(state.colorIndex)
		for _, pin in pairs(entry.pins) do
			pin.frame.BackgroundColor3 = palette.color
			pin.stroke.Color = palette.base
		end
	end

	-- Les identifiants serveur indexent les pins : le client retire exactement
	-- la demande servie, même si plusieurs demandes changent entre deux snapshots.
	local demandIds = state.demandIds
	if demandIds then
		local targetSet = {}
		for _, demandId in ipairs(demandIds) do
			targetSet[demandId] = true
		end
		for demandId, pin in pairs(entry.pins) do
			if not targetSet[demandId] then
				entry.pins[demandId] = nil
				self:removePin(entry, pin)
			end
		end
		local spawned = 0
		for _, demandId in ipairs(demandIds) do
			if not entry.pins[demandId] then
				self:createPin(entry, demandId, spawned * VISUAL.PinStagger)
				spawned += 1
			end
		end
	end

	-- La rangée la plus haute occupée détermine où se place l'alerte.
	local topRow = 0
	for slot in pairs(entry.slots) do
		topRow = math.max(topRow, rowOfSlot(slot))
	end
	local warning = entry.warning
	if topRow ~= entry.warningRows then
		entry.warningRows = topRow
		warning.Position = UDim2.new(
			0.5,
			0,
			0.5,
			-(stackHeight(topRow) + VISUAL.PinWarningGap)
		)
	end

	local level = nil
	if state.critical then
		level = "critical"
	elseif state.overloaded then
		level = "overload"
	end
	if level ~= entry.warningLevel then
		entry.warningLevel = level
		warning.Visible = level ~= nil
		if level then
			warning.BackgroundColor3 = warningColor(level)
		end
	end
	if level then
		local text = if level == "critical" then "!!" else tostring(state.overloadClock) .. "s"
		if warning.Text ~= text then
			warning.Text = text
		end
	end
end

function StoreVisualController:apply(data)
	if not self.folder then
		return
	end
	if not self.origin then
		self.pending = data
		return
	end
	if type(data) ~= "table" or type(data.stores) ~= "table" then
		return
	end

	-- Un magasin listé avec un élément partiel reste affiché tel quel : seul un
	-- magasin absent de la liste disparaît.
	local incoming = {}
	local listed = {}
	for _, raw in ipairs(data.stores) do
		if type(raw) == "table" and type(raw.id) == "number" then
			listed[raw.id] = true
		end
		local state = normalizeState(raw)
		if state then
			incoming[state.id] = state
		end
	end

	for id, entry in pairs(self.stores) do
		if not listed[id] then
			self:disposeEntry(entry)
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

-- Détruit un magasin et ses pins. Les tweens en cours sont annulés avant que
-- leurs instances ne disparaissent.
function StoreVisualController:disposeEntry(entry)
	for _, pin in pairs(entry.pins) do
		pin.removed = true
		cancelTween(pin.appear)
	end
	entry.pins = {}
	cancelTween(entry.offsetTween)
	cancelTween(entry.popTween)
	entry.anchor:Destroy()
end

function StoreVisualController:clear()
	for _, entry in pairs(self.stores) do
		self:disposeEntry(entry)
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
