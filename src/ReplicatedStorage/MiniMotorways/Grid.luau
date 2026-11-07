--[[
	Grid.luau
	Conversions entre une case (x, y) et une position 3D.
	Chaque "monde" de joueur a sa propre origine.
]]

local Config = require(script.Parent.Config)

local Grid = {}

function Grid.key(x, y)
	return x .. ":" .. y
end

function Grid.parse(key)
	if type(key) ~= "string" then
		return nil
	end
	local x, y = string.match(key, "^(%-?%d+):(%-?%d+)$")
	if not x then
		return nil
	end
	return tonumber(x), tonumber(y)
end

function Grid.inBounds(x, y)
	return x >= 0 and y >= 0 and x < Config.Grid.Size and y < Config.Grid.Size
end

function Grid.center(origin, x, y, height)
	local tile = Config.Grid.TileSize
	return origin + Vector3.new((x + 0.5) * tile, height or 0, (y + 0.5) * tile)
end

function Grid.cellFromWorld(origin, position)
	local tile = Config.Grid.TileSize
	local x = math.floor((position.X - origin.X) / tile)
	local y = math.floor((position.Z - origin.Z) / tile)
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
