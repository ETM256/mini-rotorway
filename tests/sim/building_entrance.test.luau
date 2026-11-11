-- Entrées et tailles des bâtiments : l'entrée suit la route, sans recréer le
-- Model ; les dimensions viennent de Config.Dimensions.
return function(T, H)
	local Config = H.load("Config")
	local StoreConfig = H.load("StoreConfig")
	local Grid = H.load("Grid")

	-- Côté (dx, dy) de la case correspondant à un angle d'entrée.
	local function sideOf(angle)
		return math.round(math.sin(angle)), math.round(math.cos(angle))
	end

	local function roadOnSide(session, building, angle)
		local dx, dy = sideOf(angle)
		return session.roads[Grid.key(building.x + dx, building.y + dy)] == true
	end

	T.test("entrée : une route posée d'un autre côté fait pivoter la dalle, le Model reste le même", function()
		local session = H.newSession("los_angeles")
		session.satisfaction = 1e9
		H.runSession(session, 5, 0.1)
		local store = session.destinations[1]
		local house = store.houses[1]
		local modelBefore = house.model
		local stationBefore = store.model

		H.connect(session, house, store)

		T.eq(house.model, modelBefore, "the house keeps its Model")
		T.eq(store.model, stationBefore, "the store keeps its Model")
		T.ok(roadOnSide(session, house, house.entranceAngle), "the entrance faces a road")
		session:destroy()
	end)

	T.test("entrée : chaque bâtiment garde exactement une dalle, du côté d'une route connectée", function()
		for _, map in ipairs(H.load("Maps").all()) do
			H.reset()
			local session = H.newSession(map.id)
			session.budget = 500
			session.satisfaction = 1e9
			for _, house in ipairs(session.houses) do
				H.connect(session, house, session.destinations[1])
			end
			H.runSession(session, 20, 0.1)
			for _, building in ipairs(session.buildingList) do
				local pads = 0
				for _, child in ipairs(building.model:GetChildren()) do
					if child.Name == "Entrance" then
						pads += 1
					end
				end
				T.eq(pads, 1, map.id .. " " .. building.key .. ": exactly one entrance pad")
				if #building.connections > 0 then
					T.ok(roadOnSide(session, building, building.entranceAngle),
						map.id .. " " .. building.key .. ": the entrance faces a connected road")
				end
			end
			session:destroy()
		end
	end)

	T.test("tailles : magasins et pins lisent Config.Dimensions, pas des valeurs en dur", function()
		local visual = StoreConfig.Visual
		local tile = Config.Grid.TileSize
		T.near(visual.SmallSize, Config.Dimensions.Building.SmallStore * tile, 1e-6, "small store footprint")
		T.near(visual.LargeSize, Config.Dimensions.Building.LargeStore * tile, 1e-6, "large store footprint")
		T.eq(visual.PinSize, Config.Dimensions.Pin.Size, "pin size")
		T.eq(visual.SpawnAnimationDuration, Config.Style.Motion.Spawn, "spawn duration")
		T.eq(visual.EvolutionDuration, Config.Style.Motion.Evolution, "evolution duration")
	end)

	T.test("tailles : le corps dessiné a la taille de sa case", function()
		H.reset()
		local session = H.newSession("los_angeles")
		local store = session.destinations[1]
		H.advance(1)
		local tile = Config.Grid.TileSize
		T.near(store.model.PrimaryPart.Size.X, Config.Dimensions.Building.SmallStore * tile, 1e-3, "small store body width")
		session:destroy()
	end)
end
