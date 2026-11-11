return function(T, H)
	-- Aperçu local (RoadPreview) : la forme de la route posée, en pièces de
	-- RoadGeometry, réparties dans les cases et prises dans un pool réutilisé.
	-- Les pièces sont plates, ancrées, sans collision ni ombre.

	local TILE = 4
	local ORIGIN = Vector3.new(700, 0, 0)

	local function newPreview()
		H.asClient()
		local preview = H.load("RoadPreview").new()
		preview:setWorld(ORIGIN, TILE)
		return preview
	end

	local function allParts()
		return workspace.MM_RoadPreview:GetChildren()
	end

	-- Pièces visibles (transparence < 1), dans l'ordre de création.
	local function visibleParts()
		local list = {}
		for _, part in ipairs(allParts()) do
			if part.Transparency < 1 then
				table.insert(list, part)
			end
		end
		return list
	end

	-- Bornes monde d'une case x, y : X et Z (le sol est en Y = origine).
	local function cellBounds(x, y)
		local minX = ORIGIN.X + x * TILE
		local minZ = ORIGIN.Z + y * TILE
		return minX, minX + TILE, minZ, minZ + TILE
	end

	-- Emprise au sol d'une pièce : min et max sur X et Z.
	-- Un cylindre est couché : son axe (Size.X) devient la hauteur, donc son
	-- diamètre est sur Y et Z.
	local function extents(part)
		local sx, sz
		if part.Shape == Enum.PartType.Cylinder then
			sx, sz = part.Size.Y, part.Size.Z
		else
			sx, sz = part.Size.X, part.Size.Z
		end
		local p = part.Position
		return p.X - sx / 2, p.X + sx / 2, p.Z - sz / 2, p.Z + sz / 2
	end

	-- Épaisseur d'une pièce (hauteur monde) : Size.X pour un cylindre couché.
	local function thickness(part)
		if part.Shape == Enum.PartType.Cylinder then
			return part.Size.X
		end
		return part.Size.Y
	end

	-- Vrai si le centre de la pièce tombe dans la case x, y.
	local function inCell(part, x, y)
		local minX, maxX, minZ, maxZ = cellBounds(x, y)
		local p = part.Position
		return p.X >= minX and p.X < maxX and p.Z >= minZ and p.Z < maxZ
	end

	-- Nombre maximal de pièces d'une case, sur tous les voisinages possibles
	-- (0 à 4 bras). Sert de borne au pool : pièces par case x cases.
	local function maxPiecesPerCell()
		local Grid = H.load("Grid")
		local RoadGeometry = H.load("RoadGeometry")
		local offsets = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
		local max = 0
		for mask = 0, 15 do
			local roads = { [Grid.key(5, 5)] = true }
			for arm, offset in ipairs(offsets) do
				if math.floor(mask / 2 ^ (arm - 1)) % 2 == 1 then
					roads[Grid.key(5 + offset[1], 5 + offset[2])] = true
				end
			end
			max = math.max(max, #RoadGeometry.cellPieces(roads, nil, nil, 5, 5))
		end
		return max
	end

	T.test("valid cells are mint, refused cells coral, placed exactly on the cell", function()
		local RoadConfig = H.load("RoadConfig")
		local preview = newPreview()
		preview:setCells({ { x = 2, y = 3, valid = true }, { x = 3, y = 3, valid = false } })

		-- Chaque case étant une extrémité de route (un bras, donc une tige et un
		-- capuchon), elle compte deux pièces par couche : liseré et surface.
		local validParts, refusedParts = {}, {}
		for _, part in ipairs(visibleParts()) do
			if inCell(part, 2, 3) then
				table.insert(validParts, part)
			elseif inCell(part, 3, 3) then
				table.insert(refusedParts, part)
			end
		end
		T.eq(#validParts, 4, "the valid cell: a stub and a cap, on the edge and on the body")
		T.eq(#refusedParts, 4, "the refused cell: a stub and a cap, on the edge and on the body")
		T.eq(#visibleParts(), 8, "no other piece is visible")

		local edgeHalf = RoadConfig.Visual.EdgeWidth * TILE / 2
		for _, part in ipairs(validParts) do
			T.eq(part.Color, RoadConfig.Visual.PreviewValidColor, "valid cells are mint")
		end
		for _, part in ipairs(refusedParts) do
			T.eq(part.Color, RoadConfig.Visual.PreviewInvalidColor, "refused cells are coral")
		end

		-- Chaque pièce reste dans sa case, et dans le couloir de la route (la
		-- route est horizontale : l'écart en Z ne dépasse pas le liseré).
		for _, cell in ipairs({ { 2, 3, validParts }, { 3, 3, refusedParts } }) do
			local x, y, parts = cell[1], cell[2], cell[3]
			local minX, maxX, minZ, maxZ = cellBounds(x, y)
			local centerZ = (minZ + maxZ) / 2
			local centerX = (minX + maxX) / 2
			local covered = false
			for _, part in ipairs(parts) do
				local x0, x1, z0, z1 = extents(part)
				T.ge(x0, minX - 1e-6, "piece starts inside its cell (west)")
				T.le(x1, maxX + 1e-6, "piece ends inside its cell (east)")
				T.ge(z0, minZ - 1e-6, "piece starts inside its cell (north)")
				T.le(z1, maxZ + 1e-6, "piece ends inside its cell (south)")
				T.ge(z0, centerZ - edgeHalf - 1e-6, "piece stays in the road corridor")
				T.le(z1, centerZ + edgeHalf + 1e-6, "piece stays in the road corridor")
				if x0 <= centerX and centerX <= x1 and z0 <= centerZ and centerZ <= z1 then
					covered = true
				end
			end
			T.ok(covered, "the centre of cell " .. x .. ":" .. y .. " is on the road")
		end
	end)

	T.test("clearing hides the preview and parts are reused (no growth)", function()
		local preview = newPreview()
		for i = 1, 50 do
			preview:setCells({ { x = i % 10, y = 1 }, { x = (i + 1) % 10, y = 1 } })
		end
		local bound = maxPiecesPerCell() * 2
		local pooled = #allParts()
		T.le(pooled, bound, "parts are bounded by pieces per cell x cells")
		preview:clear()
		T.eq(#visibleParts(), 0, "clear hides every piece")
		T.eq(#allParts(), pooled, "hidden pieces stay in the pool")

		-- Une nouvelle esquisse de même taille prend des pièces du pool.
		preview:setCells({ { x = 4, y = 4 }, { x = 5, y = 4 } })
		T.le(#allParts(), bound, "redrawing reuses the pool")
		T.ok(#visibleParts() > 0, "the redrawn preview is visible")
	end)

	T.test("shrinking the preview hides the extra parts", function()
		local preview = newPreview()
		preview:setCells({ { x = 1, y = 1 }, { x = 2, y = 1 }, { x = 3, y = 1 } })
		local three = #visibleParts()
		local pooled = #allParts()
		T.gt(three, 2, "three cells in a row draw more than one isolated cell")

		preview:setCells({ { x = 1, y = 1 } })
		-- Une case isolée : un disque sur le liseré et un sur la surface.
		T.eq(#visibleParts(), 2, "one isolated cell is a disc on the edge and one on the body")
		T.eq(#allParts(), pooled, "the extra pieces are hidden in the pool, not removed")
		for _, part in ipairs(allParts()) do
			if part.Transparency >= 1 then
				T.eq(part.Transparency, 1, "hidden pieces are fully transparent")
			end
		end

		preview:setCells(nil)
		T.eq(#visibleParts(), 0, "no cell left: nothing is visible")
	end)

	T.test("malformed cells are ignored; destroy removes the folder", function()
		local preview = newPreview()
		T.noThrow(function()
			preview:setCells({ "x", 5, {}, { x = 1 } })
		end)
		T.eq(#visibleParts(), 0)
		preview:destroy()
		T.eq(workspace:FindFirstChild("MM_RoadPreview"), nil)
	end)

	T.test("preview parts are flat, non-colliding and cast no shadow", function()
		local RoadConfig = H.load("RoadConfig")
		local preview = newPreview()
		preview:setCells({ { x = 1, y = 1 }, { x = 2, y = 1 } })
		local parts = visibleParts()
		T.gt(#parts, 0, "there are pieces to check")
		for _, part in ipairs(parts) do
			T.falsy(part.CanCollide, "non-colliding")
			T.falsy(part.CanQuery, "not queried by the pointer")
			T.falsy(part.CanTouch, "does not touch")
			T.ok(part.Anchored, "anchored")
			T.falsy(part.CastShadow, "casts no shadow")
			T.le(thickness(part), 0.5, "a surface, not a block")
			T.near(thickness(part), RoadConfig.Visual.PreviewHeight, 1e-6, "the configured flat height")
		end
	end)
end
