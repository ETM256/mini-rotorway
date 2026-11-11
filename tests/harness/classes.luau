--!nocheck
--[[
	classes.luau  (harnais de test)
	Comportements propres à certaines classes Roblox : pièces (CFrame/Position),
	modèles (PivotTo, ScaleTo), interface (AbsoluteSize), caméra (rayons),
	services (Players, RunService, UserInputService, TweenService, TextService,
	StarterGui, DataStoreService, DataModel) et RemoteEvent.
	Tout l'état partagé vit dans `W` (reset par H.reset).
]]

local I = require("./instance")
local D = require("./datatypes")
local Scheduler = require("./scheduler")
local Api = require("./api")

local Vector3, Vector2, CFrame = D.Vector3, D.Vector2, D.CFrame
local Enum = D.Enum
local typeOf = I.typeOf

local W = {}

function W.reset()
	W.viewport = Vector2.new(1920, 1080)
	W.localPlayer = nil
	W.isServer = true
	W.mouse = Vector2.new(0, 0)
	W.keysDown = {}
	W.buttonsDown = {}
	W.remoteLog = {}
	W.coreGui = {}
	W.core = {}
	W.dataStores = {}
	W.dataStoreError = nil
	W.bindToClose = {}
	W.renderSteps = {}
	W.deliverToClient = true
	W.services = {}
end
W.reset()

local states = I.states

-- ----------------------------------------------------------------- pièces --

local IDENTITY = CFrame.identity

local function partCFrame(st)
	return st.props.CFrame or IDENTITY
end

local function setPartCFrame(proxy, st, cf)
	st.props.CFrame = cf
	I.fireChanged(proxy, "CFrame")
	I.fireChanged(proxy, "Position")
end

I.implement("BasePart", {
	getters = {
		Position = function(_, st)
			return partCFrame(st).Position
		end,
		Orientation = function(_, st)
			local rx, ry, rz = partCFrame(st):ToOrientation()
			return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
		end,
		Rotation = function(_, st)
			local rx, ry, rz = partCFrame(st):ToOrientation()
			return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
		end,
	},
	setters = {
		CFrame = function(proxy, st, value)
			setPartCFrame(proxy, st, value)
		end,
		Position = function(proxy, st, value)
			setPartCFrame(proxy, st, CFrame.new(value) * partCFrame(st).Rotation)
		end,
		Orientation = function(proxy, st, value)
			local pos = partCFrame(st).Position
			setPartCFrame(proxy, st, CFrame.new(pos) * CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z)))
		end,
	},
})

-- ----------------------------------------------------------------- modèles --

local function partsOf(proxy)
	local parts = {}
	for _, d in ipairs(I.descendants(proxy)) do
		if states[d].info.isA.BasePart then
			table.insert(parts, d)
		end
	end
	return parts
end

local function boundingBox(parts)
	if #parts == 0 then
		return CFrame.identity, Vector3.zero
	end
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in ipairs(parts) do
		local cf, size = part.CFrame, part.Size
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local corner = cf * Vector3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2)
					minV = minV:Min(corner)
					maxV = maxV:Max(corner)
				end
			end
		end
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end

local function modelPivot(proxy, st)
	local primary = st.props.PrimaryPart
	if primary then
		return primary.CFrame
	end
	if st.props.WorldPivot then
		return st.props.WorldPivot
	end
	local cf = boundingBox(partsOf(proxy))
	return cf
end

local function pivotTo(proxy, target)
	local st = states[proxy]
	if st.info.isA.Model then
		local pivot = modelPivot(proxy, st)
		local delta = target * pivot:Inverse()
		for _, part in ipairs(partsOf(proxy)) do
			part.CFrame = delta * part.CFrame
		end
		if not st.props.PrimaryPart then
			st.props.WorldPivot = target
		end
	elseif st.info.isA.BasePart then
		proxy.CFrame = target
	else
		error("PivotTo is not supported for " .. st.class .. " in the test mock", 3)
	end
end

I.implement("PVInstance", {
	methods = {
		GetPivot = function(self)
			local st = states[self]
			if st.info.isA.Model then
				return modelPivot(self, st)
			end
			return self.CFrame
		end,
		PivotTo = function(self, target)
			if typeOf(target) ~= "CFrame" then
				error("invalid argument #2 (CFrame expected, got " .. typeOf(target) .. ")", 2)
			end
			pivotTo(self, target)
		end,
	},
})

I.implement("Model", {
	methods = {
		ScaleTo = function(self, scale)
			if type(scale) ~= "number" or scale <= 0 then
				error("Model:ScaleTo requires a number > 0 (got " .. tostring(scale) .. ")", 2)
			end
			local st = states[self]
			local old = st.scale or 1
			local ratio = scale / old
			if ratio ~= 1 then
				local pivot = modelPivot(self, st)
				local p0 = pivot.Position
				for _, part in ipairs(partsOf(self)) do
					local cf = part.CFrame
					local pos = p0 + (cf.Position - p0) * ratio
					part.Size = part.Size * ratio
					part.CFrame = CFrame.new(pos) * cf.Rotation
				end
			end
			st.scale = scale
		end,
		GetScale = function(self)
			return states[self].scale or 1
		end,
		GetBoundingBox = function(self)
			return boundingBox(partsOf(self))
		end,
		GetExtentsSize = function(self)
			local _, size = boundingBox(partsOf(self))
			return size
		end,
		TranslateBy = function(self, delta)
			pivotTo(self, CFrame.new(delta) * modelPivot(self, states[self]))
		end,
		MoveTo = function(self, position)
			local pivot = modelPivot(self, states[self])
			pivotTo(self, CFrame.new(position) * pivot.Rotation)
		end,
	},
})

-- ---------------------------------------------------------------- interface --

local function parentViewport(proxy, st)
	local parent = st.parent
	if parent and states[parent].info.props.AbsoluteSize then
		return parent.AbsoluteSize
	end
	return W.viewport
end

I.implement("GuiBase2d", {
	getters = {
		AbsoluteSize = function(proxy, st)
			if st.info.isA.LayerCollector then
				if st.class == "ScreenGui" then
					return W.viewport
				end
				local size = proxy.Size
				return Vector2.new(size.X.Offset, size.Y.Offset)
			end
			local container = parentViewport(proxy, st)
			local size = st.props.Size or D.UDim2.fromOffset(100, 100)
			local w = container.X * size.X.Scale + size.X.Offset
			local h = container.Y * size.Y.Scale + size.Y.Offset
			local scale = proxy:FindFirstChildOfClass("UIScale")
			if scale then
				w *= scale.Scale
				h *= scale.Scale
			end
			return Vector2.new(w, h)
		end,
		-- Position = parent + Position(échelle, décalage) - AnchorPoint * taille.
		-- Les mises en page automatiques (UIListLayout...) ne sont pas simulées :
		-- voir H.isLayoutManaged pour savoir quand cette valeur n'est qu'indicative.
		AbsolutePosition = function(proxy, st)
			if st.info.isA.LayerCollector then
				return Vector2.zero
			end
			local parent = st.parent
			local parentPos, parentSize = Vector2.zero, W.viewport
			if parent and states[parent].info.props.AbsoluteSize then
				parentPos, parentSize = parent.AbsolutePosition, parent.AbsoluteSize
			end
			local position = st.props.Position or D.UDim2.new()
			local anchor = st.props.AnchorPoint or Vector2.zero
			local size = proxy.AbsoluteSize
			return Vector2.new(
				parentPos.X + parentSize.X * position.X.Scale + position.X.Offset - anchor.X * size.X,
				parentPos.Y + parentSize.Y * position.Y.Scale + position.Y.Offset - anchor.Y * size.Y
			)
		end,
		AbsoluteRotation = function()
			return 0
		end,
	},
})

I.implement("GuiLabel", { defaults = { Text = "Label" } })
I.implement("TextLabel", {
	getters = {
		TextBounds = function(_, st)
			local text = st.props.Text or "Label"
			local size = st.props.TextSize or 14
			return Vector2.new(#text * size * 0.5, size)
		end,
	},
})
I.implement("TextButton", {
	getters = {
		TextBounds = function(_, st)
			local text = st.props.Text or "Button"
			local size = st.props.TextSize or 14
			return Vector2.new(#text * size * 0.5, size)
		end,
	},
	defaults = { Text = "Button" },
})
I.implement("UIListLayout", {
	getters = {
		AbsoluteContentSize = function()
			return Vector2.zero
		end,
	},
})
I.implement("UICorner", { defaults = { CornerRadius = function()
	return D.UDim.new(0, 8)
end } })

-- ------------------------------------------------------------------ caméra --

local function cameraBasis(camera)
	local fov = math.rad(camera.FieldOfView)
	local view = W.viewport
	return camera.CFrame, math.tan(fov / 2), view.X / view.Y, view
end

I.implement("Camera", {
	defaults = { FieldOfView = 70 },
	getters = {
		ViewportSize = function()
			return W.viewport
		end,
	},
	methods = {
		ViewportPointToRay = function(self, x, y)
			local cf, tanHalf, aspect, view = cameraBasis(self)
			local ndcX = (x / view.X) * 2 - 1
			local ndcY = 1 - (y / view.Y) * 2
			local direction = cf:VectorToWorldSpace(Vector3.new(ndcX * tanHalf * aspect, ndcY * tanHalf, -1)).Unit
			return D.Ray.new(cf.Position, direction)
		end,
		WorldToViewportPoint = function(self, position)
			local cf, tanHalf, aspect, view = cameraBasis(self)
			local localPos = cf:PointToObjectSpace(position)
			local depth = -localPos.Z
			if depth <= 1e-6 then
				return Vector3.new(0, 0, depth), false
			end
			local ndcX = localPos.X / (depth * tanHalf * aspect)
			local ndcY = localPos.Y / (depth * tanHalf)
			local onScreen = math.abs(ndcX) <= 1 and math.abs(ndcY) <= 1
			return Vector3.new((ndcX * 0.5 + 0.5) * view.X, (0.5 - ndcY * 0.5) * view.Y, depth), onScreen
		end,
		-- Pas d'inset de barre supérieure dans ce mock : Screen == Viewport.
		ScreenPointToRay = function(self, x, y)
			return self:ViewportPointToRay(x, y)
		end,
		WorldToScreenPoint = function(self, position)
			return self:WorldToViewportPoint(position)
		end,
	},
})
I.implement("Workspace", {
	getters = {
		CurrentCamera = function(proxy, st)
			local cam = st.props.CurrentCamera
			if not cam or states[cam].destroyed then
				cam = I.create("Camera", { internal = true })
				cam.Name = "Camera"
				I.setParent(cam, proxy)
				st.props.CurrentCamera = cam
			end
			return cam
		end,
	},
	setters = {
		CurrentCamera = function(_, st, value)
			st.props.CurrentCamera = value
		end,
	},
})

-- --------------------------------------------------------------- remotes --

local function serialize(value, depth)
	local t = typeOf(value)
	if t == "function" or t == "thread" or t == "userdata" then
		error("Attempt to send a " .. t .. " through a RemoteEvent (not serializable)", 4)
	end
	if t == "table" then
		if depth > 20 then
			error("RemoteEvent payload too deeply nested", 4)
		end
		local copy = {}
		for k, v in pairs(value) do
			if type(k) ~= "string" and type(k) ~= "number" then
				error("RemoteEvent payload has a table key of type " .. typeOf(k), 4)
			end
			copy[k] = serialize(v, depth + 1)
		end
		return copy
	end
	return value
end

local function packArgs(...)
	local n = select("#", ...)
	local args = { ... }
	for i = 1, n do
		args[i] = serialize(args[i], 0)
	end
	return table.pack(table.unpack(args, 1, n))
end

local function logRemote(entry)
	table.insert(W.remoteLog, entry)
end

local remoteImpl = {
	methods = {
		FireServer = function(self, ...)
			local args = packArgs(...)
			local player = W.localPlayer
			logRemote({ dir = "toServer", remote = self.Name, player = player, args = args })
			if not player then
				error("RemoteEvent:FireServer called but no LocalPlayer exists in the test world (call H.asClient())", 2)
			end
			I.fire(I.getSignal(self, "OnServerEvent"), player, table.unpack(args, 1, args.n))
		end,
		FireClient = function(self, player, ...)
			if typeOf(player) ~= "Instance" or not states[player].info.isA.Player then
				error("FireClient: invalid argument #2 (Player expected, got " .. typeOf(player) .. ")", 2)
			end
			local args = packArgs(...)
			logRemote({ dir = "toClient", remote = self.Name, player = player, args = args })
			if W.deliverToClient and player == W.localPlayer then
				I.fire(I.getSignal(self, "OnClientEvent"), table.unpack(args, 1, args.n))
			end
		end,
		FireAllClients = function(self, ...)
			local args = packArgs(...)
			logRemote({ dir = "toClient", remote = self.Name, player = "all", args = args })
			if W.deliverToClient and W.localPlayer then
				I.fire(I.getSignal(self, "OnClientEvent"), table.unpack(args, 1, args.n))
			end
		end,
	},
}
I.implement("BaseRemoteEvent", remoteImpl)

-- ---------------------------------------------------------------- joueurs --

I.implement("Player", {
	init = function(proxy, _, opts)
		if opts and opts.internal then
			local gui = I.create("PlayerGui", { internal = true })
			gui.Name = "PlayerGui"
			I.setParent(gui, proxy)
		end
	end,
	defaults = { UserId = 1, DisplayName = "" },
})

I.implement("Players", {
	getters = {
		LocalPlayer = function()
			return W.localPlayer
		end,
	},
	methods = {
		GetPlayers = function(self)
			local list = {}
			for _, child in ipairs(self:GetChildren()) do
				if states[child].info.isA.Player then
					table.insert(list, child)
				end
			end
			return list
		end,
		GetPlayerByUserId = function(self, userId)
			for _, child in ipairs(self:GetChildren()) do
				if states[child].info.isA.Player and child.UserId == userId then
					return child
				end
			end
			return nil
		end,
	},
})

-- --------------------------------------------------------------- services --

I.implement("RunService", {
	methods = {
		IsServer = function()
			return W.isServer
		end,
		IsClient = function()
			return not W.isServer
		end,
		IsStudio = function()
			return false
		end,
		IsRunning = function()
			return true
		end,
		IsRunMode = function()
			return true
		end,
		IsEdit = function()
			return false
		end,
		BindToRenderStep = function(_, name, priority, fn)
			if type(name) ~= "string" or type(fn) ~= "function" then
				error("BindToRenderStep: invalid arguments", 2)
			end
			W.renderSteps[name] = { priority = tonumber(priority) or 0, fn = fn }
		end,
		UnbindFromRenderStep = function(_, name)
			W.renderSteps[name] = nil
		end,
	},
})

I.implement("UserInputService", {
	defaults = {
		TouchEnabled = false,
		KeyboardEnabled = true,
		MouseEnabled = true,
		GamepadEnabled = false,
	},
	methods = {
		GetMouseLocation = function()
			return W.mouse
		end,
		IsKeyDown = function(_, keyCode)
			if typeOf(keyCode) ~= "EnumItem" then
				error("IsKeyDown: invalid argument #2 (KeyCode expected, got " .. typeOf(keyCode) .. ")", 2)
			end
			return W.keysDown[keyCode.Name] == true
		end,
		IsMouseButtonPressed = function(_, button)
			if typeOf(button) ~= "EnumItem" then
				error("IsMouseButtonPressed: invalid argument (UserInputType expected)", 2)
			end
			return W.buttonsDown[button.Name] == true
		end,
		GetFocusedTextBox = function()
			return nil
		end,
	},
})

I.implement("TextService", {
	methods = {
		GetTextSize = function(_, text, fontSize, font, frameSize)
			if type(text) ~= "string" then
				error("GetTextSize: invalid argument #2 (string expected, got " .. typeOf(text) .. ")", 2)
			end
			local width = #text * fontSize * 0.5
			local height = fontSize
			if frameSize and frameSize.X > 0 and frameSize.X < math.huge and width > frameSize.X then
				height = math.ceil(width / frameSize.X) * fontSize
				width = frameSize.X
			end
			return Vector2.new(width, height)
		end,
	},
})

I.implement("StarterGui", {
	methods = {
		SetCoreGuiEnabled = function(_, coreGuiType, enabled)
			if typeOf(coreGuiType) ~= "EnumItem" or coreGuiType.EnumType.Name ~= "CoreGuiType" then
				error("SetCoreGuiEnabled: invalid argument #2 (CoreGuiType expected, got " .. typeOf(coreGuiType) .. ")", 2)
			end
			if type(enabled) ~= "boolean" then
				error("SetCoreGuiEnabled: invalid argument #3 (boolean expected, got " .. typeOf(enabled) .. ")", 2)
			end
			W.coreGui[coreGuiType.Name] = enabled
		end,
		GetCoreGuiEnabled = function(_, coreGuiType)
			local value = W.coreGui[coreGuiType.Name]
			return value == nil and true or value
		end,
		SetCore = function(_, name, value)
			W.core[name] = value
		end,
		GetCore = function(_, name)
			return W.core[name]
		end,
	},
})

local function deepCopy(value)
	if type(value) == "table" and getmetatable(value) == nil then
		local copy = {}
		for k, v in pairs(value) do
			copy[k] = deepCopy(v)
		end
		return copy
	end
	return value
end

local DataStoreMT = { __type = "GlobalDataStore" }
local dataStoreMethods = {}
DataStoreMT.__index = dataStoreMethods

local function checkStore()
	if W.dataStoreError then
		error(W.dataStoreError, 3)
	end
end
function dataStoreMethods.GetAsync(store, key)
	checkStore()
	return deepCopy(store._data[key])
end
function dataStoreMethods.SetAsync(store, key, value)
	checkStore()
	store._data[key] = deepCopy(value)
	return "version"
end
function dataStoreMethods.UpdateAsync(store, key, fn)
	checkStore()
	local result = fn(deepCopy(store._data[key]))
	if result ~= nil then
		store._data[key] = deepCopy(result)
	end
	return deepCopy(store._data[key])
end
function dataStoreMethods.RemoveAsync(store, key)
	checkStore()
	local old = store._data[key]
	store._data[key] = nil
	return old
end

I.implement("DataStoreService", {
	methods = {
		GetDataStore = function(_, name)
			if type(name) ~= "string" then
				error("GetDataStore: invalid argument #2 (string expected)", 2)
			end
			if not W.dataStores[name] then
				W.dataStores[name] = setmetatable({ _data = {}, Name = name }, DataStoreMT)
			end
			return W.dataStores[name]
		end,
	},
})

-- --------------------------------------------------------------- tweens --

local TweenMT = { __type = "Tween" }
local tweenMethods = {}
TweenMT.__index = tweenMethods

local function tweenDuration(info)
	local cycles = (info.RepeatCount < 0) and 1 or (info.RepeatCount + 1)
	return info.DelayTime + info.Time * cycles * (info.Reverses and 2 or 1)
end

function tweenMethods.Play(tween)
	if tween._active then
		return
	end
	tween._active = true
	tween.PlaybackState = Enum.PlaybackState.Playing
	local token = {}
	tween._token = token
	Scheduler.delay(tweenDuration(tween.TweenInfo), function()
		if tween._token ~= token then
			return
		end
		tween._active = false
		tween.PlaybackState = Enum.PlaybackState.Completed
		if not tween.TweenInfo.Reverses or tween.TweenInfo.RepeatCount >= 0 then
			for key, value in pairs(tween._goal) do
				tween.Instance[key] = value
			end
		end
		I.fire(tween.Completed, Enum.PlaybackState.Completed)
	end)
end
function tweenMethods.Cancel(tween)
	if tween._active then
		tween._active = false
		tween._token = nil
		tween.PlaybackState = Enum.PlaybackState.Cancelled
		I.fire(tween.Completed, Enum.PlaybackState.Cancelled)
	end
end
function tweenMethods.Pause(tween)
	tween._active = false
	tween._token = nil
	tween.PlaybackState = Enum.PlaybackState.Paused
end
function tweenMethods.Destroy(tween)
	tween._token = nil
	tween._active = false
end

I.implement("TweenService", {
	methods = {
		Create = function(_, instance, info, goal)
			if typeOf(instance) ~= "Instance" then
				error("TweenService:Create: invalid argument #2 (Instance expected, got " .. typeOf(instance) .. ")", 2)
			end
			if typeOf(info) ~= "TweenInfo" then
				error("TweenService:Create: invalid argument #3 (TweenInfo expected, got " .. typeOf(info) .. ")", 2)
			end
			if type(goal) ~= "table" then
				error("TweenService:Create: invalid argument #4 (table expected, got " .. typeOf(goal) .. ")", 2)
			end
			local st = states[instance]
			for key, value in pairs(goal) do
				local ptype = st.info.props[key]
				if not ptype then
					error(string.format("TweenService:Create: %s is not a valid property of %s", tostring(key), st.class), 2)
				end
				local problem = I.typeProblem(value, ptype)
				if problem then
					error(string.format("TweenService:Create: property %s: %s", key, problem), 2)
				end
			end
			return setmetatable({
				Instance = instance,
				TweenInfo = info,
				PlaybackState = Enum.PlaybackState.Begin,
				Completed = I.signal("Tween.Completed"),
				_goal = table.clone(goal),
				_active = false,
			}, TweenMT)
		end,
	},
})

-- --------------------------------------------------------------- DataModel --

I.implement("DataModel", {
	methods = {
		GetService = function(self, name)
			if type(name) ~= "string" then
				error("GetService: invalid argument #2 (string expected, got " .. typeOf(name) .. ")", 2)
			end
			local found = self:FindFirstChildOfClass(name)
			if found then
				return found
			end
			if not Api.info(name) then
				error(string.format("'%s' is not a valid Service name", name), 2)
			end
			local service = I.create(name, { internal = true })
			I.setParent(service, self)
			return service
		end,
		FindService = function(self, name)
			return self:FindFirstChildOfClass(name)
		end,
		BindToClose = function(_, fn)
			table.insert(W.bindToClose, fn)
		end,
		IsLoaded = function()
			return true
		end,
	},
	defaults = { PlaceId = 0, GameId = 0, JobId = "test" },
})

I.implement("ModuleScript", {
	getters = {
		Source = function(_, st)
			return st.moduleInfo and st.moduleInfo.source or ""
		end,
	},
})

return W
