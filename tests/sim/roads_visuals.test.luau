return function(T, H)
	-- Voisines diagonales (non reliées) après effacement, et accord entre l'aperçu
	-- client et la règle serveur (eau, ponts, budget).

	local function countKeys(t)
		local n = 0
		for _ in pairs(t) do
			n += 1
		end
		return n
	end

	-- Deux cases de terre en diagonale, libres (ni bâtiment, ni route).
	local function diagonalPair(session)
		local Grid, Maps = H.load("Grid"), H.load("Maps")
		local function free(x, y)
			local key = Grid.key(x, y)
			return Grid.inBounds(x, y)
				and not session.buildings[key]
				and not session.roads[key]
				and not Maps.isWater(session.map, x, y)
		end
		for x = 0, session.size - 2 do
			for y = 0, session.size - 2 do
				if free(x, y) and free(x + 1, y + 1) then
					return x, y
				end
			end
		end
		return nil
	end

	T.test("a diagonal neighbour is not connected: erasing a cell leaves its visuals alone", function()
		local session = H.newSession("los_angeles")
		local Grid = H.load("Grid")
		local x, y = diagonalPair(session)
		T.ok(x, "two free diagonal dry cells")
		session:drawRoad({ { x, y } })
		session:drawRoad({ { x + 1, y + 1 } })
		local diagonal = Grid.key(x + 1, y + 1)
		local before = session.roadParts[diagonal]
		T.ok(before and #before > 0, "the diagonal road has visual parts")
		session:eraseRoad(Grid.key(x, y))
		T.ok(session.roadParts[diagonal] == before, "an isolated block keeps the very same parts")
		T.eq(session.roadParts[Grid.key(x, y)], nil, "the erased cell has no parts")
	end)

	T.todo("client preview and server agree on water, missing bridges and budget (needs the rewritten InputController.planCells: input PR)", function()
		local session = H.newSession("los_angeles")
		local Grid, Maps = H.load("Grid"), H.load("Maps")
		local length = 12

		-- Une ligne de `length` cases libres qui traverse au moins deux cases d'eau.
		local line = nil
		for y = 0, session.size - 1 do
			for startX = 0, session.size - length do
				local cells, water, free = {}, 0, true
				for i = 0, length - 1 do
					local x = startX + i
					local key = Grid.key(x, y)
					if session.buildings[key] then
						free = false
						break
					end
					if Maps.isWater(session.map, x, y) then
						water += 1
					end
					cells[#cells + 1] = { x, y }
				end
				if free and water >= 2 then
					line = cells
					break
				end
			end
			if line then
				break
			end
		end
		T.ok(line, "a free line of twelve cells crossing water")

		local buildings = {}
		for _, building in ipairs(session.buildingList) do
			buildings[#buildings + 1] = building.key
		end
		local startBudget, startBridges = 10, 1
		session.budget = startBudget
		session.bridgesLeft = startBridges

		-- Côté serveur : les cases réellement posées.
		session:drawRoad(line)
		local serverKeys = {}
		for key in pairs(session.roads) do
			serverKeys[key] = true
		end

		-- Côté client : l'aperçu du même tracé, avec les mêmes réserves.
		H.asClient()
		H.setViewport(1280, 720)
		local InputController = H.load("InputController")
		local input = InputController.new({
			onDraw = function() end,
			onEraseMany = function() end,
		})
		input:setMapId("los_angeles")
		input:applyRoadState({
			roads = {},
			bridges = {},
			buildings = buildings,
			budget = startBudget,
			bridgesLeft = startBridges,
		})
		local previewKeys = {}
		for _, cell in ipairs(input:planCells(line)) do
			if cell.valid then
				previewKeys[Grid.key(cell.x, cell.y)] = true
			end
		end

		T.eq(countKeys(previewKeys), countKeys(serverKeys), "same number of accepted cells")
		for key in pairs(serverKeys) do
			T.ok(previewKeys[key], "the preview accepts what the server built: " .. key)
		end
		T.ok(countKeys(serverKeys) < length, "the rules really refuse part of the line")
		T.ok(countKeys(serverKeys) > 0, "and accept part of it")
	end)
end
