--[[
	Bootstrap.server.luau
	Point d'entrée serveur : prépare le monde, les remotes, les profils,
	puis fait tourner une Session par joueur.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Remotes = require(Shared.Remotes)
local SharedRoadConfig = require(Shared.RoadConfig)

local Session = require(script.Parent.Session)
local Profile = require(script.Parent.Profile)

Players.CharacterAutoLoads = false

-- Lumière plate mais nettement moins éblouissante : le plateau reste
-- crème sans virer au blanc, avec assez de contraste pour lire l'eau,
-- les routes et les bâtiments.
Lighting.Brightness = 0.8
Lighting.ClockTime = 12
Lighting.GeographicLatitude = 0
Lighting.Ambient = Color3.fromHex("D8D2C5")
Lighting.OutdoorAmbient = Color3.fromHex("E0D8C9")
Lighting.GlobalShadows = false
Lighting.ShadowSoftness = 0
Lighting.EnvironmentDiffuseScale = 0.45
Lighting.EnvironmentSpecularScale = 0
Lighting.ExposureCompensation = -0.35

local oldWorlds = Workspace:FindFirstChild("MMWorlds")
if oldWorlds then
	oldWorlds:Destroy()
end
local worlds = Instance.new("Folder")
worlds.Name = "MMWorlds"
worlds.Parent = Workspace

Remotes.setup()

local sessions = {}
local worldCounter = 0

local function sendProfile(player)
	local data = Profile.load(player)
	Remotes.get("Profile"):FireClient(player, data)
end

local function startGame(player, mapId)
	if type(mapId) ~= "string" or not Maps.getById(mapId) then
		mapId = Maps.all()[1].id
	end

	local previous = sessions[player]
	if previous then
		previous:destroy()
		sessions[player] = nil
	end

	worldCounter += 1
	local session = Session.new(player, mapId, worldCounter)
	sessions[player] = session
	session:start()
end

local function endSession(player)
	local session = sessions[player]
	if session then
		session:destroy()
		sessions[player] = nil
	end
end

Remotes.get("StartGame").OnServerEvent:Connect(function(player, mapId)
	startGame(player, mapId)
end)

Remotes.get("DrawRoad").OnServerEvent:Connect(function(player, cells)
	local session = sessions[player]
	if not session or type(cells) ~= "table" or #cells > SharedRoadConfig.Input.MaxCellsPerRequest then
		return
	end
	session:drawRoad(cells)
end)

Remotes.get("EraseRoad").OnServerEvent:Connect(function(player, key)
	local session = sessions[player]
	if session and type(key) == "string" then
		session:eraseRoad(key)
	end
end)

Remotes.get("EraseRoads").OnServerEvent:Connect(function(player, keys)
	local session = sessions[player]
	if session and type(keys) == "table" and #keys <= SharedRoadConfig.Input.MaxCellsPerRequest then
		session:eraseRoads(keys)
	end
end)

Remotes.get("SetPaused").OnServerEvent:Connect(function(player, paused)
	local session = sessions[player]
	if session then
		session:setPaused(paused == true)
	end
end)

Remotes.get("SetSpeed").OnServerEvent:Connect(function(player, speed)
	local session = sessions[player]
	if session then
		session:setSpeed(speed)
	end
end)

Remotes.get("PlaceRoundabout").OnServerEvent:Connect(function(player, x, y)
	local session = sessions[player]
	if session then
		session:placeRoundabout(x, y)
	end
end)

Remotes.get("ChooseReward").OnServerEvent:Connect(function(player, optionId)
	local session = sessions[player]
	if session and type(optionId) == "string" then
		session:chooseReward(optionId)
	end
end)

Remotes.get("ReturnToLobby").OnServerEvent:Connect(function(player)
	endSession(player)
end)

Remotes.get("RequestProfile").OnServerEvent:Connect(function(player)
	sendProfile(player)
end)

Remotes.get("ResetRecords").OnServerEvent:Connect(function(player)
	Profile.reset(player)
	sendProfile(player)
end)

local function onPlayerAdded(player)
	task.spawn(function()
		Profile.load(player)
		sendProfile(player)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	endSession(player)
	Profile.save(player)
	Profile.forget(player)
end)

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.1)
	for _, session in pairs(sessions) do
		session:update(dt)
	end
end)

game:BindToClose(function()
	for player in pairs(sessions) do
		Profile.save(player)
	end
end)

warn("[MiniMotorways] Server ready — " .. Config.GameName .. " v" .. Config.Version)
