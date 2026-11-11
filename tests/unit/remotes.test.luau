return function(T, H)
	T.test("setup creates every named RemoteEvent under ReplicatedStorage.MMRemotes", function()
		local Remotes = H.load("Remotes")
		Remotes.setup()
		local folder = game.ReplicatedStorage:FindFirstChild("MMRemotes")
		T.ok(folder, "MMRemotes folder")
		T.ge(#folder:GetChildren(), 15)
		for _, remote in ipairs(folder:GetChildren()) do
			T.eq(remote.ClassName, "RemoteEvent")
		end
	end)

	T.test("get is idempotent and returns the same instance", function()
		local Remotes = H.load("Remotes")
		local a = Remotes.get("DrawRoad")
		local b = Remotes.get("DrawRoad")
		T.eq(a, b)
		T.eq(#game.ReplicatedStorage.MMRemotes:GetChildren(), 1)
	end)

	T.test("setup twice does not duplicate remotes", function()
		local Remotes = H.load("Remotes")
		Remotes.setup()
		local count = #game.ReplicatedStorage.MMRemotes:GetChildren()
		Remotes.setup()
		T.eq(#game.ReplicatedStorage.MMRemotes:GetChildren(), count)
	end)

	T.test("every remote name used in src/ exists in Remotes.setup", function()
		local Remotes = H.load("Remotes")
		Remotes.setup()
		local known = {}
		for _, remote in ipairs(game.ReplicatedStorage.MMRemotes:GetChildren()) do
			known[remote.Name] = true
		end
		local problems = {}
		for _, source in ipairs(H.sources()) do
			local code = H.stripComments(source.source)
			for name in string.gmatch(code, "Remotes%.get%(%s*\"([%w_]+)\"%s*%)") do
				if not known[name] then
					table.insert(problems, source.file .. ": Remotes.get(\"" .. name .. "\")")
				end
			end
			for name in string.gmatch(code, "remote%(%s*\"([%w_]+)\"%s*%)") do
				if not known[name] then
					table.insert(problems, source.file .. ": remote(\"" .. name .. "\")")
				end
			end
		end
		T.eq(#problems, 0, table.concat(problems, "; "))
	end)

	T.test("RemoteEvent payloads cannot carry functions", function()
		local Remotes = H.load("Remotes")
		local remote = Remotes.get("State")
		local player = H.newPlayer()
		T.throws(function()
			remote:FireClient(player, { callback = function() end })
		end, "not serializable")
	end)

	T.test("FireClient is logged and FireServer reaches OnServerEvent with the player", function()
		local Remotes = H.load("Remotes")
		local remote = Remotes.get("DrawRoad")
		local seen = {}
		remote.OnServerEvent:Connect(function(player, cells)
			table.insert(seen, { player = player, cells = cells })
		end)
		H.asClient()
		remote:FireServer({ { 1, 2 } })
		T.eq(#seen, 1)
		T.eq(seen[1].player, H.localPlayer)
		T.deepEq(seen[1].cells, { { 1, 2 } })
		T.eq(#H.sent("DrawRoad", "toServer"), 1)
	end)
end
