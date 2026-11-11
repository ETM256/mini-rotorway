return function(T, H)
	-- Parties 6.3 à 6.6 du cahier des charges : l'eau suit les formes de Maps,
	-- les arbres restent dans les parcs, hors de l'eau, et le décor est
	-- identique d'une construction à l'autre.

	local function treesOf(session)
		return H.find(session.world.folder, { name = "Tree" })
	end

	T.test("water fill covers every cell that Maps.isWater calls water", function()
		local Maps, Grid = H.load("Maps"), H.load("Grid")
		local FILL_CENTER_Y = 0.08
		for _, map in ipairs(Maps.all()) do
			H.reset()
			local session = H.newSession(map.id)
			local fills = H.find(session.world.Water, { name = "Water" })
			T.ok(#fills > 0 or #map.waterShapes == 0, map.id .. ": water fill exists")
			for y = 0, session.size - 1 do
				for x = 0, session.size - 1 do
					if Maps.isWater(map, x, y) then
						local point = Grid.center(session.origin, x, y, FILL_CENTER_Y)
						local covered = false
						for _, fill in ipairs(fills) do
							local localPoint = fill.CFrame:PointToObjectSpace(point)
							if math.abs(localPoint.X) <= fill.Size.X * 0.5 + 1e-6 and math.abs(localPoint.Z) <= fill.Size.Z * 0.5 + 1e-6 then
								covered = true
								break
							end
						end
						T.ok(covered, map.id .. ": water cell " .. x .. ":" .. y .. " has no water fill")
					end
				end
			end
		end
	end)

	T.test("the shoreline is a thin light ring (at most 0.35 stud)", function()
		local terrain = H.load("Config").Terrain
		T.gt(terrain.Shoreline, 0)
		T.le(terrain.Shoreline, 0.35)
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			for _, shore in ipairs(H.find(session.world.Water, { name = "Shore" })) do
				T.ok(shore.Transparency == 0, map.id .. ": shoreline is opaque but thin")
			end
		end
	end)

	T.test("no tree is drawn on water, on any map", function()
		local Maps, Grid = H.load("Maps"), H.load("Grid")
		for _, map in ipairs(Maps.all()) do
			H.reset()
			local session = H.newSession(map.id)
			for _, tree in ipairs(treesOf(session)) do
				local x, y = Grid.cellFromWorld(session.origin, tree.Position)
				T.falsy(Maps.isWater(map, x, y), map.id .. ": tree on water at " .. x .. ":" .. y)
			end
		end
	end)

	T.test("trees stand in park cells only, with their whole footprint on land", function()
		local Maps, Grid = H.load("Maps"), H.load("Grid")
		for _, map in ipairs(Maps.all()) do
			H.reset()
			local session = H.newSession(map.id)
			for _, tree in ipairs(treesOf(session)) do
				-- Le disque de l'arbre (diamètre en Size.Y / Size.Z) : centre et bords.
				local radius = tree.Size.Y * 0.5
				for _, dx in ipairs({ -radius, 0, radius }) do
					for _, dz in ipairs({ -radius, 0, radius }) do
						local x, y = Grid.cellFromWorld(session.origin, tree.Position + Vector3.new(dx, 0, dz))
						T.ok(x >= 0 and y >= 0 and x < session.size and y < session.size, map.id .. ": tree outside the board")
						T.ok(Maps.isGrass(map, x, y), map.id .. ": tree outside a park at " .. x .. ":" .. y)
						T.falsy(Maps.isWater(map, x, y), map.id .. ": tree footprint touches water at " .. x .. ":" .. y)
					end
				end
			end
		end
	end)

	T.test("trees are sparse, small and never overlap", function()
		local Config = H.load("Config")
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			local trees = treesOf(session)
			T.le(#trees, 60, map.id .. ": do not overload the map with trees")
			for i, tree in ipairs(trees) do
				T.le(math.max(tree.Size.Y, tree.Size.Z), Config.Grid.TileSize * 1.5, "trees stay small")
				for j = i + 1, #trees do
					local d = (tree.Position - trees[j].Position).Magnitude
					T.ge(d, 1.5, map.id .. ": two trees overlap")
				end
			end
		end
	end)

	T.test("every tree has a shadow disc under it, with very low opacity", function()
		local terrain = H.load("Config").Terrain
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			local trees = treesOf(session)
			local shadows = H.find(session.world.Grass, { name = "TreeShadow" })
			T.eq(#shadows, #trees, map.id .. ": one shadow per tree")
			for _, shadow in ipairs(shadows) do
				T.ge(shadow.Transparency, 0.75, map.id .. ": shadows stay very faint")
				T.near(shadow.Transparency, terrain.TreeShadowTransparency, 1e-9, map.id .. ": shadow uses the configured opacity")
			end
		end
	end)

	T.test("the same map always gets the same trees (seeded by the map id, not math.random)", function()
		local function layout(mapId)
			H.reset()
			H.seed(999)
			local session = H.newSession(mapId)
			local keys = {}
			for _, tree in ipairs(treesOf(session)) do
				table.insert(keys, string.format("%.4f,%.4f,%.4f", tree.Position.X, tree.Position.Z, tree.Size.Y))
			end
			return table.concat(keys, ";")
		end
		for _, map in ipairs(H.load("Maps").all()) do
			local first = layout(map.id)
			T.ok(#first > 0 or #map.grassShapes == 0, map.id .. ": parks have trees")
			T.eq(layout(map.id), first, map.id .. ": trees differ between two builds")
		end
	end)

	T.test("world.treeCells lists exactly the cells holding a tree", function()
		local Grid = H.load("Grid")
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			local fromParts = {}
			for _, tree in ipairs(treesOf(session)) do
				local x, y = Grid.cellFromWorld(session.origin, tree.Position)
				fromParts[Grid.key(x, y)] = true
			end
			local count = 0
			for key in pairs(session.world.treeCells) do
				count += 1
				T.ok(fromParts[key], map.id .. ": stale tree cell " .. key)
			end
			for key in pairs(fromParts) do
				T.ok(session.world.treeCells[key], map.id .. ": tree cell missing " .. key)
			end
			T.le(count, #treesOf(session), map.id .. ": more tree cells than trees")
		end
	end)

	-- Construit un monde sur une carte de test (formes libres), sans toucher à Maps.
	local function buildCustom(map)
		local Config = H.load("Config")
		H.reset()
		local session = {
			origin = Vector3.new(0, 0, 0),
			size = Config.Grid.Size,
			tile = Config.Grid.TileSize,
			map = map,
			worldIndex = 1,
		}
		return H.load("WorldBuilder").build(session), session
	end

	local function customMap(id, waterShapes)
		local C = H.load("Config").Colors
		return {
			id = id,
			land = C.Land,
			water = C.Water,
			grass = C.Park,
			waterShapes = waterShapes,
			dryShapes = {},
			grassShapes = {},
		}
	end

	T.test("a water bar leaving the board keeps Maps' geometry on the board", function()
		local Maps, Grid = H.load("Maps"), H.load("Grid")
		local map = customMap("edge_bar", {
			{ type = "bar", x1 = 0.5, y1 = 0.5, x2 = 1.3, y2 = 0.1, thickness = 0.06 },
		})
		local world, session = buildCustom(map)
		local extent = session.size * session.tile
		local fills = H.find(world.Water, { name = "Water" })
		T.ok(#fills > 0, "the bar is drawn")
		-- Le bout coupé est carré : ses coins peuvent dépasser le bord d'au plus une
		-- demi-largeur de barre, jamais davantage.
		for _, fill in ipairs(fills) do
			local halfX = math.abs(fill.CFrame.RightVector.X) * fill.Size.X * 0.5 + math.abs(fill.CFrame.LookVector.X) * fill.Size.Z * 0.5
			local halfZ = math.abs(fill.CFrame.RightVector.Z) * fill.Size.X * 0.5 + math.abs(fill.CFrame.LookVector.Z) * fill.Size.Z * 0.5
			local overhangs = {
				session.origin.X - (fill.Position.X - halfX),
				(fill.Position.X + halfX) - (session.origin.X + extent),
				session.origin.Z - (fill.Position.Z - halfZ),
				(fill.Position.Z + halfZ) - (session.origin.Z + extent),
			}
			for _, overhang in ipairs(overhangs) do
				T.le(overhang, fill.Size.X * 0.5 + 1e-3, "bar overhangs the board by more than half its width")
			end
		end
		for y = 0, session.size - 1 do
			for x = 0, session.size - 1 do
				if Maps.isWater(map, x, y) then
					local point = Grid.center(session.origin, x, y, 0.08)
					local covered = false
					for _, fill in ipairs(fills) do
						local localPoint = fill.CFrame:PointToObjectSpace(point)
						if math.abs(localPoint.X) <= fill.Size.X * 0.5 + 1e-6 and math.abs(localPoint.Z) <= fill.Size.Z * 0.5 + 1e-6 then
							covered = true
							break
						end
					end
					T.ok(covered, "water cell " .. x .. ":" .. y .. " is not drawn")
				end
			end
		end
	end)

	T.test("the shoreline ring adds exactly Config.Terrain.Shoreline on each side of the water", function()
		local shoreline = H.load("Config").Terrain.Shoreline
		local world = buildCustom(customMap("lake", {
			{ type = "ellipse", x = 0.5, y = 0.5, rx = 0.2, ry = 0.1, rotation = 0 },
		}))
		local shores = H.find(world.Water, { name = "Shore" })
		local fills = H.find(world.Water, { name = "Water" })
		T.eq(#shores, 1, "one shoreline for one lake")
		T.eq(#fills, 1, "one fill for one lake")
		-- Une ellipse est un disque plat : son épaisseur est sur X, ses diamètres sur Y et Z.
		T.eq(shores[1].Shape, Enum.PartType.Cylinder, "a lake is a flat disc, not a dome")
		T.near((shores[1].Size.Y - fills[1].Size.Y) * 0.5, shoreline, 1e-6, "shoreline width on the long axis")
		T.near((shores[1].Size.Z - fills[1].Size.Z) * 0.5, shoreline, 1e-6, "shoreline width on the short axis")
	end)

	T.test("parks with room for a tree get at least one tree", function()
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			if #map.grassShapes > 0 then
				T.ge(#treesOf(session), 1, map.id .. ": no tree at all")
			end
		end
	end)

	-- La zone de départ, au centre (4 x 4 cases), reste dégagée d'arbres.
	T.test("no tree stands in the start area at the centre", function()
		local Grid = H.load("Grid")
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			local first = math.floor((session.size - 4) / 2)
			for _, tree in ipairs(treesOf(session)) do
				local x, y = Grid.cellFromWorld(session.origin, tree.Position)
				local inStart = x >= first and x < first + 4 and y >= first and y < first + 4
				T.falsy(inStart, map.id .. ": tree in the start area at " .. x .. ":" .. y)
			end
		end
	end)
end
