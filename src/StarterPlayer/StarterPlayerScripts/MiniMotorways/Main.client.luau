--[[
	Main.client.luau
	Câble le lobby, le HUD, la caméra et les contrôles.
	Le client n'a aucune autorité : il demande, le serveur décide.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)

local remotesFolder = ReplicatedStorage:WaitForChild("MMRemotes")
local function remote(name)
	return remotesFolder:WaitForChild(name)
end

local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)
local Lobby = require(script.Parent.UI.Lobby)
local HUD = require(script.Parent.UI.HUD)

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

CameraController.lobby()

local lobby
local hud
local input
local currentMapId = nil
local inGame = false

local function playMap(mapId)
	if not mapId then
		return
	end
	currentMapId = mapId
	remote("StartGame"):FireServer(mapId)
end

local function pauseGame()
	if not inGame then
		return
	end
	remote("SetPaused"):FireServer(true)
	-- La pause fige le temps, mais on garde l'outil de construction actif :
	-- le joueur peut continuer à tracer ou effacer des routes.
end

local function resumeGame()
	remote("SetPaused"):FireServer(false)
	if hud then
		hud:hidePause()
	end
	if input then
		input:setEnabled(true)
	end
end

local function goToLobby()
	remote("ReturnToLobby"):FireServer()
	inGame = false
	if input then
		input:setEnabled(false)
	end
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
	onRestart = function()
		if currentMapId then
			hud:hideModals()
			playMap(currentMapId)
		end
	end,
	onMenu = goToLobby,
	onToolChange = function(tool)
		if input then
			input:setTool(tool)
		end
	end,
	onSpeed = function(value)
		remote("SetSpeed"):FireServer(value)
	end,
	onChooseReward = function(optionId)
		remote("ChooseReward"):FireServer(optionId)
		if input then
			input:setEnabled(true)
		end
	end,
})

input = InputController.new({
	onDraw = function(cells)
		remote("DrawRoad"):FireServer(cells)
	end,
	onErase = function(key)
		remote("EraseRoad"):FireServer(key)
	end,
	onRoundabout = function(x, y)
		remote("PlaceRoundabout"):FireServer(x, y)
	end,
	onToolChanged = function(tool)
		if hud then
			hud:setTool(tool)
		end
	end,
	onPauseRequest = pauseGame,
})

local panning = false
UserInputService.InputChanged:Connect(function(input)
	if not inGame then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		CameraController.zoomBy(-input.Position.Z * 0.14)
	elseif input.UserInputType == Enum.UserInputType.MouseMovement and panning then
		local camera = Workspace.CurrentCamera
		local mapSize = CameraController.getMapSize()
		if camera and mapSize > 0 then
			local scale = mapSize / math.max(camera.ViewportSize.Y, 1) / CameraController.getZoom()
			CameraController.pan(-input.Delta.X * scale, -input.Delta.Y * scale)
		end
	end
end)

UserInputService.InputBegan:Connect(function(input)
	if inGame and input.UserInputType == Enum.UserInputType.MouseButton3 then
		panning = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		panning = false
	end
end)

remote("GameStarted").OnClientEvent:Connect(function(data)
	currentMapId = data.mapId
	inGame = true

	lobby:hide()
	hud:showGame(data, Maps.getById(data.mapId))

	CameraController.focus(data.origin, data.size, data.tile)
	input:setWorld(data.origin, data.size, data.tile)
	input:setEnabled(true)
	input:setTool("build")
	hud:setTool("build")
end)

remote("State").OnClientEvent:Connect(function(state)
	hud:setState(state)
	if state.over then
		input:setEnabled(false)
	end
end)

remote("WeekChoice").OnClientEvent:Connect(function(data)
	hud:showWeekChoice(data)
	if input then
		input:setEnabled(false)
	end
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

lobby:show()

task.delay(1, function()
	remote("RequestProfile"):FireServer()
end)
