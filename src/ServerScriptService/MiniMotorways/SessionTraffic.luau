--[[
	SessionTraffic.luau
	Circulation de Session : voitures, trajets, réservations d'intersection.
	Ajoute ses méthodes à Session ; appelé une seule fois depuis Session.luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Grid = require(Shared.Grid)
local Pathfinding = require(Shared.Pathfinding)
local RoadConfig = require(Shared.RoadConfig)
local StoreConfig = require(Shared.StoreConfig)
local COLORS = Config.HouseColors
local SessionUtil = require(script.Parent.SessionUtil)
local makePart = SessionUtil.makePart

return function(Session)
	function Session:refreshCarPaths()
		for _, car in ipairs(self.cars) do
			self:releaseCarReservations(car)
			car.retry = 0
			car.roadVersion = -1
		end
	end

	function Session:releaseCarReservations(car)
		for key, holder in pairs(self.intersectionReservations) do
			if holder == car then
				self.intersectionReservations[key] = nil
			end
		end
	end

	function Session:releaseCarReservation(car, key)
		if key and self.intersectionReservations[key] == car then
			self.intersectionReservations[key] = nil
		end
	end

	function Session:reserveIntersection(car, key)
		if not RoadConfig.Traffic.IntersectionReservation then
			return true
		end
		if not self.intersections[key] then
			return true
		end
		local holder = self.intersectionReservations[key]
		if holder and holder ~= car then
			-- Une réservation orpheline ne doit jamais bloquer le réseau.
			if not holder.path then
				self.intersectionReservations[key] = car
				return true
			end
			return false
		end
		self.intersectionReservations[key] = car
		return true
	end

	function Session:parkingSpot(house)
		local base = Grid.center(self.origin, house.x, house.y, 0.5)
		for _, neighbor in ipairs(Grid.neighbors8(house.x, house.y)) do
			local nx, ny = neighbor[1], neighbor[2]
			if Grid.inBounds(nx, ny)
				and not self.buildings[Grid.key(nx, ny)]
				and not Maps.isWater(self.map, nx, ny)
			then
				local target = Grid.center(self.origin, nx, ny, 0.5)
				return base:Lerp(target, 0.42)
			end
		end
		return base + Vector3.new(1.1, 0, 0)
	end

	function Session:createCarVisual(house, spot)
		local palette = COLORS[house.colorIndex]
		local bodyCFrame = CFrame.new(spot)

		local model = Instance.new("Model")
		model.Name = "Car"

		-- Contour sombre sous la carrosserie.
		makePart({
			Name = "Outline",
			Parent = model,
			Size = Vector3.new(1.55, 0.28, 2.50),
			CFrame = bodyCFrame * CFrame.new(0, -0.10, 0),
			Color = Config.Colors.Ink,
		})

		local body = makePart({
			Name = "Body",
			Parent = model,
			Size = Vector3.new(1.35, 0.45, 2.30),
			CFrame = bodyCFrame,
			Color = palette.color,
		})
		model.PrimaryPart = body

		-- Toit clair, avec un liseré sombre.
		makePart({
			Name = "CabinOutline",
			Parent = model,
			Size = Vector3.new(1.02, 0.10, 1.18),
			CFrame = bodyCFrame * CFrame.new(0, 0.25, -0.15),
			Color = Config.Colors.Ink,
		})
		makePart({
			Name = "Cabin",
			Parent = model,
			Size = Vector3.new(0.84, 0.18, 0.98),
			CFrame = bodyCFrame * CFrame.new(0, 0.33, -0.15),
			Color = Config.Colors.White,
		})

		model:PivotTo(CFrame.new(spot))
		model.Parent = self.world.Cars
		return model
	end

	function Session:trySpawnCar(house)
		if house.car or self.over then
			return
		end

		-- Une voiture ne part que s'il reste une demande réellement disponible
		-- dans un magasin de sa couleur. La demande est réservée immédiatement :
		-- deux voitures ne peuvent donc jamais servir le même pin.
		local destination = self:findDestinationForHouse(house, true)
		if not destination then
			house.dest = nil
			house.timer = StoreConfig.Demand.NoDemandRetry
			return
		end
		local demandId = self.storeSystem and self.storeSystem:claimDemand(destination)
		if not demandId then
			house.timer = StoreConfig.Demand.NoDemandRetry
			return
		end
		house.dest = destination

		local spot = self:parkingSpot(house)
		local car = {
			house = house,
			dest = destination,
			demandId = demandId,
			claim = true,
			state = "out",
			path = nil,
			index = 2,
			t = 0,
			pos = spot,
			blocked = true,
			waitTime = 0,
			retry = 0,
			speedFactor = 0,
			heading = nil,
			roadVersion = -1,
			part = self:createCarVisual(house, spot),
		}

		table.insert(self.cars, car)
		house.car = car

		local path = self:findPath(car)
		if path then
			self:setCarPath(car, path)
		end
	end

	function Session:findPath(car)
		local from = car.state == "out" and car.house or car.dest
		local to = car.state == "out" and car.dest or car.house

		local goalSet = {}
		for _, key in ipairs(self:connectorCells(to)) do
			goalSet[key] = true
		end
		if next(goalSet) == nil then
			return nil
		end

		local starts = self:connectorCells(from)
		if car.currentKey and self.roads[car.currentKey] then
			starts = { car.currentKey }
		end
		if #starts == 0 then
			return nil
		end

		local bestPath = nil
		for _, startKey in ipairs(starts) do
			local path = Pathfinding.find(self.roads, self.size, startKey, goalSet, RoadConfig.AllowDiagonals)
			if path and (not bestPath or #path < #bestPath) then
				bestPath = path
			end
		end
		return bestPath
	end

	function Session:setCarPath(car, path)
		if not path or #path == 0 then
			return
		end
		self:releaseCarReservations(car)
		car.path = path
		car.index = 2
		car.t = 0
		car.currentKey = path[1]
		car.waitTime = 0
		car.retry = 0
		car.blocked = false
		car.speedFactor = 0
		car.heading = nil
		car.roadVersion = self.roadVersion
		self:reserveIntersection(car, path[1])

		local x, y = Grid.parse(path[1])
		if x then
			car.pos = Grid.center(self.origin, x, y, 0.5)
			if car.part then
				car.part:PivotTo(CFrame.new(car.pos))
			end
		end
	end

	-- Distance au véhicule le plus proche devant, dans le même couloir.
	-- nil signifie que la voie est libre. Le seuil latéral ignore les voitures
	-- qui arrivent en sens inverse : elles ont leur propre couloir.
	function Session:frontGap(car, direction)
		local best = nil
		for _, other in ipairs(self.cars) do
			if other ~= car and other.pos then
				local delta = other.pos - car.pos
				local along = delta:Dot(direction)
				if along > 0 and along < 9 then
					local lateral = (delta - direction * along).Magnitude
					if lateral < 0.95 and (not best or along < best) then
						best = along
					end
				end
			end
		end
		return best
	end

	function Session:completeLeg(car)
		if car.state == "out" then
			local delivered = false
			if car.dest and car.demandId and self.storeSystem then
				delivered = self.storeSystem:consumeDemand(car.dest, car.demandId)
			end
			car.demandId = nil
			car.claim = false

			-- On ne marque des points que si une demande a réellement été
			-- consommée. Une voiture qui arrive après coup ne peut pas voler le
			-- pin d'une autre.
			if delivered then
				self.score += Config.Game.DeliveryScore
				self.satisfaction = math.min(
					Config.Traffic.SatisfactionMax,
					self.satisfaction + Config.Game.DeliverySatisfaction
				)
				self:destinationPulse(car.dest)
			end

			car.state = "back"

			self:releaseCarReservations(car)
			local reversed = {}
			for i = #car.path, 1, -1 do
				reversed[#reversed + 1] = car.path[i]
			end
			car.path = reversed
			car.index = 2
			car.t = 0
			car.currentKey = reversed[1]
			car.waitTime = 0
			car.retry = 0
			car.speedFactor = 0
			car.roadVersion = self.roadVersion
			self:reserveIntersection(car, reversed[1])

			return false
		end

		return true
	end

	function Session:updateCar(car, dt)
		if not car.path then
			car.retry -= dt
			if car.retry <= 0 then
				car.retry = Config.Traffic.RetryPathInterval
				local path = self:findPath(car)
				if path then
					self:setCarPath(car, path)
				end
			end
			car.blocked = true
			car.waitTime += dt

			-- Si aucune route n'existe après le délai de réservation, on libère
			-- la demande et on retire la voiture. Elle repartira plus tard.
			if car.claim and car.waitTime >= StoreConfig.Demand.ClaimTimeout then
				if self.storeSystem and car.dest and car.demandId then
					self.storeSystem:releaseClaim(car.dest, car.demandId)
				end
				car.claim = false
				car.demandId = nil
				car.dest = nil
				return true
			end
			return false
		end

		-- Le réseau a changé : on recalcule une seule fois, au prochain passage
		-- de la voiture, puis roadVersion est remis à jour.
		if car.roadVersion ~= self.roadVersion then
			local path = self:findPath(car)
			if path then
				self:setCarPath(car, path)
			else
				self:releaseCarReservations(car)
				car.path = nil
				car.retry = Config.Traffic.RetryPathInterval
				car.blocked = true
				car.waitTime += dt
				return false
			end
		end

		if car.index > #car.path then
			return self:completeLeg(car)
		end

		local fromKey = car.path[car.index - 1]
		local toKey = car.path[car.index]
		if not self.roads[toKey] then
			local path = self:findPath(car)
			if path then
				self:setCarPath(car, path)
			else
				self:releaseCarReservations(car)
				car.path = nil
				car.retry = Config.Traffic.RetryPathInterval
			end
			return false
		end

		local fx, fy = Grid.parse(fromKey)
		local tx, ty = Grid.parse(toKey)
		if not fx or not tx then
			self:releaseCarReservations(car)
			car.path = nil
			return false
		end

		local fromPos = Grid.center(self.origin, fx, fy, 0.5)
		local toPos = Grid.center(self.origin, tx, ty, 0.5)
		local direction = (toPos - fromPos).Unit
		local segmentLength = math.max((toPos - fromPos).Magnitude, 0.001)

		local blocked = false
		local targetSpeed = 1

		-- Réservation d'intersection : une seule voiture à la fois au centre.
		if car.t <= 0.001 and self.intersections[toKey] then
			if not self:reserveIntersection(car, toKey) then
				blocked = true
			end
		end

		-- Distance de sécurité. On freine avant la voiture de devant, puis on
		-- s'arrête seulement quand la garde minimale est atteinte.
		local gap = self:frontGap(car, direction)
		if gap then
			if gap <= Config.Traffic.CarSpacing then
				blocked = true
			elseif gap < Config.Traffic.CarSpacing + 2.4 then
				targetSpeed = math.max(0.20, (gap - Config.Traffic.CarSpacing) / 2.4)
			end
		end

		-- Ralentissement dans les virages et à l'approche d'un carrefour.
		local nextKey = car.path[car.index + 1]
		if nextKey then
			local nx, ny = Grid.parse(nextKey)
			if nx then
				local nextDirection = (Grid.center(self.origin, nx, ny, 0.5) - toPos).Unit
				if nextDirection:Dot(direction) < 0.995 then
					targetSpeed = math.min(targetSpeed, RoadConfig.Traffic.TurnSpeedFactor)
				end
			end
		end
		if self.intersections[toKey] then
			targetSpeed = math.min(targetSpeed, RoadConfig.Traffic.IntersectionApproachSlow)
		end

		if blocked then
			car.blocked = true
			car.waitTime += dt
			car.speedFactor = math.max(0, (car.speedFactor or 0) - RoadConfig.Traffic.Braking * dt)
			-- Si la voiture n'est pas encore entrée dans l'intersection, elle
			-- rend sa réservation pour ne pas bloquer les autres directions.
			if car.t <= 0.001 and self.intersectionReservations[toKey] == car then
				self.intersectionReservations[toKey] = nil
			end
		else
			car.blocked = false
			car.waitTime = math.max(0, car.waitTime - dt * 2)
			local speedFactor = car.speedFactor or 0
			if speedFactor < targetSpeed then
				speedFactor = math.min(targetSpeed, speedFactor + RoadConfig.Traffic.Acceleration * dt)
			else
				speedFactor = math.max(targetSpeed, speedFactor - RoadConfig.Traffic.Braking * dt)
			end
			car.speedFactor = speedFactor

			local advance = (Config.Traffic.CarSpeed * speedFactor * dt) / segmentLength
			if gap then
				-- Ne jamais franchir la garde minimale, même avec l'inertie.
				local maxAdvance = (gap - Config.Traffic.CarSpacing * 0.85) / segmentLength
				advance = math.max(0, math.min(advance, maxAdvance))
			end
			car.t += advance
		end

		local heading = direction
		if car.heading then
			local alpha = math.min(1, RoadConfig.Traffic.HeadingLerp * dt)
			local blended = car.heading:Lerp(direction, alpha)
			if blended.Magnitude > 0.001 then
				heading = blended.Unit
			end
		end
		car.heading = heading

		local right = Vector3.new(-heading.Z, 0, heading.X)
		local laneOffset = math.min(0.55, self.tile * 0.14)
		local t = math.min(car.t, 1)
		car.pos = fromPos:Lerp(toPos, t) + right * laneOffset
		if car.part then
			car.part:PivotTo(CFrame.lookAt(car.pos, car.pos + heading))
		end

		if car.t >= 1 then
			car.t = 0
			car.index += 1
			car.currentKey = toKey
			self:releaseCarReservation(car, fromKey)
			car.pos = toPos + right * laneOffset
			if car.part then
				car.part:PivotTo(CFrame.lookAt(car.pos, car.pos + heading))
			end
			if car.index > #car.path then
				return self:completeLeg(car)
			end
			return false
		end

		return false
	end

	function Session:retireCar(car)
		self:releaseCarReservations(car)
		if car.claim and car.dest and car.demandId and self.storeSystem then
			self.storeSystem:releaseClaim(car.dest, car.demandId)
			car.claim = false
			car.demandId = nil
		end
		if car.part then
			car.part:Destroy()
			car.part = nil
		end
		local house = car.house
		if house then
			house.car = nil
			house.timer = Config.Game.SpawnInterval
		end
	end

	function Session:destinationPulse(destination)
		if not destination or not self.world then
			return
		end

		local ring = Instance.new("Part")
		ring.Name = "Delivery"
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		local startSize = destination.storeType == "large" and 4.5 or 3.2
		local endSize = destination.storeType == "large" and 10.5 or 7.5
		ring.Material = Enum.Material.Neon
		ring.Color = destination.color
		ring.Transparency = 0.35
		ring.Size = Vector3.new(0.1, startSize, startSize)
		ring.CFrame = CFrame.new(Grid.center(self.origin, destination.x, destination.y, 0.35))
			* CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = self.world.FX

		TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.1, endSize, endSize),
			Transparency = 1,
		}):Play()

		task.delay(0.6, function()
			if ring.Parent then
				ring:Destroy()
			end
		end)
	end
end
