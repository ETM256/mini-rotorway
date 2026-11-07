--[[
	CameraController.luau
	Caméra au-dessus de la ville, recadrée automatiquement selon l'écran.
	La molette zoome, le clic milieu (ou deux doigts) déplace la vue.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local CameraController = {}

local currentOrigin = nil
local currentSize = nil
local currentTile = nil
local activeTween = nil
local zoom = 1
local panX = 0
local panZ = 0
local active = false

local function clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	elseif value > maxValue then
		return maxValue
	end
	return value
end

local function computeTarget(origin, size, tile)
	local camera = Workspace.CurrentCamera
	local mapSize = size * tile
	local center = origin + Vector3.new(mapSize / 2 + panX, 0, mapSize / 2 + panZ)

	local viewport = camera.ViewportSize
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local halfFov = math.tan(math.rad(Config.Camera.FOV) * 0.5)
	local needed = (mapSize * (Config.Camera.Fit or 1.18)) / zoom
	local distanceByHeight = (needed * 0.5) / halfFov
	local distanceByWidth = (needed * 0.5) / (halfFov * math.max(aspect, 0.1))
	local distance = math.max(distanceByHeight, distanceByWidth)

	-- Vue quasi orthographique : la ville reste bien droite, comme dans la vidéo.
	local height = distance
	local back = distance * (Config.Camera.BackRatio or 0.035)

	return CFrame.lookAt(center + Vector3.new(0, height, back), center)
end

local function apply(instant)
	if not active or not currentOrigin or not currentSize or not currentTile then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Config.Camera.FOV

	local target = computeTarget(currentOrigin, currentSize, currentTile)
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end

	if instant then
		camera.CFrame = target
	else
		activeTween = TweenService:Create(
			camera,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = target }
		)
		activeTween:Play()
	end
end

local function clampPan()
	if not currentSize or not currentTile then
		panX = 0
		panZ = 0
		return
	end
	local mapSize = currentSize * currentTile
	local maxPan = mapSize * math.max(0, 1 - 1 / zoom) * 0.5
	panX = clamp(panX, -maxPan, maxPan)
	panZ = clamp(panZ, -maxPan, maxPan)
end

function CameraController.focus(origin, size, tile, instant)
	currentOrigin = origin
	currentSize = size
	currentTile = tile
	active = true
	zoom = 1
	panX = 0
	panZ = 0

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Config.Camera.FOV
	apply(instant)
end

function CameraController.refresh(instant)
	apply(instant)
end

function CameraController.lobby()
	currentOrigin = nil
	currentSize = nil
	currentTile = nil
	active = false
	zoom = 1
	panX = 0
	panZ = 0
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 60
	camera.CFrame = CFrame.new(0, 400, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
end

function CameraController.zoomBy(delta)
	if not active then
		return
	end
	zoom = clamp(zoom + delta, 1, 2.8)
	clampPan()
	apply(false)
end

function CameraController.setZoom(value)
	if not active then
		return
	end
	zoom = clamp(value, 1, 2.8)
	clampPan()
	apply(false)
end

function CameraController.pan(deltaX, deltaZ)
	if not active then
		return
	end
	panX += deltaX
	panZ += deltaZ
	clampPan()
	apply(false)
end

function CameraController.getZoom()
	return zoom
end

function CameraController.getMapSize()
	if not currentSize or not currentTile then
		return 0
	end
	return currentSize * currentTile
end

local camera = Workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if active then
			CameraController.refresh(true)
		end
	end)
end

return CameraController
