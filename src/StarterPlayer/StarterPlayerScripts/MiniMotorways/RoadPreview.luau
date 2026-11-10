--[[
	RoadPreview.luau
	Aperçu local des cases de route. Aucun objet n'est envoyé au serveur :
	le client affiche seulement ce qu'il est en train de dessiner.
	Les cases valides sont menthe, les cases refusées sont corail.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local RoadConfig = require(Shared.RoadConfig)

local RoadPreview = {}
RoadPreview.__index = RoadPreview

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
	part.Size = Vector3.new(1, RoadConfig.Visual.PreviewHeight, 1)
	part.Parent = nil
	return part
end

function RoadPreview.new()
	local self = setmetatable({}, RoadPreview)
	self.origin = Vector3.zero
	self.tile = Config.Grid.TileSize
	self.parts = {}
	self.folder = Instance.new("Folder")
	self.folder.Name = "MM_RoadPreview"
	self.folder.Parent = Workspace
	return self
end

function RoadPreview:setWorld(origin, tile)
	self.origin = origin or self.origin
	self.tile = tile or self.tile
end

function RoadPreview:getPart(index)
	local part = self.parts[index]
	if not part then
		part = makePart()
		part.Parent = self.folder
		self.parts[index] = part
	end
	return part
end

function RoadPreview:clear()
	for _, part in ipairs(self.parts) do
		part.Transparency = 1
	end
end

function RoadPreview:destroy()
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
	self.parts = {}
end

-- cells : { {x, y, valid = true/false, hover = true/false}, ... }
function RoadPreview:setCells(cells)
	local count = 0
	for index, cell in ipairs(cells or {}) do
		if type(cell) == "table" and cell.x and cell.y then
			local part = self:getPart(index)
			local size = self.tile * RoadConfig.Visual.PreviewScale
			part.Size = Vector3.new(size, RoadConfig.Visual.PreviewHeight, size)
			part.CFrame = CFrame.new(Grid.center(self.origin, cell.x, cell.y, RoadConfig.Visual.PreviewY))
			if cell.valid == false then
				part.Color = RoadConfig.Visual.PreviewInvalidColor
			else
				part.Color = RoadConfig.Visual.PreviewValidColor
			end
			part.Transparency = cell.hover
				and RoadConfig.Visual.PreviewHoverTransparency
				or RoadConfig.Visual.PreviewTransparency
			count = index
		end
	end

	for index = count + 1, #self.parts do
		self.parts[index].Transparency = 1
	end
end

return RoadPreview
