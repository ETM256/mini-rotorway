return function(T, H)
	-- Aperçu de forme : chaque case est dessinée comme la route posée
	-- (RoadGeometry), sans recalcul des cases inchangées.

	local ORIGIN = Vector3.new(700, 0, 0)

	local function newPreview()
		H.asClient()
		local Config = H.load("Config")
		local preview = H.load("RoadPreview").new()
		preview:setWorld(ORIGIN, Config.Grid.TileSize)
		return preview
	end

	local function visibleParts()
		local list = {}
		for _, part in ipairs(workspace.MM_RoadPreview:GetChildren()) do
			if part.Transparency < 1 then
				table.insert(list, part)
			end
		end
		return list
	end

	local function near(a, b)
		return math.abs(a - b) < 1e-6
	end

	local function countShape(shape)
		local count = 0
		for _, part in ipairs(visibleParts()) do
			if part.Shape == shape then
				count += 1
			end
		end
		return count
	end

	-- Un serpentin de 60 cases (4 rangées de 15) : virages, T et croix compris.
	local function serpentine()
		local cells = {}
		for row = 0, 3 do
			for col = 0, 14 do
				local x = if row % 2 == 0 then col else 14 - col
				table.insert(cells, { x = x, y = row })
			end
		end
		return cells
	end

	T.test("a straight cell is a full-tile band of the road width", function()
		local Config = H.load("Config")
		local RoadConfig = H.load("RoadConfig")
		local tile = Config.Grid.TileSize
		local preview = newPreview()
		preview:setCells({ { x = 2, y = 3 }, { x = 3, y = 3 }, { x = 4, y = 3 } })
		local band = false
		for _, part in ipairs(visibleParts()) do
			if part.Shape == Enum.PartType.Block and near(part.Size.X, tile) and near(part.Size.Z, RoadConfig.Visual.RoadWidth * tile) then
				band = true
			end
		end
		T.ok(band, "a straight cell is one band of RoadWidth across its full length")
	end)

	T.test("a dead end ends in a round cap", function()
		newPreview():setCells({ { x = 3, y = 3 }, { x = 3, y = 4 } })
		T.ge(countShape(Enum.PartType.Cylinder), 2, "each end of the two-cell stroke has a cap")
	end)

	T.test("a corner is rounded on its outside: the corner cell holds a disk", function()
		local Config = H.load("Config")
		local tile = Config.Grid.TileSize
		newPreview():setCells({ { x = 3, y = 3 }, { x = 3, y = 2 }, { x = 4, y = 3 } })
		local cornerX = ORIGIN.X + 3 * tile
		local cornerZ = ORIGIN.Z + 3 * tile
		local disks = 0
		for _, part in ipairs(visibleParts()) do
			local p = part.Position
			if part.Shape == Enum.PartType.Cylinder
				and p.X >= cornerX and p.X <= cornerX + tile
				and p.Z >= cornerZ and p.Z <= cornerZ + tile
			then
				disks += 1
			end
		end
		T.ge(disks, 2, "the body and the edge of the corner are both round")
	end)

	T.test("a new cell next to an existing road reaches that road's edge", function()
		local Config = H.load("Config")
		local tile = Config.Grid.TileSize
		local preview = newPreview()
		preview:setRoads({ ["4:3"] = true })
		preview:setCells({ { x = 3, y = 3 } })
		-- Bras vers l'est : demi-case, de la centre à la bordure (x = 4 cases).
		local reaches = false
		for _, part in ipairs(visibleParts()) do
			if part.Shape == Enum.PartType.Block
				and near(part.Size.X, tile / 2)
				and near(part.Position.X, ORIGIN.X + 3.75 * tile)
			then
				reaches = true
			end
		end
		T.ok(reaches, "the arm stops exactly at the shared edge with the existing road")
	end)

	T.test("refused cells are coral and the hover cell is translucent, stroke cells opaque", function()
		local RoadConfig = H.load("RoadConfig")
		local preview = newPreview()
		preview:setCells({ { x = 3, y = 3, valid = false } })
		for _, part in ipairs(visibleParts()) do
			T.eq(part.Color, RoadConfig.Visual.PreviewInvalidColor)
			T.eq(part.Transparency, 0)
		end
		preview:setCells({ { x = 3, y = 3, hover = true } })
		for _, part in ipairs(visibleParts()) do
			T.near(part.Transparency, RoadConfig.Visual.PreviewHoverTransparency, 1e-6)
		end
	end)

	T.test("a 60-cell stroke keeps at most six pieces per cell", function()
		local cells = serpentine()
		newPreview():setCells(cells)
		T.le(#visibleParts(), 6 * #cells, "bounded by the shape of one cell")
		T.gt(#visibleParts(), #cells, "the stroke is drawn as shapes, not as one marker per cell")
	end)

	T.test("toggling between two strokes reuses the pool: no growth after the first cycle", function()
		local preview = newPreview()
		local first = serpentine()
		local second = {}
		for index, cell in ipairs(first) do
			second[index] = { x = cell.x, y = cell.y + 4 }
		end
		preview:setCells(first)
		preview:setCells(second)
		preview:setCells(first)
		preview:setCells(second)
		local settled = #workspace.MM_RoadPreview:GetChildren()
		for _ = 1, 5 do
			preview:setCells(first)
			preview:setCells(second)
		end
		T.eq(#workspace.MM_RoadPreview:GetChildren(), settled, "parts are reused, never recreated")
	end)

	T.test("a new cell far from the stroke leaves every other part untouched", function()
		local preview = newPreview()
		local stroke = serpentine()
		preview:setCells(stroke)
		local snapshot = {}
		for _, part in ipairs(visibleParts()) do
			snapshot[part] = { position = part.Position, size = part.Size }
		end
		local extended = table.clone(stroke)
		table.insert(extended, { x = 0, y = 15 })
		preview:setCells(extended)
		local moved = 0
		for part, before in pairs(snapshot) do
			if part.Transparency < 1 then
				if (part.Position - before.position).Magnitude > 1e-6 or (part.Size - before.size).Magnitude > 1e-6 then
					moved += 1
				end
			end
		end
		T.eq(moved, 0, "no existing piece was rebuilt")
	end)

	T.test("clear hides every piece and destroy removes the folder", function()
		local preview = newPreview()
		preview:setCells(serpentine())
		preview:clear()
		T.eq(#visibleParts(), 0)
		preview:destroy()
		T.eq(workspace:FindFirstChild("MM_RoadPreview"), nil)
	end)
end
