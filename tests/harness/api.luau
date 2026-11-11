--!nocheck
--[[
	api.luau  (harnais de test)
	Accès aux données générées par tools/gen-roblox-api.js (api_data.luau) :
	énumérations, classes créables, propriétés / méthodes / événements d'une
	classe avec héritage aplati.
]]

local data = require("./api_data")

local Api = { data = data }

local flat = {}
local creatableSet = nil

-- Retourne { name, chain = {"Object","Instance",...,"Part"}, isA = {Name=true},
-- props = {Name = "type"}, methods = {Name=true}, events = {Name=true} }
-- ou nil si la classe est inconnue.
function Api.info(className)
	local cached = flat[className]
	if cached ~= nil then
		return cached or nil
	end
	if not data.classes[className] then
		flat[className] = false
		return nil
	end
	local chain = {}
	local current = className
	while current and current ~= "" do
		local raw = data.classes[current]
		if not raw then
			break
		end
		table.insert(chain, 1, current)
		current = raw.parent
	end
	local info = { name = className, chain = chain, isA = {}, props = {}, methods = {}, events = {} }
	for _, name in ipairs(chain) do
		info.isA[name] = true
		local raw = data.classes[name]
		if raw.props then
			for token in string.gmatch(raw.props, "%S+") do
				local colon = string.find(token, ":", 1, true)
				if colon then
					info.props[string.sub(token, 1, colon - 1)] = string.sub(token, colon + 1)
				end
			end
		end
		if raw.methods then
			for token in string.gmatch(raw.methods, "%S+") do
				info.methods[token] = true
			end
		end
		if raw.events then
			for token in string.gmatch(raw.events, "%S+") do
				info.events[token] = true
			end
		end
	end
	flat[className] = info
	return info
end

function Api.isA(className, other)
	local info = Api.info(className)
	return info ~= nil and info.isA[other] == true
end

function Api.creatable(className)
	if not creatableSet then
		creatableSet = {}
		for token in string.gmatch(data.creatable, "%S+") do
			creatableSet[token] = true
		end
	end
	return creatableSet[className] == true
end

return Api
