--[[
	RoadNetwork.luau
	Petites opérations partagées par le client et le serveur :
	  - voisinage orthogonal (ou 8 directions en mode historique) ;
	  - comptage des connexions d'une case (virage, T, croix) ;
	  - résolution d'un geste en chemin horizontal / vertical sans diagonale.

	La simulation reste dans Session : ce module ne possède aucune route et
	ne crée aucun objet.
]]

local Grid = require(script.Parent.Grid)
local RoadConfig = require(script.Parent.RoadConfig)

local RoadNetwork = {}

-- Décalages partagés avec Grid (ordre haut, droite, bas, gauche).
local ORTHOGONAL = Grid.ORTHOGONAL_OFFSETS
local DIAGONAL = Grid.DIAGONAL_OFFSETS

RoadNetwork.ORTHOGONAL = ORTHOGONAL
RoadNetwork.DIAGONAL = DIAGONAL

-- Nombre maximal de cases ajoutées par un seul tracé. Au-delà, le tracé
-- serait tronqué sans que l'appelant le sache : on le refuse en bloc.
local MAX_PATH_STEPS = RoadConfig.Input.MaxPathSteps

-- Vrai pour un nombre entier fini. NaN et l'infini échouent à ces deux tests.
local function isCell(value)
	return type(value) == "number" and value == math.floor(value) and math.abs(value) < math.huge
end

local function isFinite(value)
	return type(value) == "number" and math.abs(value) < math.huge
end

local function countAt(roads, x, y, offsets)
	local count = 0
	for _, offset in ipairs(offsets) do
		if roads[Grid.key(x + offset[1], y + offset[2])] then
			count += 1
		end
	end
	return count
end

function RoadNetwork.neighbors(x, y, allowDiagonals)
	local list = {}
	for _, direction in ipairs(ORTHOGONAL) do
		list[#list + 1] = { x + direction[1], y + direction[2] }
	end
	if allowDiagonals then
		for _, direction in ipairs(DIAGONAL) do
			list[#list + 1] = { x + direction[1], y + direction[2] }
		end
	end
	return list
end

function RoadNetwork.isAdjacent(ax, ay, bx, by, allowDiagonals)
	local dx = math.abs(bx - ax)
	local dy = math.abs(by - ay)
	if dx == 0 and dy == 0 then
		return false
	end
	if dy == 0 and dx == 1 then
		return true
	end
	if dx == 0 and dy == 1 then
		return true
	end
	return allowDiagonals == true and dx == 1 and dy == 1
end

-- Nombre de cases de route voisines. Les diagonales ne comptent que si
-- allowDiagonals : elles ne relient une case que dans ce mode.
function RoadNetwork.countRoadNeighbors(roads, x, y, allowDiagonals)
	local count = countAt(roads, x, y, ORTHOGONAL)
	if allowDiagonals then
		count += countAt(roads, x, y, DIAGONAL)
	end
	return count
end

function RoadNetwork.countRoadNeighborsAtKey(roads, key, allowDiagonals)
	local x, y = Grid.parse(key)
	if not x then
		return 0
	end
	return RoadNetwork.countRoadNeighbors(roads, x, y, allowDiagonals)
end

-- Seuil : 3 connexions ou plus = T ou croix, qui ont besoin d'un raccord.
function RoadNetwork.isIntersection(roads, x, y, allowDiagonals)
	return RoadNetwork.countRoadNeighbors(roads, x, y, allowDiagonals) >= 3
end

function RoadNetwork.isIntersectionKey(roads, key, allowDiagonals)
	return RoadNetwork.countRoadNeighborsAtKey(roads, key, allowDiagonals) >= 3
end

--[[
	Construit un chemin orthogonal entre deux cases, sans inclure la case de
	départ. Renvoie (cellules, complet) :
	  - complet vaut false si les coordonnées ne sont pas des entiers finis ou
	    si le trajet dépasse MAX_PATH_STEPS ; la liste est alors vide ;
	  - sinon la liste mène exactement à (toX, toY).
	preferredAxis vaut "x" (horizontal d'abord) ou "y" (vertical d'abord) ; sans
	préférence, l'axe dominant passe en premier, et à égalité c'est l'horizontal.
	Quand le trajet est droit, l'axe n'a pas d'effet.
]]
function RoadNetwork.manhattanPath(fromX, fromY, toX, toY, preferredAxis)
	local cells = {}
	if not (isCell(fromX) and isCell(fromY) and isCell(toX) and isCell(toY)) then
		return cells, false
	end

	local dx = toX - fromX
	local dy = toY - fromY
	local absX = math.abs(dx)
	local absY = math.abs(dy)
	if absX + absY > MAX_PATH_STEPS then
		return cells, false
	end

	local horizontalFirst
	if preferredAxis == "x" then
		horizontalFirst = true
	elseif preferredAxis == "y" then
		horizontalFirst = false
	else
		horizontalFirst = absX >= absY
	end

	local stepX = dx > 0 and 1 or -1
	local stepY = dy > 0 and 1 or -1
	local x, y = fromX, fromY
	if horizontalFirst then
		for _ = 1, absX do
			x += stepX
			cells[#cells + 1] = { x, y }
		end
		for _ = 1, absY do
			y += stepY
			cells[#cells + 1] = { x, y }
		end
	else
		for _ = 1, absY do
			y += stepY
			cells[#cells + 1] = { x, y }
		end
		for _ = 1, absX do
			x += stepX
			cells[#cells + 1] = { x, y }
		end
	end
	return cells, true
end

--[[
	Enchaîne une liste de cases cibles en tracé orthogonal depuis
	(startX, startY). Les coordonnées non entières sont ramenées à leur case
	(floor) ; une cible NaN, infinie ou absente est ignorée sans faire avancer
	le tracé. Chaque case n'apparaît qu'une fois et la case de départ n'est
	jamais renvoyée : si le tracé revient sur ses pas, une case déjà présente
	est omise, donc deux cases consécutives peuvent ne pas être voisines. La
	liste sert à poser des routes (un ensemble de cases), pas à être parcourue.
]]
function RoadNetwork.flattenPath(startX, startY, cells, preferredAxis)
	local result = {}
	if not (isFinite(startX) and isFinite(startY)) then
		return result
	end

	local x, y = math.floor(startX), math.floor(startY)
	local seen = { [Grid.key(x, y)] = true }
	for _, cell in ipairs(cells or {}) do
		if type(cell) == "table" and isFinite(cell[1]) and isFinite(cell[2]) then
			local tx, ty = math.floor(cell[1]), math.floor(cell[2])
			local steps, complete = RoadNetwork.manhattanPath(x, y, tx, ty, preferredAxis)
			if complete then
				for _, step in ipairs(steps) do
					local key = Grid.key(step[1], step[2])
					if not seen[key] then
						seen[key] = true
						result[#result + 1] = step
					end
				end
				x, y = tx, ty
			end
		end
	end
	return result
end

return RoadNetwork
