return function(T, H)
	-- Partie 16 du cahier des charges : le décor statique doit rester léger.
	-- Avant la refonte, Los Angeles comptait 705 pièces dont 426 d'eau.

	local TERRAIN_BUDGET = 300
	local WATER_BUDGET = 120

	T.test("static terrain stays within the part budget on every map", function()
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			local count = 0
			for _, child in ipairs(session.world.folder:GetChildren()) do
				if child:IsA("BasePart") then
					count += 1
				elseif child.Name ~= "Buildings" and child.Name ~= "Roads" and child.Name ~= "Cars" and child.Name ~= "FX" then
					count += H.count(child, "BasePart")
				end
			end
			T.le(count, TERRAIN_BUDGET, map.id .. ": terrain uses " .. count .. " parts")
		end
	end)

	T.test("water uses few parts on every map (a capsule is three parts, an ellipse one)", function()
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			local water = H.count(session.world.Water, "BasePart")
			T.le(water, WATER_BUDGET, map.id .. ": water uses " .. water .. " parts")
		end
	end)

	-- Pas de liseré sombre ni de couche d'ombre : seule la côte est claire.
	T.test("the water has only a light shoreline, a fill and dry land layers", function()
		local C = H.load("Config").Colors
		local function isCoast(color)
			return math.abs(color.R - C.Coast.R) < 1e-4 and math.abs(color.G - C.Coast.G) < 1e-4 and math.abs(color.B - C.Coast.B) < 1e-4
		end
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			for _, part in ipairs(session.world.Water:GetDescendants()) do
				if part:IsA("BasePart") then
					T.ok(part.Name == "Shore" or part.Name == "Water" or part.Name == "Land", map.id .. ": unexpected water layer " .. part.Name)
					if part.Name == "Shore" then
						T.ok(isCoast(part.Color), map.id .. ": shoreline must be the light coast colour")
					end
				end
			end
		end
	end)
end
