return function(T, H)
	-- Réseaux difficiles rastérisés sur le plateau entier : blocs 2x2, anneau,
	-- escalier, croix et route entre deux bâtiments, case en bord de plateau.
	-- Chaque point est rattaché à sa case (floor), puis testé contre les pièces
	-- de cette case seulement : la continuité aux jointures, les coins et les
	-- fuites sont vérifiés sans supposer le découpage en pièces.

	local RG = H.load("RoadGeometry")
	local VIS = H.load("RoadConfig").Visual

	local HALF = VIS.RoadWidth * 0.5
	local LOW = 0.5 - HALF
	local HIGH = 0.5 + HALF
	local SEAM_OFFSETS = { -0.2, -0.1, 0, 0.1, 0.2 }
	local EPS = 0.005

	local function parseKey(key)
		local x, y = string.match(key, "^(%-?%d+):(%-?%d+)$")
		return tonumber(x), tonumber(y)
	end

	-- Réseau à partir de la liste des cases de route et des raccords (clés
	-- "x:y>N"), transformés en ensembles comme les attend RoadGeometry.
	local function networkOf(cells, connectorKeys)
		local roads, connectors = {}, {}
		for _, key in ipairs(cells) do
			roads[key] = true
		end
		for _, key in ipairs(connectorKeys or {}) do
			connectors[key] = true
		end
		return { roads = roads, bridges = {}, connectors = connectors }
	end

	-- Couverture d'un point du plateau. surfaceOnly ignore le liseré.
	local function coveredAt(net, px, py, surfaceOnly)
		local cx, cy = math.floor(px), math.floor(py)
		local pieces = RG.cellPieces(net.roads, net.bridges, net.connectors, cx, cy)
		local u, v = px - cx, py - cy
		for _, piece in ipairs(pieces) do
			if not (surfaceOnly and piece.layer == "edge") then
				local du, dv = u - piece.cx, v - piece.cy
				if piece.kind == "disk" then
					if du * du + dv * dv <= piece.r * piece.r then
						return true
					end
				elseif math.abs(du) <= piece.w * 0.5 + 1e-9 and math.abs(dv) <= piece.h * 0.5 + 1e-9 then
					return true
				end
			end
		end
		return false
	end

	-- Chaque jointure entre deux cases de route est couverte sur toute sa
	-- largeur (points décalés le long de la jointure), et chaque case est
	-- couverte en son centre.
	local function checkJoints(net, label)
		for key in pairs(net.roads) do
			local x, y = parseKey(key)
			T.ok(coveredAt(net, x + 0.5, y + 0.5, true), label .. ": centre de " .. key .. " non couvert")
			for _, pair in ipairs({ { 1, 0 }, { 0, 1 } }) do
				local dx, dy = pair[1], pair[2]
				if net.roads[(x + dx) .. ":" .. (y + dy)] then
					local baseX = x + 0.5 + dx * 0.5
					local baseY = y + 0.5 + dy * 0.5
					for _, offset in ipairs(SEAM_OFFSETS) do
						local px = baseX + dy * offset
						local py = baseY + dx * offset
						T.ok(
							coveredAt(net, px, py, true),
							string.format("%s: jointure %s / %d:%d trouee en %.2f, %.2f", label, key, x + dx, y + dy, px, py)
						)
					end
				end
			end
		end
	end

	T.test("bloc 2x2 : jointures continues, coin exterieur arrondi, coin interieur vif", function()
		local net = networkOf({ "2:2", "3:2", "2:3", "3:3" })
		checkJoints(net, "bloc 2x2")
		-- Coin extérieur NW de la case (2,2) : arrondi, donc vide au coin exact.
		T.falsy(coveredAt(net, 2 + LOW + EPS, 2 + LOW + EPS, true), "bloc 2x2 : coin exterieur vif")
		-- Coin intérieur (case (2,2), angle SE) : angle rentrant vif, rien de peint au-delà.
		T.ok(coveredAt(net, 2 + HIGH - EPS, 2 + HIGH - EPS, true), "bloc 2x2 : coin interieur manquant")
		T.falsy(coveredAt(net, 2 + HIGH + EPS, 2 + HIGH + EPS, true), "bloc 2x2 : fuite dans le coin interieur")
	end)

	T.test("anneau 3x3 sans centre : chaque jointure couverte, centre libre", function()
		local cells = { "1:1", "2:1", "3:1", "3:2", "3:3", "2:3", "1:3", "1:2" }
		local net = networkOf(cells)
		checkJoints(net, "anneau")
		T.falsy(coveredAt(net, 2.5, 2.5, false), "anneau : le centre ne doit pas etre route")
	end)

	T.test("escalier diagonal : jointures continues sur tout le chemin", function()
		local net = networkOf({ "1:1", "2:1", "2:2", "3:2", "3:3" })
		checkJoints(net, "escalier")
		-- Les cases en diagonale ne se touchent pas : rien de peint au coin commun.
		T.falsy(coveredAt(net, 2.0 + EPS, 2.0 + EPS, false), "escalier : fuite au coin commun")
	end)

	T.test("croix entre quatre batiments : bras jusqu'au bord, coins vides", function()
		local net = networkOf({ "3:3" }, { "3:3>N", "3:3>E", "3:3>S", "3:3>W" })
		T.ok(coveredAt(net, 3.5, 3 + EPS, true), "croix : bord N non atteint")
		T.ok(coveredAt(net, 3.5, 4 - EPS, true), "croix : bord S non atteint")
		T.ok(coveredAt(net, 3 + EPS, 3.5, true), "croix : bord W non atteint")
		T.ok(coveredAt(net, 4 - EPS, 3.5, true), "croix : bord E non atteint")
		T.falsy(coveredAt(net, 3 + 0.02, 3 + 0.02, false), "croix : fuite dans le coin NW")
		T.falsy(coveredAt(net, 4 - 0.02, 4 - 0.02, false), "croix : fuite dans le coin SE")
	end)

	T.test("route entre deux batiments : pas de bras vers le vide", function()
		local net = networkOf({ "3:3" }, { "3:3>W", "3:3>E" })
		T.ok(coveredAt(net, 3 + EPS, 3.5, true), "raccord W : bord non atteint")
		T.ok(coveredAt(net, 4 - EPS, 3.5, true), "raccord E : bord non atteint")
		T.falsy(coveredAt(net, 3.5, 3 + EPS, false), "raccord : bras N fantome")
		T.falsy(coveredAt(net, 3.5, 4 - EPS, false), "raccord : bras S fantome")
	end)

	T.test("bord du plateau : case en coin avec raccord hors plateau, sans erreur", function()
		-- Le raccord N de (0,0) pointe hors du plateau : il ne doit ni planter ni
		-- étendre la pièce au-delà du bord.
		local net = networkOf({ "0:0", "1:0" }, { "0:0>N" })
		local pieces = RG.cellPieces(net.roads, net.bridges, net.connectors, 0, 0)
		T.ok(#pieces > 0, "case de bord : pieces attendues")
		for _, piece in ipairs(pieces) do
			T.ok(piece.cx - piece.w * 0.5 >= -1e-9 and piece.cy - piece.h * 0.5 >= -1e-9, "case de bord : piece hors du plateau")
		end
		T.ok(coveredAt(net, 0.5, EPS, true), "case de bord : bord N non atteint")
		checkJoints(net, "bord")
		T.ok(coveredAt(net, 1.0, 0.5, true), "case de bord : jointure avec (1,0)")
	end)
end
