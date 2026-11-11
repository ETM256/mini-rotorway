return function(T, H)
	-- Instances par aperçu (cadre, halo, formes, routes, maisons et leurs ombres).
	-- Une ellipse ou une barre coûte un cadre et un coin ; le liseré de côte
	-- double chaque forme d'eau. CEILING est le plafond de non-régression, au pire
	-- cas mesuré avant la refonte des rivières (dubai : 32 ellipses d'eau) ;
	-- BUDGET est la cible du menu.
	local CEILING = 160
	local BUDGET = 120
	local DIAMETER = 200

	local function sameColor(a, b)
		return a.R == b.R and a.G == b.G and a.B == b.B
	end

	local function newSetup()
		H.asClient()
		local MapPreview = H.load("UI/MapPreview")
		local Theme = H.load("UI/Theme")
		local Config = H.load("Config")
		local gui = Theme.new("ScreenGui", { Parent = H.localPlayer.PlayerGui })
		local parent = Theme.new("Frame", { Parent = gui, Size = UDim2.fromOffset(400, 400) })
		return MapPreview, Theme, Config, parent
	end

	-- Étendue des centres des pièces d'une couleur donnée (coordonnées du disque).
	local function extentOf(circle, color, zIndex)
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		local found = 0
		for _, child in ipairs(circle:GetChildren()) do
			if child:IsA("Frame") and child.ZIndex == zIndex and sameColor(child.BackgroundColor3, color) then
				found += 1
				local x = child.Position.X.Offset
				local y = child.Position.Y.Offset
				minX = math.min(minX, x)
				maxX = math.max(maxX, x)
				minY = math.min(minY, y)
				maxY = math.max(maxY, y)
			end
		end
		return { found = found, minX = minX, maxX = maxX, minY = minY, maxY = maxY }
	end

	T.test("the six maps build without error", function()
		local MapPreview, _, _, parent = newSetup()
		local Maps = H.load("Maps")
		T.eq(#Maps.all(), 6)
		for _, map in ipairs(Maps.all()) do
			local circle = MapPreview.create(parent, map, DIAMETER, UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
			T.ok(circle, map.id .. " returns its disc")
			T.eq(circle.Name, "Preview_" .. map.id)
		end
	end)

	T.test("every preview stays under the instance ceiling", function()
		local MapPreview, _, _, parent = newSetup()
		local Maps = H.load("Maps")
		for _, map in ipairs(Maps.all()) do
			local before = H.instanceCount()
			MapPreview.create(parent, map, DIAMETER, UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
			T.le(H.instanceCount() - before, CEILING, map.id .. " instance ceiling")
		end
	end)

	-- Cible de 120 instances : les rivières de dubai et los_angeles sont des
	-- chaînes de 5 ellipses (au lieu de 19), ce qui ramène les aperçus à 101 et 87.
	T.test("the previews fit the 120-instance target", function()
		local MapPreview, _, _, parent = newSetup()
		local Maps = H.load("Maps")
		for _, map in ipairs(Maps.all()) do
			local before = H.instanceCount()
			MapPreview.create(parent, map, DIAMETER, UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
			T.le(H.instanceCount() - before, BUDGET, map.id .. " instance budget")
		end
	end)

	T.test("the preview is a clipped disc with no outline and no text", function()
		local MapPreview, _, _, parent = newSetup()
		local Maps = H.load("Maps")
		local circle = MapPreview.create(parent, Maps.getById("los_angeles"), DIAMETER, nil, nil)
		T.ok(circle:IsA("CanvasGroup"), "CanvasGroup clips its children to the disc")
		local corner = H.find(circle, { class = "UICorner" })[1]
		T.eq(corner.CornerRadius.Offset, DIAMETER / 2)
		local wrapper = circle.Parent
		T.eq(#H.find(wrapper, { class = "UIStroke" }), 0, "no hard rim")
		T.eq(#H.find(wrapper, { class = "TextLabel" }), 0, "no side labels")
	end)

	T.test("houses use the palette of the house groups", function()
		local MapPreview, _, Config, parent = newSetup()
		local Maps = H.load("Maps")
		local circle = MapPreview.create(parent, Maps.getById("dubai"), DIAMETER, nil, nil)
		local houses = H.find(circle, { name = "House" })
		T.ok(#houses > 0, "at least one house on the network")
		for _, house in ipairs(houses) do
			local known = false
			for _, entry in ipairs(Config.HouseColors) do
				if sameColor(entry.color, house.BackgroundColor3) then
					known = true
				end
			end
			T.ok(known, "house colour comes from Config.HouseColors")
			T.ok(house.Position.X.Offset >= 0 and house.Position.X.Offset <= DIAMETER, "house inside the disc")
		end
	end)

	-- Direction du grand axe d'un cadre tourné (repère d'écran, sens horaire).
	local function axisOf(frame)
		local angle = math.rad(frame.Rotation)
		return math.cos(angle), math.sin(angle)
	end

	T.test("an ellipse is one rotated frame whose long axis follows rx", function()
		local MapPreview, _, Config, parent = newSetup()
		local C = Config.Colors
		local wide = {
			id = "wide",
			land = C.Land,
			water = C.Water,
			waterShapes = { { type = "ellipse", x = 0.5, y = 0.5, rx = 0.2, ry = 0.05, rotation = 0 } },
		}
		local circle = MapPreview.create(parent, wide, DIAMETER, nil, nil)
		local ext = extentOf(circle, C.Water, 3)
		T.eq(ext.found, 1, "one frame for one ellipse")
		local frame = nil
		for _, child in ipairs(circle:GetChildren()) do
			if child:IsA("Frame") and child.ZIndex == 3 and sameColor(child.BackgroundColor3, C.Water) then
				frame = child
			end
		end
		T.near(frame.Size.X.Offset, 2 * 0.2 * DIAMETER, 0.01, "rx spans the long axis")
		T.near(frame.Size.Y.Offset, 2 * 0.05 * DIAMETER, 0.01, "ry spans the short axis")
		local dx = axisOf(frame)
		T.near(math.abs(dx), 1, 1e-6, "long axis horizontal")
		T.eq(#H.find(frame, { class = "UICorner" }), 1, "rounded ends make the capsule")

		local rotated = {
			id = "rotated",
			land = C.Land,
			water = C.Water,
			waterShapes = { { type = "ellipse", x = 0.5, y = 0.5, rx = 0.2, ry = 0.05, rotation = 90 } },
		}
		local turned = MapPreview.create(parent, rotated, DIAMETER, nil, nil)
		local turnedFrame = extentOf(turned, C.Water, 3)
		T.eq(turnedFrame.found, 1)
		local turnedShape = nil
		for _, child in ipairs(turned:GetChildren()) do
			if child:IsA("Frame") and child.ZIndex == 3 and sameColor(child.BackgroundColor3, C.Water) then
				turnedShape = child
			end
		end
		local tx, ty = axisOf(turnedShape)
		T.near(math.abs(ty), 1, 1e-6, "rotated 90 degrees: the long axis runs vertically")
		T.near(math.abs(tx), 0, 1e-6, "no horizontal spread after rotation")
	end)

	T.test("ry as the larger radius turns the frame so its long axis is vertical", function()
		local MapPreview, _, Config, parent = newSetup()
		local C = Config.Colors
		local tall = {
			id = "tall",
			land = C.Land,
			water = C.Water,
			waterShapes = { { type = "ellipse", x = 0.5, y = 0.5, rx = 0.05, ry = 0.2, rotation = 0 } },
		}
		local circle = MapPreview.create(parent, tall, DIAMETER, nil, nil)
		local frame = nil
		for _, child in ipairs(circle:GetChildren()) do
			if child:IsA("Frame") and child.ZIndex == 3 and sameColor(child.BackgroundColor3, C.Water) then
				frame = child
			end
		end
		T.ok(frame, "the tall ellipse is drawn")
		T.near(frame.Size.X.Offset, 2 * 0.2 * DIAMETER, 0.01, "ry is the long side")
		T.near(frame.Size.Y.Offset, 2 * 0.05 * DIAMETER, 0.01, "rx is the short side")
		local _, ty = axisOf(frame)
		T.near(math.abs(ty), 1, 1e-6, "the long axis runs vertically")
	end)

	T.test("a circle is a square frame with fully rounded ends", function()
		local MapPreview, _, Config, parent = newSetup()
		local C = Config.Colors
		local round = {
			id = "round",
			land = C.Land,
			water = C.Water,
			waterShapes = { { type = "ellipse", x = 0.5, y = 0.5, rx = 0.1, ry = 0.1, rotation = 0 } },
		}
		local circle = MapPreview.create(parent, round, DIAMETER, nil, nil)
		local frame = nil
		for _, child in ipairs(circle:GetChildren()) do
			if child:IsA("Frame") and child.ZIndex == 3 and sameColor(child.BackgroundColor3, C.Water) then
				frame = child
			end
		end
		T.ok(frame, "the disc is drawn")
		T.near(frame.Size.X.Offset, 2 * 0.1 * DIAMETER, 0.01)
		T.near(frame.Size.Y.Offset, 2 * 0.1 * DIAMETER, 0.01)
		local corner = H.find(frame, { class = "UICorner" })[1]
		T.eq(corner.CornerRadius.Scale, 0.5, "a half-scale corner makes a disc")
	end)

	T.test("a bar is a capsule of its length plus both round ends", function()
		local MapPreview, _, Config, parent = newSetup()
		local C = Config.Colors
		local map = {
			id = "bar",
			land = C.Land,
			water = C.Water,
			waterShapes = { { type = "bar", x1 = 0.2, y1 = 0.5, x2 = 0.8, y2 = 0.5, thickness = 0.04 } },
		}
		local circle = MapPreview.create(parent, map, DIAMETER, nil, nil)
		local bars = {}
		for _, child in ipairs(circle:GetChildren()) do
			if child:IsA("Frame") and child.ZIndex == 3 and sameColor(child.BackgroundColor3, C.Water) then
				table.insert(bars, child)
			end
		end
		T.eq(#bars, 1, "one capsule for one bar")
		local capsule = bars[1]
		T.near(capsule.Size.X.Offset, 0.6 * DIAMETER + 0.04 * DIAMETER, 0.01, "length + thickness")
		T.near(capsule.Size.Y.Offset, 0.04 * DIAMETER, 0.01, "thickness")
		T.near(capsule.Position.X.Offset, 0.5 * DIAMETER, 0.01, "centred on the segment")
	end)

	T.test("a vertical bar is rotated 90 degrees around its centre", function()
		local MapPreview, _, Config, parent = newSetup()
		local C = Config.Colors
		local map = {
			id = "vertical",
			land = C.Land,
			water = C.Water,
			waterShapes = { { type = "bar", x1 = 0.5, y1 = 0.2, x2 = 0.5, y2 = 0.8, thickness = 0.04 } },
		}
		local circle = MapPreview.create(parent, map, DIAMETER, nil, nil)
		local bar = nil
		for _, child in ipairs(circle:GetChildren()) do
			if child:IsA("Frame") and child.ZIndex == 3 and sameColor(child.BackgroundColor3, C.Water) then
				bar = child
			end
		end
		T.ok(bar, "bar drawn")
		T.near(bar.Rotation, 90, 1e-6)
		T.near(bar.Size.X.Offset, 0.6 * DIAMETER + 0.04 * DIAMETER, 0.01)
		T.near(bar.Position.Y.Offset, 0.5 * DIAMETER, 0.01)
	end)

	T.test("a flat-start bar ends flat on the land side and round on the water side", function()
		local MapPreview, _, Config, parent = newSetup()
		local C = Config.Colors
		local map = {
			id = "flat",
			land = C.Land,
			water = C.Water,
			waterShapes = { { type = "bar", x1 = 0.2, y1 = 0.5, x2 = 0.8, y2 = 0.5, thickness = 0.04, flatStart = true } },
		}
		local circle = MapPreview.create(parent, map, DIAMETER, nil, nil)
		local body, cap = nil, nil
		for _, child in ipairs(circle:GetChildren()) do
			if child:IsA("Frame") and child.ZIndex == 3 and sameColor(child.BackgroundColor3, C.Water) then
				if child.Size.X.Offset > child.Size.Y.Offset then
					body = child
				else
					cap = child
				end
			end
		end
		T.ok(body and cap, "a flat body and a round cap")
		T.near(body.Size.X.Offset, 0.6 * DIAMETER, 0.01, "body spans exactly x1 to x2")
		T.near(cap.Position.X.Offset, 0.8 * DIAMETER, 0.01, "cap sits on x2")
		T.eq(#H.find(cap, { class = "UICorner" }), 1, "cap is round")
		T.eq(#H.find(body, { class = "UICorner" }), 0, "body has square ends")
	end)

	T.test("a minimal or malformed map still builds", function()
		local MapPreview, _, Config, parent = newSetup()
		local C = Config.Colors
		local bare = MapPreview.create(parent, { id = "bare" }, DIAMETER, nil, nil)
		T.ok(bare, "a map with only an id builds")
		T.eq(bare.Name, "Preview_bare")

		local odd = MapPreview.create(parent, {
			land = C.Land,
			waterShapes = { { type = "blob", x = 0.5, y = 0.5 }, { type = "ellipse", x = 0.5, y = 0.5, rx = 0, ry = 0 } },
			dryShapes = nil,
			previewRoads = { { 0.2, 0.2 }, { 0.2, 0.2, 0.8, 0.2 } },
		}, DIAMETER, nil, nil)
		T.ok(odd, "unknown shapes, zero ellipses and short roads are skipped")
		T.ok(odd.Parent ~= nil)
	end)

	T.test("two previews of one map are two separate discs", function()
		local MapPreview, _, _, parent = newSetup()
		local Maps = H.load("Maps")
		local a = MapPreview.create(parent, Maps.getById("dubai"), DIAMETER, nil, nil)
		local b = MapPreview.create(parent, Maps.getById("dubai"), DIAMETER, nil, nil)
		T.ok(a ~= b, "each call builds its own preview")
		T.eq(#H.find(parent, { name = "PreviewFrame_dubai" }), 2)
	end)
end
