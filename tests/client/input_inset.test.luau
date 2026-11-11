return function(T, H)
	-- Barre supérieure Roblox (GUI inset) : le harnais n'en a pas
	-- (ScreenPointToRay == ViewportPointToRay), ce qui cacherait un décalage d'une
	-- barre dans la visée. Ici la caméra simulée a un inset réel, et les entrées
	-- suivent la règle de Roblox :
	--   * UserInputService:GetMouseLocation() : coordonnées de VUE (barre incluse) ;
	--   * InputObject.Position (souris et doigt) : coordonnées ÉCRAN (barre déduite) ;
	--   * Camera:ScreenPointToRay attend l'écran, ViewportPointToRay la vue.
	-- Un contrôleur qui visait avec GetMouseLocation + ScreenPointToRay serait
	-- décalé d'une barre : la route apparaîtrait une barre trop bas.

	local INSET = Vector2.new(0, 58)
	local I, W = H.I, H.W
	local UIS_EVENTS = { began = "InputBegan", changed = "InputChanged", ended = "InputEnded" }

	-- Caméra du harnais (voir tests/harness/classes.luau) + inset sur les points
	-- « écran ». Le même code, sans inset, est remis en place à la fin.
	local function installCamera(inset)
		local function basis(camera)
			local view = W.viewport
			return camera.CFrame, math.tan(math.rad(camera.FieldOfView) / 2), view.X / view.Y, view
		end
		I.implement("Camera", {
			defaults = { FieldOfView = 70 },
			getters = {
				ViewportSize = function()
					return W.viewport
				end,
			},
			methods = {
				ViewportPointToRay = function(self, x, y)
					local cf, tanHalf, aspect, view = basis(self)
					local ndcX = (x / view.X) * 2 - 1
					local ndcY = 1 - (y / view.Y) * 2
					local direction = cf:VectorToWorldSpace(Vector3.new(ndcX * tanHalf * aspect, ndcY * tanHalf, -1)).Unit
					return Ray.new(cf.Position, direction)
				end,
				WorldToViewportPoint = function(self, position)
					local cf, tanHalf, aspect, view = basis(self)
					local localPos = cf:PointToObjectSpace(position)
					local depth = -localPos.Z
					local ndcX = localPos.X / (depth * tanHalf * aspect)
					local ndcY = localPos.Y / (depth * tanHalf)
					return Vector3.new((ndcX * 0.5 + 0.5) * view.X, (0.5 - ndcY * 0.5) * view.Y, depth),
						math.abs(ndcX) <= 1 and math.abs(ndcY) <= 1
				end,
				ScreenPointToRay = function(self, x, y)
					return self:ViewportPointToRay(x + inset.X, y + inset.Y)
				end,
				WorldToScreenPoint = function(self, position)
					local point, onScreen = self:WorldToViewportPoint(position)
					return Vector3.new(point.X - inset.X, point.Y - inset.Y, point.Z), onScreen
				end,
			},
		})
	end

	local function withInset(body)
		installCamera(INSET)
		local ok, err = pcall(body)
		installCamera(Vector2.zero)
		if not ok then
			error(err, 0)
		end
	end

	local function boot()
		H.runScript("Bootstrap")
		H.asClient()
		H.runScript("Main")
		H.advance(0.1)
		H.fireServer("StartGame", "los_angeles")
		H.advance(0.5)
	end

	-- Point d'écran (InputObject.Position) au centre d'une case.
	local function screenOfCell(x, y)
		local Config = H.load("Config")
		local origin = H.lastSent("GameStarted").origin
		local world = origin + Vector3.new((x + 0.5) * Config.Grid.TileSize, 0.1, (y + 0.5) * Config.Grid.TileSize)
		local point = workspace.CurrentCamera:WorldToScreenPoint(world)
		return Vector2.new(point.X, point.Y)
	end

	local function fire(kind, inputType, state, screen, delta)
		local input = {
			UserInputType = inputType,
			UserInputState = state,
			KeyCode = Enum.KeyCode.Unknown,
			Position = Vector3.new(screen.X, screen.Y, 0),
			Delta = delta or Vector3.zero,
		}
		I.fire(I.getSignal(game.UserInputService, UIS_EVENTS[kind]), input, false)
		return input
	end

	-- Souris réelle : GetMouseLocation en vue, Position en écran.
	local mouse = {}
	function mouse.move(screen)
		local old = W.mouse
		W.mouse = screen + INSET
		fire("changed", Enum.UserInputType.MouseMovement, Enum.UserInputState.Change, screen, Vector3.new(screen.X + INSET.X - old.X, screen.Y + INSET.Y - old.Y, 0))
	end
	function mouse.down(screen, button)
		W.mouse = screen + INSET
		local inputType = button == 2 and Enum.UserInputType.MouseButton2 or Enum.UserInputType.MouseButton1
		W.buttonsDown[inputType.Name] = true
		fire("began", inputType, Enum.UserInputState.Begin, screen)
	end
	function mouse.up(screen, button)
		W.mouse = screen + INSET
		local inputType = button == 2 and Enum.UserInputType.MouseButton2 or Enum.UserInputType.MouseButton1
		W.buttonsDown[inputType.Name] = nil
		fire("ended", inputType, Enum.UserInputState.End, screen)
	end

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

	-- Cases couvertes par l'aperçu affiché.
	local function previewCells()
		local Config = H.load("Config")
		local origin = H.lastSent("GameStarted").origin
		local cells = {}
		for _, part in ipairs(H.find(workspace, { name = "RoadPreviewCell" })) do
			if part.Transparency < 1 then
				local x = math.floor((part.Position.X - origin.X) / Config.Grid.TileSize)
				local y = math.floor((part.Position.Z - origin.Z) / Config.Grid.TileSize)
				cells[x .. ":" .. y] = true
			end
		end
		return cells
	end

	T.test("the test camera really offsets screen and viewport points", function()
		withInset(function()
			boot()
			local camera = workspace.CurrentCamera
			local screen = camera:ScreenPointToRay(400, 300)
			local viewport = camera:ViewportPointToRay(400, 300)
			T.ne(screen.Direction, viewport.Direction, "screen and viewport rays differ when there is an inset")
			local same = camera:ViewportPointToRay(400 + INSET.X, 300 + INSET.Y)
			T.near((screen.Direction - same.Direction).Magnitude, 0, 1e-9)
		end)
	end)

	T.test("hovering previews the cell under the cursor, not one bar lower", function()
		withInset(function()
			boot()
			local x, y = freeRow()
			T.ok(x, "a free row of 6 cells is needed")
			mouse.move(screenOfCell(x + 2, y))
			H.advance(0.2)
			local cells = previewCells()
			T.ok(cells[(x + 2) .. ":" .. y], "the hovered cell is previewed")
			local count = 0
			for _ in pairs(cells) do
				count += 1
			end
			T.eq(count, 1, "only the hovered cell is previewed")
		end)
	end)

	T.test("a mouse stroke draws exactly the cells the cursor crossed", function()
		withInset(function()
			boot()
			local x, y = freeRow()
			T.ok(x, "a free row of 6 cells is needed")
			mouse.move(screenOfCell(x, y))
			mouse.down(screenOfCell(x, y), 1)
			for i = 1, 4 do
				mouse.move(screenOfCell(x + i, y))
			end
			mouse.up(screenOfCell(x + 4, y), 1)
			H.advance(0.3)
			local sent = H.sent("DrawRoad", "toServer")
			T.eq(#sent, 1, "one stroke, one DrawRoad")
			local cells = sent[1][1]
			T.eq(#cells, 5, "five cells from the press to the release")
			for i, cell in ipairs(cells) do
				T.eq(cell[1], x + i - 1, "column of cell " .. i)
				T.eq(cell[2], y, "row of cell " .. i)
			end
		end)
	end)

	T.test("a finger stroke draws exactly the cells the finger crossed", function()
		withInset(function()
			boot()
			local x, y = freeRow()
			T.ok(x, "a free row of 6 cells is needed")
			local start = screenOfCell(x, y)
			H.input.touchBegin(1, start.X, start.Y)
			for i = 1, 3 do
				local at = screenOfCell(x + i, y)
				H.input.touchMove(1, at.X, at.Y)
			end
			local last = screenOfCell(x + 3, y)
			H.input.touchEnd(1, last.X, last.Y)
			H.advance(0.3)
			local sent = H.sent("DrawRoad", "toServer")
			T.eq(#sent, 1, "one stroke, one DrawRoad")
			local cells = sent[1][1]
			T.eq(#cells, 4, "four cells from the press to the release")
			for i, cell in ipairs(cells) do
				T.eq(cell[1], x + i - 1, "column of cell " .. i)
				T.eq(cell[2], y, "row of cell " .. i)
			end
		end)
	end)

	T.test("a right-click erase picks the roads under the cursor", function()
		withInset(function()
			boot()
			local x, y = freeRow()
			T.ok(x, "a free row of 6 cells is needed")
			mouse.move(screenOfCell(x, y))
			mouse.down(screenOfCell(x, y), 1)
			for i = 1, 3 do
				mouse.move(screenOfCell(x + i, y))
			end
			mouse.up(screenOfCell(x + 3, y), 1)
			H.advance(1)

			mouse.move(screenOfCell(x + 1, y))
			mouse.down(screenOfCell(x + 1, y), 2)
			mouse.move(screenOfCell(x + 2, y))
			mouse.up(screenOfCell(x + 2, y), 2)
			H.advance(0.3)
			local sent = H.sent("EraseRoads", "toServer")
			T.eq(#sent, 1, "one erase stroke, one EraseRoads")
			local keys = sent[1][1]
			T.eq(#keys, 2, "the two crossed roads")
			T.eq(keys[1], (x + 1) .. ":" .. y)
			T.eq(keys[2], (x + 2) .. ":" .. y)
		end)
	end)
end
