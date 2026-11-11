--[[
	CameraController.luau
	Vue aérienne de la ville : cadrage automatique sur la carte, zoom progressif
	à la molette et déplacement borné pour que la carte reste à l'écran.
	L'orientation ne change jamais : seuls la distance (zoom) et la position au
	sol varient. Les réglages sont dans Config.Camera. setSafeInsets réserve les
	marges de l'interface : la carte se cadre dans la zone libre.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local CAMERA = Config.Camera
local ZOOM_EPSILON = 1e-4
local LOBBY_POSE = CFrame.new(0, CAMERA.LobbyHeight, 0) * CFrame.Angles(-math.pi / 2, 0, 0)

local CameraController = {}

-- Carte en cours ; nil tant qu'aucune partie n'est lancée.
local currentOrigin = nil
local currentSize = nil
local currentTile = nil
local active = false

-- zoom : valeur affichée, qui glisse vers zoomGoal (demandée par la molette).
local zoom = 1
local zoomGoal = 1
local panX = 0
local panZ = 0

-- Arrivée sur la carte : la pose part d'un cran plus éloigné puis descend.
local intro = nil
local frameConnection = nil
local viewportConnection = nil

local function clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	elseif value > maxValue then
		return maxValue
	end
	return value
end

-- Marges de l'interface en pixels écran (haut, droite, bas, gauche), réglées
-- par setSafeInsets. Une marge absente vaut zéro.
local insets = { top = 0, right = 0, bottom = 0, left = 0 }
-- Part minimale de la vue gardée pour la carte, même si les marges prennent
-- presque tout l'écran.
local MIN_USABLE_FRACTION = 0.25

-- Distance de la caméra, taille d'un pixel au sol (au plan de la carte) et zone
-- utile en pixels pour un zoom donné. La carte tient en entier dans la zone
-- utile, en largeur comme en hauteur, avec la marge Config.Camera.Fit.
local function viewAt(zoomValue)
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(16, 9)
	local vw = math.max(viewport.X, 1)
	local vh = math.max(viewport.Y, 1)
	local usableW = math.max(vw - insets.left - insets.right, vw * MIN_USABLE_FRACTION)
	local usableH = math.max(vh - insets.top - insets.bottom, vh * MIN_USABLE_FRACTION)
	local halfFov = math.tan(math.rad(CAMERA.FOV) * 0.5)
	local needed = currentSize * currentTile * CAMERA.Fit / zoomValue
	-- Demi-hauteur au sol : la carte tient en hauteur dans usableH et en largeur
	-- dans usableW, la vue faisant vw x vh pixels.
	local halfGround = math.max(needed * vh / (2 * usableH), needed * vh / (2 * usableW))
	return halfGround / halfFov, 2 * halfGround / vh, usableW, usableH
end

-- Déplacement maximal sur un axe. Tant que la carte tient dans la vue sur cet
-- axe, elle reste centrée ; sinon le centre peut dépasser le bord de la carte
-- de PanOverscroll fois l'écart, ce qui garde une part nette de carte visible.
local function panLimit(mapHalf, viewHalf)
	if viewHalf >= mapHalf then
		return 0
	end
	return (mapHalf - viewHalf) * (1 + CAMERA.PanOverscroll)
end

-- Décalage du centre de vue borné pour un zoom donné. Le décalage stocké n'est
-- pas modifié : pendant un zoom, la vue reste dans les bornes du zoom courant
-- sans effacer le déplacement voulu par le joueur. Le pan est mesuré depuis le
-- centre de la zone utile, qui coïncide avec le centre de la carte.
local function clampedPan(zoomValue)
	local mapHalf = currentSize * currentTile * 0.5
	local _, perPixel, usableW, usableH = viewAt(zoomValue)
	local limitX = panLimit(mapHalf, perPixel * usableW * 0.5)
	local limitZ = panLimit(mapHalf, perPixel * usableH * 0.5)
	return clamp(panX, -limitX, limitX), clamp(panZ, -limitZ, limitZ)
end

-- Pose de la caméra au-dessus du centre de la carte (décalé par le pan). La
-- carte se projette au centre de la zone utile : si les marges sont inégales,
-- la visée est décalée de la moitié de l'écart. Le décalage arrière est
-- proportionnel à la distance : orientation fixe.
local function poseFor(zoomValue, offsetX, offsetZ)
	local distance, perPixel = viewAt(zoomValue)
	local shiftX = -(insets.left - insets.right) * 0.5 * perPixel
	local shiftZ = -(insets.top - insets.bottom) * 0.5 * perPixel
	local mapHalf = currentSize * currentTile * 0.5
	local center = currentOrigin + Vector3.new(mapHalf + offsetX + shiftX, 0, mapHalf + offsetZ + shiftZ)
	local eye = center + Vector3.new(0, distance, distance * CAMERA.BackRatio)
	return CFrame.lookAt(eye, center)
end

local function takeControl(camera)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = CAMERA.FOV
end

-- Écrit la pose courante dans la caméra. Appelé sur chaque changement d'état et,
-- pendant une animation seulement, à chaque frame.
local function render()
	local camera = Workspace.CurrentCamera
	if not active or not camera then
		return
	end
	local offsetX, offsetZ = clampedPan(zoom)
	local pose = poseFor(zoom, offsetX, offsetZ)
	if intro then
		local t = clamp(intro.elapsed / CAMERA.IntroSeconds, 0, 1)
		pose = intro.from:Lerp(pose, t * t * (3 - 2 * t))
	end
	camera.CFrame = pose
end

local function needsFrames()
	return zoom ~= zoomGoal or intro ~= nil
end

local function stopFrames()
	if frameConnection then
		frameConnection:Disconnect()
		frameConnection = nil
	end
end

local function onFrame(dt)
	if zoom ~= zoomGoal then
		-- Lissage exponentiel en espace logarithmique : chaque cran de molette a
		-- la même sensation, et la valeur ne dépasse jamais la cible.
		local delta = math.log(zoomGoal / zoom)
		if math.abs(delta) < ZOOM_EPSILON then
			zoom = zoomGoal
		else
			local alpha = 1 - math.exp(-CAMERA.ZoomSmoothing * dt)
			zoom *= math.exp(delta * alpha)
		end
	end
	if intro then
		intro.elapsed += dt
		if intro.elapsed >= CAMERA.IntroSeconds then
			intro = nil
		end
	end
	render()
	if not needsFrames() then
		stopFrames()
	end
end

-- Les frames ne tournent que pendant une animation : rien à faire au repos.
local function updateFrames()
	if not needsFrames() then
		stopFrames()
	elseif not frameConnection then
		frameConnection = RunService.RenderStepped:Connect(onFrame)
	end
end

local function onViewportChanged()
	if active then
		CameraController.refresh(true)
	end
end

-- Suit le viewport de la caméra courante, y compris si Roblox la remplace.
local function bindCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
		if active then
			takeControl(camera)
			render()
		end
	end
end

bindCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

-- Valeur numérique finie : un NaN ou un infini donnerait une CFrame invalide,
-- et clamp ne le rattrape pas (toute comparaison avec NaN est fausse).
local function isFinite(value)
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

function CameraController.focus(origin, size, tile, instant)
	-- Une carte invalide laisserait la caméra active sans dimensions : chaque
	-- rendu suivant multiplierait nil.
	if typeof(origin) ~= "Vector3" or not isFinite(size) or not isFinite(tile) or size <= 0 or tile <= 0 then
		return
	end
	currentOrigin = origin
	currentSize = size
	currentTile = tile
	active = true
	zoom = 1
	zoomGoal = 1
	panX = 0
	panZ = 0
	intro = nil

	local camera = Workspace.CurrentCamera
	if camera then
		takeControl(camera)
	end
	if not instant then
		intro = { from = poseFor(1 / CAMERA.IntroZoomOut, 0, 0), elapsed = 0 }
	end
	render()
	updateFrames()
end

function CameraController.refresh(instant)
	if not active then
		return
	end
	if instant then
		zoom = zoomGoal
	end
	render()
	updateFrames()
end

function CameraController.lobby()
	currentOrigin = nil
	currentSize = nil
	currentTile = nil
	active = false
	zoom = 1
	zoomGoal = 1
	panX = 0
	panZ = 0
	intro = nil
	stopFrames()

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = CAMERA.LobbyFOV
	camera.CFrame = LOBBY_POSE
end

local function setZoomGoal(value)
	if not isFinite(value) then
		return
	end
	zoomGoal = clamp(value, CAMERA.ZoomMin, CAMERA.ZoomMax)
	updateFrames()
end

-- Les méthodes de zoom ne bougent pas la caméra tout de suite : le zoom glisse
-- vers la cible à chaque frame.
function CameraController.zoomBy(delta)
	if not active then
		return
	end
	setZoomGoal(zoomGoal + delta)
end

function CameraController.setZoom(value)
	if not active then
		return
	end
	setZoomGoal(value)
end

function CameraController.pan(deltaX, deltaZ)
	if not active or not isFinite(deltaX) or not isFinite(deltaZ) then
		return
	end
	-- Borné avec la cible du zoom : le décalage reste valide une fois le zoom
	-- arrivé à destination.
	panX += deltaX
	panZ += deltaZ
	panX, panZ = clampedPan(zoomGoal)
	render()
end

-- Déplace la vue de pixelsX, pixelsY pixels écran : la carte suit le curseur
-- ou le doigt, quels que soient le zoom et la résolution.
function CameraController.panByPixels(pixelsX, pixelsY)
	if not active then
		return
	end
	if not Workspace.CurrentCamera then
		return
	end
	-- Un pixel vaut la même distance au sol sur les deux axes.
	local _, perPixel = viewAt(zoom)
	-- Sur l'écran, X va vers la droite (+X monde) et Y vers le bas (+Z monde).
	-- Tirer la carte vers la droite déplace donc la caméra vers la gauche.
	CameraController.pan(-pixelsX * perPixel, -pixelsY * perPixel)
end

-- Marges de l'interface (pixels écran) : la carte se cadre dans la zone libre,
-- jamais sous la barre supérieure, les compteurs ou la barre d'outils.
local function marginOf(value)
	if not isFinite(value) or value < 0 then
		return 0
	end
	return value
end

function CameraController.setSafeInsets(top, right, bottom, left)
	insets.top = marginOf(top)
	insets.right = marginOf(right)
	insets.bottom = marginOf(bottom)
	insets.left = marginOf(left)
	if active then
		panX, panZ = clampedPan(zoomGoal)
		CameraController.refresh(true)
	end
end

-- Valeur demandée : la molette agit sur elle, l'affichage la rejoint ensuite.
function CameraController.getZoom()
	return zoomGoal
end

function CameraController.getMapSize()
	if not currentSize or not currentTile then
		return 0
	end
	return currentSize * currentTile
end

return CameraController
