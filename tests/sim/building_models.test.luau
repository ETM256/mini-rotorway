-- Construction pure des maisons et des magasins (BuildingModels), sans partie.
-- Ces tests fixent le budget de parts, la géométrie dans la case, la palette
-- et le déterminisme des variantes.
return function(T, H)
	local Config = H.load("Config")
	local BuildingModels = H.load("BuildingModels")
	local HALF_CELL = Config.Grid.TileSize * 0.5
	local WHITE = Config.Colors.White
	local SHADOW = Config.Colors.BuildingShadow

	local HOUSE_BUDGET = 14
	local STORE_BUDGET = 20

	local function sameColor(a, b)
		return math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
	end

	local function build(kind, id, colorIndex, storeType, options)
		return BuildingModels.build(kind, id, Vector3.new(0, 0, 0), colorIndex, storeType, options)
	end

	-- Tous les cas construits : maisons et deux types de magasin, sur chaque
	-- couleur de la palette.
	local function eachCase(callback)
		for colorIndex = 1, #Config.HouseColors do
			for id = 1, 8 do
				callback("house", id, colorIndex, nil)
				callback("store", id, colorIndex, "small")
				callback("store", id, colorIndex, "large")
			end
		end
	end

	local function eachBasePart(model, callback)
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				callback(descendant)
			end
		end
	end

	local function cornersOf(part)
		local half = part.Size * 0.5
		local corners = {}
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					corners[#corners + 1] = part.CFrame:PointToWorldSpace(
						Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
					)
				end
			end
		end
		return corners
	end

	local function signature(model)
		local parts = {}
		eachBasePart(model, function(part)
			local p = part.CFrame.Position
			local s = part.Size
			table.insert(parts, string.format(
				"%s|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f",
				part.Name, p.X, p.Y, p.Z, s.X, s.Y, s.Z,
				part.CFrame.LookVector.X, part.CFrame.LookVector.Y, part.CFrame.LookVector.Z
			))
		end)
		return table.concat(parts, ";")
	end

	T.test("every kind and colour stays within the part budget", function()
		eachCase(function(kind, id, colorIndex, storeType)
			local model = build(kind, id, colorIndex, storeType)
			local count = H.count(model, "BasePart")
			local budget = kind == "house" and HOUSE_BUDGET or STORE_BUDGET
			T.le(count, budget, kind .. " " .. tostring(storeType) .. " colour " .. colorIndex .. " id " .. id)
		end)
	end)

	T.test("every part is anchored, non-colliding and casts no shadow", function()
		eachCase(function(kind, id, colorIndex, storeType)
			local model = build(kind, id, colorIndex, storeType)
			eachBasePart(model, function(part)
				T.ok(part.Anchored, part.Name .. " anchored")
				T.falsy(part.CanCollide, part.Name .. " no collision")
				T.falsy(part.CanQuery, part.Name .. " not queryable")
				T.falsy(part.CanTouch, part.Name .. " not touchable")
				T.falsy(part.CastShadow, part.Name .. " casts no shadow")
			end)
		end)
	end)

	T.test("every part stays inside its cell footprint", function()
		eachCase(function(kind, id, colorIndex, storeType)
			local model = build(kind, id, colorIndex, storeType)
			eachBasePart(model, function(part)
				for _, corner in ipairs(cornersOf(part)) do
					local label = kind .. " " .. tostring(storeType) .. " " .. part.Name
					T.le(math.abs(corner.X), HALF_CELL + 1e-3, label .. " x inside cell")
					T.le(math.abs(corner.Z), HALF_CELL + 1e-3, label .. " z inside cell")
					T.ok(corner.Y > 0.3 and corner.Y < 0.7, label .. " sits above the roads and below the caps")
				end
			end)
		end)
	end)

	T.test("houses never exceed two thirds of a cell", function()
		for id = 1, 16 do
			local model = build("house", id, 1, nil)
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			eachBasePart(model, function(part)
				if part.Name == "Body" then
					for _, corner in ipairs(cornersOf(part)) do
						minX, maxX = math.min(minX, corner.X), math.max(maxX, corner.X)
						minZ, maxZ = math.min(minZ, corner.Z), math.max(maxZ, corner.Z)
					end
				end
			end)
			T.le(maxX - minX, Config.Grid.TileSize * 0.66 + 1e-3, "house width for id " .. id)
			T.le(maxZ - minZ, Config.Grid.TileSize * 0.66 + 1e-3, "house depth for id " .. id)
		end
	end)

	T.test("colours come from the palette, the white accents, or the shadow tone", function()
		for colorIndex, palette in ipairs(Config.HouseColors) do
			local allowed = { palette.color, palette.base or palette.color, WHITE, SHADOW }
			for id = 1, 8 do
				for _, storeType in ipairs({ nil, "small", "large" }) do
					local kind = storeType and "store" or "house"
					local model = build(kind, id, colorIndex, storeType)
					eachBasePart(model, function(part)
						local known = false
						for _, color in ipairs(allowed) do
							if sameColor(part.Color, color) then
								known = true
								break
							end
						end
						T.ok(known, kind .. " part " .. part.Name .. " uses an unknown colour")
					end)
				end
			end
		end
	end)

	T.test("the body of a house or a store keeps the colour of its group", function()
		for colorIndex, palette in ipairs(Config.HouseColors) do
			local house = build("house", 3, colorIndex, nil)
			T.ok(sameColor(house.PrimaryPart.Color, palette.color), "house body colour " .. palette.name)
			for _, storeType in ipairs({ "small", "large" }) do
				local store = build("store", 3, colorIndex, storeType)
				T.ok(sameColor(store.PrimaryPart.Color, palette.color), storeType .. " store colour " .. palette.name)
			end
		end
	end)

	T.test("shadows are soft: transparency between 0.65 and 0.85", function()
		eachCase(function(kind, id, colorIndex, storeType)
			local model = build(kind, id, colorIndex, storeType)
			eachBasePart(model, function(part)
				if part.Name == "Shadow" then
					T.ge(part.Transparency, 0.65, "shadow not too dense")
					T.le(part.Transparency, 0.85, "shadow not too faint to be visible")
				end
			end)
		end)
	end)

	T.test("shadows fall down-right by the same offset for every kind", function()
		for _, case in ipairs({ { "house", nil }, { "store", "small" }, { "store", "large" } }) do
			local model = build(case[1], 5, 1, case[2])
			local shadow = model:FindFirstChild("Shadow")
			local offset = shadow.CFrame.Position - model.PrimaryPart.CFrame.Position
			T.ok(offset.X > 0 and offset.Z > 0, case[1] .. " shadow falls down-right")
			T.near(offset.X, offset.Z, 1e-3, case[1] .. " shadow offset is diagonal")
			T.ok(offset.X < 0.2, case[1] .. " shadow offset stays discreet")
		end
	end)

	T.test("houses and small stores have rounded corners, large stores are discs", function()
		local function cylinders(model)
			local count = 0
			eachBasePart(model, function(part)
				if part.Name == "Body" and part.Shape == Enum.PartType.Cylinder then
					count += 1
				end
			end)
			return count
		end
		T.eq(cylinders(build("house", 2, 1, nil)), 4, "a house body has four rounded corners")
		T.eq(cylinders(build("store", 2, 1, "small")), 4, "a small store has four rounded corners")
		T.eq(cylinders(build("store", 2, 1, "large")), 1, "a large store body is one disc")
	end)

	T.test("the same id and colour always give the same model", function()
		for id = 1, 8 do
			T.eq(signature(build("house", id, 2, nil)), signature(build("house", id, 2, nil)))
			T.eq(signature(build("store", id, 2, "small")), signature(build("store", id, 2, "small")))
		end
	end)

	T.test("houses of one colour use several distinct variants", function()
		local seen = {}
		local count = 0
		for id = 1, 4 do
			local body = build("house", id, 1, nil).PrimaryPart
			local key = string.format("%.3f,%.3f", body.Size.X, body.Size.Z)
			if not seen[key] then
				seen[key] = true
				count += 1
			end
		end
		T.ge(count, 3, "at least three footprint variants per colour")
	end)

	T.test("house orientation is a multiple of a quarter turn", function()
		for id = 0, 15 do
			local look = build("house", id, 1, nil).PrimaryPart.CFrame.LookVector
			T.ok(math.abs(look.X) < 1e-3 or math.abs(look.Z) < 1e-3, "axis-aligned house " .. id)
		end
	end)

	T.test("the entrance pad sits on the requested side", function()
		local east = build("house", 3, 1, nil, { entranceAngle = math.pi * 0.5 })
		local entrance = east:FindFirstChild("Entrance")
		T.ok(entrance, "the house has an entrance pad")
		T.ok(entrance.CFrame.Position.X > 0.5, "east side")
		T.near(entrance.CFrame.Position.Z, 0, 1e-3)

		local north = build("store", 3, 1, "small", { entranceAngle = math.pi })
		local pad = north:FindFirstChild("Entrance")
		T.ok(pad.CFrame.Position.Z < -0.5, "north side for a small store")
		T.near(pad.CFrame.Position.X, 0, 1e-3)
	end)

	T.test("the model name and attributes identify the building", function()
		local house = build("house", 7, 4, nil)
		T.eq(house.Name, "house_7")
		T.eq(house:GetAttribute("BuildingKind"), "house")
		T.eq(house:GetAttribute("ColorIndex"), 4)

		local large = build("store", 7, 4, "large")
		T.eq(large.Name, "store_7_large")
		T.eq(large:GetAttribute("StoreType"), "large")
	end)

	T.test("a large store is a disc, a small store is a square, both bigger than a house", function()
		local small = build("store", 1, 1, "small")
		local large = build("store", 1, 1, "large")
		local house = build("house", 1, 1, nil)

		local disc = large:FindFirstChild("Body")
		T.eq(disc.Shape, Enum.PartType.Cylinder, "large store body is a disc")
		T.near(disc.Size.Y, disc.Size.Z, 1e-3, "the disc is round")

		local function footprint(model)
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			eachBasePart(model, function(part)
				if part.Name == "Body" then
					for _, corner in ipairs(cornersOf(part)) do
						minX, maxX = math.min(minX, corner.X), math.max(maxX, corner.X)
						minZ, maxZ = math.min(minZ, corner.Z), math.max(maxZ, corner.Z)
					end
				end
			end)
			return maxX - minX, maxZ - minZ
		end

		local smallW, smallD = footprint(small)
		T.near(smallW, smallD, 1e-3, "the small store is square")
		local houseW = footprint(house)
		local largeW = footprint(large)
		T.gt(smallW, houseW * 1.2, "a small store is clearly bigger than a house")
		T.gt(largeW, houseW * 1.2, "a large store is clearly bigger than a house")
	end)
end
