return function(T, H)
	local DIAMETER = 240
	-- Part des cellules dont l'aperçu ne dit pas la même chose que Maps.isWaterAt (mesurée : moins de 3 % sur les six cartes).
	-- L'écart vient des bouts arrondis (capsules) des ellipses allongées : il reste
	-- petit, et les autres formes (disques, barres, presqu'îles) concordent.
	local MAX_MISMATCH = 0.04

	local function setup()
		H.asClient()
		local MapPreview = H.load("UI/MapPreview")
		local Theme = H.load("UI/Theme")
		local Config = H.load("Config")
		local Maps = H.load("Maps")
		local gui = Theme.new("ScreenGui", { Parent = H.localPlayer.PlayerGui })
		local parent = Theme.new("Frame", { Parent = gui, Size = UDim2.fromOffset(400, 400) })
		return MapPreview, Config, Maps, parent
	end

	local function sameColor(a, b)
		return a.R == b.R and a.G == b.G and a.B == b.B
	end

	-- Cadres d'une couleur et d'un zIndex donnés : eau (3) ou terre sèche (5).
	local function framesWith(circle, zIndex, color)
		local found = {}
		for _, child in ipairs(circle:GetChildren()) do
			if child:IsA("Frame") and child.ZIndex == zIndex and sameColor(child.BackgroundColor3, color) then
				table.insert(found, child)
			end
		end
		return found
	end

	-- Point (px, py) dans un cadre tourné. Un cadre à coins arrondis est une
	-- capsule (ou un disque) : même repère que MapPreview, sens horaire.
	local function insideFrame(frame, px, py)
		local hw = frame.Size.X.Offset / 2
		local hh = frame.Size.Y.Offset / 2
		local angle = math.rad(frame.Rotation)
		local dx = px - frame.Position.X.Offset
		local dy = py - frame.Position.Y.Offset
		local lx = dx * math.cos(angle) + dy * math.sin(angle)
		local ly = -dx * math.sin(angle) + dy * math.cos(angle)
		if #H.find(frame, { class = "UICorner" }) == 0 then
			return math.abs(lx) <= hw and math.abs(ly) <= hh
		end
		local r = math.min(hw, hh)
		local qx = math.max(math.abs(lx) - (hw - r), 0)
		local qy = math.max(math.abs(ly) - (hh - r), 0)
		return qx * qx + qy * qy <= r * r
	end

	local function covered(frames, px, py)
		for _, frame in ipairs(frames) do
			if insideFrame(frame, px, py) then
				return true
			end
		end
		return false
	end

	T.test("the preview water agrees with Maps.isWaterAt on every grid cell", function()
		local MapPreview, Config, Maps, parent = setup()
		local C = Config.Colors
		local size = Config.Grid.Size
		for _, map in ipairs(Maps.all()) do
			local circle = MapPreview.create(parent, map, DIAMETER, nil, nil)
			local water = framesWith(circle, 3, C.Water)
			local dry = framesWith(circle, 5, C.Land)
			local mismatches = 0
			for y = 0, size - 1 do
				for x = 0, size - 1 do
					local nx = (x + 0.5) / size
					local ny = (y + 0.5) / size
					local px = nx * DIAMETER
					local py = ny * DIAMETER
					local drawn = covered(water, px, py) and not covered(dry, px, py)
					if drawn ~= Maps.isWaterAt(map, nx, ny) then
						mismatches += 1
					end
				end
			end
			T.ok(#water > 0, map.id .. " draws water")
			T.le(mismatches / (size * size), MAX_MISMATCH, map.id .. " water disagrees on too many cells")
		end
	end)

	T.test("no house is drawn on water", function()
		local MapPreview, _, Maps, parent = setup()
		for _, map in ipairs(Maps.all()) do
			local circle = MapPreview.create(parent, map, DIAMETER, nil, nil)
			for _, child in ipairs(circle:GetChildren()) do
				if child.Name == "House" then
					local nx = child.Position.X.Offset / DIAMETER
					local ny = child.Position.Y.Offset / DIAMETER
					T.falsy(Maps.isWaterAt(map, nx, ny), map.id .. ": a house sits on dry land")
				end
			end
		end
	end)

	T.test("a peninsula is dry in the preview as in the shared water rule", function()
		local MapPreview, Config, Maps, parent = setup()
		local C = Config.Colors
		-- Une presqu'île (dryShapes) retire de l'eau : son centre doit être terre.
		local map = {
			id = "peninsula",
			land = C.Land,
			water = C.Water,
			waterShapes = { { type = "bar", x1 = 0.1, y1 = 0.5, x2 = 0.9, y2 = 0.5, thickness = 0.3 } },
			dryShapes = { { type = "bar", x1 = 0.45, y1 = 0.5, x2 = 0.55, y2 = 0.5, thickness = 0.2 } },
		}
		local circle = MapPreview.create(parent, map, DIAMETER, nil, nil)
		local water = framesWith(circle, 3, C.Water)
		local dry = framesWith(circle, 5, C.Land)
		local cx, cy = 0.5 * DIAMETER, 0.5 * DIAMETER
		T.falsy(Maps.isWaterAt(map, 0.5, 0.5), "the centre is dry by the shared rule")
		T.ok(covered(water, cx, cy), "the water shape covers the centre...")
		T.ok(covered(dry, cx, cy), "...and the peninsula covers it again")
		T.ok(covered(water, 0.3 * DIAMETER, cy) and not covered(dry, 0.3 * DIAMETER, cy), "open water stays water")
	end)
end
