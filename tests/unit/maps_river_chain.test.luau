return function(T, H)
	-- Partie 6.4 du cahier des charges : une rivière est une bande continue, du
	-- bord nord au bord sud, large de une à deux cases. Les tests lisent la règle
	-- de construction (Maps.isWater), la même que le rendu et l'aperçu.

	local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

	-- Cases d'eau atteignables depuis le bord nord (4 voisins).
	local function waterFromNorth(Maps, map, n)
		local seen = {}
		local queue = {}
		for x = 0, n - 1 do
			if Maps.isWater(map, x, 0) then
				seen[x] = true
				table.insert(queue, { x, 0 })
			end
		end
		local head = 1
		local reachesSouth = false
		while head <= #queue do
			local cx, cy = queue[head][1], queue[head][2]
			head += 1
			if cy == n - 1 then
				reachesSouth = true
			end
			for _, d in ipairs(NEIGHBOURS) do
				local nx, ny = cx + d[1], cy + d[2]
				local key = ny * n + nx
				if nx >= 0 and ny >= 0 and nx < n and ny < n and not seen[key] and Maps.isWater(map, nx, ny) then
					seen[key] = true
					table.insert(queue, { nx, ny })
				end
			end
		end
		return reachesSouth
	end

	-- Largeur d'une rivière : nombre d'eau par ligne, dans une bande de colonnes.
	local function widthsOf(Maps, map, rows, cols)
		local widths = {}
		for y = rows[1], rows[2] do
			local count = 0
			for x = cols[1], cols[2] do
				if Maps.isWater(map, x, y) then
					count += 1
				end
			end
			table.insert(widths, count)
		end
		return widths
	end

	T.test("the dubai and los angeles rivers form one band from the north edge to the south edge", function()
		local Maps, Config = H.load("Maps"), H.load("Config")
		local n = Config.Grid.Size
		for _, id in ipairs({ "dubai", "los_angeles" }) do
			T.ok(waterFromNorth(Maps, Maps.getById(id), n), id .. ": the river must not stop short of the south edge")
		end
	end)

	T.test("the dubai and los angeles rivers are one or two cells wide", function()
		local Maps = H.load("Maps")
		-- Dubaï : la rivière descend à travers les lignes au-dessus du golfe.
		-- Los Angeles : la côte ouest prend le relais plus bas, on mesure le haut.
		local bands = {
			dubai = { rows = { 0, 13 }, cols = { 0, 8 } },
			los_angeles = { rows = { 0, 5 }, cols = { 0, 7 } },
		}
		for id, band in pairs(bands) do
			for i, count in ipairs(widthsOf(Maps, Maps.getById(id), band.rows, band.cols)) do
				T.ge(count, 1, id .. " row " .. (band.rows[1] + i - 1) .. ": the river is cut")
				T.le(count, 2, id .. " row " .. (band.rows[1] + i - 1) .. ": the river is wider than two cells")
			end
		end
	end)
end
