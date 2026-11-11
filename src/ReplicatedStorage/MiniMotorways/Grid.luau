--[[
	Grid.luau
	Conversions entre une case (x, y) et une position 3D, et clés de case
	« x:y ». Chaque "monde" de joueur a sa propre origine.

	Une clé est toujours canonique : entiers seulement, sans « -0 ». Ainsi
	Grid.parse(Grid.key(x, y)) redonne (x, y) et deux clés égales désignent
	toujours la même case.
]]

local Config = require(script.Parent.Config)

local Grid = {}

-- Décalages partagés, à ne jamais modifier : ils permettent de parcourir le
-- voisinage sans allouer une table par case.
Grid.ORTHOGONAL_OFFSETS = {
	{ 0, -1 },
	{ 1, 0 },
	{ 0, 1 },
	{ -1, 0 },
}

Grid.DIAGONAL_OFFSETS = {
	{ 1, -1 },
	{ 1, 1 },
	{ -1, 1 },
	{ -1, -1 },
}

-- Tolérance sur les bords de case, en cases. Un point posé à quelques
-- millionièmes de case sous une frontière (erreur de flottant du raycast ou
-- de Grid.center) doit tomber dans la case qui commence à cette frontière.
local BORDER_EPSILON = 1e-6

-- -0 s'écrit « -0 » dans une clé : on le ramène à 0 pour garder la clé unique.
local function normalizeZero(value)
	if value == 0 then
		return 0
	end
	return value
end

function Grid.key(x, y)
	-- Une coordonnée non entière serait une clé que parse ne relit pas : on la
	-- ramène à sa case, comme le fait cellFromWorld.
	return normalizeZero(math.floor(x)) .. ":" .. normalizeZero(math.floor(y))
end

function Grid.parse(key)
	if type(key) ~= "string" then
		return nil
	end
	local sx, sy = string.match(key, "^(%-?%d+):(%-?%d+)$")
	if not sx then
		return nil
	end
	return normalizeZero(tonumber(sx)), normalizeZero(tonumber(sy))
end

local function isIndex(value, size)
	return type(value) == "number" and value >= 0 and value < size and value == math.floor(value)
end

-- Vrai si (x, y) est une case entière dans une grille carrée de taille size.
-- NaN, infini, nil et les flottants sont rejetés.
function Grid.inRange(x, y, size)
	return isIndex(x, size) and isIndex(y, size)
end

function Grid.inBounds(x, y)
	return Grid.inRange(x, y, Config.Grid.Size)
end

function Grid.center(origin, x, y, height)
	local tile = Config.Grid.TileSize
	return origin + Vector3.new((x + 0.5) * tile, height or 0, (y + 0.5) * tile)
end

function Grid.cellFromWorld(origin, position)
	local tile = Config.Grid.TileSize
	local x = math.floor((position.X - origin.X) / tile + BORDER_EPSILON)
	local y = math.floor((position.Z - origin.Z) / tile + BORDER_EPSILON)
	return x, y
end

function Grid.neighbors(x, y)
	return {
		{ x + 1, y },
		{ x - 1, y },
		{ x, y + 1 },
		{ x, y - 1 },
	}
end

-- Voisins orthogonaux + diagonaux. Les routes et les trajets utilisent cette
-- liste : un déplacement en diagonale relie deux cases par leur coin.
function Grid.neighbors8(x, y)
	return {
		{ x + 1, y },
		{ x - 1, y },
		{ x, y + 1 },
		{ x, y - 1 },
		{ x + 1, y + 1 },
		{ x + 1, y - 1 },
		{ x - 1, y + 1 },
		{ x - 1, y - 1 },
	}
end

function Grid.distance(a, b)
	return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

return Grid
