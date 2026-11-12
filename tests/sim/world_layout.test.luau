return function(T, H)
	-- Parties 6.1, 6.2 et 7 du cahier des charges : un plateau clair et uniforme,
	-- une grille fine alignée sur les cases, et aucun décor parasite.

	local DYNAMIC = { Buildings = true, Roads = true, Cars = true, FX = true }
	local BANNED = {
		BorderHatch = true,
		MapLabelStrip = true,
		Paper = true,
		Backdrop = true,
		WaterMaskTop = true,
		WaterMaskBottom = true,
		WaterMaskLeft = true,
		WaterMaskRight = true,
		MapLipTop = true,
		MapLipBottom = true,
		MapLipLeft = true,
		MapLipRight = true,
	}

	local function luminance(c)
		return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	end

	local function sameColor(a, b)
		return math.abs(a.R - b.R) < 1e-4 and math.abs(a.G - b.G) < 1e-4 and math.abs(a.B - b.B) < 1e-4
	end

	local function paletteHas(color)
		for _, value in pairs(H.load("Config").Colors) do
			if sameColor(value, color) then
				return true
			end
		end
		return false
	end

	-- Pièces du décor (sans routes, bâtiments, voitures ni effets).
	local function terrainParts(session)
		local list = {}
		for _, child in ipairs(session.world.folder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(list, child)
			elseif not DYNAMIC[child.Name] then
				for _, d in ipairs(child:GetDescendants()) do
					if d:IsA("BasePart") then
						table.insert(list, d)
					end
				end
			end
		end
		return list
	end

	T.test("the world exposes every folder, the grid included", function()
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			local world = session.world
			for _, key in ipairs({ "Buildings", "Roads", "Cars", "FX", "Water", "Grass", "Grid" }) do
				T.ok(world[key] and world[key]:IsA("Folder"), map.id .. ": world." .. key)
				T.ok(world[key]:IsDescendantOf(world.folder), map.id .. ": " .. key .. " lives in the city folder")
			end
			T.eq(world.Grid.Name, "Grid")
			T.eq(world.folder:FindFirstChild("Grid"), world.Grid)
		end
	end)

	T.test("no hatched border, side label, paper or water-mask layer remains", function()
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			for _, d in ipairs(session.world.folder:GetDescendants()) do
				T.falsy(BANNED[d.Name], map.id .. ": leftover " .. d.Name)
			end
			T.eq(#H.find(session.world.folder, { class = "SurfaceGui" }), 0, map.id .. ": no SurfaceGui on the terrain")
		end
	end)

	T.test("the board is one light, uniform slab with a soft edge shadow on a background tone", function()
		local C = H.load("Config").Colors
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			local folder = session.world.folder
			local extent = session.size * session.tile
			local ground = folder:FindFirstChild("Ground")
			T.ok(ground, map.id .. ": ground")
			T.eq(#H.find(folder, { name = "Ground" }), 1, map.id .. ": one ground")
			T.near(ground.Size.X, extent, 1e-6, map.id .. ": board width")
			T.near(ground.Size.Z, extent, 1e-6, map.id .. ": board depth")
			T.ok(ground.CanQuery, map.id .. ": the mouse ray must hit the board")
			T.falsy(ground.CanCollide, map.id .. ": the board has no physics")
			T.gt(luminance(ground.Color), 0.9, map.id .. ": the board is very light")

			local shadows = H.find(folder, { name = "BoardShadow" })
			T.ge(#shadows, 1, map.id .. ": board shadow")
			for _, shadow in ipairs(shadows) do
				T.ge(shadow.Transparency, 0.7, map.id .. ": the edge shadow stays low-alpha")
				T.gt(shadow.Size.X, extent, map.id .. ": the shadow surrounds the board")
			end

			local backdrop = H.find(folder, { name = "Background" })
			T.eq(#backdrop, 1, map.id .. ": one background plate")
			T.gt(backdrop[1].Size.X, extent, map.id .. ": background larger than the board")
			T.ok(not sameColor(backdrop[1].Color, ground.Color), map.id .. ": background tone differs from the board")
			T.ok(sameColor(backdrop[1].Color, C.Background), map.id .. ": background uses the palette background")
		end
	end)

	T.test("the grid has one line per interior cell border, all in the Grid folder", function()
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			local vertical = H.find(session.world.Grid, { name = "GridV" })
			local horizontal = H.find(session.world.Grid, { name = "GridH" })
			T.eq(#vertical, session.size - 1, map.id .. ": vertical lines")
			T.eq(#horizontal, session.size - 1, map.id .. ": horizontal lines")
			T.eq(#H.find(session.world.folder, { name = "GridV" }), #vertical, map.id .. ": no grid line outside the Grid folder")
		end
	end)

	T.test("grid lines sit exactly on the cell borders used by Grid.center", function()
		local Grid = H.load("Grid")
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			local origin, tile, size = session.origin, session.tile, session.size
			local seen = {}
			for _, line in ipairs(H.find(session.world.Grid, { name = "GridV" })) do
				local offset = (line.Position.X - origin.X) / tile
				T.near(offset, math.floor(offset + 0.5), 1e-6, map.id .. ": vertical line off the cell grid")
				seen[math.floor(offset + 0.5)] = true
			end
			for _, line in ipairs(H.find(session.world.Grid, { name = "GridH" })) do
				local offset = (line.Position.Z - origin.Z) / tile
				T.near(offset, math.floor(offset + 0.5), 1e-6, map.id .. ": horizontal line off the cell grid")
			end
			-- Chaque bord intérieur existe, et le centre d'une case tombe entre deux bords.
			for i = 1, size - 1 do
				T.ok(seen[i], map.id .. ": missing border " .. i)
			end
			for x = 0, size - 1 do
				local center = Grid.center(origin, x, 0)
				local between = (center.X - origin.X) / tile - x
				T.near(between, 0.5, 1e-6, map.id .. ": cell centre is not between its borders")
			end
		end
	end)

	T.test("the grid is hair-thin, faint and rises only while building", function()
		local terrain = H.load("Config").Terrain
		local C = H.load("Config").Colors
		T.le(terrain.GridLineWidth, 0.05, "grid lines are at most 0.05 stud")
		T.ge(terrain.GridBaseTransparency, 0.6, "grid is faint in normal play")
		T.lt(terrain.GridActiveTransparency, terrain.GridBaseTransparency, "building makes the grid more visible")
		T.lt(math.abs(luminance(C.GridTerrain) - luminance(C.Land)), 0.05, "grid colour is close to the terrain")
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			local grid = session.world.Grid
			T.near(grid:GetAttribute("BaseTransparency"), terrain.GridBaseTransparency, 1e-9, map.id .. ": base attribute")
			T.near(grid:GetAttribute("ActiveTransparency"), terrain.GridActiveTransparency, 1e-9, map.id .. ": active attribute")
			for _, line in ipairs(H.find(grid, { class = "BasePart" })) do
				T.le(math.min(line.Size.X, line.Size.Z), 0.05, map.id .. ": " .. line.Name .. " is too thick")
				T.near(line.Transparency, terrain.GridBaseTransparency, 1e-9, map.id .. ": line transparency")
				T.ok(sameColor(line.Color, C.GridTerrain), map.id .. ": grid colour token")
			end
		end
	end)

	T.test("terrain parts are anchored, non-colliding, shadowless and use palette colours", function()
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			for _, part in ipairs(terrainParts(session)) do
				local label = map.id .. ": " .. part.Name
				T.ok(part.Anchored, label .. " anchored")
				T.falsy(part.CanCollide, label .. " CanCollide")
				T.falsy(part.CastShadow, label .. " CastShadow")
				if part.Name ~= "Ground" then
					T.falsy(part.CanQuery, label .. " CanQuery")
				end
				T.ok(paletteHas(part.Color), label .. " colour is not a palette token")
			end
		end
	end)

	T.test("terrain sits between the board shadow and the grass, nothing floats above the roads", function()
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			for _, part in ipairs(terrainParts(session)) do
				-- Demi-hauteur réelle : une pièce tournée (disque d'arbre) a son axe ailleurs que Size.Y.
				local cf = part.CFrame
				local halfY = math.abs(cf.RightVector.Y) * part.Size.X * 0.5
					+ math.abs(cf.UpVector.Y) * part.Size.Y * 0.5
					+ math.abs(cf.LookVector.Y) * part.Size.Z * 0.5
				T.ge(part.Position.Y - halfY, -2, map.id .. ": " .. part.Name .. " too deep")
				T.le(part.Position.Y + halfY, 0.25, map.id .. ": " .. part.Name .. " too high")
			end
		end
	end)

	-- Les rectangles et barres sont rognés au bord par WorldBuilder ; une ellipse
	-- ne peut pas l'être avec une Part : Maps.luau doit donc garder chaque
	-- ellipse dans le plateau.
	T.test("water, parks and trees stay inside the board", function()
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			local origin = session.origin
			local extent = session.size * session.tile
			for _, part in ipairs(terrainParts(session)) do
				if part.Name ~= "Background" and part.Name ~= "BoardShadow" and part.Name ~= "Ground" then
					-- Boîte englobante réelle : un disque couché (Cylinder) a son
					-- épaisseur sur X local, ses diamètres sur Y et Z.
					local right, up, look = part.CFrame.RightVector, part.CFrame.UpVector, part.CFrame.LookVector
					local halfX = math.abs(right.X) * part.Size.X * 0.5
						+ math.abs(up.X) * part.Size.Y * 0.5
						+ math.abs(look.X) * part.Size.Z * 0.5
					local halfZ = math.abs(right.Z) * part.Size.X * 0.5
						+ math.abs(up.Z) * part.Size.Y * 0.5
						+ math.abs(look.Z) * part.Size.Z * 0.5
					local label = map.id .. ": " .. part.Name .. " at " .. part.Position.X .. "," .. part.Position.Z
					T.ge(part.Position.X - halfX, origin.X - 1e-3, label .. " hangs over the west edge")
					T.le(part.Position.X + halfX, origin.X + extent + 1e-3, label .. " hangs over the east edge")
					T.ge(part.Position.Z - halfZ, origin.Z - 1e-3, label .. " hangs over the north edge")
					T.le(part.Position.Z + halfZ, origin.Z + extent + 1e-3, label .. " hangs over the south edge")
				end
			end
		end
	end)
end
