--!nocheck
--[[
	instance.luau  (harnais de test)
	Implémentation générique d'Instance en Luau pur, pilotée par api_data :
	une propriété, une méthode ou un événement absent de la classe lève la
	même erreur que Roblox ("X is not a valid member of Y"). Les valeurs
	assignées sont vérifiées (type primitif, type de donnée, EnumItem du bon
	Enum, Instance). Les signaux appellent leurs gestionnaires dans des tâches
	du scheduler : une erreur dans un gestionnaire est capturée et remontée.
]]

local Api = require("./api")
local D = require("./datatypes")
local Scheduler = require("./scheduler")

local I = {}

local Vector3, Vector2, Color3, UDim2, UDim, CFrame = D.Vector3, D.Vector2, D.Color3, D.UDim2, D.UDim, D.CFrame
local Enum = D.Enum

-- ------------------------------------------------------------------ utils --

local function typeOf(v)
	local t = type(v)
	if t == "table" then
		local mt = getmetatable(v)
		if mt and mt.__type then
			return mt.__type
		end
	end
	return t
end
I.typeOf = typeOf

I.stats = { connections = 0, instances = 0 }

function I.resetStats()
	I.stats.connections = 0
	I.stats.instances = 0
end

-- ---------------------------------------------------------------- signals --

local SignalMT = { __type = "RBXScriptSignal" }
local ConnectionMT = { __type = "RBXScriptConnection" }
local connectionMethods = {}

ConnectionMT.__index = connectionMethods

function connectionMethods.Disconnect(conn)
	if conn.Connected then
		rawset(conn, "Connected", false)
		I.stats.connections -= 1
		local signal = rawget(conn, "_signal")
		if signal then
			for i, other in ipairs(signal._list) do
				if other == conn then
					table.remove(signal._list, i)
					break
				end
			end
		end
	end
end
connectionMethods.disconnect = connectionMethods.Disconnect

local function newSignal(name)
	return setmetatable({ _list = {}, _name = name }, SignalMT)
end

local function addConnection(signal, fn, once)
	if type(fn) ~= "function" then
		error("Attempt to connect failed: Passed value is not a function", 3)
	end
	local conn = setmetatable({ Connected = true, _signal = signal, _fn = fn, _once = once }, ConnectionMT)
	table.insert(signal._list, conn)
	I.stats.connections += 1
	return conn
end

SignalMT.__index = {
	Connect = function(signal, fn)
		return addConnection(signal, fn, false)
	end,
	Once = function(signal, fn)
		return addConnection(signal, fn, true)
	end,
	Wait = function(signal)
		local co = coroutine.running()
		if not Scheduler.isManaged(co) then
			error("Signal:Wait() would block the test body forever; call it from a task.spawn thread", 2)
		end
		addConnection(signal, function(...)
			Scheduler.resumeSoon(co, ...)
		end, true)
		return coroutine.yield()
	end,
}
SignalMT.__index.ConnectParallel = SignalMT.__index.Connect
SignalMT.__tostring = function(signal)
	return "Signal " .. tostring(signal._name)
end

local function fire(signal, ...)
	if #signal._list == 0 then
		return
	end
	local snapshot = table.clone(signal._list)
	local n = select("#", ...)
	local args = { ... }
	for _, conn in ipairs(snapshot) do
		if conn.Connected then
			if conn._once then
				conn:Disconnect()
			end
			Scheduler.spawn(conn._fn, table.unpack(args, 1, n))
		end
	end
end
I.fire = fire
I.newSignal = newSignal

-- Un signal autonome (non lié à une Instance), utile pour les mocks.
function I.signal(name)
	return newSignal(name)
end

-- -------------------------------------------------------------- instances --

local states = setmetatable({}, { __mode = "k" })
local InstanceMT = { __type = "Instance" }
I.states = states

local classImpl = {}
-- classImpl[class] = { methods = {}, getters = {}, setters = {}, defaults = {}, init = function(inst, st) end }
function I.implement(className, impl)
	classImpl[className] = impl
end

local function implFor(st, field, key)
	local chain = st.info.chain
	for i = #chain, 1, -1 do
		local impl = classImpl[chain[i]]
		if impl then
			local table_ = impl[field]
			if table_ and table_[key] ~= nil then
				return table_[key]
			end
		end
	end
	return nil
end

local function fullName(st)
	local parts = {}
	local cur = st
	while cur do
		if cur.class ~= "DataModel" then
			table.insert(parts, 1, cur.name)
		end
		cur = cur.parent and states[cur.parent]
	end
	return table.concat(parts, ".")
end

local READ_ONLY = {
	AbsoluteSize = true,
	AbsolutePosition = true,
	AbsoluteRotation = true,
	AbsoluteContentSize = true,
	AbsoluteCanvasSize = true,
	AbsoluteWindowSize = true,
	TextBounds = true,
	TextFits = true,
	UserId = true,
	ViewportSize = true,
	PlaybackState = true,
}

local ENUM_DEFAULTS = {
	Material = "Plastic",
	SurfaceType = "Smooth",
	PartType = "Block",
	Font = "SourceSans",
	TextXAlignment = "Center",
	TextYAlignment = "Center",
	SortOrder = "LayoutOrder",
	FillDirection = "Vertical",
	HorizontalAlignment = "Center",
	VerticalAlignment = "Center",
	ApplyStrokeMode = "Contextual",
	ZIndexBehavior = "Sibling",
	ScaleType = "Stretch",
	AutomaticSize = "None",
	SizeConstraint = "RelativeXY",
	CameraType = "Fixed",
	ScrollingDirection = "XY",
	NormalId = "Front",
	TextTruncate = "None",
	EasingStyle = "Quad",
	EasingDirection = "Out",
	StartCorner = "TopLeft",
	ResamplerMode = "Default",
	ScrollBarInset = "None",
	ElasticBehavior = "WhenScrollable",
	AspectType = "FitWithinMaxSize",
	DominantAxis = "Width",
}

local NAME_DEFAULTS = {
	Transparency = 0,
	BackgroundTransparency = 0,
	ImageTransparency = 0,
	TextTransparency = 0,
	TextStrokeTransparency = 1,
	BorderSizePixel = 1,
	Visible = true,
	Enabled = true,
	ZIndex = 1,
	LayoutOrder = 0,
	TextSize = 14,
	Text = "",
	Rotation = 0,
	Scale = 1,
	Thickness = 1,
	Anchored = false,
	CanCollide = true,
	CanQuery = true,
	CanTouch = true,
	CastShadow = true,
	ClipsDescendants = false,
	Active = false,
	Selectable = false,
	AutoButtonColor = true,
	TextScaled = false,
	TextWrapped = false,
	RichText = false,
	ResetOnSpawn = true,
	DisplayOrder = 0,
	IgnoreGuiInset = false,
	AlwaysOnTop = false,
	MaxDistance = 0,
	LightInfluence = 1,
	Brightness = 1,
	FieldOfView = 70,
	MinTextSize = 1,
	MaxTextSize = 100,
	ScrollBarThickness = 12,
	Reflectance = 0,
	Locked = false,
	Massless = false,
	Value = 0,
	Archivable = true,
	AspectRatio = 1,
}

local function firstEnumItem(enumName)
	local want = ENUM_DEFAULTS[enumName]
	if want then
		return Enum[enumName][want]
	end
	local list = Enum[enumName]:GetEnumItems()
	return list[1]
end

local function defaultFor(st, key, ptype)
	local impl = implFor(st, "defaults", key)
	if impl ~= nil then
		if type(impl) == "function" then
			return impl(st)
		end
		return impl
	end
	if NAME_DEFAULTS[key] ~= nil then
		return NAME_DEFAULTS[key]
	end
	local base = string.gsub(ptype, "%?$", "")
	if base == "number" then
		return 0
	elseif base == "boolean" then
		return false
	elseif base == "string" then
		return ""
	elseif base == "Vector3" then
		if key == "Size" then
			return Vector3.new(4, 1.2, 2)
		end
		return Vector3.zero
	elseif base == "Vector2" then
		return Vector2.zero
	elseif base == "UDim2" then
		if key == "Size" then
			return UDim2.fromOffset(100, 100)
		end
		return UDim2.new()
	elseif base == "UDim" then
		return UDim.new()
	elseif base == "CFrame" then
		return CFrame.identity
	elseif base == "Color3" then
		if key == "BackgroundColor3" then
			return Color3.fromRGB(163, 162, 165)
		elseif key == "Color" and st.info.isA.BasePart then
			return Color3.fromRGB(163, 162, 165)
		end
		return Color3.new(0, 0, 0)
	elseif string.sub(base, 1, 4) == "Enum" then
		local enumName = string.sub(base, 5)
		if Api.data.enums[enumName] then
			return firstEnumItem(enumName)
		end
	elseif base == "NumberSequence" then
		return D.NumberSequence.new(0)
	elseif base == "ColorSequence" then
		return D.ColorSequence.new(Color3.new(1, 1, 1))
	elseif base == "Rect" then
		return D.Rect.new(0, 0, 0, 0)
	elseif base == "NumberRange" then
		return D.NumberRange.new(0, 0)
	elseif base == "Font" then
		return D.Font.fromEnum(Enum.Font.SourceSans)
	end
	return nil
end

local PRIMITIVE = { number = true, boolean = true, string = true }
local DATATYPE = {
	Vector3 = true,
	Vector2 = true,
	Color3 = true,
	UDim = true,
	UDim2 = true,
	CFrame = true,
	Rect = true,
	NumberRange = true,
	NumberSequence = true,
	ColorSequence = true,
	Font = true,
}

-- Vérifie qu'une valeur est acceptable pour le type déclaré. Retourne nil si
-- elle l'est, sinon un message d'erreur.
local function typeProblem(value, ptype)
	local nullable = string.sub(ptype, -1) == "?"
	local base = nullable and string.sub(ptype, 1, -2) or ptype
	if value == nil then
		if PRIMITIVE[base] or DATATYPE[base] or string.sub(base, 1, 4) == "Enum" then
			return base .. " expected, got nil"
		end
		return nil
	end
	local actual = typeOf(value)
	if PRIMITIVE[base] then
		if actual ~= base then
			return base .. " expected, got " .. actual
		end
	elseif DATATYPE[base] then
		if actual ~= base then
			return base .. " expected, got " .. actual
		end
	elseif string.sub(base, 1, 4) == "Enum" and Api.data.enums[string.sub(base, 5)] then
		if not D.isEnumItem(value, string.sub(base, 5)) then
			return "EnumItem " .. string.sub(base, 5) .. " expected, got " .. actual
		end
	elseif Api.info(base) then
		if actual ~= "Instance" then
			return base .. " expected, got " .. actual
		end
		if not states[value].info.isA[base] then
			return base .. " expected, got " .. states[value].class
		end
	end
	return nil
end

local function newState(className, info)
	return {
		class = className,
		info = info,
		name = className,
		parent = nil,
		children = {},
		props = {},
		attrs = {},
		tags = {},
		signals = {},
		waiters = {},
		destroyed = false,
	}
end

local function getSignal(st, key)
	local signal = st.signals[key]
	if not signal then
		signal = newSignal(st.class .. "." .. key)
		st.signals[key] = signal
	end
	return signal
end

local function fireChanged(st, key, value)
	local changed = st.signals.Changed
	if changed then
		if st.info.isA.ValueBase then
			-- ValueBase.Changed ne se déclenche que pour Value, avec la valeur.
			if key == "Value" then
				fire(changed, value)
			end
		else
			fire(changed, key)
		end
	end
	local prop = st.signals["prop:" .. key]
	if prop then
		fire(prop)
	end
end
I.fireChanged = function(inst, key, value)
	fireChanged(states[inst], key, value)
end

local function getProperty(proxy, st, key, ptype)
	local getter = implFor(st, "getters", key)
	if getter then
		return getter(proxy, st)
	end
	local v = st.props[key]
	if v ~= nil then
		return v
	end
	-- game.Workspace, game.Players... sont des propriétés de DataModel qui
	-- désignent le service enfant de cette classe.
	if st.class == "DataModel" then
		local className = string.gsub(ptype, "%?$", "")
		if Api.info(className) then
			return I.methods.FindFirstChildOfClass(proxy, className)
		end
	end
	return defaultFor(st, key, ptype)
end

local function setProperty(proxy, st, key, value, ptype)
	local problem = typeProblem(value, ptype)
	if problem then
		error(string.format("Unable to assign property %s. %s", key, problem), 3)
	end
	local setter = implFor(st, "setters", key)
	if setter then
		setter(proxy, st, value)
		return
	end
	local old = st.props[key]
	st.props[key] = value
	if old ~= value then
		fireChanged(st, key, value)
	end
end

local function findChild(st, name, recursive)
	for _, child in ipairs(st.children) do
		if states[child].name == name then
			return child
		end
	end
	if recursive then
		for _, child in ipairs(st.children) do
			local found = findChild(states[child], name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

local function isDescendantState(st, ancestorSt)
	local cur = st.parent and states[st.parent]
	while cur do
		if cur == ancestorSt then
			return true
		end
		cur = cur.parent and states[cur.parent]
	end
	return false
end

local function fireDescendantAdded(st, descendant)
	local cur = st
	while cur do
		local sig = cur.signals.DescendantAdded
		if sig then
			fire(sig, descendant)
		end
		cur = cur.parent and states[cur.parent]
	end
end

local function fireDescendantRemoving(st, descendant)
	local cur = st
	while cur do
		local sig = cur.signals.DescendantRemoving
		if sig then
			fire(sig, descendant)
		end
		cur = cur.parent and states[cur.parent]
	end
end

local function fireAncestryChanged(st, child, newParent)
	local sig = st.signals.AncestryChanged
	if sig then
		fire(sig, child, newParent)
	end
	for _, c in ipairs(st.children) do
		fireAncestryChanged(states[c], child, newParent)
	end
end

local function setParent(proxy, st, newParent)
	if newParent ~= nil and (type(newParent) ~= "table" or not states[newParent]) then
		error("Unable to assign property Parent. Instance expected, got " .. typeOf(newParent), 3)
	end
	if st.parent == newParent then
		return
	end
	if st.destroyed then
		error(string.format(
			"The Parent property of %s is locked, current parent: NULL, new parent %s",
			st.name,
			newParent and states[newParent].name or "NULL"
		), 3)
	end
	if newParent ~= nil then
		local newSt = states[newParent]
		if newSt == st or isDescendantState(newSt, st) then
			error(string.format(
				"Attempt to set %s as its own parent / would result in a circular reference (%s)",
				st.name,
				newSt.name
			), 3)
		end
	end
	local old = st.parent
	if old then
		local oldSt = states[old]
		for i, child in ipairs(oldSt.children) do
			if child == proxy then
				table.remove(oldSt.children, i)
				break
			end
		end
		fireDescendantRemoving(oldSt, proxy)
		local sig = oldSt.signals.ChildRemoved
		if sig then
			fire(sig, proxy)
		end
	end
	st.parent = newParent
	if newParent then
		local newSt = states[newParent]
		table.insert(newSt.children, proxy)
		local sig = newSt.signals.ChildAdded
		if sig then
			fire(sig, proxy)
		end
		fireDescendantAdded(newSt, proxy)
		local waiting = newSt.waiters[st.name]
		if waiting then
			newSt.waiters[st.name] = nil
			for _, co in ipairs(waiting) do
				Scheduler.resumeSoon(co, proxy)
			end
		end
	end
	fireAncestryChanged(st, proxy, newParent)
	fireChanged(st, "Parent", newParent)
end

local function destroyState(proxy, st)
	if st.destroyed then
		return
	end
	local sig = st.signals.Destroying
	if sig then
		fire(sig)
	end
	for _, child in ipairs(table.clone(st.children)) do
		destroyState(child, states[child])
	end
	if st.parent then
		setParent(proxy, st, nil)
	end
	st.destroyed = true
	-- Détruire une instance déconnecte ses propres événements.
	for _, signal in pairs(st.signals) do
		for _, conn in ipairs(table.clone(signal._list)) do
			conn:Disconnect()
		end
	end
	I.stats.instances -= 1
end

local function collectDescendants(st, out)
	for _, child in ipairs(st.children) do
		table.insert(out, child)
		collectDescendants(states[child], out)
	end
	return out
end

local function checkString(value, argName, level)
	if type(value) ~= "string" then
		error(string.format("invalid argument %s (string expected, got %s)", argName, typeOf(value)), level or 3)
	end
end

-- ------------------------------------------------------------ base methods --

local M = {}

function M.IsA(self, className)
	checkString(className, "#1")
	return states[self].info.isA[className] == true
end
M.isA = M.IsA

function M.GetChildren(self)
	return table.clone(states[self].children)
end
M.children = M.GetChildren
M.getChildren = M.GetChildren

function M.GetDescendants(self)
	return collectDescendants(states[self], {})
end

function M.FindFirstChild(self, name, recursive)
	checkString(name, "#2")
	return findChild(states[self], name, recursive == true)
end
M.findFirstChild = M.FindFirstChild

function M.FindFirstChildOfClass(self, className)
	for _, child in ipairs(states[self].children) do
		if states[child].class == className then
			return child
		end
	end
	return nil
end

function M.FindFirstChildWhichIsA(self, className, recursive)
	for _, child in ipairs(states[self].children) do
		if states[child].info.isA[className] then
			return child
		end
	end
	if recursive then
		for _, child in ipairs(states[self].children) do
			local found = M.FindFirstChildWhichIsA(child, className, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function M.FindFirstDescendant(self, name)
	return findChild(states[self], name, true)
end

function M.FindFirstAncestor(self, name)
	local cur = states[self].parent
	while cur do
		if states[cur].name == name then
			return cur
		end
		cur = states[cur].parent
	end
	return nil
end

function M.FindFirstAncestorOfClass(self, className)
	local cur = states[self].parent
	while cur do
		if states[cur].class == className then
			return cur
		end
		cur = states[cur].parent
	end
	return nil
end

function M.FindFirstAncestorWhichIsA(self, className)
	local cur = states[self].parent
	while cur do
		if states[cur].info.isA[className] then
			return cur
		end
		cur = states[cur].parent
	end
	return nil
end

function M.WaitForChild(self, name, timeout)
	checkString(name, "#2")
	local st = states[self]
	local found = findChild(st, name, false)
	if found then
		return found
	end
	local co = coroutine.running()
	if Scheduler.isManaged(co) then
		st.waiters[name] = st.waiters[name] or {}
		table.insert(st.waiters[name], co)
		return coroutine.yield()
	end
	if timeout then
		return nil
	end
	error(string.format(
		"Infinite yield possible on '%s:WaitForChild(\"%s\")' (child does not exist in the headless test world)",
		fullName(st),
		name
	), 2)
end

function M.IsDescendantOf(self, ancestor)
	return ancestor ~= nil and isDescendantState(states[self], states[ancestor])
end
M.isDescendantOf = M.IsDescendantOf

function M.IsAncestorOf(self, descendant)
	return isDescendantState(states[descendant], states[self])
end

function M.GetFullName(self)
	return fullName(states[self])
end

function M.Destroy(self)
	destroyState(self, states[self])
end
M.destroy = M.Destroy
M.Remove = M.Destroy

function M.ClearAllChildren(self)
	for _, child in ipairs(table.clone(states[self].children)) do
		destroyState(child, states[child])
	end
end

function M.SetAttribute(self, name, value)
	checkString(name, "#2")
	local st = states[self]
	local old = st.attrs[name]
	st.attrs[name] = value
	if old ~= value then
		local sig = st.signals.AttributeChanged
		if sig then
			fire(sig, name)
		end
		local nameSig = st.signals["attr:" .. name]
		if nameSig then
			fire(nameSig)
		end
	end
end

function M.GetAttribute(self, name)
	checkString(name, "#2")
	return states[self].attrs[name]
end

function M.GetAttributes(self)
	return table.clone(states[self].attrs)
end

function M.GetAttributeChangedSignal(self, name)
	checkString(name, "#2")
	return getSignal(states[self], "attr:" .. name)
end

function M.GetPropertyChangedSignal(self, name)
	checkString(name, "#2")
	local st = states[self]
	if not st.info.props[name] and name ~= "Name" and name ~= "Parent" then
		error(string.format("%s is not a valid property name of %s", name, st.class), 2)
	end
	return getSignal(st, "prop:" .. name)
end

function M.AddTag(self, tag)
	states[self].tags[tag] = true
end

function M.RemoveTag(self, tag)
	states[self].tags[tag] = nil
end

function M.HasTag(self, tag)
	return states[self].tags[tag] == true
end

function M.GetTags(self)
	local list = {}
	for tag in pairs(states[self].tags) do
		table.insert(list, tag)
	end
	table.sort(list)
	return list
end

function M.GetDebugId(self)
	return "mock:" .. fullName(states[self])
end

local create

local function cloneState(st, map)
	local copy = create(st.class, { internal = true })
	local cst = states[copy]
	cst.name = st.name
	for key, value in pairs(st.props) do
		cst.props[key] = value
	end
	for key, value in pairs(st.attrs) do
		cst.attrs[key] = value
	end
	for tag in pairs(st.tags) do
		cst.tags[tag] = true
	end
	cst.moduleInfo = st.moduleInfo
	map[st.proxy] = copy
	for _, child in ipairs(st.children) do
		local childSt = states[child]
		if childSt.props.Archivable ~= false then
			local childCopy = cloneState(childSt, map)
			setParent(childCopy, states[childCopy], copy)
		end
	end
	return copy
end

function M.Clone(self)
	local st = states[self]
	if st.props.Archivable == false then
		return nil
	end
	local map = {}
	local copy = cloneState(st, map)
	-- Les propriétés qui pointent vers un descendant (PrimaryPart...) doivent
	-- pointer vers la copie.
	for _, newInst in pairs(map) do
		local nst = states[newInst]
		for key, value in pairs(nst.props) do
			if type(value) == "table" and map[value] then
				nst.props[key] = map[value]
			end
		end
	end
	return copy
end
M.clone = M.Clone

I.methods = M

-- ------------------------------------------------------------------- proxy --

local function memberError(st, key)
	return string.format('%s is not a valid member of %s "%s"', tostring(key), st.class, fullName(st))
end

InstanceMT.__index = function(self, key)
	local st = states[self]
	if key == "Parent" then
		return st.parent
	elseif key == "Name" then
		return st.name
	elseif key == "ClassName" then
		return st.class
	end
	if type(key) ~= "string" then
		error(memberError(st, key), 2)
	end
	local info = st.info
	local ptype = info.props[key]
	if ptype then
		return getProperty(self, st, key, ptype)
	end
	if info.events[key] then
		return getSignal(st, key)
	end
	if info.methods[key] then
		local impl = implFor(st, "methods", key)
		if impl then
			return impl
		end
		local base = M[key]
		if base then
			return base
		end
		return function()
			error(string.format("[test mock] %s:%s is a valid Roblox method but is not implemented by the harness", st.class, key), 2)
		end
	end
	local child = findChild(st, key, false)
	if child then
		return child
	end
	error(memberError(st, key), 2)
end

InstanceMT.__newindex = function(self, key, value)
	local st = states[self]
	if key == "Parent" then
		setParent(self, st, value)
		return
	elseif key == "Name" then
		checkString(value, "Name", 2)
		if st.name ~= value then
			st.name = value
			fireChanged(st, "Name", value)
		end
		return
	elseif key == "ClassName" then
		error("Unable to assign property ClassName. Property is read only", 2)
	end
	local ptype = type(key) == "string" and st.info.props[key]
	if not ptype then
		if type(key) == "string" and (st.info.methods[key] or st.info.events[key]) then
			error(string.format("Unable to assign property %s. Property is read only", key), 2)
		end
		error(memberError(st, key), 2)
	end
	if READ_ONLY[key] then
		error(string.format("Unable to assign property %s. Property is read only", key), 2)
	end
	setProperty(self, st, key, value, ptype)
end

InstanceMT.__tostring = function(self)
	return states[self].name
end

create = function(className, opts)
	local info = Api.info(className)
	if not info then
		error(string.format("Unable to create an Instance of type \"%s\"", tostring(className)), 3)
	end
	local st = newState(className, info)
	local proxy = setmetatable({}, InstanceMT)
	st.proxy = proxy
	states[proxy] = st
	I.stats.instances += 1
	for _, name in ipairs(info.chain) do
		local impl = classImpl[name]
		if impl and impl.init then
			impl.init(proxy, st, opts)
		end
	end
	return proxy
end
I.create = create

local InstanceLib = {}
function InstanceLib.new(className, parent)
	if type(className) ~= "string" then
		error("invalid argument #1 to 'new' (string expected, got " .. typeOf(className) .. ")", 2)
	end
	if not Api.creatable(className) then
		error(string.format("Unable to create an Instance of type \"%s\"", className), 2)
	end
	local inst = create(className)
	if parent ~= nil then
		setParent(inst, states[inst], parent)
	end
	return inst
end
I.Instance = InstanceLib

-- Accès aux détails internes, pour les classes qui étendent l'Instance.
I.getState = function(inst)
	return states[inst]
end
I.getSignal = function(inst, key)
	return getSignal(states[inst], key)
end
I.setParent = function(inst, parent)
	setParent(inst, states[inst], parent)
end
I.destroy = function(inst)
	destroyState(inst, states[inst])
end
I.descendants = function(inst)
	return collectDescendants(states[inst], {})
end
I.fullName = function(inst)
	return fullName(states[inst])
end
I.isInstance = function(v)
	return type(v) == "table" and states[v] ~= nil
end
I.typeProblem = typeProblem
I.clearChildrenRaw = function(inst)
	states[inst].children = {}
end
I.setRawProp = function(inst, key, value)
	states[inst].props[key] = value
end
I.getRawProp = function(inst, key)
	return states[inst].props[key]
end

return I
