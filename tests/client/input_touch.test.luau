return function(T, H)
	-- Écran tactile : un doigt trace une route (même chemin que la souris, via le
	-- remote DrawRoad) ; un second doigt ne démarre jamais un tracé.

	local function boot()
		H.runScript("Bootstrap")
		H.asClient()
		H.runScript("Main")
		H.advance(0.1)
		H.fireServer("StartGame", "los_angeles")
		H.advance(0.5)
	end

	local function screenOf(x, y)
		local Config = H.load("Config")
		local origin = H.lastSent("GameStarted").origin
		local world = origin + Vector3.new((x + 0.5) * Config.Grid.TileSize, 0, (y + 0.5) * Config.Grid.TileSize)
		local point = workspace.CurrentCamera:WorldToViewportPoint(world)
		return point.X, point.Y
	end

	-- Ligne de 6 cases libres d'après les bâtiments connus du client.
	local function freeRow()
		local road = H.lastSent("RoadState")
		local Maps = H.load("Maps")
		local map = Maps.getById("los_angeles")
		local blocked = {}
		for _, key in ipairs(road.buildings) do
			blocked[key] = true
		end
		for y = 1, 16 do
			local run = 0
			for x = 0, 17 do
				if blocked[x .. ":" .. y] or Maps.isWater(map, x, y) then
					run = 0
				else
					run += 1
					if run == 6 then
						return x - 5, y
					end
				end
			end
		end
		return nil, nil
	end

	T.test("a single finger draws a road through the DrawRoad remote", function()
		boot()
		local x, y = freeRow()
		T.ok(x, "a free row of 6 cells is needed")
		local sx, sy = screenOf(x, y)
		H.input.touchBegin(1, sx, sy)
		for i = 1, 3 do
			local mx, my = screenOf(x + i, y)
			H.input.touchMove(1, mx, my)
		end
		H.input.touchEnd(1, screenOf(x + 3, y))
		H.advance(0.3)
		local sent = H.sent("DrawRoad", "toServer")
		T.eq(#sent, 1, "one stroke, one DrawRoad")
		local cells = sent[1][1]
		T.eq(#cells, 4, "four cells from the start to the last finger position")
		for i, cell in ipairs(cells) do
			T.eq(cell[1], x + i - 1, "column of cell " .. i)
			T.eq(cell[2], y, "row of cell " .. i)
		end
	end)

	T.test("a second finger while one is down does not start a build", function()
		boot()
		local x, y = freeRow()
		T.ok(x, "a free row of 6 cells is needed")
		H.input.touchBegin(1, screenOf(x, y))
		H.input.touchBegin(2, screenOf(x + 4, y))
		H.input.touchMove(1, screenOf(x + 1, y))
		H.input.touchMove(1, screenOf(x + 2, y))
		H.input.touchEnd(1, screenOf(x + 2, y))
		H.input.touchEnd(2, screenOf(x + 4, y))
		H.advance(0.3)
		T.eq(#H.sent("DrawRoad", "toServer"), 0, "the second finger cancels the stroke; nothing is sent")
	end)
end
