--[[
	Main.client.luau
	Câble le lobby, le HUD, la caméra et les contrôles.
	Le client n'a aucune autorité : il demande, le serveur décide.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)

local remotesFolder = ReplicatedStorage:WaitForChild("MMRemotes")
local remoteCache = {}
local function remote(name)
	local found = remoteCache[name]
	if not found then
		found = remotesFolder:WaitForChild(name)
		remoteCache[name] = found
	end
	return found
end

local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)
local StoreVisualController = require(script.Parent.StoreVisualController)
local Lobby = require(script.Parent.UI.Lobby)
local HUD = require(script.Parent.UI.HUD)

local CORE_GUI_ATTEMPTS = 5

-- StarterGui refuse parfois ces réglages au tout premier instant : on réessaie
-- quelques fois, sans bloquer le client. Le menu Échap de Roblox (Paramètres)
-- n'est pas un CoreGuiType : il reste accessible.
local function hideDefaultUi(attempt)
	local ok, err = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		-- Le bouton de réinitialisation remettrait le personnage à zéro, sans
		-- rapport avec une partie de gestion.
		StarterGui:SetCore("ResetButtonCallback", false)
	end)
	if ok then
		return
	end
	if attempt < CORE_GUI_ATTEMPTS then
		task.delay(0.5 * attempt, hideDefaultUi, attempt + 1)
	else
		warn("Interface Roblox non masquée : " .. tostring(err))
	end
end
hideDefaultUi(1)

-- Un affichage qui échoue ne doit pas couper les autres mises à jour du client.
local function guarded(label, handler)
	return function(...)
		local ok, err = pcall(handler, ...)
		if not ok then
			warn(label .. " : " .. tostring(err))
		end
	end
end

CameraController.lobby()

local lobby
local hud
local input
local storeVisuals = StoreVisualController.new()
local currentMapId = nil
local inGame = false

-- La carte se cadre hors des bandes que le HUD déclare (barre, compteurs,
-- outils). Sans getter côté HUD, la carte garde toute la vue.
local function syncSafeInsets()
	if hud and hud.getSafeInsets then
		local top, right, bottom, left = hud:getSafeInsets()
		CameraController.setSafeInsets(top, right, bottom, left)
	end
end

-- Recalcule les marges à chaque changement de taille de la vue, y compris si
-- Roblox remplace la caméra courante.
local viewportConnection = nil
local function bindViewport()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(syncSafeInsets)
	end
end
bindViewport()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport)

-- Clic milieu maintenu : glisser déplace la vue sans jamais construire. Les
-- gestes tactiles sont portés par InputController (un doigt construit, deux
-- doigts déplacent et zooment).
local panning = false

local function playMap(mapId)
	if not mapId then
		return
	end
	currentMapId = mapId
	remote("StartGame"):FireServer(mapId)
end

-- Le menu pause s'ouvre avec la demande de pause au serveur ; les commandes de
-- la carte sont coupées derrière lui. P (ou le bouton) le referme.
local function resumeGame()
	remote("SetPaused"):FireServer(false)
	if hud then
		hud:hidePause()
	end
	-- Un choix hebdomadaire rouvert par la reprise garde les commandes coupées.
	if input then
		input:setEnabled(not (hud and hud:isChoiceOpen()))
	end
end

local function pauseGame()
	if not inGame or not hud then
		return
	end
	if hud:isPauseOpen() then
		resumeGame()
		return
	end
	-- Partie terminée : rien à mettre en pause.
	if hud:isGameOverOpen() then
		return
	end
	remote("SetPaused"):FireServer(true)
	hud:showPause()
	if input then
		input:setEnabled(false)
	end
end

-- Réinitialise les commandes et les overlays de la partie précédente. Les
-- magasins ne sont pas touchés ici : StoreVisualController:setWorld les
-- reconstruit, et la caméra est recadrée par GameStarted.
local function resetGameView()
	panning = false
	if input then
		input:setEnabled(false)
		input:setTool("build")
	end
	if hud then
		hud:hideModals()
	end
end

local function goToLobby()
	remote("ReturnToLobby"):FireServer()
	inGame = false
	resetGameView()
	storeVisuals:clear()
	if hud then
		hud:hide()
	end
	if lobby then
		lobby:show()
		lobby:showMaps()
	end
	CameraController.lobby()
end

lobby = Lobby.new({
	onPlay = function()
		lobby:showMaps()
	end,
	onQuit = function()
		player:Kick("Merci d'avoir joué à " .. Config.GameName .. " !")
	end,
	onStartMap = playMap,
	onResetRecords = function()
		remote("ResetRecords"):FireServer()
		lobby:toast("Records réinitialisés")
	end,
})

-- Affiche le menu immédiatement : même si un autre module échoue plus tard,
-- les boutons du lobby restent visibles et réactifs.
lobby:show()

hud = HUD.new({
	onPause = pauseGame,
	onResume = resumeGame,
	-- Nouvelle partie sur le même plan : le serveur repart de zéro, et GameStarted
	-- remet le HUD, la grille, les magasins et la caméra à leur état initial.
	onRestart = function()
		if inGame and currentMapId then
			playMap(currentMapId)
		end
	end,
	-- L'aide (« hints ») se gère dans le HUD lui-même : rien à faire côté jeu.
	onSetting = function(name, value)
		if name == "grid" and input then
			input:setGridPinned(value == true)
		end
	end,
	onMenu = goToLobby,
	onToolChange = function(tool)
		input:setTool(tool)
	end,
	onSpeed = function(value)
		remote("SetSpeed"):FireServer(value)
	end,
	onChooseReward = function(optionId)
		remote("ChooseReward"):FireServer(optionId)
		input:setEnabled(true)
	end,
})

input = InputController.new({
	onDraw = function(cells)
		remote("DrawRoad"):FireServer(cells)
	end,
	onErase = function(key)
		remote("EraseRoad"):FireServer(key)
	end,
	onEraseMany = function(keys)
		remote("EraseRoads"):FireServer(keys)
	end,
	onRoundabout = function(x, y)
		remote("PlaceRoundabout"):FireServer(x, y)
	end,
	onToolChanged = function(tool)
		if hud then
			hud:setTool(tool)
		end
	end,
	-- Outil « main » et glissement à deux doigts : déplacement en pixels écran.
	onPan = CameraController.panByPixels,
	-- Pincement : InputController fournit la variation relative de l'écart,
	-- convertie en zoom par RoadConfig.Input.PinchZoomGain.
	onZoom = CameraController.zoomBy,
})

-- Le clic milieu démarre le déplacement seulement hors de toute interface, mais
-- le déplacement, lui, continue même si le curseur passe sur un bouton.
UserInputService.InputBegan:Connect(function(event, processed)
	if processed or not inGame then
		return
	end
	if event.UserInputType == Enum.UserInputType.MouseButton3 then
		panning = true
	elseif event.KeyCode == Enum.KeyCode.P then
		-- P ouvre et referme le menu pause. Les commandes de la carte sont coupées
		-- derrière le menu : la touche est donc lue ici, pas par InputController.
		pauseGame()
	end
end)

UserInputService.InputChanged:Connect(function(event, processed)
	if not inGame then
		return
	end
	if event.UserInputType == Enum.UserInputType.MouseMovement then
		if panning then
			CameraController.panByPixels(event.Delta.X, event.Delta.Y)
		end
	elseif event.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		-- Molette vers l'avant : Position.Z > 0, donc zoom avant.
		CameraController.zoomBy(event.Position.Z * Config.Camera.ZoomStep)
	end
end)

UserInputService.InputEnded:Connect(function(event)
	if event.UserInputType == Enum.UserInputType.MouseButton3 then
		panning = false
	end
end)

-- Fenêtre perdue clic milieu tenu : le relâchement n'arrive jamais, la vue
-- ne doit pas rester collée au curseur au retour.
UserInputService.WindowFocusReleased:Connect(function()
	panning = false
end)

-- Chaque étape de GameStarted est isolée : si le HUD échoue à s'afficher, la
-- caméra se cadre et les commandes s'activent quand même, sans quoi le joueur
-- resterait devant une carte immobile.
local function runStep(label, step)
	guarded("GameStarted/" .. label, step)()
end

remote("GameStarted").OnClientEvent:Connect(function(data)
	runStep("reset", resetGameView)
	currentMapId = data.mapId
	inGame = true

	runStep("lobby", function()
		lobby:hide()
	end)
	runStep("hud", function()
		hud:showGame(data, Maps.getById(data.mapId))
	end)
	runStep("stores", function()
		storeVisuals:setWorld(data.origin, data.tile)
	end)
	-- Les marges viennent du HUD déjà affiché : la première pose est cadrée juste.
	runStep("camera", function()
		syncSafeInsets()
		CameraController.focus(data.origin, data.size, data.tile)
	end)
	runStep("input", function()
		input:setWorld(data.origin, data.size, data.tile)
		input:setMapId(data.mapId)
		input:setEnabled(true)
		input:setTool("build")
	end)
	runStep("settings", function()
		-- Le réglage « Grille visible » de la session s'applique aussi aux nouvelles parties.
		input:setGridPinned(hud:getSetting("grid"))
		hud:setTool("build")
	end)
end)

remote("State").OnClientEvent:Connect(function(state)
	hud:setState(state)
	if state.over then
		input:setEnabled(false)
	end
end)

remote("StoreState").OnClientEvent:Connect(guarded("StoreState", function(data)
	storeVisuals:apply(data)
end))

remote("RoadState").OnClientEvent:Connect(function(data)
	input:applyRoadState(data)
end)

remote("WeekChoice").OnClientEvent:Connect(function(data)
	hud:showWeekChoice(data)
	input:setEnabled(false)
end)

remote("GameOver").OnClientEvent:Connect(function(data)
	hud:showGameOver(data)
	input:setEnabled(false)
end)

remote("Toast").OnClientEvent:Connect(function(text)
	if inGame then
		hud:toast(text)
	else
		lobby:toast(text)
	end
end)

remote("Profile").OnClientEvent:Connect(function(profile)
	lobby:setProfile(profile)
end)

task.delay(1, function()
	remote("RequestProfile"):FireServer()
end)
