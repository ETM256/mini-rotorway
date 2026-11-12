-- Bâtiments dans une vraie partie : placement, cases, connexions, évolution.
return function(T, H)
	local Config = H.load("Config")
	local Grid = H.load("Grid")
	local HALF_CELL = Config.Grid.TileSize * 0.5

	local function eachBasePart(model, callback)
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				callback(descendant)
			end
		end
	end

	-- Vérifie qu'aucune part du modèle ne sort de la case (cx, cz).
	local function assertInsideCell(model, cx, cz, label)
		eachBasePart(model, function(part)
			local half = part.Size * 0.5
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local corner = part.CFrame:PointToWorldSpace(
							Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
						)
						T.le(math.abs(corner.X - cx), HALF_CELL + 1e-3, label .. " " .. part.Name .. " x")
						T.le(math.abs(corner.Z - cz), HALF_CELL + 1e-3, label .. " " .. part.Name .. " z")
					end
				end
			end
		end)
	end

	T.test("every building stays inside its own cell during a run with roads", function()
		local session = H.newSession("los_angeles")
		local house, store = H.houseAndStore(session)
		T.ok(house and store, "the session starts with a house and a store")
		H.connect(session, house, store)
		H.runSession(session, 150, 0.1, { autoChoose = true })

		T.ok(#session.buildingList >= 2, "buildings exist")
		for _, building in ipairs(session.buildingList) do
			local center = Grid.center(session.origin, building.x, building.y, 0)
			assertInsideCell(building.model, center.X, center.Z, building.kind .. " " .. building.key)
			T.falsy(session.roads[building.key], "a building cell never holds a road")
		end
	end)

	T.test("evolution keeps the colour, the cell and a single model", function()
		local session = H.newSession("los_angeles")
		local _, store = H.houseAndStore(session)
		local colorIndex = store.colorIndex
		local before = store.model.PrimaryPart.CFrame.Position

		session:replaceStoreModel(store)

		T.eq(store.model:GetAttribute("StoreType"), "large")
		T.eq(store.model:GetAttribute("ColorIndex"), colorIndex)
		T.eq(store.model:GetAttribute("BuildingId"), store.id)
		local after = store.model.PrimaryPart.CFrame.Position
		T.near(after.X, before.X, 1e-3, "same X after evolution")
		T.near(after.Z, before.Z, 1e-3, "same Z after evolution")
		T.eq(store.model.Parent, session.world.Buildings)

		local palette = Config.HouseColors[colorIndex]
		local body = store.model:FindFirstChild("Body")
		T.near(body.Color.R, palette.color.R, 1e-3, "same colour after evolution")
		T.near(body.Color.G, palette.color.G, 1e-3)
		T.near(body.Color.B, palette.color.B, 1e-3)

		H.advance(1)
		local leftovers = 0
		for _, child in ipairs(session.world.Buildings:GetChildren()) do
			if string.find(child.Name, "store_" .. store.id .. "_small", 1, true) then
				leftovers += 1
			end
		end
		T.eq(leftovers, 0, "the small model is removed once the fade is over")
	end)

	T.test("an entrance faces an adjacent road when one exists", function()
		local session = H.newSession("los_angeles")
		local x, y = session:findBuildingSpot()
		T.ok(x ~= nil, "a free spot exists on the default map")
		session.roads[Grid.key(x + 1, y)] = true
		T.near(session:entranceAngle(x, y, 1), math.pi * 0.5, 1e-6, "the entrance faces the road to the east")
		session.roads[Grid.key(x + 1, y)] = nil
		local fallback = session:entranceAngle(x, y, 1)
		local valid = { 0, math.pi, math.pi * 0.5, -math.pi * 0.5 }
		local known = false
		for _, angle in ipairs(valid) do
			known = known or math.abs(fallback - angle) < 1e-6
		end
		T.ok(known, "without a road the entrance still takes one of the four sides")
		T.eq(session:entranceAngle(x, y, 1), fallback, "the fallback is deterministic")
	end)

	T.test("building spots stay inside the playable area and keep their spacing", function()
		local session = H.newSession("los_angeles")
		local created = 0
		for i = 1, 40 do
			local x, y = session:findBuildingSpot()
			if not x then
				break
			end
			T.ok(x >= 1 and y >= 1 and x <= session.size - 2 and y <= session.size - 2, "spot inside the margin")
			T.ok(session:isFreeCell(x, y), "spot is a free cell")
			for _, other in ipairs(session.buildingList) do
				T.ge(math.abs(x - other.x) + math.abs(y - other.y), 2, "spacing between buildings " .. i)
			end
			session:createBuilding("house", x, y, ((i - 1) % #Config.HouseColors) + 1)
			created += 1
		end
		T.ge(created, 5, "several houses fit on the map")
	end)

	T.test("a new building is connected only through an orthogonal road", function()
		local session = H.newSession("los_angeles")
		local x, y = session:findBuildingSpot()
		local house = session:createBuilding("house", x, y, 1)
		T.falsy(house.connected, "no road yet")

		session.roads[Grid.key(x + 1, y + 1)] = true
		session:updateBuildingConnections()
		T.falsy(house.connected, "a diagonal road does not connect")

		session.roads[Grid.key(x + 1, y)] = true
		session:updateBuildingConnections()
		T.ok(house.connected, "an orthogonal road connects")
		T.eq(#house.connections, 1)
	end)

	T.test("an evolved store keeps the entrance side it was built with", function()
		local session = H.newSession("los_angeles")
		local x, y = session:findBuildingSpot()
		local store = session:createBuilding("store", x, y, 1, "small")
		local angle = store.entranceAngle
		T.ok(angle ~= nil, "the building records its entrance side")

		-- Une route apparaît du côté opposé à l'entrée : sans mémoire, le
		-- magasin évoluerait vers cette route et changerait de face.
		local ox = -math.round(math.sin(angle))
		local oy = -math.round(math.cos(angle))
		session.roads[Grid.key(x + ox, y + oy)] = true

		session:replaceStoreModel(store)
		T.near(store.entranceAngle, angle, 1e-6, "the recorded side is unchanged")

		local center = Grid.center(session.origin, x, y, 0)
		local pad = store.model:FindFirstChild("Entrance")
		local dx = pad.CFrame.Position.X - center.X
		local dz = pad.CFrame.Position.Z - center.Z
		local along = dx * math.sin(angle) + dz * math.cos(angle)
		local across = dx * math.cos(angle) - dz * math.sin(angle)
		T.gt(along, 0.5, "the pad still faces the recorded side")
		T.near(across, 0, 1e-3, "the pad is centred on that side")
	end)

	T.test("houses and small stores never spawn on a park tree", function()
		local Maps = H.load("Maps")
		for _, map in ipairs(Maps.all()) do
			H.reset()
			local session = H.newSession(map.id)
			local treeCells = {}
			for _, tree in ipairs(H.find(session.world.folder, { name = "Tree" })) do
				local tx, ty = Grid.cellFromWorld(session.origin, tree.Position)
				treeCells[Grid.key(tx, ty)] = true
			end
			for _ = 1, 200 do
				local x, y = session:findBuildingSpot()
				if not x then
					break
				end
				T.falsy(treeCells[Grid.key(x, y)], map.id .. " spot " .. Grid.key(x, y) .. " holds a tree")
			end
			session:destroy()
		end
	end)
end
