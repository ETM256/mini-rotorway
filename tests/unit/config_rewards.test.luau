-- Lots de récompense hebdomadaires (Config.Rewards) : chaque entrée doit être
-- complète et utilisable par SessionProgress / l'interface de choix.
return function(T, H)
	local KINDS = { roads = true, bridges = true, roundabouts = true }

	T.test("rewards: every entry has an id, kind, amount, title and description", function()
		for key, reward in pairs(H.load("Config").Rewards) do
			T.eq(type(reward.id), "string", key .. ".id")
			T.ok(#reward.id > 0, key .. ".id must not be empty")
			T.ok(KINDS[reward.kind], key .. ".kind is unknown: " .. tostring(reward.kind))
			T.ok(reward.amount == math.floor(reward.amount) and reward.amount > 0, key .. ".amount must be a positive integer")
			T.eq(type(reward.title), "string", key .. ".title")
			T.ok(#reward.title > 0, key .. ".title must not be empty")
			T.eq(type(reward.description), "string", key .. ".description")
			T.ok(#reward.description > 0, key .. ".description must not be empty")
		end
	end)

	T.test("rewards: ids are unique and match their key", function()
		local seen = {}
		for key, reward in pairs(H.load("Config").Rewards) do
			T.falsy(seen[reward.id], "duplicate reward id " .. reward.id)
			seen[reward.id] = true
			T.eq(string.lower(key), string.lower((string.gsub(reward.id, "_", ""))), "key " .. key .. " should match id " .. reward.id)
		end
	end)

	T.test("rewards: optional road cost and traffic factor are in range", function()
		for key, reward in pairs(H.load("Config").Rewards) do
			if reward.roads ~= nil then
				T.ok(reward.roads == math.floor(reward.roads) and reward.roads > 0, key .. ".roads must be a positive integer")
			end
			if reward.trafficFactor ~= nil then
				T.gt(reward.trafficFactor, 0, key .. ".trafficFactor")
				T.le(reward.trafficFactor, 1, key .. ".trafficFactor")
			end
		end
	end)

	T.test("rewards: a traffic lot is the only one that changes traffic", function()
		for key, reward in pairs(H.load("Config").Rewards) do
			if key == "Traffic" then
				T.lt(reward.trafficFactor, 1, "the traffic lot must shorten the safety distance")
			else
				T.falsy(reward.trafficFactor, key .. " must not change traffic")
			end
		end
	end)
end
