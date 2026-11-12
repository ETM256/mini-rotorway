return function(T, H)
	-- Audit des visuels serveur contre le vrai moteur : orientation des disques,
	-- hauteurs des couches, parts translucides, tweens et indicateurs de
	-- collision. Le faux monde n'affiche rien : on vérifie la géométrie.

	local EPS = 1e-6

	-- Une scène complète : maison, magasin reliés, rond-point, voitures en route.
	local function scene()
		local session = H.newSession("los_angeles")
		session.budget = 200
		session.roundaboutsLeft = 2
		local house, store = H.houseAndStore(session)
		H.connect(session, house, store)
		for key in pairs(session.roads) do
			if not session.bridges[key] and not session.roundaboutParts[key] then
				local x, y = H.load("Grid").parse(key)
				session:placeRoundabout(x, y)
				break
			end
		end
		H.runSession(session, 30, 0.1, { autoChoose = true })
		return session
	end

	local function parts(session)
		local list = {}
		for _, descendant in ipairs(session.world.folder:GetDescendants()) do
			if descendant:IsA("BasePart") then
				list[#list + 1] = descendant
			end
		end
		return list
	end

	-- Boîte englobante en XZ et hauteur du dessus, d'après la rotation réelle.
	local function bounds(part)
		local cf, size = part.CFrame, part.Size
		local right, up, look = cf.RightVector, cf.UpVector, cf.LookVector
		local halfX = math.abs(right.X) * size.X * 0.5 + math.abs(up.X) * size.Y * 0.5 + math.abs(look.X) * size.Z * 0.5
		local halfY = math.abs(right.Y) * size.X * 0.5 + math.abs(up.Y) * size.Y * 0.5 + math.abs(look.Y) * size.Z * 0.5
		local halfZ = math.abs(right.Z) * size.X * 0.5 + math.abs(up.Z) * size.Y * 0.5 + math.abs(look.Z) * size.Z * 0.5
		local p = part.Position
		return p.X - halfX, p.X + halfX, p.Z - halfZ, p.Z + halfZ, p.Y + halfY
	end

	local function sameColor(a, b)
		return math.abs(a.R - b.R) < 1e-4 and math.abs(a.G - b.G) < 1e-4 and math.abs(a.B - b.B) < 1e-4
	end

	T.test("every cylinder is a flat disc: axis vertical, thickness on X, diameters on Y and Z", function()
		local session = scene()
		T.ok(#H.find(session.world.Cars, { class = "BasePart" }) > 0 or #session.cars > 0, "the scene has cars")
		local cylinders = 0
		for _, part in ipairs(parts(session)) do
			if part.Shape == Enum.PartType.Cylinder then
				cylinders += 1
				local label = part:GetFullName()
				T.ge(math.abs(part.CFrame.RightVector.Y), 0.999, label .. ": the cylinder axis is not vertical")
				T.le(part.Size.X, math.min(part.Size.Y, part.Size.Z) + EPS, label .. ": the disc is thicker than wide")
			end
		end
		T.gt(cylinders, 20, "the scene uses cylinders (roads, buildings, cars, trees)")
	end)

	T.test("no part is thinner than the engine minimum", function()
		local session = scene()
		for _, part in ipairs(parts(session)) do
			local size = part.Size
			T.ge(math.min(size.X, size.Y, size.Z), 0.001, part:GetFullName() .. " is too thin")
		end
	end)

	T.test("terrain ellipses and shoreline caps are flat discs, not sphere meshes", function()
		local session = scene()
		T.eq(#H.find(session.world.folder, { class = "SpecialMesh" }), 0, "no SpecialMesh dome in the world")
	end)

	T.test("only the ground is hit by raycasts; nothing collides, touches or casts a shadow", function()
		local session = scene()
		for _, part in ipairs(parts(session)) do
			local label = part:GetFullName()
			T.falsy(part.CanCollide, label .. " collides")
			T.falsy(part.CanTouch, label .. " fires touches")
			T.falsy(part.CastShadow, label .. " casts a shadow")
			T.ok(part.Anchored, label .. " is not anchored")
			T.eq(part.CanQuery, part.Name == "Ground", label .. " raycast flag")
		end
	end)

	-- Deux couleurs différentes ne partagent jamais le même plan de dessus : sous
	-- 0.01 stud d'écart elles se disputeraient le tampon de profondeur.
	T.test("different-coloured faces never share a plane (roads, buildings, cars)", function()
		local session = scene()
		local list = {}
		for _, folder in ipairs({ session.world.Roads, session.world.Buildings, session.world.Cars, session.world.FX }) do
			for _, descendant in ipairs(folder:GetDescendants()) do
				if descendant:IsA("BasePart") then
					local x0, x1, z0, z1, top = bounds(descendant)
					list[#list + 1] = { part = descendant, x0 = x0, x1 = x1, z0 = z0, z1 = z1, top = top }
				end
			end
		end
		T.gt(#list, 30, "enough parts to compare")
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				if math.abs(a.top - b.top) < 0.01 - EPS and not sameColor(a.part.Color, b.part.Color) then
					local overlapX = math.min(a.x1, b.x1) - math.max(a.x0, b.x0)
					local overlapZ = math.min(a.z1, b.z1) - math.max(a.z0, b.z0)
					T.falsy(
						overlapX > 1e-3 and overlapZ > 1e-3,
						a.part:GetFullName() .. " and " .. b.part:GetFullName() .. " share a plane"
					)
				end
			end
		end
	end)

	-- Un recouvrement de deux parts translucides serait mélangé deux fois : une
	-- croix plus foncée dans l'ombre. Les ombres sont donc d'une seule part.
	T.test("translucent parts of a building never overlap each other", function()
		local BuildingModels = H.load("BuildingModels")
		for _, case in ipairs({ { "house", nil }, { "store", "small" }, { "store", "large" } }) do
			for id = 1, 4 do
				local model = BuildingModels.build("store" == case[1] and "store" or "house", id, Vector3.new(0, 0, 0), 1, case[2])
				local translucent = {}
				for _, descendant in ipairs(model:GetDescendants()) do
					if descendant:IsA("BasePart") and descendant.Transparency > 0 then
						local x0, x1, z0, z1 = bounds(descendant)
						translucent[#translucent + 1] = { name = descendant.Name, x0 = x0, x1 = x1, z0 = z0, z1 = z1 }
					end
				end
				T.ge(#translucent, 1, case[1] .. " has a soft shadow")
				T.le(#translucent, 1, case[1] .. " " .. tostring(case[2]) .. ": the shadow is one part, so it cannot overlap itself")
			end
		end
	end)

	T.test("a car shadow sits above the road and the roundabout ring", function()
		local CarModel = H.load("CarModel")
		local layers = H.load("RoadConfig").Layers
		local model = CarModel.create(Color3.new(1, 0, 0), 4)
		local shadow = model:FindFirstChild("Shadow")
		T.ok(shadow, "the car has a shadow")
		local worldBottom = CarModel.CenterY + shadow.Position.Y - shadow.Size.Y * 0.5
		T.gt(worldBottom, layers.Body.Top, "the shadow is above the road")
		T.gt(worldBottom, layers.RoundaboutBody.Top - EPS, "the shadow is above the roundabout ring")
		T.ok(shadow.Transparency > 0, "the shadow is soft")
	end)

	T.test("grid crossings do not share a plane: horizontal lines sit above vertical ones", function()
		local session = H.newSession("los_angeles")
		local v = H.find(session.world.Grid, { name = "GridV" })[1]
		local h = H.find(session.world.Grid, { name = "GridH" })[1]
		T.ge(h.Position.Y - v.Position.Y, 0.01 - EPS, "the crossing of two translucent lines is ordered")
	end)

	T.test("terrain ellipses keep the full footprint of their shape", function()
		local session = H.newSession("los_angeles")
		local grass = H.find(session.world.Grass, { name = "Grass" })
		for _, part in ipairs(grass) do
			if part.Shape == Enum.PartType.Cylinder then
				T.near(part.Position.Y + part.Size.X * 0.5, 0.015, 1e-6, "an ellipse keeps a flat top at the grass height")
			end
		end
	end)

	local function freeLine(session, length)
		local Grid, Maps = H.load("Grid"), H.load("Maps")
		for y = 0, session.size - 1 do
			for startX = 0, session.size - length do
				local cells, ok = {}, true
				for i = 0, length - 1 do
					local x = startX + i
					if session.buildings[Grid.key(x, y)] or Maps.isWater(session.map, x, y) then
						ok = false
						break
					end
					cells[#cells + 1] = { x, y }
				end
				if ok then
					return cells
				end
			end
		end
		return nil
	end

	-- Tweens dont la cible est une pièce de route (les bâtiments en ont aussi).
	local function roadTweens(session)
		local n = 0
		for tween in pairs(session.tweens) do
			if tween.Instance:IsDescendantOf(session.world.Roads) then
				n += 1
			end
		end
		return n
	end

	T.test("a stroke longer than MaxAnimatedCells appears without any tween", function()
		local session = H.newSession("los_angeles")
		session.budget = 100
		local RoadConfig = H.load("RoadConfig")
		local line = freeLine(session, 6)
		RoadConfig.Construction.MaxAnimatedCells = 5
		session:drawRoad(line)
		T.eq(roadTweens(session), 0, "no road tween for a long stroke")
		for _, part in ipairs(H.find(session.world.Roads, { class = "BasePart" })) do
			T.eq(part.Transparency, 0, "the road part is opaque at once")
		end
		T.gt(H.count(session.world.Roads, "BasePart"), 0, "the road is drawn")
	end)

	T.test("a stroke within MaxAnimatedCells still animates", function()
		local session = H.newSession("los_angeles")
		session.budget = 100
		local RoadConfig = H.load("RoadConfig")
		local line = freeLine(session, 5)
		RoadConfig.Construction.MaxAnimatedCells = 5
		session:drawRoad(line)
		T.gt(roadTweens(session), 0, "a short stroke animates its new cells")
	end)

	T.test("the default animation limit keeps a 40-cell stroke under 250 tweened parts", function()
		local RoadConfig = H.load("RoadConfig")
		local limit = RoadConfig.Construction.MaxAnimatedCells
		T.le(limit, 40, "the animated stroke length stays bounded")
		-- Pire cas par case : un virage (3 pièces de liseré, 3 de surface).
		T.le(limit * 6, 250, "worst-case simultaneous road tweens")
	end)

	T.test("erasing a cell mid-animation cancels its tweens: none runs on a destroyed part", function()
		local session = H.newSession("los_angeles")
		session.budget = 100
		local line = freeLine(session, 4)
		session:drawRoad(line)
		local before = roadTweens(session)
		T.gt(before, 0, "the stroke is animating")
		local Grid = H.load("Grid")
		session:eraseRoad(Grid.key(line[2][1], line[2][2]))
		for tween in pairs(session.tweens) do
			T.ok(tween.Instance:IsDescendantOf(session.world.folder), "a tween still targets a destroyed part")
		end
		T.lt(roadTweens(session), before, "the tweens of the erased cell were cancelled")
	end)

	T.test("makePart defaults: anchored, no collision, no query, no shadow", function()
		local part = H.load("SessionUtil").makePart({ Name = "X", Size = Vector3.new(1, 1, 1) })
		T.ok(part.Anchored)
		T.falsy(part.CanCollide)
		T.falsy(part.CanQuery)
		T.falsy(part.CanTouch)
		T.falsy(part.CastShadow)
	end)
end
