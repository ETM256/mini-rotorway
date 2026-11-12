-- Disposition des maisons autour de leur magasin : petits groupes irréguliers,
-- jamais alignés, jamais collés, mesurés sur de vraies parties graines sur
-- chaque carte (quatre graines par carte, dix minutes simulées).
return function(T, H)
	local Maps = H.load("Maps")
	local StoreConfig = H.load("StoreConfig")

	-- Produit vectoriel : nul quand les trois cases sont alignées.
	local function cross(a, b, c)
		return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	end

	T.test("groupes : aucun magasin à trois maisons alignées, sur six cartes et quatre graines", function()
		local stores, lines = 0, 0
		for _, map in ipairs(Maps.all()) do
			for seed = 1, 4 do
				H.reset()
				H.seed(seed)
				local session = H.newSession(map.id)
				session.satisfaction = 1e9
				H.runSession(session, 600, 0.25)
				for _, store in ipairs(session.destinations) do
					local houses = store.houses
					if #houses >= 3 then
						stores += 1
						local aligned = true
						for i = 1, #houses do
							for j = i + 1, #houses do
								for k = j + 1, #houses do
									if cross(houses[i], houses[j], houses[k]) ~= 0 then
										aligned = false
									end
								end
							end
						end
						if aligned then
							lines += 1
						end
					end
				end
				session:destroy()
			end
		end
		T.ge(stores, 20, "the sample must contain enough three-house stores to mean something")
		T.eq(lines, 0, "houses of one store must not sit on a straight line")
	end)

	T.test("espacement : deux bâtiments quelconques restent à la distance minimale", function()
		local minimum = StoreConfig.Houses.MinDistanceFromBuilding - 1e-6
		for _, map in ipairs(Maps.all()) do
			H.reset()
			H.seed(7)
			local session = H.newSession(map.id)
			session.satisfaction = 1e9
			H.runSession(session, 600, 0.25)
			local list = session.buildingList
			for i = 1, #list do
				for j = i + 1, #list do
					local a, b = list[i], list[j]
					local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
					T.ge(d, minimum, map.id .. ": " .. a.key .. " and " .. b.key .. " are too close")
				end
			end
			session:destroy()
		end
	end)
end
