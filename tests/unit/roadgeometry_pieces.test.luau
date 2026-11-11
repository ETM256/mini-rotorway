return function(T, H)
	-- Tests de RoadGeometry. Une rastérisation par points d'échantillonnage
	-- vérifie la forme réelle des pièces (couverture, largeur, fuites, arrondis,
	-- continuité entre cases, rotation) sans supposer comment elles sont calculées.

	local RG = H.load("RoadGeometry")
	local VIS = H.load("RoadConfig").Visual

	local C = 0.5
	local EPS = 1e-6
	local SAMPLES = 20
	local BODY_W = VIS.RoadWidth
	local BODY_R = VIS.CornerRadius * BODY_W
	local EDGE_W = VIS.EdgeWidth
	local EDGE_R = BODY_R + (EDGE_W - BODY_W) * 0.5

	-- "edge" = liseré ; "surface" = couche body ou bridge.
	local EDGE_SPEC = { name = "edge", half = EDGE_W * 0.5, r = EDGE_R }
	local SURFACE_SPEC = { name = "surface", half = BODY_W * 0.5, r = BODY_R }
	local SPECS = { EDGE_SPEC, SURFACE_SPEC }

	-- rotated : direction du bras après une rotation de 90 degrés dans le sens horaire.
	local ARMS = {
		{ name = "N", bit = 1, dx = 0, dy = -1, rotated = "E" },
		{ name = "E", bit = 2, dx = 1, dy = 0, rotated = "S" },
		{ name = "S", bit = 4, dx = 0, dy = 1, rotated = "W" },
		{ name = "W", bit = 8, dx = -1, dy = 0, rotated = "N" },
	}
	local ARM_BY_NAME = {}
	for _, arm in ipairs(ARMS) do
		ARM_BY_NAME[arm.name] = arm
	end

	local ROT = { [0] = { 1, 0 }, [90] = { 0, 1 }, [180] = { -1, 0 }, [270] = { 0, -1 } }

	local function hasBit(mask, bit)
		return math.floor(mask / bit) % 2 == 1
	end

	local function armsFromMask(mask)
		local arms = {}
		for _, arm in ipairs(ARMS) do
			if hasBit(mask, arm.bit) then
				arms[arm.name] = true
			end
		end
		return arms
	end

	local function labelOf(mask)
		local label = ""
		for _, arm in ipairs(ARMS) do
			if hasBit(mask, arm.bit) then
				label = label .. arm.name
			end
		end
		if label == "" then
			return "masque 0 (isolee)"
		end
		return "masque " .. label
	end

	-- Rastérisation ---------------------------------------------------------

	local function covers(piece, px, py)
		local dx, dy = px - piece.cx, py - piece.cy
		if piece.kind == "disk" then
			return dx * dx + dy * dy <= piece.r * piece.r
		end
		if piece.kind ~= "rect" then
			error("genre de piece inconnu : " .. tostring(piece.kind))
		end
		local c = ROT[piece.rotation]
		if not c then
			error("rotation hors multiples de 90 : " .. tostring(piece.rotation))
		end
		local lx = dx * c[1] + dy * c[2]
		local ly = dy * c[1] - dx * c[2]
		return math.abs(lx) <= piece.w * 0.5 + 1e-9 and math.abs(ly) <= piece.h * 0.5 + 1e-9
	end

	-- Couverture d'une couche : spec.name "edge" ne voit que le liseré, "surface"
	-- voit body et bridge.
	local function coveredBy(pieces, spec, px, py)
		for _, piece in ipairs(pieces) do
			if (spec.name == "edge") == (piece.layer == "edge") and covers(piece, px, py) then
				return true
			end
		end
		return false
	end

	-- Distance depuis (cx, cy) dans la direction (dx, dy) jusqu'au dernier point
		-- peint, par pas de 0.001 case.
		local function arcReach(pieces, spec, cx, cy, dx, dy)
			local reach = 0
			for k = 0, 600 do
				local d = k * 0.001
				if coveredBy(pieces, spec, cx + dx * d, cy + dy * d) then
					reach = d
				end
			end
			return reach
		end

		local function extentOf(piece)
		local hw, hh = piece.w * 0.5, piece.h * 0.5
		if piece.rotation == 90 or piece.rotation == 270 then
			hw, hh = hh, hw
		end
		return piece.cx - hw, piece.cx + hw, piece.cy - hh, piece.cy + hh
	end

	-- Zone autorisée : carré central et bande de chaque bras jusqu'au bord.
	-- Tout ce qui est peint hors de cette zone est une fuite.
	local function inCorridor(arms, px, py, half)
		local dx, dy = px - C, py - C
		if math.abs(dx) <= half and math.abs(dy) <= half then
			return true
		end
		for _, arm in ipairs(ARMS) do
			if arms[arm.name] then
				local along = dx * arm.dx + dy * arm.dy
				local across = math.abs(dx * arm.dy - dy * arm.dx)
				if along >= 0 and across <= half then
					return true
				end
			end
		end
		return false
	end

	local function eachSample(fn)
		for i = 0, SAMPLES - 1 do
			for j = 0, SAMPLES - 1 do
				fn((j + 0.5) / SAMPLES, (i + 0.5) / SAMPLES)
			end
		end
	end

	-- Réseau d'une seule case (4,4) : ses bras sont des routes voisines, ou des
	-- raccords vers un bâtiment si asConnector est vrai.
	local function networkFor(mask, bridge, asConnector)
		local key = "4:4"
		local roads, bridges, connectors = { [key] = true }, {}, {}
		if bridge then
			bridges[key] = true
		end
		for _, arm in ipairs(ARMS) do
			if hasBit(mask, arm.bit) then
				if asConnector then
					connectors[key .. ">" .. arm.name] = true
				else
					roads[(4 + arm.dx) .. ":" .. (4 + arm.dy)] = true
				end
			end
		end
		return roads, bridges, connectors
	end

	local function piecesFor(mask, options, bridge, asConnector)
		local roads, bridges, connectors = networkFor(mask, bridge, asConnector)
		return RG.cellPieces(roads, bridges, connectors, 4, 4, options)
	end

	-- Contrôles communs à une case ----------------------------------------

	local function checkPieces(pieces, label)
		T.le(#pieces, 6, label .. ": plus de 6 pieces")
		for _, piece in ipairs(pieces) do
			T.ok(piece.kind == "rect" or piece.kind == "disk", label .. ": genre " .. tostring(piece.kind))
			T.ok(piece.layer == "edge" or piece.layer == "body" or piece.layer == "bridge", label .. ": couche")
			T.ok(ROT[piece.rotation] ~= nil, label .. ": rotation " .. tostring(piece.rotation))
			local x0, x1, y0, y1 = extentOf(piece)
			T.ok(x0 >= -1e-9 and x1 <= 1 + 1e-9 and y0 >= -1e-9 and y1 <= 1 + 1e-9, label .. ": piece hors de la case")
			T.ok(piece.w > 0 and piece.h > 0, label .. ": taille nulle")
		end
	end

	-- Chaque bras est couvert sur son axe ; rien n'est peint hors des bras.
	local function checkCell(pieces, arms, label)
		checkPieces(pieces, label)
		for _, spec in ipairs(SPECS) do
			local name = label .. " (" .. spec.name .. ")"
			T.ok(coveredBy(pieces, spec, C, C), name .. ": centre non couvert")
			for _, arm in ipairs(ARMS) do
				if arms[arm.name] then
					for t = 0, 0.49, 0.02 do
						T.ok(coveredBy(pieces, spec, C + arm.dx * t, C + arm.dy * t), name .. ": axe " .. arm.name .. " non couvert")
					end
				end
			end
			local leak = nil
			eachSample(function(px, py)
				if not leak and coveredBy(pieces, spec, px, py) and not inCorridor(arms, px, py, spec.half) then
					leak = string.format("%.3f, %.3f", px, py)
				end
			end)
			T.falsy(leak, name .. ": fuite hors des bras en " .. tostring(leak))
		end
	end

	-- Bord partagé entre deux cases (A à gauche ou au-dessus de B) : même
	-- couverture des deux côtés, et pleine largeur sur chaque couche.
	local function checkSharedBorder(piecesA, piecesB, horizontal, label)
		for _, spec in ipairs(SPECS) do
			local name = label .. " (" .. spec.name .. ")"
			local count = 0
			for k = 0, 199 do
				local t = (k + 0.5) / 200
				local ca, cb
				if horizontal then
					ca = coveredBy(piecesA, spec, 1 - EPS, t)
					cb = coveredBy(piecesB, spec, EPS, t)
				else
					ca = coveredBy(piecesA, spec, t, 1 - EPS)
					cb = coveredBy(piecesB, spec, t, EPS)
				end
				T.eq(ca, cb, name .. ": trou ou decalage sur le bord")
				if ca then
					count += 1
				end
			end
			T.near(count / 200, spec.half * 2, 0.01, name .. ": largeur du bord")
		end
	end

	-- Réseaux aléatoires (graine fixe, générateur de Park-Miller) -----------

	local SIZE = 7

	local function randomNetwork(seed)
		local state = seed
		local function rand()
			state = (state * 16807) % 2147483647
			return state / 2147483647
		end
		local roads, bridges, connectors = {}, {}, {}
		for y = 0, SIZE - 1 do
			for x = 0, SIZE - 1 do
				if rand() < 0.55 then
					roads[x .. ":" .. y] = true
					if rand() < 0.15 then
						bridges[x .. ":" .. y] = true
					end
				end
			end
		end
		for y = 0, SIZE - 1 do
			for x = 0, SIZE - 1 do
				local key = x .. ":" .. y
				if roads[key] then
					for _, arm in ipairs(ARMS) do
						local neighbor = (x + arm.dx) .. ":" .. (y + arm.dy)
						if not roads[neighbor] and rand() < 0.3 then
							connectors[key .. ">" .. arm.name] = true
						end
					end
				end
			end
		end
		return roads, bridges, connectors
	end

	-- Bras d'une case lus directement dans le réseau (indépendant de RoadGeometry).
	local function armsAt(roads, bridges, connectors, x, y)
		local arms = {}
		local key = x .. ":" .. y
		for _, arm in ipairs(ARMS) do
			local neighbor = (x + arm.dx) .. ":" .. (y + arm.dy)
			if roads[neighbor] or bridges[neighbor] or connectors[key .. ">" .. arm.name] then
				arms[arm.name] = true
			end
		end
		return arms
	end

	-- Tests --------------------------------------------------------------

	T.test("classification des 16 masques", function()
		local expected = {
			[0] = { "isolated", "" },
			[1] = { "end", "N" },
			[2] = { "end", "E" },
			[4] = { "end", "S" },
			[8] = { "end", "W" },
			[3] = { "corner", "NE" },
			[6] = { "corner", "ES" },
			[12] = { "corner", "SW" },
			[9] = { "corner", "NW" },
			[5] = { "straight", "NS" },
			[10] = { "straight", "EW" },
			[7] = { "tee", "E" },
			[11] = { "tee", "N" },
			[13] = { "tee", "W" },
			[14] = { "tee", "S" },
			[15] = { "cross", "NESW" },
		}
		for mask = 0, 15 do
			local kind, orientation = RG.classify(mask)
			T.eq(kind, expected[mask][1], "genre du masque " .. mask)
			T.eq(orientation, expected[mask][2], "orientation du masque " .. mask)
		end
	end)

	T.test("neighborMask lit les routes et les raccords ; connectorKey", function()
		local roads = { ["3:3"] = true, ["4:4"] = true }
		local connectors = { ["3:4>W"] = true }
		T.eq(RG.neighborMask(roads, 3, 4, nil, connectors), 1 + 2 + 8, "N route, E route, W raccord")
		T.eq(RG.neighborMask(roads, 3, 4), 1 + 2, "sans raccord")
		T.eq(RG.neighborMask({}, 3, 4), 0, "aucune route")
		T.eq(RG.neighborMask(roads, 4, 4, { ["3:4"] = true }), 8, "voisin W en pont")
		T.eq(RG.connectorKey(3, 4, "E"), "3:4>E")
	end)

	T.test("affectedCells : la case et ses quatre voisins", function()
		local cells = RG.affectedCells("3:4")
		T.eq(#cells, 5)
		local set = {}
		for _, key in ipairs(cells) do
			set[key] = true
		end
		for _, key in ipairs({ "3:4", "3:3", "4:4", "3:5", "2:4" }) do
			T.ok(set[key], "manque " .. key)
		end
		T.eq(#RG.affectedCells("nimporte"), 0, "cle invalide")
	end)

	T.test("pieces : genres, couches, bornes et nombre pour les 16 masques", function()
		for mask = 0, 15 do
			local pieces = piecesFor(mask)
			checkPieces(pieces, labelOf(mask))
			local hasEdge, hasBody = false, false
			for _, piece in ipairs(pieces) do
				hasEdge = hasEdge or piece.layer == "edge"
				hasBody = hasBody or piece.layer == "body"
			end
			T.ok(hasEdge and hasBody, labelOf(mask) .. ": couches edge et body attendues")
		end
		-- Une case de pont utilise la couche bridge à la place de body.
		local bridged = piecesFor(5, nil, true)
		local layers = {}
		for _, piece in ipairs(bridged) do
			layers[piece.layer] = true
		end
		T.ok(layers.bridge and layers.edge, "pont : couches bridge et edge")
		T.falsy(layers.body, "pont : pas de couche body")
	end)

	T.test("couverture : centre et axe de chaque bras, pour les 16 masques", function()
		for mask = 0, 15 do
			checkCell(piecesFor(mask), armsFromMask(mask), labelOf(mask))
		end
	end)

	T.test("largeur identique sur chaque bras, pour toutes les formes", function()
		-- t = 0.46 : seul le bras mesuré atteint cette ligne (les autres bras
		-- et les arrondis sont plus loin du centre).
		local t = 0.46
		for mask = 1, 15 do
			local pieces = piecesFor(mask)
			for _, arm in ipairs(ARMS) do
				if hasBit(mask, arm.bit) then
					for _, spec in ipairs(SPECS) do
						local count = 0
						for k = 0, 1000 do
							local s = -0.5 + k / 1000
							local px = C + arm.dx * t - arm.dy * s
							local py = C + arm.dy * t + arm.dx * s
							if coveredBy(pieces, spec, px, py) then
								count += 1
							end
						end
						T.near(count / 1000, spec.half * 2, 0.003, labelOf(mask) .. " bras " .. arm.name .. " (" .. spec.name .. ")")
					end
				end
			end
		end
	end)

	T.test("virage : coin exterieur arrondi, bras interieurs couverts", function()
		for _, mask in ipairs({ 3, 6, 12, 9 }) do
			local pieces = piecesFor(mask)
			local arms = armsFromMask(mask)
			local vy = arms.N and -1 or 1
			local hx = arms.E and 1 or -1
			-- Coin extérieur : opposé aux deux bras.
			local sx, sy = -hx, -vy
			local norm = math.sqrt(0.5)
			for _, spec in ipairs(SPECS) do
				local name = labelOf(mask) .. " (" .. spec.name .. ")"
				local half, r = spec.half, spec.r
				T.falsy(coveredBy(pieces, spec, C + sx * half, C + sy * half), name .. ": coin exterieur vif")

				local roundX, roundY = C + sx * (half - r), C + sy * (half - r)
				T.ok(coveredBy(pieces, spec, roundX + sx * norm * r * 0.9, roundY + sy * norm * r * 0.9), name .. ": arc trop entame")
				T.falsy(coveredBy(pieces, spec, roundX + sx * norm * r * 1.1, roundY + sy * norm * r * 1.1), name .. ": arc trop large")

				T.ok(coveredBy(pieces, spec, C + hx * 0.25, C), name .. ": bras horizontal interieur")
				T.ok(coveredBy(pieces, spec, C, C + vy * 0.25), name .. ": bras vertical interieur")
				-- Le bord droit du bras vertical reste droit jusqu'au début de l'arrondi.
				T.ok(coveredBy(pieces, spec, C + sx * (half - 0.01), C + sy * 0.02), name .. ": bord droit coupe")
				-- Coin intérieur (angle rentrant) : vif, rien n'est peint dans le quart vide.
				T.falsy(coveredBy(pieces, spec, C - sx * (half + 0.01), C - sy * (half + 0.01)), name .. ": coin interieur arrondi")
				T.ok(coveredBy(pieces, spec, C - sx * (half - 0.01), C - sy * (half - 0.01)), name .. ": coin interieur manquant")
			end

			-- Arcs concentriques : depuis le centre d'arrondi de la surface, la
			-- surface s'arrête à BODY_R et le liseré à EDGE_R, dans la diagonale.
			local bodyHalf = BODY_W * 0.5
			local roundX, roundY = C + sx * (bodyHalf - BODY_R), C + sy * (bodyHalf - BODY_R)
			local diagX, diagY = sx * norm, sy * norm
			local reachSurface = arcReach(pieces, SURFACE_SPEC, roundX, roundY, diagX, diagY)
			local reachEdge = arcReach(pieces, EDGE_SPEC, roundX, roundY, diagX, diagY)
			T.near(reachSurface, BODY_R, 0.002, labelOf(mask) .. ": arc de la surface")
			T.near(reachEdge, EDGE_R, 0.002, labelOf(mask) .. ": arc du liseré non concentrique")
		end
	end)

	T.test("cul-de-sac : capuchon rond ; cellule isolee : bloc rond", function()
		for _, arm in ipairs(ARMS) do
			-- Cul-de-sac : le bras part vers arm, la pointe est du côté opposé.
			local pieces = piecesFor(arm.bit)
			local fx, fy = -arm.dx, -arm.dy
			local px, py = -fy, fx
			for _, spec in ipairs(SPECS) do
				local name = labelOf(arm.bit) .. " (" .. spec.name .. ")"
				local half = spec.half
				T.ok(coveredBy(pieces, spec, C + fx * (half - 0.01), C + fy * (half - 0.01)), name .. ": pointe du capuchon")
				T.falsy(coveredBy(pieces, spec, C + fx * (half + 0.01), C + fy * (half + 0.01)), name .. ": depasse la pointe")
				T.falsy(coveredBy(pieces, spec, C + (fx + px) * 0.8 * half, C + (fy + py) * 0.8 * half), name .. ": coin du cul-de-sac carre")
				T.ok(coveredBy(pieces, spec, C + (fx + px) * 0.5 * half, C + (fy + py) * 0.5 * half), name .. ": interieur du capuchon")
			end
		end

		local blob = piecesFor(0)
		local bodyDisks = 0
		for _, piece in ipairs(blob) do
			if piece.layer == "body" then
				T.eq(piece.kind, "disk", "bloc isole : disque attendu")
				T.near(piece.r, BODY_W * 0.5, 1e-9, "bloc isole : rayon = demi-largeur")
				bodyDisks += 1
			end
		end
		T.eq(bodyDisks, 1, "bloc isole : une seule piece body")
		for _, spec in ipairs(SPECS) do
			T.ok(coveredBy(blob, spec, C + 0.6 * spec.half, C + 0.6 * spec.half), "bloc isole : interieur")
			T.falsy(coveredBy(blob, spec, C + 0.8 * spec.half, C + 0.8 * spec.half), "bloc isole : coin hors du disque")
		end
	end)

	T.test("raccord bâtiment : le bras s'arrete au bord, comme une route voisine", function()
		for mask = 0, 15 do
			local connected = piecesFor(mask, nil, false, true)
			T.deepEq(connected, piecesFor(mask), labelOf(mask) .. ": raccord different d'une route")
			for _, arm in ipairs(ARMS) do
				if hasBit(mask, arm.bit) then
					-- Distance maximale du centre vers le bord, dans la direction du bras.
					local best = nil
					for _, piece in ipairs(connected) do
						local x0, x1, y0, y1 = extentOf(piece)
						local value
						if arm.dx == 1 then
							value = x1 - C
						elseif arm.dx == -1 then
							value = C - x0
						elseif arm.dy == 1 then
							value = y1 - C
						else
							value = C - y0
						end
						if best == nil or value > best then
							best = value
						end
					end
					T.near(best, C, 1e-9, labelOf(mask) .. ": bras " .. arm.name .. " ne touche pas le bord")
				end
			end
		end
	end)

	T.test("continuite : deux cases voisines relient leurs bords sans trou", function()
		for maskA = 0, 15 do
			for maskB = 0, 15 do
				for _, pair in ipairs({ { "E", "W", true }, { "S", "N", false } }) do
					local armA, armB = ARM_BY_NAME[pair[1]], ARM_BY_NAME[pair[2]]
					if hasBit(maskA, armA.bit) and hasBit(maskB, armB.bit) then
						checkSharedBorder(
							piecesFor(maskA),
							piecesFor(maskB),
							pair[3],
							labelOf(maskA) .. " | " .. labelOf(maskB) .. " (" .. pair[1] .. ")"
						)
					end
				end
			end
		end
	end)

	T.test("rotation : tourner l'entree tourne la sortie, pour les 16 masques", function()
		for mask = 0, 15 do
			local rotated = 0
			for _, arm in ipairs(ARMS) do
				if hasBit(mask, arm.bit) then
					rotated += ARM_BY_NAME[arm.rotated].bit
				end
			end
			local original = piecesFor(mask)
			local turned = piecesFor(rotated)
			T.eq(RG.classify(rotated), RG.classify(mask), "genre inchange par rotation")
			for _, spec in ipairs(SPECS) do
				local mismatch = nil
				eachSample(function(u, v)
					-- Rotation horaire de 90 degrés du repère de la case.
					if not mismatch and coveredBy(original, spec, u, v) ~= coveredBy(turned, spec, 1 - v, u) then
						mismatch = string.format("%.3f, %.3f", u, v)
					end
				end)
				T.falsy(mismatch, labelOf(mask) .. " (" .. spec.name .. ") rotation en " .. tostring(mismatch))
			end
		end
	end)

	T.test("options : largeurs et rayon d'angle surchargent RoadConfig.Visual", function()
		local pieces = piecesFor(5, { RoadWidth = 0.5, EdgeWidth = 0.6 })
		for _, piece in ipairs(pieces) do
			if piece.layer == "body" then
				T.near(piece.w, 0.5, 1e-9, "largeur body surchargee")
			elseif piece.layer == "edge" then
				T.near(piece.w, 0.6, 1e-9, "largeur edge surchargee")
			end
		end
		-- Rayon nul : la surface reste à angle vif ; le liseré garde un arc de
		-- décalage (EdgeWidth - RoadWidth) / 2 pour rester d'épaisseur uniforme.
		local corner = piecesFor(3, { CornerRadius = 0 })
		local edgeDisks = 0
		for _, piece in ipairs(corner) do
			if piece.layer == "body" then
				T.eq(piece.kind, "rect", "rayon nul : surface a angle vif")
			elseif piece.kind == "disk" then
				T.near(piece.r, (EDGE_W - BODY_W) * 0.5, 1e-9, "rayon nul : liseré décalé")
				edgeDisks += 1
			end
		end
		T.eq(edgeDisks, 1, "rayon nul : le liseré garde son arc")
		local rounded = piecesFor(3)
		local disks = 0
		for _, piece in ipairs(rounded) do
			if piece.kind == "disk" then
				disks += 1
			end
		end
		T.eq(disks, 2, "virage arrondi : un disque par couche")
	end)

	T.test("reseaux aleatoires (graines fixes) : invariants de chaque case", function()
		for seed = 1, 6 do
			local roads, bridges, connectors = randomNetwork(seed)
			for y = 0, SIZE - 1 do
				for x = 0, SIZE - 1 do
					local key = x .. ":" .. y
					local pieces = RG.cellPieces(roads, bridges, connectors, x, y)
					if roads[key] or bridges[key] then
						checkCell(pieces, armsAt(roads, bridges, connectors, x, y), "graine " .. seed .. " case " .. key)
					else
						T.eq(#pieces, 0, "graine " .. seed .. " case vide " .. key)
					end
				end
			end
		end
	end)

	T.test("reseaux aleatoires : continuite sur chaque bord partage", function()
		for seed = 1, 6 do
			local roads, bridges, connectors = randomNetwork(seed)
			for y = 0, SIZE - 1 do
				for x = 0, SIZE - 1 do
					local key = x .. ":" .. y
					if roads[key] or bridges[key] then
						local pieces = RG.cellPieces(roads, bridges, connectors, x, y)
						for _, pair in ipairs({ { 1, 0, true }, { 0, 1, false } }) do
							local nx, ny = x + pair[1], y + pair[2]
							local neighbor = nx .. ":" .. ny
							if roads[neighbor] or bridges[neighbor] then
								local other = RG.cellPieces(roads, bridges, connectors, nx, ny)
								checkSharedBorder(pieces, other, pair[3], "graine " .. seed .. " " .. key .. " / " .. neighbor)
							end
						end
					end
				end
			end
		end
	end)

	T.test("reseaux aleatoires : tourner tout le reseau tourne chaque case", function()
		for seed = 1, 3 do
			local roads, bridges, connectors = randomNetwork(seed)
			local roads2, bridges2, connectors2 = {}, {}, {}
			for y = 0, SIZE - 1 do
				for x = 0, SIZE - 1 do
					local key = x .. ":" .. y
					-- (x, y) -> (SIZE - 1 - y, x) : N devient E, E devient S, etc.
					local rotatedKey = (SIZE - 1 - y) .. ":" .. x
					if roads[key] then
						roads2[rotatedKey] = true
					end
					if bridges[key] then
						bridges2[rotatedKey] = true
					end
					for _, arm in ipairs(ARMS) do
						if connectors[key .. ">" .. arm.name] then
							connectors2[rotatedKey .. ">" .. arm.rotated] = true
						end
					end
				end
			end
			for y = 0, SIZE - 1 do
				for x = 0, SIZE - 1 do
					local key = x .. ":" .. y
					if roads[key] or bridges[key] then
						local original = RG.cellPieces(roads, bridges, connectors, x, y)
						local turned = RG.cellPieces(roads2, bridges2, connectors2, SIZE - 1 - y, x)
						for _, spec in ipairs(SPECS) do
							local mismatch = nil
							eachSample(function(u, v)
								if not mismatch and coveredBy(original, spec, u, v) ~= coveredBy(turned, spec, 1 - v, u) then
									mismatch = string.format("%.3f, %.3f", u, v)
								end
							end)
							T.falsy(mismatch, "graine " .. seed .. " case " .. key .. " (" .. spec.name .. ") : " .. tostring(mismatch))
						end
					end
				end
			end
		end
	end)
end
