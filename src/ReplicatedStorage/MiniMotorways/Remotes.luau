--[[
	Remotes.luau
	Crée (côté serveur) et récupère les RemoteEvents partagés.
	Le client utilise WaitForChild pour être sûr qu'ils existent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local FOLDER_NAME = "MMRemotes"

function Remotes.folder()
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	return folder
end

function Remotes.get(name)
	local folder = Remotes.folder()
	local event = folder:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
	end
	return event
end

function Remotes.setup()
	local names = {
		"StartGame",
		"DrawRoad",
		"EraseRoad",
		"EraseRoads",
		"SetPaused",
		"SetSpeed",
		"PlaceRoundabout",
		"WeekChoice",
		"ChooseReward",
		"ReturnToLobby",
		"RequestProfile",
		"ResetRecords",
		"GameStarted",
		"State",
		"StoreState",
		"RoadState",
		"GameOver",
		"Toast",
		"Profile",
	}
	for _, name in ipairs(names) do
		Remotes.get(name)
	end
end

return Remotes
