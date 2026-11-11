--!nocheck
--[[
	datatypes.luau  (harnais de test)
	Types de valeur Roblox en Luau pur : Vector2/3, Color3, UDim/UDim2, CFrame,
	TweenInfo, NumberSequence, ColorSequence, Rect, Random, Font, Enum strict.
	Les valeurs sont immuables (table gelée), comme dans Roblox : écrire
	`v.X = 1` lève une erreur.
]]

local D = {}

local api = require("./api")

local function fmt(n)
	if n == math.floor(n) then
		return string.format("%d", n)
	end
	return string.format("%.4g", n)
end

local function lazyIndex(typeName, methods, props)
	return function(self, key)
		local m = methods[key]
		if m ~= nil then
			return m
		end
		local p = props[key]
		if p then
			return p(self)
		end
		error(string.format("%s is not a valid member of %s", tostring(key), typeName), 2)
	end
end

local function isKind(v, name)
	if type(v) ~= "table" then
		return false
	end
	local mt = getmetatable(v)
	return mt ~= nil and mt.__type == name
end
D.isKind = isKind

local function num(v, what, fallback)
	if v == nil then
		return fallback or 0
	end
	if type(v) ~= "number" then
		error(string.format("invalid argument (%s): number expected, got %s", what, typeof(v)), 3)
	end
	return v
end

-- ------------------------------------------------------------------ Enum --

local Enum = {}
local enumCache = {}
local EnumItemMT = {
	__type = "EnumItem",
	__tostring = function(self)
		return "Enum." .. self.EnumType.Name .. "." .. self.Name
	end,
}
local EnumMT = { __type = "Enum" }

local function getEnum(name)
	local cached = enumCache[name]
	if cached then
		return cached
	end
	local itemsText = api.data.enums[name]
	if not itemsText then
		error(string.format("%s is not a valid member of Enum", tostring(name)), 3)
	end
	local enumObject = setmetatable({}, EnumMT)
	local raw = { Name = name }
	local byName, list = {}, {}
	local i = 0
	for itemName in string.gmatch(itemsText, "%S+") do
		local item = table.freeze(setmetatable({ Name = itemName, Value = i, EnumType = enumObject }, EnumItemMT))
		byName[itemName] = item
		i += 1
		list[i] = item
	end
	enumCache[name] = enumObject
	rawset(enumObject, "__raw", raw)
	raw.byName = byName
	raw.list = list
	return enumObject
end

EnumMT.__index = function(self, key)
	local raw = rawget(self, "__raw")
	if key == "Name" then
		return raw.Name
	elseif key == "GetEnumItems" then
		return function()
			return table.clone(raw.list)
		end
	elseif key == "FromName" then
		return function(_, name)
			return raw.byName[name]
		end
	elseif key == "FromValue" then
		return function(_, value)
			return raw.list[value + 1]
		end
	end
	local item = raw.byName[key]
	if item then
		return item
	end
	error(string.format("%s is not a valid member of Enum.%s", tostring(key), raw.Name), 2)
end
EnumMT.__tostring = function(self)
	return "Enum." .. rawget(self, "__raw").Name
end
EnumMT.__newindex = function()
	error("Enums are read-only", 2)
end

setmetatable(Enum, {
	__index = function(_, key)
		return getEnum(key)
	end,
	__newindex = function()
		error("Enum is read-only", 2)
	end,
})
D.Enum = Enum

-- Vrai si `value` est un EnumItem de l'énumération `enumName` (sans préfixe "Enum").
function D.isEnumItem(value, enumName)
	if not isKind(value, "EnumItem") then
		return false
	end
	return enumName == nil or value.EnumType.Name == enumName
end

-- --------------------------------------------------------------- Vector3 --

local V3 = { __type = "Vector3" }
local v3methods = {}
local v3props = {}

local function newV3(x, y, z)
	return table.freeze(setmetatable({ X = x, Y = y, Z = z }, V3))
end

local Vector3 = {}
function Vector3.new(x, y, z)
	return newV3(num(x, "x"), num(y, "y"), num(z, "z"))
end
Vector3.zero = newV3(0, 0, 0)
Vector3.one = newV3(1, 1, 1)
Vector3.xAxis = newV3(1, 0, 0)
Vector3.yAxis = newV3(0, 1, 0)
Vector3.zAxis = newV3(0, 0, 1)

function v3methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function v3methods.Cross(a, b)
	return newV3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function v3methods.Lerp(a, b, t)
	return newV3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function v3methods.Abs(a)
	return newV3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function v3methods.Floor(a)
	return newV3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
end
function v3methods.Ceil(a)
	return newV3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z))
end
function v3methods.Max(a, b)
	return newV3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function v3methods.Min(a, b)
	return newV3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function v3methods.Angle(a, b)
	local d = a:Dot(b) / (a.Magnitude * b.Magnitude)
	return math.acos(math.clamp(d, -1, 1))
end
function v3methods.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps and math.abs(a.Z - b.Z) <= eps
end
v3props.Magnitude = function(a)
	return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
end
v3props.Unit = function(a)
	local m = v3props.Magnitude(a)
	if m == 0 then
		return a
	end
	return newV3(a.X / m, a.Y / m, a.Z / m)
end

V3.__index = lazyIndex("Vector3", v3methods, v3props)
V3.__add = function(a, b)
	return newV3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return newV3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return newV3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return newV3(a.X * b, a.Y * b, a.Z * b)
	end
	return newV3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return newV3(a.X / b, a.Y / b, a.Z / b)
	end
	return newV3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__unm = function(a)
	return newV3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(a)
	return fmt(a.X) .. ", " .. fmt(a.Y) .. ", " .. fmt(a.Z)
end
D.Vector3 = Vector3

-- --------------------------------------------------------------- Vector2 --

local V2 = { __type = "Vector2" }
local v2methods = {}
local v2props = {}
local function newV2(x, y)
	return table.freeze(setmetatable({ X = x, Y = y }, V2))
end
local Vector2 = {}
function Vector2.new(x, y)
	return newV2(num(x, "x"), num(y, "y"))
end
Vector2.zero = newV2(0, 0)
Vector2.one = newV2(1, 1)
Vector2.xAxis = newV2(1, 0)
Vector2.yAxis = newV2(0, 1)
function v2methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end
function v2methods.Cross(a, b)
	return a.X * b.Y - a.Y * b.X
end
function v2methods.Lerp(a, b, t)
	return newV2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
end
function v2methods.Abs(a)
	return newV2(math.abs(a.X), math.abs(a.Y))
end
function v2methods.Floor(a)
	return newV2(math.floor(a.X), math.floor(a.Y))
end
function v2methods.Ceil(a)
	return newV2(math.ceil(a.X), math.ceil(a.Y))
end
function v2methods.Max(a, b)
	return newV2(math.max(a.X, b.X), math.max(a.Y, b.Y))
end
function v2methods.Min(a, b)
	return newV2(math.min(a.X, b.X), math.min(a.Y, b.Y))
end
function v2methods.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps
end
v2props.Magnitude = function(a)
	return math.sqrt(a.X * a.X + a.Y * a.Y)
end
v2props.Unit = function(a)
	local m = v2props.Magnitude(a)
	if m == 0 then
		return a
	end
	return newV2(a.X / m, a.Y / m)
end
V2.__index = lazyIndex("Vector2", v2methods, v2props)
V2.__add = function(a, b)
	return newV2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return newV2(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return newV2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return newV2(a.X * b, a.Y * b)
	end
	return newV2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	if type(b) == "number" then
		return newV2(a.X / b, a.Y / b)
	end
	return newV2(a.X / b.X, a.Y / b.Y)
end
V2.__unm = function(a)
	return newV2(-a.X, -a.Y)
end
V2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2.__tostring = function(a)
	return fmt(a.X) .. ", " .. fmt(a.Y)
end
D.Vector2 = Vector2

-- ---------------------------------------------------------------- Color3 --

local C3 = { __type = "Color3" }
local c3methods = {}
local function newC3(r, g, b)
	return table.freeze(setmetatable({ R = r, G = g, B = b }, C3))
end
local Color3 = {}
function Color3.new(r, g, b)
	r, g, b = num(r, "r"), num(g, "g"), num(b, "b")
	return newC3(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
end
function Color3.fromRGB(r, g, b)
	return newC3(math.clamp(num(r, "r"), 0, 255) / 255, math.clamp(num(g, "g"), 0, 255) / 255, math.clamp(num(b, "b"), 0, 255) / 255)
end
function Color3.fromHex(hex)
	if type(hex) ~= "string" then
		error("invalid argument #1 (string expected, got " .. typeof(hex) .. ")", 2)
	end
	local h = string.gsub(hex, "^#", "")
	if #h == 3 then
		h = string.gsub(h, ".", function(c)
			return c .. c
		end)
	end
	if #h ~= 6 or string.find(h, "[^%x]") then
		error("Color3.fromHex: invalid hex string '" .. hex .. "'", 2)
	end
	return newC3(tonumber(string.sub(h, 1, 2), 16) / 255, tonumber(string.sub(h, 3, 4), 16) / 255, tonumber(string.sub(h, 5, 6), 16) / 255)
end
function Color3.fromHSV(h, s, v)
	h = h % 1
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then
		return newC3(v, t, p)
	elseif i == 1 then
		return newC3(q, v, p)
	elseif i == 2 then
		return newC3(p, v, t)
	elseif i == 3 then
		return newC3(p, q, v)
	elseif i == 4 then
		return newC3(t, p, v)
	end
	return newC3(v, p, q)
end
function c3methods.Lerp(a, b, t)
	return newC3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function c3methods.ToHex(a)
	return string.format("%02X%02X%02X", math.floor(a.R * 255 + 0.5), math.floor(a.G * 255 + 0.5), math.floor(a.B * 255 + 0.5))
end
function c3methods.ToHSV(a)
	local mx, mn = math.max(a.R, a.G, a.B), math.min(a.R, a.G, a.B)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == a.R then
			h = ((a.G - a.B) / d) % 6
		elseif mx == a.G then
			h = (a.B - a.R) / d + 2
		else
			h = (a.R - a.G) / d + 4
		end
		h /= 6
	end
	return h, mx == 0 and 0 or d / mx, mx
end
C3.__index = lazyIndex("Color3", c3methods, {})
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3.__tostring = function(a)
	return fmt(a.R) .. ", " .. fmt(a.G) .. ", " .. fmt(a.B)
end
D.Color3 = Color3

-- ------------------------------------------------------------ UDim/UDim2 --

local UD = { __type = "UDim" }
local function newUD(s, o)
	return table.freeze(setmetatable({ Scale = s, Offset = o }, UD))
end
UD.__index = lazyIndex("UDim", {}, {})
UD.__add = function(a, b)
	return newUD(a.Scale + b.Scale, a.Offset + b.Offset)
end
UD.__sub = function(a, b)
	return newUD(a.Scale - b.Scale, a.Offset - b.Offset)
end
UD.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UD.__tostring = function(a)
	return fmt(a.Scale) .. ", " .. fmt(a.Offset)
end
local UDim = {}
function UDim.new(s, o)
	return newUD(num(s, "scale"), num(o, "offset"))
end
D.UDim = UDim

local U2 = { __type = "UDim2" }
local u2methods = {}
local function newU2(xs, xo, ys, yo)
	local x, y = newUD(xs, xo), newUD(ys, yo)
	return table.freeze(setmetatable({ X = x, Y = y, Width = x, Height = y }, U2))
end
function u2methods.Lerp(a, b, t)
	local function l(p, q)
		return p + (q - p) * t
	end
	return newU2(l(a.X.Scale, b.X.Scale), l(a.X.Offset, b.X.Offset), l(a.Y.Scale, b.Y.Scale), l(a.Y.Offset, b.Y.Offset))
end
U2.__index = lazyIndex("UDim2", u2methods, {})
U2.__add = function(a, b)
	return newU2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
U2.__sub = function(a, b)
	return newU2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
U2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
U2.__tostring = function(a)
	return "{" .. tostring(a.X) .. "}, {" .. tostring(a.Y) .. "}"
end
local UDim2 = {}
function UDim2.new(a, b, c, d)
	if isKind(a, "UDim") then
		return newU2(a.Scale, a.Offset, b.Scale, b.Offset)
	end
	return newU2(num(a, "xScale"), num(b, "xOffset"), num(c, "yScale"), num(d, "yOffset"))
end
function UDim2.fromScale(x, y)
	return newU2(num(x, "xScale"), 0, num(y, "yScale"), 0)
end
function UDim2.fromOffset(x, y)
	return newU2(0, num(x, "xOffset"), 0, num(y, "yOffset"))
end
D.UDim2 = UDim2

-- ---------------------------------------------------------------- CFrame --

local CF = { __type = "CFrame" }
local cfmethods = {}
local cfprops = {}

-- Rotation stockée par lignes : r11 r12 r13 r21 r22 r23 r31 r32 r33.
local function newCF(x, y, z, r11, r12, r13, r21, r22, r23, r31, r32, r33)
	return table.freeze(setmetatable({
		X = x, Y = y, Z = z,
		r11 = r11, r12 = r12, r13 = r13,
		r21 = r21, r22 = r22, r23 = r23,
		r31 = r31, r32 = r32, r33 = r33,
	}, CF))
end

local function matrixFromColumns(pos, vx, vy, vz)
	return newCF(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end

local function rotX(a)
	local c, s = math.cos(a), math.sin(a)
	return newCF(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
end
local function rotY(a)
	local c, s = math.cos(a), math.sin(a)
	return newCF(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
end
local function rotZ(a)
	local c, s = math.cos(a), math.sin(a)
	return newCF(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
end

local function mulCF(a, b)
	return newCF(
		a.r11 * b.X + a.r12 * b.Y + a.r13 * b.Z + a.X,
		a.r21 * b.X + a.r22 * b.Y + a.r23 * b.Z + a.Y,
		a.r31 * b.X + a.r32 * b.Y + a.r33 * b.Z + a.Z,
		a.r11 * b.r11 + a.r12 * b.r21 + a.r13 * b.r31,
		a.r11 * b.r12 + a.r12 * b.r22 + a.r13 * b.r32,
		a.r11 * b.r13 + a.r12 * b.r23 + a.r13 * b.r33,
		a.r21 * b.r11 + a.r22 * b.r21 + a.r23 * b.r31,
		a.r21 * b.r12 + a.r22 * b.r22 + a.r23 * b.r32,
		a.r21 * b.r13 + a.r22 * b.r23 + a.r23 * b.r33,
		a.r31 * b.r11 + a.r32 * b.r21 + a.r33 * b.r31,
		a.r31 * b.r12 + a.r32 * b.r22 + a.r33 * b.r32,
		a.r31 * b.r13 + a.r32 * b.r23 + a.r33 * b.r33
	)
end

local function quatFromCF(c)
	local trace = c.r11 + c.r22 + c.r33
	local w, x, y, z
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		w = 0.25 * s
		x = (c.r32 - c.r23) / s
		y = (c.r13 - c.r31) / s
		z = (c.r21 - c.r12) / s
	elseif c.r11 > c.r22 and c.r11 > c.r33 then
		local s = math.sqrt(1 + c.r11 - c.r22 - c.r33) * 2
		w = (c.r32 - c.r23) / s
		x = 0.25 * s
		y = (c.r12 + c.r21) / s
		z = (c.r13 + c.r31) / s
	elseif c.r22 > c.r33 then
		local s = math.sqrt(1 + c.r22 - c.r11 - c.r33) * 2
		w = (c.r13 - c.r31) / s
		x = (c.r12 + c.r21) / s
		y = 0.25 * s
		z = (c.r23 + c.r32) / s
	else
		local s = math.sqrt(1 + c.r33 - c.r11 - c.r22) * 2
		w = (c.r21 - c.r12) / s
		x = (c.r13 + c.r31) / s
		y = (c.r23 + c.r32) / s
		z = 0.25 * s
	end
	return x, y, z, w
end

local function cfFromQuat(px, py, pz, qx, qy, qz, qw)
	local m = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	if m == 0 then
		return newCF(px, py, pz, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	qx, qy, qz, qw = qx / m, qy / m, qz / m, qw / m
	return newCF(
		px, py, pz,
		1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw),
		2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw),
		2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)
	)
end

local IDENTITY = newCF(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)

local function lookAt(at, target, up)
	up = up or newV3(0, 1, 0)
	local z = (at - target)
	if z.Magnitude < 1e-9 then
		return newCF(at.X, at.Y, at.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	z = z.Unit
	local x = up:Cross(z)
	if x.Magnitude < 1e-6 then
		x = newV3(1, 0, 0)
		if math.abs(z.X) > 0.99 then
			x = newV3(0, 0, 1)
		end
		x = x - z * x:Dot(z)
	end
	x = x.Unit
	local y = z:Cross(x)
	return matrixFromColumns(at, x, y, z)
end

local CFrame = {}
function CFrame.new(a, b, c, d, e, f, g, h, i, j, k, l)
	if a == nil then
		return IDENTITY
	end
	if isKind(a, "Vector3") then
		if b == nil then
			return newCF(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		end
		return lookAt(a, b)
	end
	if type(a) ~= "number" then
		error("CFrame.new: invalid argument #1 (" .. typeof(a) .. ")", 2)
	end
	if l ~= nil then
		return newCF(a, b, c, d, e, f, g, h, i, j, k, l)
	elseif g ~= nil then
		return cfFromQuat(a, b, c, d, e, f, g)
	end
	return newCF(a, num(b, "y"), num(c, "z"), 1, 0, 0, 0, 1, 0, 0, 0, 1)
end
CFrame.identity = IDENTITY
CFrame.lookAt = lookAt
function CFrame.lookAlong(at, direction, up)
	return lookAt(at, at + direction, up)
end
function CFrame.fromMatrix(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy)
	return matrixFromColumns(pos, vx, vy, vz)
end
function CFrame.Angles(rx, ry, rz)
	return mulCF(mulCF(rotX(rx), rotY(ry)), rotZ(rz))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(rx, ry, rz)
	return mulCF(mulCF(rotY(ry), rotX(rx)), rotZ(rz))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromAxisAngle(axis, angle)
	local u = axis.Unit
	local s, c = math.sin(angle / 2), math.cos(angle / 2)
	return cfFromQuat(0, 0, 0, u.X * s, u.Y * s, u.Z * s, c)
end

function cfmethods.Inverse(a)
	return newCF(
		-(a.r11 * a.X + a.r21 * a.Y + a.r31 * a.Z),
		-(a.r12 * a.X + a.r22 * a.Y + a.r32 * a.Z),
		-(a.r13 * a.X + a.r23 * a.Y + a.r33 * a.Z),
		a.r11, a.r21, a.r31,
		a.r12, a.r22, a.r32,
		a.r13, a.r23, a.r33
	)
end
function cfmethods.ToWorldSpace(a, b)
	return mulCF(a, b)
end
function cfmethods.ToObjectSpace(a, b)
	return mulCF(cfmethods.Inverse(a), b)
end
function cfmethods.PointToWorldSpace(a, v)
	return newV3(a.r11 * v.X + a.r12 * v.Y + a.r13 * v.Z + a.X, a.r21 * v.X + a.r22 * v.Y + a.r23 * v.Z + a.Y, a.r31 * v.X + a.r32 * v.Y + a.r33 * v.Z + a.Z)
end
function cfmethods.PointToObjectSpace(a, v)
	return cfmethods.PointToWorldSpace(cfmethods.Inverse(a), v)
end
function cfmethods.VectorToWorldSpace(a, v)
	return newV3(a.r11 * v.X + a.r12 * v.Y + a.r13 * v.Z, a.r21 * v.X + a.r22 * v.Y + a.r23 * v.Z, a.r31 * v.X + a.r32 * v.Y + a.r33 * v.Z)
end
function cfmethods.VectorToObjectSpace(a, v)
	return cfmethods.VectorToWorldSpace(cfmethods.Inverse(a), v)
end
function cfmethods.Lerp(a, b, t)
	local ax, ay, az, aw = quatFromCF(a)
	local bx, by, bz, bw = quatFromCF(b)
	if ax * bx + ay * by + az * bz + aw * bw < 0 then
		bx, by, bz, bw = -bx, -by, -bz, -bw
	end
	return cfFromQuat(
		a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t,
		ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t, aw + (bw - aw) * t
	)
end
function cfmethods.GetComponents(a)
	return a.X, a.Y, a.Z, a.r11, a.r12, a.r13, a.r21, a.r22, a.r23, a.r31, a.r32, a.r33
end
cfmethods.components = cfmethods.GetComponents
function cfmethods.ToOrientation(a)
	-- Ordre YXZ : renvoie rx, ry, rz.
	local sx = -a.r23
	local rx = math.asin(math.clamp(sx, -1, 1))
	local ry, rz
	if math.abs(sx) < 0.9999999 then
		ry = math.atan2(a.r13, a.r33)
		rz = math.atan2(a.r21, a.r22)
	else
		ry = math.atan2(-a.r31, a.r11)
		rz = 0
	end
	return rx, ry, rz
end
function cfmethods.ToEulerAnglesYXZ(a)
	return cfmethods.ToOrientation(a)
end
function cfmethods.ToEulerAnglesXYZ(a)
	local ry = math.asin(math.clamp(a.r13, -1, 1))
	local rx, rz
	if math.abs(a.r13) < 0.9999999 then
		rx = math.atan2(-a.r23, a.r33)
		rz = math.atan2(-a.r12, a.r11)
	else
		rx = math.atan2(a.r32, a.r22)
		rz = 0
	end
	return rx, ry, rz
end
cfmethods.ToEulerAngles = cfmethods.ToEulerAnglesXYZ
function cfmethods.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	local pa = { cfmethods.GetComponents(a) }
	local pb = { cfmethods.GetComponents(b) }
	for i = 1, 12 do
		if math.abs(pa[i] - pb[i]) > eps then
			return false
		end
	end
	return true
end
function cfmethods.Orthonormalize(a)
	return a
end
cfprops.Position = function(a)
	return newV3(a.X, a.Y, a.Z)
end
cfprops.Rotation = function(a)
	return newCF(0, 0, 0, a.r11, a.r12, a.r13, a.r21, a.r22, a.r23, a.r31, a.r32, a.r33)
end
cfprops.RightVector = function(a)
	return newV3(a.r11, a.r21, a.r31)
end
cfprops.UpVector = function(a)
	return newV3(a.r12, a.r22, a.r32)
end
cfprops.LookVector = function(a)
	return newV3(-a.r13, -a.r23, -a.r33)
end
cfprops.XVector = cfprops.RightVector
cfprops.YVector = cfprops.UpVector
cfprops.ZVector = function(a)
	return newV3(a.r13, a.r23, a.r33)
end

CF.__index = lazyIndex("CFrame", cfmethods, cfprops)
CF.__mul = function(a, b)
	if isKind(b, "Vector3") then
		return cfmethods.PointToWorldSpace(a, b)
	elseif isKind(b, "CFrame") then
		return mulCF(a, b)
	end
	error("attempt to multiply a CFrame with " .. typeof(b), 2)
end
CF.__add = function(a, b)
	return newCF(a.X + b.X, a.Y + b.Y, a.Z + b.Z, a.r11, a.r12, a.r13, a.r21, a.r22, a.r23, a.r31, a.r32, a.r33)
end
CF.__sub = function(a, b)
	return newCF(a.X - b.X, a.Y - b.Y, a.Z - b.Z, a.r11, a.r12, a.r13, a.r21, a.r22, a.r23, a.r31, a.r32, a.r33)
end
CF.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z and a.r11 == b.r11 and a.r12 == b.r12 and a.r13 == b.r13 and a.r21 == b.r21 and a.r22 == b.r22 and a.r23 == b.r23 and a.r31 == b.r31 and a.r32 == b.r32 and a.r33 == b.r33
end
CF.__tostring = function(a)
	return table.concat({ fmt(a.X), fmt(a.Y), fmt(a.Z) }, ", ") .. ", ..."
end
D.CFrame = CFrame

-- ------------------------------------------------------------- TweenInfo --

local TI = { __type = "TweenInfo" }
TI.__index = lazyIndex("TweenInfo", {}, {})
local TweenInfo = {}
function TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)
	style = style or Enum.EasingStyle.Quad
	direction = direction or Enum.EasingDirection.Out
	if not D.isEnumItem(style, "EasingStyle") then
		error("TweenInfo.new: invalid argument #2 (EasingStyle expected, got " .. typeof(style) .. ")", 2)
	end
	if not D.isEnumItem(direction, "EasingDirection") then
		error("TweenInfo.new: invalid argument #3 (EasingDirection expected, got " .. typeof(direction) .. ")", 2)
	end
	return table.freeze(setmetatable({
		Time = num(time, "time", 1),
		EasingStyle = style,
		EasingDirection = direction,
		RepeatCount = num(repeatCount, "repeatCount"),
		Reverses = reverses == true,
		DelayTime = num(delayTime, "delayTime"),
	}, TI))
end
D.TweenInfo = TweenInfo

-- ------------------------------------------------- NumberRange/Sequences --

local NR = { __type = "NumberRange" }
NR.__index = lazyIndex("NumberRange", {}, {})
local NumberRange = {}
function NumberRange.new(min, max)
	max = max or min
	if min > max then
		error("NumberRange: min must be <= max", 2)
	end
	return table.freeze(setmetatable({ Min = min, Max = max }, NR))
end
D.NumberRange = NumberRange

local NSK = { __type = "NumberSequenceKeypoint" }
NSK.__index = lazyIndex("NumberSequenceKeypoint", {}, {})
local NumberSequenceKeypoint = {}
function NumberSequenceKeypoint.new(t, value, envelope)
	return table.freeze(setmetatable({ Time = t, Value = value, Envelope = envelope or 0 }, NSK))
end
D.NumberSequenceKeypoint = NumberSequenceKeypoint

local function checkKeypoints(name, list)
	if #list < 2 then
		error(name .. " needs at least 2 keypoints", 3)
	end
	if list[1].Time ~= 0 then
		error(name .. " must start at time=0", 3)
	end
	if list[#list].Time ~= 1 then
		error(name .. " must end at time=1", 3)
	end
	for i = 2, #list do
		if list[i].Time < list[i - 1].Time then
			error(name .. " keypoints must be in ascending time order", 3)
		end
	end
end

local NS = { __type = "NumberSequence" }
NS.__index = lazyIndex("NumberSequence", {}, {})
local NumberSequence = {}
function NumberSequence.new(a, b)
	local list
	if type(a) == "table" and getmetatable(a) == nil then
		list = a
	elseif type(a) == "number" and b == nil then
		list = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, a) }
	else
		list = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) }
	end
	checkKeypoints("NumberSequence", list)
	return table.freeze(setmetatable({ Keypoints = list }, NS))
end
D.NumberSequence = NumberSequence

local CSK = { __type = "ColorSequenceKeypoint" }
CSK.__index = lazyIndex("ColorSequenceKeypoint", {}, {})
local ColorSequenceKeypoint = {}
function ColorSequenceKeypoint.new(t, color)
	if not isKind(color, "Color3") then
		error("ColorSequenceKeypoint.new: Color3 expected, got " .. typeof(color), 2)
	end
	return table.freeze(setmetatable({ Time = t, Value = color }, CSK))
end
D.ColorSequenceKeypoint = ColorSequenceKeypoint

local CS = { __type = "ColorSequence" }
CS.__index = lazyIndex("ColorSequence", {}, {})
local ColorSequence = {}
function ColorSequence.new(a, b)
	local list
	if isKind(a, "Color3") and b == nil then
		list = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, a) }
	elseif isKind(a, "Color3") then
		list = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) }
	elseif type(a) == "table" then
		list = a
	else
		error("ColorSequence.new: invalid argument #1 (" .. typeof(a) .. ")", 2)
	end
	checkKeypoints("ColorSequence", list)
	return table.freeze(setmetatable({ Keypoints = list }, CS))
end
D.ColorSequence = ColorSequence

-- ------------------------------------------------------------ Rect/Font --

local RC = { __type = "Rect" }
RC.__index = lazyIndex("Rect", {}, {
	Width = function(r)
		return r.Max.X - r.Min.X
	end,
	Height = function(r)
		return r.Max.Y - r.Min.Y
	end,
})
local Rect = {}
function Rect.new(a, b, c, d)
	local mn, mx
	if isKind(a, "Vector2") then
		mn, mx = a, b
	else
		mn, mx = newV2(a or 0, b or 0), newV2(c or 0, d or 0)
	end
	return table.freeze(setmetatable({ Min = mn, Max = mx }, RC))
end
D.Rect = Rect

local FT = { __type = "Font" }
FT.__index = lazyIndex("Font", {}, {})
local Font = {}
function Font.new(family, weight, style)
	return table.freeze(setmetatable({
		Family = family,
		Weight = weight or Enum.FontWeight.Regular,
		Style = style or Enum.FontStyle.Normal,
		Bold = false,
	}, FT))
end
function Font.fromEnum(font)
	return Font.new("rbxasset://fonts/families/" .. font.Name .. ".json")
end
function Font.fromName(name, weight, style)
	return Font.new("rbxasset://fonts/families/" .. name .. ".json", weight, style)
end
function Font.fromId(id, weight, style)
	return Font.new("rbxassetid://" .. tostring(id), weight, style)
end
D.Font = Font

-- ---------------------------------------------------------------- Random --

local RND = { __type = "Random" }
local rndmethods = {}
RND.__index = lazyIndex("Random", rndmethods, {})
local Random = {}
function Random.new(seed)
	local state = { s = (seed or 0) % 2147483647 }
	if state.s <= 0 then
		state.s += 2147483646
	end
	return setmetatable({ _state = state }, RND)
end
local function nextUnit(r)
	local st = r._state
	st.s = (st.s * 48271) % 2147483647
	return (st.s - 1) / 2147483646
end
function rndmethods.NextNumber(r, min, max)
	local u = nextUnit(r)
	if min == nil then
		return u
	end
	return min + (max - min) * u
end
function rndmethods.NextInteger(r, min, max)
	return min + math.floor(nextUnit(r) * (max - min + 1))
end
function rndmethods.NextUnitVector(r)
	local z = nextUnit(r) * 2 - 1
	local a = nextUnit(r) * math.pi * 2
	local s = math.sqrt(1 - z * z)
	return newV3(s * math.cos(a), s * math.sin(a), z)
end
function rndmethods.Clone(r)
	return setmetatable({ _state = { s = r._state.s } }, RND)
end
D.Random = Random


-- ------------------------------------------------------------------- Ray --

local RY = { __type = "Ray" }
local raymethods = {}
RY.__index = lazyIndex("Ray", raymethods, {
	Unit = function(r)
		return table.freeze(setmetatable({ Origin = r.Origin, Direction = r.Direction.Unit }, RY))
	end,
})
function raymethods.ClosestPoint(r, point)
	local d = r.Direction
	local t = math.max(0, (point - r.Origin):Dot(d) / d:Dot(d))
	return r.Origin + d * t
end
function raymethods.Distance(r, point)
	return (r:ClosestPoint(point) - point).Magnitude
end
local Ray = {}
function Ray.new(origin, direction)
	return table.freeze(setmetatable({ Origin = origin, Direction = direction }, RY))
end
D.Ray = Ray

D.fmt = fmt
D.newV3 = newV3
D.newV2 = newV2
D.newC3 = newC3
D.newCF = newCF
D.newU2 = newU2

return D
