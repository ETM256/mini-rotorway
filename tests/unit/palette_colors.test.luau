-- Palette centrale (Config.Colors) et couleurs des maisons (Config.HouseColors).
-- Ces tests protègent la direction artistique : pastel, routes anthracite,
-- contraste route / sol, maisons reconnaissables de loin.
return function(T, H)
	-- Groupes de la palette, dans l'ordre de Config.luau. Chaque groupe a
	-- une borne de saturation (HSV) : le terrain et l'interface restent doux.
	local GROUPS = {
		terrain = { keys = { "Background", "GridLine", "Land", "Paper", "BorderStripe", "Cream", "Coast", "GridTerrain" }, maxSaturation = 0.2 },
		uiNeutral = {
			keys = { "White", "Panel", "PanelSoft", "PanelDark", "Border", "Ink", "InkSoft", "CardShadow", "BuildingShadow", "LobbyBackground", "LobbyGrid", "LobbyRoadShadow", "RingShadow" },
			maxSaturation = 0.25,
		},
		roads = { keys = { "Road", "Bridge", "RoadEdge", "RoadContour", "BridgeEdge" }, maxSaturation = 0.2, maxValue = 0.3, minValue = 0.12 },
		water = { keys = { "Water", "WaterDeep", "WaterEdge", "WaterPale", "Ring" }, maxSaturation = 0.35, minValue = 0.7 },
		vegetation = { keys = { "Grass", "Park", "TreeDark", "TreeLight" }, maxSaturation = 0.4, minValue = 0.7 },
		accents = { keys = { "Teal", "TealDark", "Orange", "Danger", "LobbyButton", "LobbyButtonDark", "LobbyOrange" }, maxSaturation = 0.7 },
	}

	-- Les seuls doublons de valeur autorisés : des alias voulus dans Config.luau.
	local ALIAS_SETS = {
		{ "White", "Panel", "RoadEdge", "RoadContour", "BridgeEdge", "LobbyRoad" },
		{ "Road", "Bridge" },
		{ "Paper", "BorderStripe" },
	}

	-- Luminance relative WCAG : les composantes Color3 sont en sRGB, il faut
	-- les linéariser avant de pondérer.
	local function linear(c)
		if c <= 0.04045 then
			return c / 12.92
		end
		return ((c + 0.055) / 1.055) ^ 2.4
	end

	local function relativeLuminance(color)
		return 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
	end

	local function contrastRatio(a, b)
		local la, lb = relativeLuminance(a), relativeLuminance(b)
		local light, dark = math.max(la, lb), math.min(la, lb)
		return (light + 0.05) / (dark + 0.05)
	end

	local function rgbDistance(a, b)
		return math.sqrt((a.R - b.R) ^ 2 + (a.G - b.G) ^ 2 + (a.B - b.B) ^ 2)
	end

	local function hueDegrees(color)
		local hue = color:ToHSV()
		return hue * 360
	end

	local function circularHueGap(a, b)
		local gap = math.abs(a - b) % 360
		return math.min(gap, 360 - gap)
	end

	T.test("palette: every token is a Color3 with channels in 0..1", function()
		local C = H.load("Config").Colors
		local count = 0
		for key, value in pairs(C) do
			T.isType(value, "Color3", "Config.Colors." .. key)
			for _, channel in ipairs({ value.R, value.G, value.B }) do
				T.ok(channel >= 0 and channel <= 1, "channel out of range in " .. key)
			end
			count += 1
		end
		T.ge(count, 40, "the central palette covers every surface")
	end)

	T.test("palette: every group token exists in Config.Colors", function()
		local C = H.load("Config").Colors
		for groupName, group in pairs(GROUPS) do
			for _, key in ipairs(group.keys) do
				T.isType(C[key], "Color3", groupName .. "." .. key)
			end
		end
	end)

	T.test("palette: terrain is off-white / very light (low saturation, high value)", function()
		local C = H.load("Config").Colors
		for _, key in ipairs(GROUPS.terrain.keys) do
			local _, saturation, value = C[key]:ToHSV()
			T.le(saturation, GROUPS.terrain.maxSaturation, "terrain " .. key .. " saturation")
			T.ge(value, 0.85, "terrain " .. key .. " must be very light")
		end
	end)

	T.test("palette: interface neutrals stay desaturated", function()
		local C = H.load("Config").Colors
		for _, key in ipairs(GROUPS.uiNeutral.keys) do
			local _, saturation = C[key]:ToHSV()
			T.le(saturation, GROUPS.uiNeutral.maxSaturation, "UI " .. key .. " saturation")
		end
	end)

	T.test("palette: roads are uniform dark anthracite, slightly desaturated, not black", function()
		local C = H.load("Config").Colors
		local road = C.Road
		for _, key in ipairs(GROUPS.roads.keys) do
			local _, saturation, value = C[key]:ToHSV()
			if key == "Road" or key == "Bridge" then
				T.le(saturation, GROUPS.roads.maxSaturation, key .. " saturation")
				T.le(value, GROUPS.roads.maxValue, key .. " must stay very dark")
				T.ge(value, GROUPS.roads.minValue, key .. " must not be pure black")
			end
		end
		T.eq(C.Bridge, road, "bridges use the same anthracite as roads")
	end)

	T.test("palette: water is turquoise pastel / very light blue", function()
		local C = H.load("Config").Colors
		for _, key in ipairs(GROUPS.water.keys) do
			local _, saturation, value = C[key]:ToHSV()
			T.le(saturation, GROUPS.water.maxSaturation, "water " .. key .. " saturation")
			T.ge(value, GROUPS.water.minValue, "water " .. key .. " value")
		end
	end)

	T.test("palette: vegetation is soft green / sage (no fluorescent green)", function()
		local C = H.load("Config").Colors
		for _, key in ipairs(GROUPS.vegetation.keys) do
			local _, saturation, value = C[key]:ToHSV()
			T.le(saturation, GROUPS.vegetation.maxSaturation, "vegetation " .. key .. " saturation")
			T.ge(value, GROUPS.vegetation.minValue, "vegetation " .. key .. " value")
		end
	end)

	-- La teinte, pas seulement la saturation, dit « turquoise / bleu » ou
	-- « vert » : un gris ou un jaune saturé passerait les tests ci-dessus.
	T.test("palette: water hue sits in the turquoise-to-pale-blue band", function()
		local C = H.load("Config").Colors
		for _, key in ipairs(GROUPS.water.keys) do
			local hue = hueDegrees(C[key])
			T.ge(hue, 150, "water " .. key .. " hue")
			T.le(hue, 215, "water " .. key .. " hue")
		end
	end)

	T.test("palette: vegetation hue sits in the green-to-sage band", function()
		local C = H.load("Config").Colors
		for _, key in ipairs(GROUPS.vegetation.keys) do
			local hue = hueDegrees(C[key])
			T.ge(hue, 60, "vegetation " .. key .. " hue")
			T.le(hue, 150, "vegetation " .. key .. " hue")
		end
	end)

	-- Fluorescent = saturation proche de 1 ; 0.7 laisse passer les accents
	-- moderés tout en refusant les couleurs criardes.
	T.test("palette: no token is fluorescent (saturation capped everywhere, accents included)", function()
		local C = H.load("Config").Colors
		for key, color in pairs(C) do
			local _, saturation = color:ToHSV()
			T.le(saturation, 0.7, "saturation of " .. key)
		end
	end)

	T.test("palette: accents are few and moderate", function()
		local C = H.load("Config").Colors
		for _, key in ipairs(GROUPS.accents.keys) do
			local _, saturation = C[key]:ToHSV()
			T.le(saturation, GROUPS.accents.maxSaturation, "accent " .. key)
		end
	end)

	T.test("palette: road vs terrain contrast ratio is at least 4 (WCAG)", function()
		local C = H.load("Config").Colors
		T.ge(contrastRatio(C.Road, C.Land), 4, "road on land")
		T.ge(contrastRatio(C.Road, C.Paper), 4, "road on paper")
		T.ge(contrastRatio(C.Road, C.Background), 4, "road on background")
		T.ge(contrastRatio(C.Water, C.Road), 4, "water versus road")
	end)

	T.test("palette: road edges stay light so the dark ribbon reads on any ground", function()
		local C = H.load("Config").Colors
		T.ge(contrastRatio(C.RoadEdge, C.Road), 4, "edge versus road")
	end)

	T.test("palette: a token value is shared only through a declared alias", function()
		local C = H.load("Config").Colors
		local byHex = {}
		for key, color in pairs(C) do
			local hex = color:ToHex()
			byHex[hex] = byHex[hex] or {}
			table.insert(byHex[hex], key)
		end
		for hex, keys in pairs(byHex) do
			if #keys > 1 then
				local allowed = false
				for _, set in ipairs(ALIAS_SETS) do
					local lookup = {}
					for _, name in ipairs(set) do
						lookup[name] = true
					end
					local every = true
					for _, key in ipairs(keys) do
						if not lookup[key] then
							every = false
						end
					end
					if every then
						allowed = true
					end
				end
				T.ok(allowed, "accidental duplicate " .. hex .. ": " .. table.concat(keys, ", "))
			end
		end
	end)

	T.test("house colours: eight entries with unique names and colours", function()
		local colors = H.load("Config").HouseColors
		T.eq(#colors, 8, "one store colour per house family")
		local names, hexes = {}, {}
		for i, entry in ipairs(colors) do
			T.eq(type(entry.name), "string", "entry " .. i .. " name")
			T.falsy(names[entry.name], "duplicate name " .. entry.name)
			names[entry.name] = true
			T.isType(entry.color, "Color3", entry.name .. ".color")
			T.isType(entry.base, "Color3", entry.name .. ".base")
			T.falsy(hexes[entry.color:ToHex()], "duplicate colour " .. entry.name)
			hexes[entry.color:ToHex()] = true
		end
	end)

	T.test("house colours: pastel band (moderate saturation, bright)", function()
		for _, entry in ipairs(H.load("Config").HouseColors) do
			local _, saturation, value = entry.color:ToHSV()
			T.ge(saturation, 0.25, entry.name .. " must not be washed out")
			T.le(saturation, 0.52, entry.name .. " must stay pastel")
			T.ge(value, 0.85, entry.name .. " must be bright")
			local _, baseSaturation, baseValue = entry.base:ToHSV()
			T.ge(baseSaturation, 0.25, entry.name .. " base saturation")
			T.le(baseSaturation, 0.6, entry.name .. " base must stay pastel")
			T.ge(baseValue, 0.7, entry.name .. " base value")
			T.lt(baseValue, value, entry.name .. " base must read darker than the roof")
		end
	end)

	T.test("house colours: hue separation of at least 20 degrees pairwise", function()
		local colors = H.load("Config").HouseColors
		for i = 1, #colors do
			for j = i + 1, #colors do
				local gap = circularHueGap(hueDegrees(colors[i].color), hueDegrees(colors[j].color))
				T.ge(gap, 20, colors[i].name .. " vs " .. colors[j].name .. " hue gap")
			end
		end
	end)

	T.test("house colours: pairwise RGB distance of at least 0.18 (recognisable from afar)", function()
		local colors = H.load("Config").HouseColors
		for i = 1, #colors do
			for j = i + 1, #colors do
				local distance = rgbDistance(colors[i].color, colors[j].color)
				T.ge(distance, 0.18, colors[i].name .. " vs " .. colors[j].name)
			end
		end
	end)

	T.test("house colours: roof bases stay distinct from each other", function()
		local colors = H.load("Config").HouseColors
		for i = 1, #colors do
			for j = i + 1, #colors do
				local distance = rgbDistance(colors[i].base, colors[j].base)
				T.ge(distance, 0.12, "base " .. colors[i].name .. " vs " .. colors[j].name)
			end
		end
	end)

	T.test("house colours: the eight hues are the brief's families", function()
		local hues = {}
		for _, entry in ipairs(H.load("Config").HouseColors) do
			table.insert(hues, hueDegrees(entry.color))
		end
		-- Rouge, orange, jaune, vert, turquoise, bleu, violet, rose : chaque
		-- famille doit avoir une teinte dans son secteur.
		local sectors = { { 340, 15 }, { 15, 40 }, { 40, 75 }, { 75, 140 }, { 140, 190 }, { 190, 235 }, { 235, 300 }, { 300, 340 } }
		for index, sector in ipairs(sectors) do
			local found = false
			for _, hue in ipairs(hues) do
				local inSector
				if sector[1] < sector[2] then
					inSector = hue >= sector[1] and hue < sector[2]
				else
					inSector = hue >= sector[1] or hue < sector[2]
				end
				if inSector then
					found = true
				end
			end
			T.ok(found, "no house colour in hue family #" .. index)
		end
	end)

	T.test("palette: the grid stays discreet next to the background", function()
		local C = H.load("Config").Colors
		local ratio = contrastRatio(C.GridLine, C.Background)
		T.gt(ratio, 1.03, "grid must still be visible while building")
		T.lt(ratio, 1.25, "grid must stay discreet")
	end)
end
