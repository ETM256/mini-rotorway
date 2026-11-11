--[[
	RoadPreview.luau
	Aperçu local du tracé : la forme exacte de la route qui sera posée
	(RoadGeometry), en menthe si elle est valide, en corail si elle est refusée
	ou si elle va être effacée. Aucun objet n'est envoyé au serveur.

	Les pièces sont un pool : une case n'est reconstruite que si elle change, ou
	si un voisin change (ses bras changent). Les routes déjà posées servent de
	contexte sans être copiées : une table à __index lit le réseau du client et
	les cases de l'aperçu. Les pièces sont opaques : deux pièces translucides qui
	se recouvrent dessineraient une couture plus foncée (spec 3.3).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local RoadConfig = require(Shared.RoadConfig)
local RoadGeometry = require(Shared.RoadGeometry)

local RoadPreview = {}
RoadPreview.__index = RoadPreview

local NO_BRIDGES = {}
local HALF_TURN = math.pi / 2
-- Le liseré passe sous la surface : un écart de hauteur évite le scintillement.
local EDGE_LIFT = 0.01

local function makePart()
	local part = Instance.new("Part")
	part.Name = "RoadPreviewCell"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = 1
	part.Parent = nil
	return part
end

function RoadPreview.new()
	local self = setmetatable({}, RoadPreview)
	self.origin = Vector3.zero
	self.tile = Config.Grid.TileSize
	-- Routes posées telles que le serveur les décrit (ensemble clé -> true).
	self.roads = NO_BRIDGES
	-- Cases de l'aperçu : clé -> { x, y, valid, hover }.
	self.cells = {}
	-- Pièces affichées par case, et pièces libres du pool.
	self.cellParts = {}
	self.free = {}
	self.folder = Instance.new("Folder")
	self.folder.Name = "MM_RoadPreview"
	self.folder.Parent = Workspace
	-- Vue du réseau pour RoadGeometry : routes posées ou cases de l'aperçu,
	-- sans copie de la table des routes.
	self.view = setmetatable({}, {
		__index = function(_, key)
			return self.roads[key] or self.cells[key] ~= nil
		end,
	})
	return self
end

function RoadPreview:setWorld(origin, tile)
	self.origin = origin or self.origin
	self.tile = tile or self.tile
	-- Les routes mémorisées ne valent plus pour le nouveau monde.
	self.roads = NO_BRIDGES
	self:clear()
end

-- Rend une pièce au pool : elle reste dans le dossier, cachée.
function RoadPreview:releaseCell(key)
	local parts = self.cellParts[key]
	if not parts then
		return
	end
	for _, part in ipairs(parts) do
		part.Transparency = 1
		self.free[#self.free + 1] = part
	end
	self.cellParts[key] = nil
end

function RoadPreview:acquire()
	local part = table.remove(self.free)
	if part then
		return part
	end
	part = makePart()
	part.Parent = self.folder
	return part
end

-- Place une pièce de RoadGeometry sur la case x, y (repère de la case en 0..1).
function RoadPreview:place(part, piece, x, y, color)
	local tile = self.tile
	local thickness = RoadConfig.Visual.PreviewHeight
	local lift = if piece.layer == "edge" then -EDGE_LIFT else 0
	local worldX = self.origin.X + (x + piece.cx) * tile
	local worldY = self.origin.Y + RoadConfig.Visual.PreviewY + lift
	local worldZ = self.origin.Z + (y + piece.cy) * tile
	if piece.kind == "disk" then
		-- Un cylindre a son axe en X : il est couché à plat par une rotation.
		local diameter = piece.w * tile
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(thickness, diameter, diameter)
		part.CFrame = CFrame.new(worldX, worldY, worldZ) * CFrame.Angles(0, 0, HALF_TURN)
	else
		part.Shape = Enum.PartType.Block
		part.Size = Vector3.new(piece.w * tile, thickness, piece.h * tile)
		part.CFrame = CFrame.new(worldX, worldY, worldZ)
	end
	part.Color = color
	part.Transparency = 0
end

-- Recalcule les pièces d'une case de l'aperçu, selon ses voisins actuels.
function RoadPreview:drawCell(key)
	self:releaseCell(key)
	local cell = self.cells[key]
	if not cell then
		return
	end
	local visual = RoadConfig.Visual
	local color = if cell.valid then visual.PreviewValidColor else visual.PreviewInvalidColor
	local transparency = if cell.hover then visual.PreviewHoverTransparency else 0
	local pieces = RoadGeometry.cellPieces(self.view, NO_BRIDGES, nil, cell.x, cell.y)
	local parts = {}
	for index, piece in ipairs(pieces) do
		local part = self:acquire()
		self:place(part, piece, cell.x, cell.y, color)
		part.Transparency = transparency
		parts[index] = part
	end
	self.cellParts[key] = parts
end

-- Clés des cases de l'aperçu touchées par un changement sur key : la case
-- elle-même et ses quatre voisins, dont les bras peuvent changer.
local function markAround(dirty, key)
	local x, y = Grid.parse(key)
	if not x then
		return
	end
	dirty[key] = true
	dirty[Grid.key(x + 1, y)] = true
	dirty[Grid.key(x - 1, y)] = true
	dirty[Grid.key(x, y + 1)] = true
	dirty[Grid.key(x, y - 1)] = true
end

-- Routes posées (RoadState). Les cases de l'aperçu sont redessinées, car leurs
-- bras dépendent de ces routes.
function RoadPreview:setRoads(roads)
	self.roads = roads or NO_BRIDGES
	for key in pairs(self.cells) do
		self:drawCell(key)
	end
end

-- cells : { {x = , y = , valid = true/false, hover = true/false}, ... }
-- valid = false est affiché en corail (case refusée, ou case à effacer).
-- Seules les cases qui changent sont redessinées.
function RoadPreview:setCells(cells)
	if not self.folder then
		return
	end
	local nextCells = {}
	for _, cell in ipairs(cells or {}) do
		if type(cell) == "table" and type(cell.x) == "number" and type(cell.y) == "number" then
			local x, y = math.floor(cell.x), math.floor(cell.y)
			nextCells[Grid.key(x, y)] = {
				x = x,
				y = y,
				valid = cell.valid ~= false,
				hover = cell.hover == true,
			}
		end
	end

	local dirty = {}
	for key, old in pairs(self.cells) do
		local new = nextCells[key]
		if not new or new.valid ~= old.valid or new.hover ~= old.hover then
			markAround(dirty, key)
		end
	end
	for key in pairs(nextCells) do
		if not self.cells[key] then
			markAround(dirty, key)
		end
	end

	self.cells = nextCells
	for key in pairs(dirty) do
		if nextCells[key] then
			self:drawCell(key)
		else
			self:releaseCell(key)
		end
	end
end

function RoadPreview:clear()
	for key in pairs(self.cellParts) do
		self:releaseCell(key)
	end
	self.cells = {}
end

function RoadPreview:destroy()
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
	self.cells = {}
	self.cellParts = {}
	self.free = {}
end

return RoadPreview
