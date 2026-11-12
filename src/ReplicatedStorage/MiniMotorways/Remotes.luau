--[[
	Remotes.luau
	Crée les RemoteEvents partagés côté serveur et les récupère côté client.
	Le serveur crée chaque remote une seule fois : il n'y a aucun yield entre
	la recherche et la création, donc pas de doublon. Le client attend que le
	serveur ait répliqué le dossier et ne crée jamais de remote local, qui ne
	communiquerait avec personne.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER_NAME = "MMRemotes"
-- Délai côté client avant de signaler un remote absent (serveur mal démarré).
local WAIT_SECONDS = 10

local NAMES = {
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

function Remotes.folder()
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder
	end

	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_SECONDS)
	if not folder then
		error("[MiniMotorways] Dossier de remotes introuvable : " .. FOLDER_NAME, 2)
	end
	return folder
end

function Remotes.get(name)
	local folder = Remotes.folder()
	local event = folder:FindFirstChild(name)
	if event then
		return event
	end

	if RunService:IsServer() then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
		return event
	end

	event = folder:WaitForChild(name, WAIT_SECONDS)
	if not event then
		error("[MiniMotorways] Remote introuvable : " .. name, 2)
	end
	return event
end

-- Idempotent : relancer le serveur ou rappeler setup ne duplique rien.
function Remotes.setup()
	if not RunService:IsServer() then
		return
	end
	for _, name in ipairs(NAMES) do
		Remotes.get(name)
	end
end

return Remotes
