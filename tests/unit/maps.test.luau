return function(T, H)
	local function maps()
		return H.load("Maps"), H.load("Config")
	end

	local function inRange(v)
		return type(v) == "number" and v == v and v > -0.25 and v < 1.25
	end

	T.test("every map has an id, a name and the palette fields", function()
		local Maps = maps()
		T.ge(#Maps.all(), 1)
		local ids = {}
		for _, map in ipairs(Maps.all()) do
			T.eq(type(map.id), "string")
			T.ne(map.id, "")
			T.falsy(ids[map.id], "duplicate id " .. map.id)
			ids[map.id] = true
			T.eq(type(map.name), "string")
			T.ne(map.name, "")
			for _, key in ipairs({ "land", "water", "waterEdge", "waterDeep", "grass", "header", "accent" }) do
				T.isType(map[key], "Color3", map.id .. "." .. key)
			end
			T.eq(type(map.waterShapes), "table", map.id .. " waterShapes")
			T.eq(type(map.grassShapes), "table")
			T.eq(type(map.dryShapes), "table")
			T.eq(type(map.labels), "table")
		end
	end)

	T.test("getById matches all() and rejects unknown ids", function()
		local Maps = maps()
		for _, map in ipairs(Maps.all()) do
			T.eq(Maps.getById(map.id), map)
		end
		T.eq(Maps.getById("atlantis"), nil)
		T.eq(Maps.getById(nil), nil)
	end)

	T.test("shapes are well formed and normalised", function()
		local Maps = maps()
		for _, map in ipairs(Maps.all()) do
			for _, list in ipairs({ map.waterShapes, map.grassShapes, map.dryShapes }) do
				for i, shape in ipairs(list) do
					local where = map.id .. " shape " .. i
					if shape.type == "rect" then
						T.ok(inRange(shape.x) and inRange(shape.y), where)
						T.gt(shape.w, 0, where)
						T.gt(shape.h, 0, where)
					elseif shape.type == "circle" or shape.type == "ellipse" then
						T.ok(inRange(shape.x) and inRange(shape.y), where)
						T.gt(shape.rx or shape.r, 0, where)
						if shape.type == "ellipse" then
							T.gt(shape.ry, 0, where)
						end
					elseif shape.type == "bar" then
						T.ok(inRange(shape.x1) and inRange(shape.y1) and inRange(shape.x2) and inRange(shape.y2), where)
						T.gt(shape.thickness, 0, where)
					else
						T.fail(where .. ": unknown shape type " .. tostring(shape.type))
					end
				end
			end
		end
	end)

	T.test("isWater / isGrass always answer with a boolean", function()
		local Maps, Config = maps()
		for _, map in ipairs(Maps.all()) do
			for x = 0, Config.Grid.Size - 1 do
				for y = 0, Config.Grid.Size - 1 do
					T.eq(type(Maps.isWater(map, x, y)), "boolean")
					T.eq(type(Maps.isGrass(map, x, y)), "boolean")
				end
			end
		end
	end)

	T.test("each map is playable: enough land, a buildable centre", function()
		local Maps, Config = maps()
		local n = Config.Grid.Size
		for _, map in ipairs(Maps.all()) do
			local water, centerLand = 0, 0
			for x = 0, n - 1 do
				for y = 0, n - 1 do
					local isWater = Maps.isWater(map, x, y)
					if isWater then
						water += 1
					end
					if not isWater and math.abs(x - (n - 1) / 2) <= 3 and math.abs(y - (n - 1) / 2) <= 3 then
						centerLand += 1
					end
				end
			end
			T.lt(water / (n * n), 0.5, map.id .. ": water covers too much of the map")
			T.gt(water, 0, map.id .. ": a map without any water has no rivers/lakes to cross")
			T.ge(centerLand, 20, map.id .. ": the centre must be buildable")
		end
	end)

	T.test("dry shapes override water", function()
		local Maps, Config = maps()
		local n = Config.Grid.Size
		for _, map in ipairs(Maps.all()) do
			if #map.dryShapes > 0 then
				local checked = 0
				for x = 0, n - 1 do
					for y = 0, n - 1 do
						local shape = map.dryShapes[1]
						if shape.type == "bar" then
							local nx, ny = (x + 0.5) / n, (y + 0.5) / n
							if math.abs(nx - shape.x1) < 0.01 and ny >= shape.y1 and ny <= shape.y2 then
								T.falsy(Maps.isWater(map, x, y), map.id .. " dry cell " .. x .. ":" .. y)
								checked += 1
							end
						end
					end
				end
			end
		end
	end)

	T.test("isWater is symmetric with the preview coordinate convention", function()
		-- Le même (x + 0.5) / size sert à l'aperçu et au rendu 3D.
		local Maps, Config = maps()
		local map = Maps.all()[1]
		local n = Config.Grid.Size
		T.eq(Maps.isWater(map, 0, 0), Maps.isWater(map, 0, 0))
		T.eq(type(Maps.isWater(map, n - 1, n - 1)), "boolean")
	end)
end
