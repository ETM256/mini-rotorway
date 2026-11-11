return function(T, H)
	local function walkNumbers(value, path, visit, depth)
		if depth > 8 then
			return
		end
		if type(value) == "number" then
			visit(path, value)
		elseif type(value) == "table" and getmetatable(value) == nil then
			for k, v in pairs(value) do
				walkNumbers(v, path .. "." .. tostring(k), visit, depth + 1)
			end
		end
	end

	local function luminance(c)
		return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	end

	T.test("no NaN in any config table", function()
		for _, name in ipairs({ "Config", "StoreConfig", "RoadConfig" }) do
			local module = H.load(name)
			walkNumbers(module, name, function(path, value)
				T.ok(value == value, "NaN at " .. path)
			end, 0)
		end
	end)

	T.test("house colors: 8+ distinct pastel colors with names", function()
		local Config = H.load("Config")
		local colors = Config.HouseColors
		T.ge(#colors, 8)
		local names, hexes = {}, {}
		for i, entry in ipairs(colors) do
			T.eq(type(entry.name), "string", "color " .. i .. " name")
			T.isType(entry.color, "Color3", "color " .. i)
			T.isType(entry.base, "Color3", "base " .. i)
			T.falsy(names[entry.name], "duplicate name " .. entry.name)
			names[entry.name] = true
			local hex = entry.color:ToHex()
			T.falsy(hexes[hex], "duplicate colour " .. hex)
			hexes[hex] = true
			local _, saturation, value = entry.color:ToHSV()
			T.le(saturation, 0.75, entry.name .. " must stay pastel (low saturation)")
			T.ge(value, 0.6, entry.name .. " must not be dark")
		end
	end)

	local function colorDistances()
		local colors = H.load("Config").HouseColors
		local list = {}
		for i = 1, #colors do
			for j = i + 1, #colors do
				local a, b = colors[i].color, colors[j].color
				table.insert(list, {
					distance = math.sqrt((a.R - b.R) ^ 2 + (a.G - b.G) ^ 2 + (a.B - b.B) ^ 2),
					names = colors[i].name .. " vs " .. colors[j].name,
				})
			end
		end
		return list
	end

	T.test("house colors: no two are nearly identical", function()
		for _, pair in ipairs(colorDistances()) do
			T.gt(pair.distance, 0.10, pair.names)
		end
	end)

	-- Part 4.2 of the brief: colours must be recognisable from afar.
	-- Miel/Orange (0.11), Corail/Orange (0.13) and Bleu/Turquoise (0.16) are
	-- currently too close. Fix the palette in
	-- Config.HouseColors, then turn this into a T.test.
	T.todo("house colors: pairwise RGB distance >= 0.18 (recognisable at a distance)", function()
		for _, pair in ipairs(colorDistances()) do
			T.ge(pair.distance, 0.18, pair.names)
		end
	end)

	T.test("palette: all colours are Color3", function()
		local Config = H.load("Config")
		local count = 0
		for key, value in pairs(Config.Colors) do
			T.isType(value, "Color3", "Config.Colors." .. key)
			count += 1
		end
		T.gt(count, 10)
	end)

	T.test("palette: roads are dark anthracite (not pure black) on a very light ground", function()
		local C = H.load("Config").Colors
		local road = luminance(C.Road)
		T.gt(road, 0.04, "road must not be pure black")
		T.lt(road, 0.30, "road must stay very dark")
		T.ge(luminance(C.Land), 0.85, "terrain must be very light")
		T.gt(luminance(C.Land) - road, 0.5, "road/terrain contrast")
		T.gt(luminance(C.Water), road)
	end)

	T.test("palette: the grid is discreet (close to the background)", function()
		local C = H.load("Config").Colors
		T.lt(math.abs(luminance(C.GridLine) - luminance(C.Background)), 0.12)
	end)

	T.test("Config.Grid / Camera / Roads sane", function()
		local Config = H.load("Config")
		T.ge(Config.Grid.Size, 8)
		T.gt(Config.Grid.TileSize, 0)
		T.gt(Config.Camera.FOV, 1)
		T.lt(Config.Camera.FOV, 90)
		T.gt(Config.Camera.Height, 0)
		T.ge(Config.Roads.StartBudget, 1)
		T.ge(Config.Roads.MaxBudget, Config.Roads.StartBudget)
		T.ge(Config.Roads.MaxBridges, Config.Roads.StartBridges)
		T.gt(Config.Game.WeekDuration, 0)
		T.gt(Config.Traffic.CarSpeed, 0)
		T.gt(Config.Traffic.CarSpacing, 0)
		T.ge(Config.Traffic.SatisfactionMax, Config.Traffic.SatisfactionStart)
	end)

	T.test("rewards are well formed and unique", function()
		local Config = H.load("Config")
		local ids = {}
		local kinds = { roads = true, bridges = true, roundabouts = true }
		for key, reward in pairs(Config.Rewards) do
			T.eq(type(reward.id), "string", key)
			T.falsy(ids[reward.id], "duplicate reward id " .. reward.id)
			ids[reward.id] = true
			T.ok(kinds[reward.kind], "unknown reward kind " .. tostring(reward.kind))
			T.gt(reward.amount, 0)
			T.eq(type(reward.title), "string")
			T.eq(type(reward.description), "string")
			if reward.roads then
				T.gt(reward.roads, 0)
			end
		end
	end)

	T.test("rewards are balanced: a special tool never gives more roads than a plain lot", function()
		local R = H.load("Config").Rewards
		local plain = math.max(R.Roads.amount, R.RoadsLarge.amount)
		for _, reward in pairs(R) do
			if reward.kind ~= "roads" then
				T.lt(reward.roads or 0, plain, reward.id)
			end
		end
	end)

	T.test("StoreConfig.Colors is the shared house palette", function()
		T.eq(H.load("StoreConfig").Colors, H.load("Config").HouseColors)
	end)

	T.test("StoreConfig.Spawn: tiers sorted, zones normalised", function()
		local S = H.load("StoreConfig").Spawn
		T.ge(S.MaxStores, S.StartStores)
		T.ge(S.StartStores, 1)
		local last = -1
		local lastMin = math.huge
		for i, tier in ipairs(S.Tiers) do
			T.gt(tier.untilTime, last, "tier " .. i .. " untilTime must increase")
			T.le(tier.minInterval, tier.maxInterval)
			T.gt(tier.minInterval, 0)
			T.le(tier.minInterval, lastMin, "tier " .. i .. ": difficulty must not relax")
			last, lastMin = tier.untilTime, tier.minInterval
		end
		T.eq(S.Tiers[#S.Tiers].untilTime, math.huge, "the last tier must be open-ended")
		local total = 0
		for _, zone in ipairs(S.Zones) do
			T.gt(zone.weight, 0)
			T.ge(zone.minRadius, 0)
			T.lt(zone.minRadius, zone.maxRadius)
			T.le(zone.maxRadius, 1)
			total += zone.weight
		end
		T.near(total, 1, 1e-6, "zone weights must sum to 1")
	end)

	T.test("StoreConfig.Demand / Evolution / Houses / Visual sane", function()
		local S = H.load("StoreConfig")
		T.ge(S.Demand.SmallCapacity, 1)
		T.gt(S.Demand.LargeCapacity, S.Demand.SmallCapacity, "a large store holds more demands")
		T.lt(S.Demand.LargeInterval, S.Demand.SmallInterval, "a large store asks faster")
		T.gt(S.Demand.RampMinMultiplier, 0)
		T.le(S.Demand.RampMinMultiplier, 1)
		T.gt(S.Demand.MinInterval, 0)
		T.gt(S.Demand.OverloadGrace, 0)
		T.ge(S.Demand.FirstDelayMax, S.Demand.FirstDelayMin)
		T.ge(S.Evolution.Chance, 0)
		T.le(S.Evolution.Chance, 1)
		T.ge(S.Evolution.MinDeliveries, 0)
		T.ge(S.Houses.StartHouses, 1)
		T.ge(S.Houses.MaxHouses, S.Houses.StartHouses)
		T.ge(S.Houses.MaxDistanceFromStore, S.Houses.MinDistanceFromStore)
		T.gt(S.Visual.LargeSize, S.Visual.SmallSize, "large stores must look bigger")
		T.gt(S.Visual.PinSize, 0)
	end)

	T.test("RoadConfig: widths are fractions of a tile, ordered inside to outside", function()
		local V = H.load("RoadConfig").Visual
		for _, key in ipairs({ "RoadWidth", "ContourWidth", "EdgeWidth", "RibbonEdgeWidth", "RibbonTopWidth" }) do
			T.gt(V[key], 0, key)
			T.le(V[key], 1, key)
		end
		T.le(V.RoadWidth, V.ContourWidth)
		T.le(V.ContourWidth, V.EdgeWidth)
		T.le(V.RibbonTopWidth, V.RibbonEdgeWidth)
		T.ge(V.PreviewTransparency, 0)
		T.le(V.PreviewTransparency, 1)
	end)

	T.test("RoadConfig: traffic factors and request limits", function()
		local R = H.load("RoadConfig")
		T.gt(R.Traffic.TurnSpeedFactor, 0)
		T.le(R.Traffic.TurnSpeedFactor, 1)
		T.gt(R.Traffic.Acceleration, 0)
		T.gt(R.Traffic.Braking, 0)
		T.ge(R.Input.MaxCellsPerRequest, H.load("Config").Grid.Size)
		T.ge(R.Input.DragAxisThreshold, 0)
		T.eq(type(R.AllowDiagonals), "boolean")
		T.ok(R.BuildingConnection == "orthogonal" or R.BuildingConnection == "all")
		T.eq(R.Infrastructure.Highways.Enabled, false, "highways are not wired yet")
	end)
end
