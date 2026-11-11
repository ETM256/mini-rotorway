-- Dimensions partagées (Config.Dimensions) et style (Config.Style) : une seule
-- source pour les tailles visibles. Ordre attendu : route < maison < case.
return function(T, H)
	local function near(a, b, message)
		T.near(a, b, 1e-9, message)
	end

	T.test("dimensions: road is narrower than a house, and a house fits in its cell", function()
		local D = H.load("Config").Dimensions
		T.lt(D.Road.Width, D.Building.House, "road core narrower than a house")
		T.lt(D.Road.Edge, D.Building.House, "white edge never wider than a house")
		T.lt(D.Building.House, 1, "a house stays inside its tile")
	end)

	T.test("dimensions: road layers ordered from core to edge", function()
		local R = H.load("Config").Dimensions.Road
		T.gt(R.Width, 0)
		T.le(R.Width, R.Contour)
		T.le(R.Contour, R.Edge)
		T.le(R.Edge, 1)
	end)

	T.test("dimensions: store footprints ordered and inside the tile", function()
		local B = H.load("Config").Dimensions.Building
		T.lt(B.House, B.SmallStore, "a small store is bigger than a house")
		T.le(B.SmallStore, B.LargeStore, "a large store is at least as big")
		T.lt(B.LargeStore, 1, "stores stay inside their tile")
	end)

	T.test("dimensions: car size is a fraction of a tile and fits the road", function()
		local Config = H.load("Config")
		local car = Config.Dimensions.Car
		T.gt(car.Length, 0)
		T.gt(car.Width, 0)
		T.lt(car.Length, 1)
		T.lt(car.Width, Config.Dimensions.Road.Width, "a car is narrower than the road")
	end)

	T.test("road visuals come from Config.Dimensions (single source of truth)", function()
		local Config = H.load("Config")
		local D = Config.Dimensions
		local V = H.load("RoadConfig").Visual
		near(V.RoadWidth, D.Road.Width, "RoadWidth")
		near(V.EdgeWidth, D.Road.Edge, "EdgeWidth")
		near(V.PreviewScale, D.Road.Edge, "PreviewScale")
	end)

	T.test("road widths are ordered: Width <= Contour <= Edge <= 1, and RoadConfig.Visual keeps the two it uses", function()
		local D = H.load("Config").Dimensions
		local V = H.load("RoadConfig").Visual
		T.le(D.Road.Width, D.Road.Contour)
		T.le(D.Road.Contour, D.Road.Edge)
		T.le(D.Road.Edge, 1)
		T.le(V.RoadWidth, V.EdgeWidth)
		T.le(V.EdgeWidth, 1)
	end)

	T.todo("RoadConfig no longer carries the retired, unread keys (needs core PR: RoadConfig cleanup)", function()
		local R = H.load("RoadConfig")
		for _, key in ipairs({ "ContourWidth", "RibbonEdgeWidth", "RibbonTopWidth" }) do
			T.eq(R.Visual[key], nil, key)
		end
		T.eq(R.Traffic.ReservationReleaseTime, nil, "ReservationReleaseTime")
		T.eq(R.Vehicle.ReservationBackoff, nil, "ReservationBackoff")
	end)

	T.todo("vehicles: sizes follow Config.Dimensions.Car (needs traffic PR: RoadConfig.Vehicle)", function()
		local Config = H.load("Config")
		local vehicle = H.load("RoadConfig").Vehicle
		near(vehicle.LengthTiles, Config.Dimensions.Car.Length, "LengthTiles")
		near(vehicle.WidthTiles, Config.Dimensions.Car.Width, "WidthTiles")
	end)

	T.todo("vehicles: lanes keep cars inside the road and opposite lanes apart (needs traffic PR: RoadConfig.Vehicle)", function()
		local Config = H.load("Config")
		local vehicle = H.load("RoadConfig").Vehicle
		local halfRoad = Config.Dimensions.Road.Width * 0.5
		local halfCar = vehicle.WidthTiles * 0.5
		T.le(vehicle.LaneOffsetTiles + halfCar, halfRoad, "a car must not overhang the road")
		T.ge(2 * vehicle.LaneOffsetTiles, vehicle.WidthTiles, "opposite cars must not overlap")
	end)

	T.test("grid line is thinner than a road, in studs", function()
		local Config = H.load("Config")
		local roadStuds = Config.Dimensions.Road.Width * Config.Grid.TileSize
		T.gt(Config.Dimensions.Grid.LineWidth, 0)
		T.lt(Config.Dimensions.Grid.LineWidth, roadStuds)
		near(Config.Terrain.GridLineWidth, Config.Dimensions.Grid.LineWidth, "terrain grid uses the shared width")
	end)

	T.test("pins: size in screen pixels stays readable without becoming a blob", function()
		local pin = H.load("Config").Dimensions.Pin
		T.ge(pin.Size, 8, "a pin below 8 px is lost when zoomed out")
		T.le(pin.Size, 14, "a pin above 14 px looks like a prototype blob")
	end)

	T.todo("pins: StoreConfig uses the shared pin size (needs buildings PR: StoreConfig.Visual)", function()
		local Config = H.load("Config")
		T.eq(H.load("StoreConfig").Visual.PinSize, Config.Dimensions.Pin.Size, "pin size must come from Config.Dimensions")
	end)

	-- StoreConfig.Visual.SmallSize / LargeSize servent au décalage des pins : elles
	-- égalent l'emprise dessinée des magasins (BuildingModels : tuile x fraction).
	T.todo("store visuals: StoreConfig sizes equal the drawn store footprint in studs (needs buildings PR: StoreConfig.Visual)", function()
		local Config = H.load("Config")
		local visual = H.load("StoreConfig").Visual
		T.near(visual.SmallSize, Config.Dimensions.Building.SmallStore * Config.Grid.TileSize, 1e-6, "small store")
		T.near(visual.LargeSize, Config.Dimensions.Building.LargeStore * Config.Grid.TileSize, 1e-6, "large store")
	end)

	T.test("style: corner radii grow from small to large, in pixels", function()
		local radius = H.load("Config").Style.CornerRadius
		T.gt(radius.Small, 0)
		T.lt(radius.Small, radius.Medium)
		T.lt(radius.Medium, radius.Large)
	end)

	T.test("style: building corner ratio is a fraction of the short side", function()
		local ratio = H.load("Config").Style.BuildingCornerRatio
		T.gt(ratio, 0)
		T.le(ratio, 0.5)
	end)

	T.test("style: shadows are soft (transparent, small offset, never black)", function()
		local Config = H.load("Config")
		local shadow = Config.Style.Shadow
		T.ge(shadow.Transparency, 0.6, "a shadow must stay discreet")
		T.lt(shadow.Transparency, 1, "a shadow must still be visible")
		T.ge(shadow.Offset, 0)
		T.lt(shadow.Offset, Config.Grid.TileSize * 0.25, "a shadow stays inside its tile")
		T.ge(shadow.Grow, 0)
	end)

	T.test("style: outlines are thin and capped", function()
		local outline = H.load("Config").Style.Outline
		T.gt(outline.Thin, 0)
		T.le(outline.Thin, outline.Max)
		T.le(outline.Max, 2, "no thick dark outline")
	end)

	T.test("style: animations are short and ordered", function()
		local motion = H.load("Config").Style.Motion
		local ordered = { "Hover", "Fast", "Standard", "Spawn", "Evolution" }
		local last = 0
		for _, name in ipairs(ordered) do
			T.gt(motion[name], 0, name)
			T.le(motion[name], 0.6, name .. " must stay short")
			T.ge(motion[name], last, name .. " must not be faster than the previous one")
			last = motion[name]
		end
	end)

	T.test("version: semantic version string", function()
		local version = H.load("Config").Version
		T.eq(type(version), "string")
		T.ok(string.match(version, "^%d+%.%d+%.%d+$") ~= nil, "Version must be MAJOR.MINOR.PATCH")
	end)
end
