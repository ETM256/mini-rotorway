--[[
	Profile.luau
	Meilleurs scores par carte, sauvegardés dans un DataStore.
	En Studio sans API Services, tout fonctionne quand même :
	les scores restent en mémoire pour la session.
]]

local DataStoreService = game:GetService("DataStoreService")

local Profile = {}

local store = nil
local ok, result = pcall(function()
	return DataStoreService:GetDataStore("MiniMotorwaysV1")
end)
if ok then
	store = result
else
	warn("[MiniMotorways] DataStore unavailable: " .. tostring(result))
end

local cache = {}

local function keyFor(player)
	return "player_" .. tostring(player.UserId)
end

function Profile.load(player)
	if cache[player.UserId] then
		return cache[player.UserId]
	end

	local data = {}
	if store then
		local success, value = pcall(function()
			return store:GetAsync(keyFor(player))
		end)
		if success and type(value) == "table" then
			data = value
		elseif not success then
			warn("[MiniMotorways] Could not load profile: " .. tostring(value))
		end
	end

	cache[player.UserId] = data
	return data
end

function Profile.save(player)
	local data = cache[player.UserId]
	if not data or not store then
		return
	end
	local success, err = pcall(function()
		store:SetAsync(keyFor(player), data)
	end)
	if not success then
		warn("[MiniMotorways] Could not save profile: " .. tostring(err))
	end
end

function Profile.submit(player, mapId, score)
	local data = Profile.load(player)
	local best = tonumber(data[mapId]) or 0
	if score > best then
		data[mapId] = score
		best = score
		Profile.save(player)
	end
	return best
end

function Profile.getBest(player, mapId)
	local data = Profile.load(player)
	return tonumber(data[mapId]) or 0
end

function Profile.reset(player)
	cache[player.UserId] = {}
	if store then
		local success, err = pcall(function()
			store:SetAsync(keyFor(player), {})
		end)
		if not success then
			warn("[MiniMotorways] Could not reset profile: " .. tostring(err))
		end
	end
end

function Profile.forget(player)
	cache[player.UserId] = nil
end

return Profile
