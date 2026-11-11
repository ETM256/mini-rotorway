--[[
	HUDIcons.luau
	Pictogrammes dessinés avec des Frame et des UICorner (aucune image, aucun
	texte). Chaque fonction crée un carré centré dans le parent, de taille
	DEFAULT_SIZE px sauf indication contraire, et renvoie ce carré.

	Le dessin est exprimé sur une grille de 24 unités, en fractions du carré :
	il suit donc la taille demandée, et son centre tombe toujours au centre du
	carré. Tous les traits ont la même épaisseur (LINE unités, ou
	Theme.Stroke.Max px pour les contours) et des extrémités rondes.

	Paramètres optionnels : couleur (blanc par défaut, pour un fond sombre ou
	teinté ; passer Theme.Ink sur un fond clair) et taille du carré. La couleur
	d'une pastille « pont » est Theme.Bridge.
]]

local Theme = require(script.Parent.Theme)

local Icons = {}

-- Grille de dessin, en unités. Le centre est à CENTER.
local GRID = 24
local CENTER = GRID / 2
-- Épaisseur commune des traits, en unités (2 unités = 2 px au format 24 px).
local LINE = 2
-- Taille par défaut du carré d'un pictogramme, en pixels.
local DEFAULT_SIZE = 24

-- Position et taille en unités de grille, converties en fractions du carré.
local function at(x, y)
	return UDim2.fromScale(x / GRID, y / GRID)
end

local function span(width, height)
	return UDim2.fromScale(width / GRID, height / GRID)
end

-- Carré centré qui porte le pictogramme. Renvoie aussi la couleur retenue.
local function begin(parent, color, size)
	local canvas = Theme.new("Frame", {
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size or DEFAULT_SIZE, size or DEFAULT_SIZE),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	return canvas, color or Theme.White
end

-- Arrondi en fraction du petit côté : 0.5 donne des extrémités rondes.
local function round(frame, fraction)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(fraction or 0.5, 0)
	corner.Parent = frame
end

-- Trait plein centré en (x, y), tourné de rotation degrés. Un trait carré
-- devient un point.
local function bar(canvas, x, y, width, height, color, rotation, fraction)
	local frame = Theme.new("Frame", {
		Parent = canvas,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at(x, y),
		Size = span(width, height),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Rotation = rotation or 0,
	})
	round(frame, fraction)
	return frame
end

-- Contour fin centré en (x, y) : un cadre sans fond, dont seul le trait est dessiné.
local function outline(canvas, x, y, width, height, color, fraction)
	local frame = Theme.new("Frame", {
		Parent = canvas,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at(x, y),
		Size = span(width, height),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	round(frame, fraction)
	Theme.stroke(frame, color, Theme.Stroke.Max, 0)
	return frame
end

-- Crayon à 45 degrés : fût, gomme et pointe placés symétriquement autour du centre.
function Icons.pen(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	bar(canvas, CENTER, CENTER, 19, 6, ink, -45)
	bar(canvas, 18.7, 5.3, 5, 5, ink)
	bar(canvas, 5.3, 18.7, 5, 5, ink)
	return canvas
end

-- Poubelle : poignée, couvercle, corps et deux cannelures.
function Icons.trash(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	bar(canvas, CENTER, 4, 6, LINE, ink)
	bar(canvas, CENTER, 6.5, 16, LINE, ink)
	outline(canvas, CENTER, 15, 12, 12, ink, 0.2)
	bar(canvas, 10, 15, LINE, 6, ink)
	bar(canvas, 14, 15, LINE, 6, ink)
	return canvas
end

-- Rond-point : anneau, îlot central et quatre branches qui y entrent.
function Icons.roundabout(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	outline(canvas, CENTER, CENTER, 14, 14, ink)
	bar(canvas, CENTER, CENTER, 4, 4, ink)
	bar(canvas, CENTER, 2.5, LINE, 5, ink)
	bar(canvas, CENTER, 21.5, LINE, 5, ink)
	bar(canvas, 2.5, CENTER, 5, LINE, ink)
	bar(canvas, 21.5, CENTER, 5, LINE, ink)
	return canvas
end

-- Route : deux bords parallèles inclinés et une ligne centrale, vus de dessus.
function Icons.road(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	bar(canvas, 14.3, 15.3, 22, LINE, ink, -35)
	bar(canvas, 9.7, 8.7, 22, LINE, ink, -35)
	bar(canvas, CENTER, CENTER, 8, LINE, ink, -35)
	return canvas
end

-- Déplacement de la vue : croix à quatre pointes en losange.
function Icons.pan(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	bar(canvas, CENTER, CENTER, 18, LINE, ink)
	bar(canvas, CENTER, CENTER, LINE, 18, ink)
	bar(canvas, CENTER, 4, 5, 5, ink, 45, 0.2)
	bar(canvas, CENTER, 20, 5, 5, ink, 45, 0.2)
	bar(canvas, 4, CENTER, 5, 5, ink, 45, 0.2)
	bar(canvas, 20, CENTER, 5, 5, ink, 45, 0.2)
	return canvas
end

-- Retour : flèche pointant à gauche, un trait et deux ailes à 45 degrés. Dessinée
-- en Frame : le glyphe « ← » n'est pas garanti dans la police Roblox.
function Icons.back(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	bar(canvas, CENTER, CENTER, 16, LINE, ink)
	bar(canvas, 6.8, 9.2, 8, LINE, ink, -45)
	bar(canvas, 6.8, 14.8, 8, LINE, ink, 45)
	return canvas
end

-- Pont : tablier et deux pylônes, vus de côté.
function Icons.bridge(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	bar(canvas, CENTER, 14, 20, LINE, ink)
	bar(canvas, 7, CENTER, LINE, 16, ink)
	bar(canvas, 17, CENTER, LINE, 16, ink)
	return canvas
end

-- Lecture : triangle pointant à droite, fait de bandes qui raccourcissent vers les bords.
function Icons.play(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	for row = -2, 2 do
		local width = 14 * (3 - math.abs(row)) / 3
		bar(canvas, 6 + width / 2, CENTER + row * 3.6, width, 3.6, ink, 0, 0.2)
	end
	return canvas
end

-- Recommencer : anneau ouvert et pointe de flèche.
function Icons.reload(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	outline(canvas, CENTER, CENTER, 16, 16, ink)
	bar(canvas, 18.5, 5.5, 6, 6, ink, 45, 0.2)
	return canvas
end

-- Réglages : trois curseurs.
function Icons.sliders(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	for _, row in ipairs({ { y = 6, x = 15 }, { y = 12, x = 8 }, { y = 18, x = 16 } }) do
		bar(canvas, CENTER, row.y, 20, LINE, ink)
		bar(canvas, row.x, row.y, 6, 6, ink)
	end
	return canvas
end

-- Menu : trois barres.
function Icons.menu(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	for _, y in ipairs({ 6, 12, 18 }) do
		bar(canvas, CENTER, y, 16, LINE, ink)
	end
	return canvas
end

-- Circulation : trois petites voitures en file.
function Icons.cars(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	for _, x in ipairs({ 4.5, 12, 19.5 }) do
		bar(canvas, x, CENTER, 5, 9, ink, 0, 0.3)
	end
	return canvas
end

-- Pause : deux barres verticales aux bouts arrondis.
function Icons.pause(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	bar(canvas, 8.5, CENTER, 4, 14, ink, 0, 0.3)
	bar(canvas, 15.5, CENTER, 4, 14, ink, 0, 0.3)
	return canvas
end

-- Maison : petit carré arrondi vu de dessus, avec son faîtage.
function Icons.house(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	outline(canvas, CENTER, CENTER, 16, 16, ink, 0.2)
	bar(canvas, CENTER, CENTER, 8, LINE, ink)
	return canvas
end

-- Destination : disque plein, comme les magasins ronds vus de dessus.
function Icons.store(parent, color, size)
	local canvas, ink = begin(parent, color, size)
	bar(canvas, CENTER, CENTER, 16, 16, ink)
	return canvas
end

return Icons
