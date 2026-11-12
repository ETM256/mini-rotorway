return function(T, H)
	local Grid = H.load("Grid")

	-- Le tablier d'un pont est plus haut que la route : une voiture qui le
	-- traverse monte de la même hauteur au lieu de s'enfoncer dedans.
	local function firstCarY(session, bridgeAll)
		if bridgeAll then
			for key in pairs(session.roads) do
				session.bridges[key] = true
			end
		end
		local y = nil
		local elapsed = 0
		while not y and elapsed < 30 and not session.over do
			session:update(0.1)
			H.flush(0.1)
			elapsed += 0.1
			if session.awaitingChoice then
				session:chooseReward(session.choice.options[1].id)
			end
			for _, car in ipairs(session.cars) do
				if car.part and car.pos then
					-- On mesure une fois la voiture engagée sur une case de route
					-- (au départ elle est garée à côté de la maison).
					local cx, cy = Grid.cellFromWorld(session.origin, car.pos)
					if session.roads[Grid.key(cx, cy)] then
						y = car.part:GetPivot().Position.Y - session.origin.Y
						break
					end
				end
			end
		end
		return y
	end

	local function connectedGame()
		local session = H.newSession("los_angeles")
		session.budget = 400
		local store = session.destinations[1]
		for _, house in ipairs(session.houses) do
			H.connect(session, house, store)
		end
		return session
	end

	T.test("a car on a bridge is lifted by the deck height, a car on a road is not", function()
		local RoadConfig = H.load("RoadConfig")
		local CarModel = H.load("CarModel")
		local lift = RoadConfig.Layers.Bridge.Top - RoadConfig.Layers.Body.Top

		local onRoad = firstCarY(connectedGame(), false)
		T.ok(onRoad, "a car drove on the road")
		T.near(onRoad, CarModel.CenterY, 1e-6, "road: no lift")

		local onBridge = firstCarY(connectedGame(), true)
		T.ok(onBridge, "a car drove on the bridge")
		T.near(onBridge, CarModel.CenterY + lift, 1e-6, "bridge: lifted by the deck height")
	end)
end
