return function(T, H)
	local function stepRun(session, seconds, dt, check)
		local elapsed = 0
		while elapsed < seconds and not session.over do
			session:update(dt)
			H.flush(dt)
			elapsed += dt
			if session.awaitingChoice then
				session:chooseReward(session.choice.options[1].id)
			end
			if check then
				check(session, elapsed)
			end
		end
	end

	local function connectedGame(mapId)
		local session = H.newSession(mapId or "los_angeles")
		session.budget = 400
		local store = session.destinations[1]
		for _, house in ipairs(session.houses) do
			H.connect(session, house, store)
		end
		return session, store
	end

	-- Mesure, pour chaque voiture, le déplacement de son axe central et le
	-- changement de cap entre deux pas de 0,1 s.
	local function measureSteps(session, seconds, onStep)
		local previous = {}
		stepRun(session, seconds, 0.1, function(s)
			for _, car in ipairs(s.cars) do
				local before = previous[car]
				if before and car.center and before.center then
					onStep(car, (car.center - before.center).Magnitude, before.heading, car.heading)
				end
				previous[car] = { center = car.center, heading = car.heading }
			end
		end)
	end

	local function angleBetween(a, b)
		if not a or not b then
			return 0
		end
		local dot = math.clamp(a:Dot(b), -1, 1)
		return math.acos(dot)
	end

	T.test("the centre line never jumps: a car moves at most CarSpeed * dt per step, corners included", function()
		local Config = H.load("Config")
		local session = connectedGame()
		local maxStep = 0
		measureSteps(session, 200, function(_, step)
			maxStep = math.max(maxStep, step)
		end)
		T.le(maxStep, Config.Traffic.CarSpeed * 0.1 + 0.01, "a car jumped " .. maxStep .. " studs in 0.1 s")
	end)

	T.test("heading turns no faster than RoadConfig.Vehicle.TurnRate, corners included", function()
		local RoadConfig = H.load("RoadConfig")
		local session = connectedGame()
		local maxAngle = 0
		local turned = 0
		measureSteps(session, 200, function(_, _, before, after)
			local angle = angleBetween(before, after)
			maxAngle = math.max(maxAngle, angle)
			if angle > 0 then
				turned += 1
			end
		end)
		T.gt(turned, 0, "no car ever turned: the scenario is too simple")
		local limit = RoadConfig.Vehicle.TurnRate * 0.1 + 0.001
		T.le(maxAngle, limit, "heading turned " .. math.deg(maxAngle) .. " degrees in one step")
	end)

	T.test("a car between two road cells stays on the road network (never over a building)", function()
		local Grid = H.load("Grid")
		local session = connectedGame()
		local checked = 0
		stepRun(session, 200, 0.1, function(s)
			for _, car in ipairs(s.cars) do
				-- Segment entre deux cases de route (et non le départ ou l'arrivée
				-- à une place de bâtiment) : le centre doit rester sur une case route.
				if car.seg and car.path and car.index >= 2 and car.index <= #car.path then
					local x, y = Grid.cellFromWorld(s.origin, car.center)
					checked += 1
					T.ok(s.roads[Grid.key(x, y)] ~= nil, "car centre left the road at cell " .. Grid.key(x, y))
				end
			end
		end)
		T.gt(checked, 0, "no car was checked on the road")
	end)

	T.test("speed changes are bounded by the braking rate (no sudden stop or start)", function()
		local Config = H.load("Config")
		local RoadConfig = H.load("RoadConfig")
		local session = connectedGame()
		local previousSpeed = {}
		local maxChange = 0
		local bound = Config.Traffic.CarSpeed * RoadConfig.Traffic.Braking * 0.1
		measureSteps(session, 200, function(car, step)
			local speed = step / 0.1
			local before = previousSpeed[car]
			if before then
				maxChange = math.max(maxChange, math.abs(speed - before))
			end
			previousSpeed[car] = speed
		end)
		T.le(maxChange, bound + 0.5, "speed changed by " .. maxChange .. " studs/s in one step")
	end)

	T.test("speed never exceeds the nominal CarSpeed, corners included", function()
		local Config = H.load("Config")
		local session = connectedGame()
		local maxSpeed = 0
		measureSteps(session, 200, function(_, step)
			maxSpeed = math.max(maxSpeed, step / 0.1)
		end)
		T.le(maxSpeed, Config.Traffic.CarSpeed * 1.05, "a car reached " .. maxSpeed .. " studs/s")
	end)

	T.test("a 0.3 s simulated frame (speed x3) never moves a car more than 0.3 s of driving", function()
		local Config = H.load("Config")
		local session = connectedGame()
		session:setSpeed(3)
		local maxStep = 0
		local previous = {}
		local elapsed = 0
		while elapsed < 120 and not session.over do
			session:update(0.1)
			H.flush(0.1)
			elapsed += 0.1
			if session.awaitingChoice then
				session:chooseReward(session.choice.options[1].id)
			end
			for _, car in ipairs(session.cars) do
				local before = previous[car]
				if before then
					maxStep = math.max(maxStep, (car.center - before).Magnitude)
				end
				previous[car] = car.center
			end
		end
		T.le(maxStep, Config.Traffic.CarSpeed * 0.3 + 0.01, "frame step " .. maxStep)
		T.gt(session.score, 0, "a fast game must still deliver")
	end)

	T.test("cars on the same lane keep the minimum route distance", function()
		local Config = H.load("Config")
		local session = connectedGame()
		local minGap = math.huge
		stepRun(session, 200, 0.1, function(s)
			for a = 1, #s.cars do
				for b = a + 1, #s.cars do
					local ca, cb = s.cars[a], s.cars[b]
					if ca.seg and cb.seg and ca.laneFrom == cb.laneFrom and ca.laneTo == cb.laneTo then
						minGap = math.min(minGap, math.abs(ca.s - cb.s))
					end
				end
			end
		end)
		if minGap ~= math.huge then
			T.ge(minGap, Config.Traffic.CarSpacing * 0.75, "two cars on one lane are " .. minGap .. " studs apart")
		end
	end)

	T.test("at most one car is inside an intersection at any time", function()
		local Grid = H.load("Grid")
		local session, store = connectedGame()
		local checked = 0
		stepRun(session, 200, 0.1, function(s)
			for key in pairs(s.intersections) do
				local x, y = Grid.parse(key)
				local center = Grid.center(s.origin, x, y, 0.5)
				local inside = 0
				for _, car in ipairs(s.cars) do
					if car.seg and car.center and (car.center - center).Magnitude < 1.5 then
						inside += 1
					end
				end
				checked += 1
				T.le(inside, 1, "two cars inside intersection " .. key)
			end
		end)
		T.ge(store.delivered, 1)
		T.gt(checked, 0, "the connected network must contain intersections")
	end)

	T.test("erasing roads under moving cars keeps every car on existing roads without a jump", function()
		local session = connectedGame()
		stepRun(session, 40, 0.1)
		local keys = {}
		for key in pairs(session.roads) do
			table.insert(keys, key)
		end
		table.sort(keys)
		local cut = {}
		for i = 1, #keys, 3 do
			table.insert(cut, keys[i])
		end
		session:eraseRoads(cut)

		local maxStep = 0
		local previous = {}
		stepRun(session, 60, 0.1, function(s)
			for _, car in ipairs(s.cars) do
				T.ok(car.pos.X == car.pos.X and car.pos.Z == car.pos.Z, "NaN position after erase")
				if car.path then
					for i = car.index, #car.path do
						T.ok(s.roads[car.path[i]], "a car keeps a route through an erased cell")
					end
				end
				local before = previous[car]
				if before and car.center then
					maxStep = math.max(maxStep, (car.center - before).Magnitude)
				end
				previous[car] = car.center
			end
		end)
		T.eq(#H.handlerErrors, 0)
		T.le(maxStep, 0.9 + 0.01, "re-routing made a car jump " .. maxStep .. " studs")
	end)

	T.test("a car is never created for a house without any route, and no demand is claimed", function()
		local session = H.newSession("los_angeles")
		local destination = session.destinations[1]
		local spawned = 0
		stepRun(session, 40, 0.1, function(s)
			spawned = math.max(spawned, #s.cars)
		end)
		T.eq(spawned, 0)
		T.eq(destination.reserved or 0, 0, "an unroutable house must not reserve a demand")
	end)

	T.test("destroy() removes the world folder and forgets every car", function()
		local session = connectedGame()
		local maxCars = 0
		stepRun(session, 60, 0.1, function(s)
			maxCars = math.max(maxCars, #s.cars)
		end)
		T.gt(maxCars, 0, "the scenario must have cars")
		local folder = session.world.folder
		session:destroy()
		T.falsy(folder.Parent, "world folder still attached")
		T.eq(#session.cars, 0)
		T.eq(session.world, nil)
	end)

	T.test("statistics hooks are called on spawn and delivery when they exist", function()
		local session = connectedGame()
		local counts = {}
		session.recordStat = function(_, name, amount)
			counts[name] = (counts[name] or 0) + amount
		end
		stepRun(session, 150, 0.1)
		T.gt(counts.carsSpawned or 0, 0, "carsSpawned not recorded")
		T.gt(counts.deliveries or 0, 0, "deliveries not recorded")
	end)

	T.test("onDelivery replaces the built-in scoring when provided", function()
		local session = connectedGame()
		local calls = 0
		session.onDelivery = function(_, house, destination)
			calls += 1
			T.ok(house ~= nil and destination ~= nil, "onDelivery needs house and destination")
		end
		stepRun(session, 150, 0.1)
		T.gt(calls, 0, "onDelivery never called")
		T.eq(session.score, 0, "built-in scoring must not run twice")
	end)

	T.test("the car model is a small top-view vehicle with at most five parts", function()
		local Config = H.load("Config")
		local CarModel = H.load("CarModel")
		local model = CarModel.create(Config.HouseColors[1].color, 4)
		local parts = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
				T.falsy(d.CanCollide, "car parts must not collide")
			end
		end
		T.ok(parts >= 3 and parts <= 5, "car has " .. parts .. " parts")
		T.ok(model.PrimaryPart ~= nil, "car needs a PrimaryPart pivot")
		model:Destroy()
	end)
end
