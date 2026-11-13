--[[
	SessionTraffic.luau
	Circulation de Session : voitures, trajets, réservations d'intersection.
	Ajoute ses méthodes à Session ; appelé une seule fois depuis Session.luau.

	Une voiture suit un chemin de cases de route, mais sa position est continue :
	elle avance le long d'un segment (ligne droite, ou arc de Bézier dans un
	virage) et ne saute jamais d'une case à l'autre. Les intersections et les
	cases qui touchent un bâtiment se réservent par suites entières avant d'y
	entrer : deux voitures ne s'y croisent pas, une voiture qui ne peut pas
	les prendre s'arrête avant, et une boucle d'attente est cassée. Les trajets
	sont mis en cache par version du réseau et ne sont recalculés que pour les
	voitures dont la route a disparu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Pathfinding = require(Shared.Pathfinding)
local RoadConfig = require(Shared.RoadConfig)
local StoreConfig = require(Shared.StoreConfig)
local SessionUtil = require(script.Parent.SessionUtil)
local CarModel = require(script.Parent.CarModel)
local COLORS = Config.HouseColors
local clamp = SessionUtil.clamp

local TRAFFIC = RoadConfig.Traffic
local VEHICLE = RoadConfig.Vehicle
local DEFAULT_HEADING = Vector3.new(0, 0, -1)
-- Reste de course (studs) au-dessous duquel une voiture arrêtée devant une
-- case occupée compte comme en attente.
local STOP_EPSILON = 0.05
-- Plancher de la vitesse relative dans un arc très serré.
local MIN_TURN_FACTOR = 0.2
-- Longueur maximale de la chaîne d'attente examinée pour trouver une boucle.
local CYCLE_LIMIT = 64

-- Voies de chaque partie, indexées par la table des voitures de la session
-- (recréée à chaque remise à zéro : les voies repartent donc vides, sans champ
-- de plus dans Session). Les clés faibles laissent partir une partie finie.
local lanesOfCars = setmetatable({}, { __mode = "k" })
-- Numéro de voiture : ordre total pour désigner qui casse une boucle d'attente.
local nextCarId = 0

-- Vecteur unitaire, ou nil si le vecteur est (presque) nul.
local function unitOrNil(vector)
	local magnitude = vector.Magnitude
	if magnitude < 0.0001 then
		return nil
	end
	return vector / magnitude
end

local function cellCenter(session, key)
	local x, y = Grid.parse(key)
	return Grid.center(session.origin, x, y, 0.5)
end

-- Origine et destination du trajet en cours, selon l'aller ou le retour.
local function carEnds(car)
	if car.state == "out" then
		return car.house, car.dest
	end
	return car.dest, car.house
end

-- Point de la courbe de Bézier quadratique d'un virage (u dans [0, 1]).
local function bezierPoint(seg, u)
	local a = 1 - u
	return seg.lineEnd * (a * a) + seg.ctrl * (2 * a * u) + seg.to * (u * u)
end

-- Segment parcouru par une voiture : une ligne droite, suivie d'un arc de
-- Bézier si le segment tourne à son extrémité. `cut` est la distance du
-- centre de la case à laquelle l'arc commence.
local function makeSegment(from, to, nextPoint, cut)
	local seg = {
		from = from,
		lineEnd = to,
		ctrl = nil,
		to = to,
		samples = nil,
		speedLimit = 1,
		lineLength = 0,
		curveLength = 0,
		length = 0,
	}
	local delta = to - from
	local len = delta.Magnitude
	if nextPoint and len > 0.0001 then
		local outDelta = nextPoint - to
		local outLen = outDelta.Magnitude
		if outLen > 0.0001 then
			local dirIn = delta / len
			local dirOut = outDelta / outLen
			if dirIn:Dot(dirOut) < VEHICLE.TurnDot then
				local radius = math.min(cut, len * 0.5, outLen * 0.5)
				seg.lineEnd = to - dirIn * radius
				seg.ctrl = to
				seg.to = to + dirOut * radius
				-- Longueur de l'arc sur quelques échantillons : la vitesse de la
				-- voiture reste constante dans le virage.
				local count = VEHICLE.CurveSamples
				local samples = { 0 }
				local total = 0
				local previous = seg.lineEnd
				for i = 1, count do
					local point = bezierPoint(seg, i / count)
					total += (point - previous).Magnitude
					samples[i + 1] = total
					previous = point
				end
				seg.samples = samples
				seg.curveLength = total
				-- Courbure maximale de l'arc : 1,414 / rayon. La voiture ralentit pour
				-- que son cap tourne à moins de 80 % de la vitesse de rotation limite.
				local safe = 0.8 * VEHICLE.TurnRate * radius / math.sqrt(2) / Config.Traffic.CarSpeed
				seg.speedLimit = clamp(safe, MIN_TURN_FACTOR, 1)
			end
		end
	end
	seg.lineLength = (seg.lineEnd - from).Magnitude
	seg.length = seg.lineLength + seg.curveLength
	return seg
end

-- Cap exprimé en angle autour de Y (0 = vers -Z, l'avant de la voiture).
local function yawOf(direction)
	return math.atan2(direction.X, -direction.Z)
end

local function headingFromYaw(yaw)
	return Vector3.new(math.sin(yaw), 0, -math.cos(yaw))
end

-- Ramène un écart d'angle dans [-pi, pi[ pour tourner par le plus court côté.
local function wrapAngle(angle)
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Paramètre u de la courbe pour une distance `distance` depuis son début.
local function curveParameter(seg, distance)
	if distance <= 0 then
		return 0
	end
	if distance >= seg.curveLength then
		return 1
	end
	local samples = seg.samples
	local count = #samples - 1
	for i = 1, count do
		if samples[i + 1] >= distance then
			local span = samples[i + 1] - samples[i]
			local fraction = 0
			if span > 0 then
				fraction = (distance - samples[i]) / span
			end
			return (i - 1 + fraction) / count
		end
	end
	return 1
end

-- Point de l'axe central à la distance `s` le long du segment.
local function pointAt(seg, s)
	if not seg.ctrl or s <= seg.lineLength then
		if seg.lineLength <= 0.0001 then
			return seg.lineEnd
		end
		return seg.from:Lerp(seg.lineEnd, clamp(s / seg.lineLength, 0, 1))
	end
	return bezierPoint(seg, curveParameter(seg, s - seg.lineLength))
end

-- Direction de déplacement à la distance `s` (nil si elle est indéfinie).
local function tangentAt(seg, s)
	if seg.ctrl and s > seg.lineLength then
		local u = curveParameter(seg, s - seg.lineLength)
		local a = 1 - u
		return unitOrNil((seg.ctrl - seg.lineEnd) * a + (seg.to - seg.ctrl) * u)
	end
	return unitOrNil(seg.lineEnd - seg.from)
end

return function(Session)
	-- Voies ------------------------------------------------------------------------

	-- Une voie est une paire orientée (nœud de départ, nœud d'arrivée) : deux sens
	-- de circulation ne se gênent jamais. Chaque voie liste ses voitures : l'écart
	-- avec la voiture qui précède ne parcourt jamais tout le trafic.
	local function leaveLane(car)
		local list = car.lane
		if not list then
			return
		end
		local count = #list
		for i = 1, count do
			if list[i] == car then
				list[i] = list[count]
				list[count] = nil
				break
			end
		end
		car.lane = nil
	end

	local function laneList(self, from, to, create)
		local lanes = lanesOfCars[self.cars]
		if not lanes then
			if not create then
				return nil
			end
			lanes = {}
			lanesOfCars[self.cars] = lanes
		end
		local byFrom = lanes[from]
		if not byFrom then
			if not create then
				return nil
			end
			byFrom = {}
			lanes[from] = byFrom
		end
		local list = byFrom[to]
		if not list and create then
			list = {}
			byFrom[to] = list
		end
		return list
	end

	local function setLane(self, car, from, to)
		if car.lane and car.laneFrom == from and car.laneTo == to then
			return
		end
		leaveLane(car)
		car.laneFrom = from
		car.laneTo = to
		local list = laneList(self, from, to, true)
		list[#list + 1] = car
		car.lane = list
	end

	-- Réservations d'intersection ---------------------------------------------

	-- Cases réservées : les intersections, et les cases qui touchent un bâtiment.
	-- Une route qui longe une maison n'est pas une intersection, mais une voiture
	-- qui en sort ou qui s'y gare ne doit pas croiser une voiture de passage.
	local function isHoldCell(self, key)
		if self.intersections[key] then
			return true
		end
		if self.holdCellVersion ~= self.roadVersion or self.holdCellCount ~= #self.buildingList then
			local cells = {}
			for _, building in ipairs(self.buildingList) do
				for _, cellKey in ipairs(building.connections or {}) do
					cells[cellKey] = true
				end
			end
			self.holdCells = cells
			self.holdCellVersion = self.roadVersion
			self.holdCellCount = #self.buildingList
		end
		return self.holdCells[key] == true
	end

	local function removeHeld(car, key)
		local held = car.held
		for i = #held, 1, -1 do
			if held[i] == key then
				table.remove(held, i)
			end
		end
	end

	-- Réserve, tout ou rien, la suite de cases réservables consécutives qui
	-- commence au nœud j du trajet. Une voiture ne garde donc jamais une
	-- intersection en attendant la suivante : deux voitures de sens opposés sur
	-- deux intersections voisines ne se bloquent pas. Renvoie false (et note la
	-- voiture qui bloque) si une case est tenue par une autre voiture. `force`
	-- prend les cases même tenues : réservé à la rupture d'une boucle d'attente.
	local function secureNode(self, car, j, force)
		if not TRAFFIC.IntersectionReservation then
			return true
		end
		local path = car.path
		local first = path[j]
		if not first or not isHoldCell(self, first) then
			return true
		end
		local last = j
		local nextKey = path[last + 1]
		while nextKey and isHoldCell(self, nextKey) do
			last += 1
			nextKey = path[last + 1]
		end

		local reservations = self.intersectionReservations
		if not force then
			for k = j, last do
				local holder = reservations[path[k]]
				-- Une réservation orpheline (voiture sans trajet) ne bloque jamais le réseau.
				if holder and holder ~= car and holder.path ~= nil then
					car.blocker = holder
					car.blockedIndex = j
					return false
				end
			end
		end
		for k = j, last do
			local key = path[k]
			local holder = reservations[key]
			if holder ~= car then
				if holder then
					removeHeld(holder, key)
				end
				reservations[key] = car
				car.held[#car.held + 1] = key
			end
		end
		return true
	end

	-- Une voiture qui attend une case tenue par une voiture qui attend, ... qui
	-- attend la première : boucle d'attente. Renvoie la voiture de numéro le plus
	-- bas de la boucle (la seule autorisée à la casser), ou nil s'il n'y a pas de boucle.
	local function lowestInWaitCycle(car)
		local lowest = car
		local cursor = car.blocker
		for _ = 1, CYCLE_LIMIT do
			if cursor == nil then
				return nil
			end
			if cursor == car then
				return lowest
			end
			if cursor.id < lowest.id then
				lowest = cursor
			end
			cursor = cursor.blocker
		end
		return nil
	end

	-- Case sous la voiture, si c'est une route : celle-là n'est jamais rendue
	-- tant que la voiture s'y trouve.
	local function standingKey(self, car)
		if not car.center then
			return nil
		end
		local x, y = Grid.cellFromWorld(self.origin, car.center)
		local key = Grid.key(x, y)
		return self.roads[key] and key or nil
	end

	function Session:releaseCarReservation(car, key)
		if not key then
			return
		end
		if self.intersectionReservations[key] == car then
			self.intersectionReservations[key] = nil
		end
		removeHeld(car, key)
	end

	-- Libère toutes les réservations de la voiture, sauf `keepKey` : la case
	-- où elle se trouve encore reste occupée tant qu'elle n'en est pas sortie.
	function Session:releaseCarReservations(car, keepKey)
		local kept = {}
		for _, key in ipairs(car.held) do
			if key == keepKey then
				kept[#kept + 1] = key
			elseif self.intersectionReservations[key] == car then
				self.intersectionReservations[key] = nil
			end
		end
		car.held = kept
	end

	-- Libère les réservations qui ne servent plus à la voiture après un
	-- changement de trajet : seules restent la case quittée et celles du trajet
	-- restant.
	function Session:releaseUnusedHolds(car)
		local path = car.path
		local keep = {}
		if car.lastKey then
			keep[car.lastKey] = true
		end
		for i = car.index, #path do
			keep[path[i]] = true
		end
		for i = #car.held, 1, -1 do
			local key = car.held[i]
			if not keep[key] then
				self:releaseCarReservation(car, key)
			end
		end
	end

	-- Une voiture arrêtée derrière une autre ne garde pas les cases qu'elle n'a
	-- pas encore atteintes : la voiture de devant peut en avoir besoin, et sans
	-- cela chacune attendrait l'autre (l'une retient la case, l'autre bloque le
	-- passage). La case du segment en cours n'est rendue qu'avant d'y entrer.
	local function releaseAheadHolds(self, car)
		local path = car.path
		local reservations = self.intersectionReservations
		local k = car.index
		if car.s > 0 then
			k += 1
		end
		-- Une suite prise en avance commence au nœud visé ou au suivant.
		if reservations[path[k]] ~= car then
			k += 1
		end
		while path[k] and reservations[path[k]] == car do
			self:releaseCarReservation(car, path[k])
			k += 1
		end
	end

	-- Trajets ------------------------------------------------------------------

	-- Chemin de cases entre deux bâtiments, depuis une case de route donnée
	-- (fromKey) ou depuis les connecteurs de l'origine. Une seule recherche
	-- même avec plusieurs connecteurs de départ.
	function Session:computeRoute(origin, goal, fromKey)
		local goalSet = {}
		for _, key in ipairs(self:connectorCells(goal)) do
			goalSet[key] = true
		end
		if next(goalSet) == nil then
			return nil
		end

		local starts = fromKey and { fromKey } or self:connectorCells(origin)
		return Pathfinding.findFromAny(self.roads, self.size, starts, goalSet, RoadConfig.AllowDiagonals)
	end

	-- Mis en cache : les chemins sont recalculés seulement quand la version du
	-- réseau change.
	function Session:findRoute(origin, goal, fromKey)
		if self.routeCacheVersion ~= self.roadVersion then
			self.routeCache = {}
			self.routeCacheVersion = self.roadVersion
		end
		local startName = fromKey or Grid.key(origin.x, origin.y)
		local cacheKey = startName .. ">" .. Grid.key(goal.x, goal.y)
		local cached = self.routeCache[cacheKey]
		if cached == nil then
			cached = self:computeRoute(origin, goal, fromKey) or false
			self.routeCache[cacheKey] = cached
		end
		return cached or nil
	end

	-- Magasin de la couleur de la maison, avec une demande libre, le plus proche
	-- par la route. Une seule recherche vers les connecteurs de tous ces magasins
	-- (au lieu d'une par magasin). Renvoie le magasin et le chemin, ou nil.
	local function nearestReachableStore(self, house)
		local goalSet, owner = {}, {}
		local found = false
		for _, store in ipairs(self.destinations) do
			if store.colorIndex == house.colorIndex and store.demands - store.reserved > 0 then
				for _, key in ipairs(self:connectorCells(store)) do
					goalSet[key] = true
					owner[key] = store
					found = true
				end
			end
		end
		if not found then
			return nil, nil
		end
		local path = Pathfinding.findFromAny(
			self.roads,
			self.size,
			self:connectorCells(house),
			goalSet,
			RoadConfig.AllowDiagonals
		)
		if not path then
			return nil, nil
		end
		return owner[path[#path]], path
	end

	-- Chemin restant de la voiture. Une voiture déjà sur le réseau repart de la
	-- dernière case atteinte ; sinon elle part du connecteur de sa maison.
	function Session:findPath(car)
		local origin, goal = carEnds(car)
		local fromKey = car.lastKey
		if fromKey then
			if not self.roads[fromKey] then
				return nil
			end
			return self:findRoute(origin, goal, fromKey)
		end
		return self:findRoute(origin, goal, nil)
	end

	-- Prépare le segment vers le nœud courant du trajet, depuis la position
	-- actuelle : la voiture ne se téléporte jamais vers une case.
	function Session:startSegment(car)
		local path = car.path
		local index = car.index
		local count = #path
		local origin, goal = carEnds(car)
		local targetKey = path[index]
		local target = targetKey and cellCenter(self, targetKey) or self:carTargetSpot(car)

		local nextPoint = nil
		if index < count then
			nextPoint = cellCenter(self, path[index + 1])
		elseif index == count then
			nextPoint = self:carTargetSpot(car)
		end

		car.seg = makeSegment(car.center, target, nextPoint, self.tile * VEHICLE.CornerCutTiles)
		car.s = 0
		setLane(self, car, index > 1 and path[index - 1] or origin, targetKey or goal)
	end

	-- Le trajet restant ne traverse que des cases encore routières : il n'y a
	-- alors aucune raison de le recalculer.
	local function pathIntact(self, car)
		local path = car.path
		if car.lastKey and not self.roads[car.lastKey] then
			return false
		end
		for i = car.index, #path do
			if not self.roads[path[i]] then
				return false
			end
		end
		return true
	end

	-- Recalcule le trajet après un changement du réseau. Le segment en cours
	-- est conservé quand sa cible existe encore ; sinon la voiture revient
	-- à la dernière case atteinte, ou reste sur place sans route.
	function Session:replanCar(car)
		car.roadVersion = self.roadVersion
		local oldKey = car.path and car.path[car.index] or nil
		local lastKey = car.lastKey

		if oldKey and self.roads[oldKey] then
			local origin, goal = carEnds(car)
			local tail = self:findRoute(origin, goal, oldKey)
			if tail then
				local path = {}
				local offset = 0
				-- La dernière case atteinte n'est reprise devant que si la suite ne
				-- commence pas déjà par elle (retour pas encore arrivé à son premier nœud).
				if lastKey and lastKey ~= oldKey and self.roads[lastKey] then
					path[1] = lastKey
					offset = 1
				end
				for i, key in ipairs(tail) do
					path[i + offset] = key
				end
				car.path = path
				car.index = offset + 1
				car.lostTime = 0
				self:releaseUnusedHolds(car)
				self:startSegment(car)
				return
			end
		end

		local path = self:findPath(car)
		if path then
			car.path = path
			car.index = 1
			car.lostTime = 0
			self:releaseUnusedHolds(car)
			self:startSegment(car)
		else
			car.path = nil
			car.seg = nil
			self:releaseCarReservations(car, standingKey(self, car))
			car.retry = Config.Traffic.RetryPathInterval
		end
	end

	-- Après un lot de routes (la version du réseau a déjà changé) : une voiture
	-- dont le trajet reste valide continue sans recherche ; les autres sont
	-- recalculées une seule fois, à leur prochain pas.
	function Session:refreshCarPaths()
		for _, car in ipairs(self.cars) do
			if car.path and pathIntact(self, car) then
				car.roadVersion = self.roadVersion
			else
				car.retry = 0
			end
		end
	end

	-- Espacement -----------------------------------------------------------------

	-- Distance le long du trajet jusqu'à la voiture qui précède sur la même
	-- voie (ou sur les voies suivantes du trajet), ou nil si la voie est libre.
	function Session:frontGap(car)
		local horizon = VEHICLE.LookaheadTiles * self.tile
		local best = nil

		local list = car.lane
		if list then
			local s = car.s
			for i = 1, #list do
				local other = list[i]
				if other ~= car and other.s > s then
					local d = other.s - s
					if d < horizon and (best == nil or d < best) then
						best = d
					end
				end
			end
		end

		local path = car.path
		if path and car.seg then
			local _, goal = carEnds(car)
			local along = car.seg.length - car.s
			for j = car.index + 1, #path + 1 do
				if along >= horizon then
					break
				end
				local ahead = laneList(self, path[j - 1], path[j] or goal, false)
				if ahead then
					for i = 1, #ahead do
						local d = along + ahead[i].s
						if d < horizon and (best == nil or d < best) then
							best = d
						end
					end
				end
				along += self.tile
			end
		end
		return best
	end

	-- Apparence -----------------------------------------------------------------

	-- Place de stationnement du bâtiment, côté de son connecteur : la voiture
	-- reste entièrement dans la case du bâtiment, son bout extérieur affleurant
	-- le bord de la case. Elle ne déborde jamais dans la case du connecteur.
	-- Chaque connecteur a sa place : deux voitures qui utilisent des connecteurs
	-- différents ne se garent jamais au même endroit.
	function Session:parkingSpot(building, connectorKey)
		local base = Grid.center(self.origin, building.x, building.y, CarModel.CenterY)
		local x, y = Grid.parse(connectorKey)
		if not x then
			return base
		end
		local toConnector = Grid.center(self.origin, x, y, CarModel.CenterY) - base
		local reach = self.tile * (0.5 - Config.Dimensions.Car.Length * 0.5)
		return base + toConnector.Unit * reach
	end

	-- Point d'arrivée du trajet : la place du bâtiment d'arrivée, reliée au
	-- dernier connecteur du chemin.
	function Session:carTargetSpot(car)
		local _, goal = carEnds(car)
		return self:parkingSpot(goal, car.path[#car.path])
	end

	function Session:createCarVisual(house, spot)
		local palette = COLORS[house.colorIndex]
		local model = CarModel.create(palette.color, self.tile)
		model:PivotTo(CFrame.new(spot))
		model.Parent = self.world.Cars
		return model
	end

	-- Cycle de vie ----------------------------------------------------------------

	-- Crée la voiture d'un trajet déjà validé (demande réservée, chemin connu).
	function Session:createCar(house, destination, demandId, path)
		local homeSpot = self:parkingSpot(house, path[1])
		nextCarId += 1
		local car = {
			id = nextCarId,
			house = house,
			dest = destination,
			demandId = demandId,
			claim = true,
			state = "out",
			path = path,
			index = 1,
			lastKey = nil,
			held = {},
			reserveWait = 0,
			blocker = nil,
			blockedIndex = nil,
			center = homeSpot,
			pos = homeSpot,
			s = 0,
			seg = nil,
			lane = nil,
			heading = nil,
			speedFactor = 0,
			laneFrom = false,
			laneTo = false,
			roadVersion = self.roadVersion,
			blocked = false,
			waitTime = 0,
			lostTime = 0,
			retry = 0,
			part = self:createCarVisual(house, homeSpot),
		}

		table.insert(self.cars, car)
		house.car = car
		self:startSegment(car)
		if self.recordStat then
			self:recordStat("carsSpawned", 1)
		end
		return car
	end

	function Session:trySpawnCar(house)
		if house.car or self.over or not self.world then
			return
		end

		-- Un seul calcul de chemin pour tous les magasins candidats : la maison
		-- ne vise qu'un magasin qu'une route atteint réellement.
		local nearest, nearestPath = nearestReachableStore(self, house)
		local destination = self:findDestinationForHouse(house, true, function(store)
			return store == nearest
		end)
		if not destination then
			house.dest = nil
			house.timer = StoreConfig.Demand.NoDemandRetry
			return
		end

		-- Aucune voiture sans route : on vérifie le trajet avant de réserver la
		-- demande ou de créer le modèle.
		local path = destination == nearest and nearestPath or self:findRoute(house, destination, nil)
		if not path then
			house.dest = nil
			house.timer = StoreConfig.Demand.NoDemandRetry
			return
		end

		-- La demande est réservée immédiatement : deux voitures ne peuvent
		-- jamais servir le même pin.
		local demandId = self.storeSystem and self.storeSystem:claimDemand(destination)
		if not demandId then
			house.timer = StoreConfig.Demand.NoDemandRetry
			return
		end
		house.dest = destination
		self:createCar(house, destination, demandId, path)
	end

	-- Fin de trajet : livraison à l'aller, retour à la maison.
	function Session:completeLeg(car)
		if car.state ~= "out" then
			return true
		end

		local delivered = false
		if car.dest and car.demandId and self.storeSystem then
			delivered = self.storeSystem:consumeDemand(car.dest, car.demandId)
		end
		car.demandId = nil
		car.claim = false

		-- On ne marque des points que si une demande a réellement été
		-- consommée. Une voiture qui arrive après coup ne peut pas voler le
		-- pin d'une autre. Session:onDelivery est le seul endroit qui score.
		if delivered then
			self:onDelivery(car.house, car.dest)
			self:destinationPulse(car.dest)
		end

		car.state = "back"
		car.waitTime = 0
		car.lostTime = 0
		car.roadVersion = self.roadVersion
		local path = self:findPath(car)
		if path then
			-- Le retour repart du connecteur du magasin : la voiture garde
			-- cette case jusqu'à la quitter, pour qu'aucune autre n'y entre.
			car.path = path
			car.index = 1
			self:releaseUnusedHolds(car)
			self:startSegment(car)
		else
			car.path = nil
			car.seg = nil
			self:releaseCarReservations(car)
			car.retry = Config.Traffic.RetryPathInterval
		end
		return false
	end

	-- Arrivée au bout du segment courant : nœud du trajet, ou place du bâtiment.
	-- Renvoie true si la voiture doit être retirée.
	function Session:arriveAt(car)
		local index = car.index
		local key = car.path[index]
		if not key then
			return self:completeLeg(car)
		end
		car.lastKey = key
		if index > 1 then
			self:releaseCarReservation(car, car.path[index - 1])
		end
		car.index = index + 1
		self:startSegment(car)
		return false
	end

	-- Distance (depuis le début du segment) que la voiture peut atteindre :
	-- nil si elle ne peut pas entrer dans le segment, la longueur du segment si
	-- tout est libre. Les cases réservables se prennent en avance, avant d'y
	-- entrer : si la suivante n'est pas libre, la voiture s'arrête avant elle
	-- (au bout du segment, ou au début de l'arc qui la pousserait dans la case),
	-- jamais dedans. Le second résultat indique que la voiture doit s'arrêter
	-- avant la case suivante.
	local function segmentRoom(self, car)
		local seg = car.seg
		local index = car.index
		if car.s <= 0 and not secureNode(self, car, index) then
			return nil, true
		end
		if secureNode(self, car, index + 1) then
			return seg.length, false
		end
		local stop = seg.ctrl and seg.lineLength or seg.length
		if car.s > stop then
			-- Trop tard pour s'arrêter avant l'arc.
			return seg.length, false
		end
		return stop, true
	end

	-- Cap de la voiture : il suit exactement la tangente de la trajectoire, donc
	-- la carrosserie reste dans la chaussée dans les virages. Seule une rupture
	-- de la tangente (demi-tour sur la place de stationnement, nouveau trajet)
	-- est lissée : l'écart créé par la rupture s'efface en angle, avec un lissage
	-- exponentiel et une vitesse de rotation limitée.
	function Session:smoothHeading(car, tangentYaw, h)
		local lastTangent = car.tangentYaw or tangentYaw
		local jump = wrapAngle(tangentYaw - lastTangent)
		car.tangentYaw = tangentYaw
		local offset = car.yawOffset or 0
		if math.abs(jump) > VEHICLE.TurnRate * h then
			offset = wrapAngle(offset - jump)
		end
		local alpha = 1 - math.exp(-TRAFFIC.HeadingLerp * h)
		local maxTurn = VEHICLE.TurnRate * h
		local target = offset - clamp(offset * alpha, -maxTurn, maxTurn)
		-- L'écart ne peut que se réduire : jamais de rotation à contresens.
		if math.abs(target) > math.abs(offset) then
			target = offset
		end
		car.yawOffset = target
		return headingFromYaw(tangentYaw + target)
	end

	-- Avance la voiture d'un pas `h` (secondes simulées). Renvoie true si la
	-- voiture doit être retirée.
	function Session:stepCar(car, h, spacing)
		local path = car.path
		local seg = car.seg
		local gap = self:frontGap(car)
		local blockedByGap = gap ~= nil and gap <= spacing

		car.blocker = nil
		local room, stopAhead = seg.length, false
		if blockedByGap then
			releaseAheadHolds(self, car)
		else
			room, stopAhead = segmentRoom(self, car)
		end
		local waitingForNode = room == nil
		if waitingForNode then
			room = 0
		elseif stopAhead and room - car.s <= STOP_EPSILON then
			waitingForNode = true
		end

		if waitingForNode then
			car.reserveWait += h
			-- Boucle d'attente : une seule voiture de la boucle prend la case, les
			-- autres suivent ensuite chacune à leur tour.
			if car.reserveWait >= VEHICLE.DeadlockCheckTime and car.blocker and lowestInWaitCycle(car) == car then
				secureNode(self, car, car.blockedIndex, true)
				car.reserveWait = 0
			end
		else
			car.reserveWait = 0
		end

		local blocked = blockedByGap or waitingForNode
		local mustStop = stopAhead or car.index > #path
		local remain = room - car.s

		local speed = Config.Traffic.CarSpeed
		local speedTarget = 1
		if seg.ctrl then
			speedTarget = math.min(speedTarget, TRAFFIC.TurnSpeedFactor, seg.speedLimit)
		end
		local targetKey = path[car.index]
		if targetKey and self.intersections[targetKey] then
			speedTarget = math.min(speedTarget, TRAFFIC.IntersectionApproachSlow)
		end
		if gap and not blockedByGap and gap < spacing + VEHICLE.FollowBand then
			speedTarget = math.min(speedTarget, math.max(0.2, (gap - spacing) / VEHICLE.FollowBand))
		end
		local misalign = car.yawOffset
		if misalign and misalign ~= 0 then
			speedTarget = math.min(speedTarget, math.max(0, 1 - math.abs(misalign) / VEHICLE.AlignAngle))
		end
		-- Arrivée à la place du bâtiment, ou case suivante prise : la voiture
		-- freine pour s'arrêter au point d'arrêt (vitesse = racine de 2 a d), au
		-- lieu de s'arrêter net. Un retour part ainsi de l'arrêt.
		if not blocked and mustStop then
			local brake = speed * TRAFFIC.Braking * VEHICLE.StopBrakeFactor
			speedTarget = math.min(speedTarget, math.sqrt(2 * brake * math.max(remain, 0)) / speed)
		end
		if blocked then
			speedTarget = 0
		end

		local factor = car.speedFactor
		if speedTarget > factor then
			factor = math.min(speedTarget, factor + TRAFFIC.Acceleration * h)
		else
			factor = math.max(speedTarget, factor - TRAFFIC.Braking * h)
		end
		car.speedFactor = factor

		car.blocked = blocked
		if blocked then
			car.waitTime += h
			if car.waitTime >= Config.Traffic.StuckAfter and self.recordStat then
				self:recordStat("stuckSeconds", h)
			end
		else
			car.waitTime = math.max(0, car.waitTime - 2 * h)
		end

		local distance = 0
		if not blocked then
			distance = speed * factor * h
			if gap then
				distance = math.min(distance, math.max(0, gap - spacing))
			end
			if mustStop then
				distance = math.min(distance, remain)
			end
		end

		local first = true
		while distance > 0 and car.seg do
			if not first then
				room = segmentRoom(self, car)
				if room == nil then
					-- La case suivante n'est pas libre : on s'arrête à la case.
					break
				end
			end
			first = false
			local current = car.seg
			local available = room - car.s
			if distance < available then
				car.s += distance
				break
			end
			distance -= available
			car.s = room
			if room < current.length then
				-- Arrêt avant l'arc : la voiture attend là.
				break
			end
			car.center = current.to
			if self:arriveAt(car) then
				return true
			end
		end

		seg = car.seg
		if seg then
			car.center = pointAt(seg, car.s)
			local tangent = tangentAt(seg, car.s)
			local heading = car.heading or tangent or DEFAULT_HEADING
			if tangent then
				heading = self:smoothHeading(car, yawOf(tangent), h)
			end
			car.heading = heading

			-- Voie de droite : le décalage suit le cap lissé, donc reste continu.
			local right = Vector3.new(-heading.Z, 0, heading.X)
			local lane = self.tile * VEHICLE.LaneOffsetTiles
			if seg.ctrl and car.s > seg.lineLength then
				local u = math.min((car.s - seg.lineLength) / seg.curveLength, 1)
				lane *= 1 - VEHICLE.CurveLanePull * math.sin(math.pi * u)
			end
			car.pos = car.center + right * lane
			if car.part then
				-- Sur un pont, le tablier est plus haut que la route : la voiture
				-- monte de la même hauteur pour ne pas s'enfoncer dans le tablier.
				local lift = 0
				if next(self.bridges) ~= nil then
					local cx, cy = Grid.cellFromWorld(self.origin, car.pos)
					if self.bridges[Grid.key(cx, cy)] then
						lift = RoadConfig.Layers.Bridge.Top - RoadConfig.Layers.Body.Top
					end
				end
				local position = car.pos + Vector3.new(0, lift, 0)
				car.part:PivotTo(CFrame.lookAt(position, position + heading))
			end
		end
		return false
	end

	-- Met à jour une voiture. Renvoie true si elle doit être retirée.
	function Session:updateCar(car, dt)
		if car.roadVersion ~= self.roadVersion then
			self:replanCar(car)
		end

		if not car.seg then
			-- Sans route, la voiture reste à sa place et réessaie régulièrement.
			-- Après ClaimTimeout elle disparaît : sa demande est alors libérée.
			car.blocked = true
			car.lostTime += dt
			car.retry -= dt
			if car.retry <= 0 then
				self:replanCar(car)
			end
			return car.lostTime >= StoreConfig.Demand.ClaimTimeout
		end

		-- L'amélioration de circulation raccourcit la distance de sécurité.
		local spacing = Config.Traffic.CarSpacing
		if self.getTrafficMultiplier then
			spacing *= self:getTrafficMultiplier()
		end

		local remaining = dt
		while remaining > 0 do
			local h = math.min(remaining, VEHICLE.MaxStep)
			remaining -= h
			if self:stepCar(car, h, spacing) then
				return true
			end
			if not car.seg then
				return false
			end
		end
		return false
	end

	function Session:retireCar(car)
		leaveLane(car)
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
		if house and house.car == car then
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

		-- Suivi par la session : destroy() arrête l'anneau en cours.
		local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		SessionUtil.trackTween(
			self.tweens,
			TweenService:Create(ring, info, {
				Size = Vector3.new(0.1, endSize, endSize),
				Transparency = 1,
			})
		):Play()

		task.delay(0.6, function()
			if ring.Parent then
				ring:Destroy()
			end
		end)
	end
end
