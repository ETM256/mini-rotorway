--[[
	InputController.luau
	Dessin, effacement et rond-point à la souris ou au doigt.

	Outils (ids partagés avec le HUD, ne pas les renommer) :
	  "build" (touche 1), "erase" (touche 2), "roundabout" (touche 3),
	  "camera" (touche 4 : glisser pour déplacer la vue).
	Clic droit : efface le tracé, quel que soit l'outil. Clic milieu : caméra
	(géré par Main). Deux doigts : caméra, un second doigt ne construit jamais.

	Le tracé est une suite de cases orthogonales sans répétition : un
	mouvement rapide est comblé case par case, et revenir sur une case du
	tracé retire les cases posées après elle. Une case refusée coupe le
	tracé : jamais envoyée, elle sépare deux requêtes. Le client n'envoie
	rien avant le relâchement ; Échap ou un changement d'outil annule sans
	rien consommer. La validation finale et les ressources restent au serveur.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Maps = require(Shared.Maps)
local RoadConfig = require(Shared.RoadConfig)
local RoadNetwork = require(Shared.RoadNetwork)

local RoadPreview = require(script.Parent.RoadPreview)

local InputController = {}
InputController.__index = InputController

local GHOST_SCALE = 1.10
local GHOST_TRANSPARENCY = 0.45
local GHOST_HEIGHT = 0.52
-- Les marqueurs d'aperçu et les routes sont posés à cette hauteur : la visée
-- coupe donc le terrain à ce niveau, et non au sol.
local PICK_HEIGHT = RoadConfig.Visual.PreviewY

-- Ids d'outils par touche, comme le HUD les nomme.
local TOOL_BY_KEY = {
	One = "build",
	Two = "erase",
	Three = "roundabout",
	Four = "camera",
}

-- Position écran d'une entrée, toujours lue sur l'InputObject. Elle est dans
-- le repère que Camera:ScreenPointToRay attend (barre supérieure Roblox
-- déduite) : souris et doigt se visent donc de la même façon.
-- Piège : UserInputService:GetMouseLocation() est en coordonnées de vue,
-- barre incluse. L'associer à ScreenPointToRay décalerait chaque visée de la
-- hauteur de la barre (36 à 58 px), donc ne jamais l'utiliser ici.
local function pointerFrom(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function countEntries(map)
	local count = 0
	for _ in pairs(map) do
		count += 1
	end
	return count
end

-- Centre et écart moyen des doigts posés (au moins deux). Le centre sert au
-- panoramique, l'écart moyen au zoom par pincement.
local function gestureMetrics(touches)
	local sumX, sumY, count = 0, 0, 0
	for _, position in pairs(touches) do
		sumX += position.X
		sumY += position.Y
		count += 1
	end
	local cx, cy = sumX / count, sumY / count
	local spread = 0
	for _, position in pairs(touches) do
		local dx, dy = position.X - cx, position.Y - cy
		spread += math.sqrt(dx * dx + dy * dy)
	end
	return cx, cy, spread / count
end

-- Grille de la ville du joueur : Workspace.MMWorlds.City_N.Grid, où N suit
-- l'origine (index * OriginSpacing sur X, voir Session). Nil tant qu'elle
-- n'existe pas.
-- Couplage isolé ici : GameStarted ne porte pas le nom du monde, donc on le
-- reconstruit depuis l'origine. À retirer si le payload porte City_N.
local function findGrid(origin)
	local worlds = Workspace:FindFirstChild("MMWorlds")
	if not worlds or Config.World.OriginSpacing <= 0 then
		return nil
	end
	local index = math.floor(origin.X / Config.World.OriginSpacing + 0.5)
	local city = worlds:FindFirstChild("City_" .. index)
	if not city then
		return nil
	end
	return city:FindFirstChild("Grid")
end

local function makeGhostPart(size)
	local part = Instance.new("Part")
	part.Name = "MM_Ghost"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Config.Colors.Teal
	part.Transparency = 1
	part.Size = size
	part.Parent = Workspace
	return part
end

function InputController.new(callbacks)
	local self = setmetatable({}, InputController)
	self.callbacks = callbacks or {}
	self.enabled = false
	self.destroyed = false
	self.tool = "build"
	self.origin = Vector3.zero
	self.size = Config.Grid.Size
	self.tile = Config.Grid.TileSize
	self.map = nil

	-- Réseau tel que le serveur le décrit (RoadState). Lecture seule.
	self.roads = {}
	self.buildingSet = {}
	self.budget = Config.Roads.StartBudget
	self.bridgesLeft = Config.Roads.StartBridges

	self.connections = {}
	self.pointer = nil
	self.hoverClock = 0
	self.ghostKey = nil
	self.gridActive = nil
	self.gridFolder = nil
	-- Grille toujours visible (réglage « grid » du HUD), même hors construction.
	self.gridPinned = false
	self.touches = {}
	self.gesture = nil
	-- Clic milieu tenu (déplacement de vue, dans Main) : aucun tracé ne démarre.
	self.middleDown = false

	self.ghost = nil
	self.preview = RoadPreview.new()
	self:createGhost()
	self:resetStroke()
	self:bind()
	return self
end

function InputController:createGhost()
	-- Le fantôme ne sert qu'au rond-point : les routes ont leur aperçu.
	local size = Vector3.new(self.tile * GHOST_SCALE, 0.04, self.tile * GHOST_SCALE)
	self.ghost = makeGhostPart(size)
end

function InputController:track(connection)
	table.insert(self.connections, connection)
end

function InputController:bind()
	self:track(UserInputService.InputBegan:Connect(function(input, processed)
		self:onInputBegan(input, processed)
	end))
	self:track(UserInputService.InputChanged:Connect(function(input, processed)
		self:onInputChanged(input, processed)
	end))
	self:track(UserInputService.InputEnded:Connect(function(input)
		self:onInputEnded(input)
	end))
	-- Fenêtre perdue : le relâchement peut ne jamais arriver, on annule.
	self:track(UserInputService.WindowFocusReleased:Connect(function()
		self:onFocusLost()
	end))
	self:track(RunService.RenderStepped:Connect(function(dt)
		self:onFrame(dt)
	end))
end

function InputController:onInputBegan(input, processed)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Touch then
		-- Un doigt posé sur l'interface n'est pas suivi.
		if not processed then
			self:touchBegan(input)
		end
		return
	end

	if kind == Enum.UserInputType.MouseButton3 then
		-- Clic milieu : Main déplace la vue. Tant qu'il est tenu, aucun tracé ni
		-- effacement ne démarre, et un geste en cours est annulé sans rien envoyer.
		self.middleDown = true
		self:cancelDrag()
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		self:cancelDrag()
		return
	end
	if processed or not self.enabled then
		return
	end

	if kind == Enum.UserInputType.MouseButton1 then
		-- Un second bouton pendant un geste ne le remplace jamais : un
		-- déplacement de caméra ou un effacement ne devient pas un tracé.
		if self.dragging or self.middleDown then
			return
		end
		self.pointer = pointerFrom(input)
		self:pressTool(kind, nil, self.pointer)
	elseif kind == Enum.UserInputType.MouseButton2 then
		-- Clic droit : efface, quel que soit l'outil (le clic milieu déplace, dans Main).
		if self.dragging or self.middleDown then
			return
		end
		self.pointer = pointerFrom(input)
		self:beginDrag("erase", kind, nil, self.pointer)
	elseif kind == Enum.UserInputType.Keyboard then
		self:onKey(input.KeyCode)
	end
end

function InputController:onInputChanged(input, processed)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseMovement then
		local previous = self.pointer
		local nextPointer = pointerFrom(input)
		self.pointer = nextPointer
		if not (self.enabled and self.dragging) then
			-- Survol immédiat ; les cases inchangées ne sont pas réécrites.
			self:refreshPreview()
			return
		end
		-- Bouton relâché hors de la fenêtre : on valide le tracé fait jusque-là.
		if self.dragButton and not UserInputService:IsMouseButtonPressed(self.dragButton) then
			self:endDrag()
			return
		end
		if previous then
			self:moveDrag(previous, nextPointer, processed)
		end
	elseif kind == Enum.UserInputType.Touch then
		local previous = self.touches[input]
		if previous == nil or not self.enabled then
			return
		end
		local nextPointer = pointerFrom(input)
		self.touches[input] = nextPointer
		if self.gesture then
			self:updateGesture()
		elseif self.dragging and self.dragTouch == input then
			self:moveDrag(previous, nextPointer, processed)
		end
	end
end

function InputController:onInputEnded(input)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Touch then
		self:touchEnded(input)
	elseif kind == Enum.UserInputType.MouseButton3 then
		self.middleDown = false
	elseif self.dragging and self.dragButton and kind == self.dragButton then
		self:endDrag()
	end
end

function InputController:onKey(keyCode)
	local tool = TOOL_BY_KEY[keyCode.Name]
	if tool then
		self:setTool(tool)
		if self.callbacks.onToolChanged then
			self.callbacks.onToolChanged(tool)
		end
	end
end

function InputController:onFocusLost()
	self:cancelDrag()
	-- Le relâchement d'un bouton hors de la fenêtre n'arrive jamais : on oublie.
	self.middleDown = false
	self.touches = {}
	self.gesture = nil
	self.pointer = nil
	self:refreshPreview()
end

-- Image par image : seulement l'outil rond-point (le fantôme suit le
-- curseur) et, à cadence réduite, l'aperçu survolé (la caméra peut bouger
-- sous un curseur immobile).
function InputController:onFrame(dt)
	if self.destroyed then
		return
	end
	if self.tool == "roundabout" then
		self:updateGhost()
		return
	end
	self.hoverClock += dt
	if self.hoverClock < RoadConfig.Input.HoverRefresh then
		return
	end
	self.hoverClock = 0
	-- La grille peut être répliquée après le début de la partie : on la
	-- recherche à cette cadence, sans rien faire quand elle est déjà réglée.
	self:updateGridVisibility()
	if not self.dragging then
		self:refreshPreview()
	end
end

-- Une pression de l'outil actif (bouton gauche ou premier doigt).
function InputController:pressTool(mouseButton, touch, position)
	if self.tool == "camera" then
		self:beginDrag("camera", mouseButton, touch, nil)
	elseif self.tool == "roundabout" then
		local cell = self:cellAt(position)
		if cell and self.callbacks.onRoundabout then
			self.callbacks.onRoundabout(cell[1], cell[2])
		end
	elseif self.tool == "erase" then
		self:beginDrag("erase", mouseButton, touch, position)
	else
		self:beginDrag("build", mouseButton, touch, position)
	end
end

-- Démarre un geste : routes ou effacement (case de départ requise), ou caméra.
function InputController:beginDrag(tool, mouseButton, touch, position)
	self:resetStroke()
	local cell = nil
	if tool ~= "camera" then
		cell = self:cellAt(position)
		if not cell then
			return
		end
	end

	self.dragging = true
	self.dragTool = tool
	self.dragButton = mouseButton
	self.dragTouch = touch
	if cell then
		self.lastCell = { cell[1], cell[2] }
		if tool == "erase" then
			self:addErase(cell[1], cell[2])
		else
			self:addBuild(cell[1], cell[2])
		end
	end
	self:refreshPreview()
	self:updateGridVisibility()
end

-- Déplacement du geste courant entre deux positions écran.
function InputController:moveDrag(previous, nextPointer, processed)
	if self.dragTool == "camera" then
		if self.callbacks.onPan then
			self.callbacks.onPan(nextPointer.X - previous.X, nextPointer.Y - previous.Y)
		end
		return
	end
	-- Le tracé ne passe pas sous une fenêtre d'interface : il s'arrête là.
	if processed then
		self:endDrag()
		return
	end
	self:accumulateAxis(nextPointer.X - previous.X, nextPointer.Y - previous.Y)
	local cell = self:cellAt(nextPointer)
	if cell then
		self:extendTo(cell[1], cell[2])
	end
end

-- Axe dominant du geste, avec hystérésis : l'axe ne change que si l'autre
-- composante dépasse la première d'une marge (DragAxisThreshold). Un
-- mouvement hésitant en diagonale ne fait donc pas zigzaguer le tracé.
function InputController:accumulateAxis(dx, dy)
	self.axisX += dx
	self.axisY += dy
	local ax, ay = math.abs(self.axisX), math.abs(self.axisY)
	if math.max(ax, ay) < RoadConfig.Input.AxisMinPixels then
		return
	end
	local band = 1 + RoadConfig.Input.DragAxisThreshold
	if ax > ay * band then
		self.dragAxis = "x"
	elseif ay > ax * band then
		self.dragAxis = "y"
	end
end

-- Comble le chemin orthogonal entre la dernière case et la case pointée.
function InputController:extendTo(x, y)
	local last = self.lastCell
	if x == last[1] and y == last[2] then
		return
	end
	-- Trajet en L selon l'axe du geste. Le module partagé renvoie une liste vide
	-- pour un trajet hors borne (impossible avec la grille actuelle) : le tracé
	-- repart alors de la case visée, sans repli case par case qui pouvait boucler
	-- sans fin sur une coordonnée invalide.
	local path = RoadNetwork.manhattanPath(last[1], last[2], x, y, self.dragAxis)
	for _, step in ipairs(path) do
		if self.dragTool == "erase" then
			self:addErase(step[1], step[2])
		else
			self:addBuild(step[1], step[2])
		end
	end
	self.lastCell = { x, y }
	-- Le prochain axe se décide sur le mouvement depuis cette nouvelle case.
	self.axisX = 0
	self.axisY = 0
	self:refreshPreview()
end

function InputController:addBuild(x, y)
	local key = Grid.key(x, y)
	local index = self.walkIndex[key]
	if index then
		-- Revenir sur une case du tracé retire les cases posées après elle.
		for position = #self.walk, index + 1, -1 do
			local cell = self.walk[position]
			self.walkIndex[Grid.key(cell[1], cell[2])] = nil
			self.walk[position] = nil
		end
		return
	end
	self.walk[#self.walk + 1] = { x, y }
	self.walkIndex[key] = #self.walk
end

function InputController:addErase(x, y)
	local key = Grid.key(x, y)
	-- Seules les routes existantes sont effaçables : le reste n'est pas envoyé.
	if self.eraseSet[key] or not self.roads[key] then
		return
	end
	self.eraseSet[key] = true
	table.insert(self.eraseList, key)
end

function InputController:isWater(x, y)
	return self.map ~= nil and Maps.isWater(self.map, x, y)
end

-- Miroir local de Session:canDraw, dans le même ordre de refus : hors carte
-- et bâtiment, puis eau sans pont, puis budget. Une route déjà posée est
-- « existante » : elle reste valide, ne coûte rien et n'est pas redessinée.
-- Les cases refusées ont valid = false.
function InputController:planCells(list, hover)
	local cells = {}
	local budget = self.budget
	local bridges = self.bridgesLeft
	for _, cell in ipairs(list) do
		local x, y = cell[1], cell[2]
		local key = Grid.key(x, y)
		local existing = self.roads[key] == true
		local valid = true
		if not existing then
			valid = Grid.inBounds(x, y) and not self.buildingSet[key]
			if valid then
				local water = self:isWater(x, y)
				if water and bridges <= 0 then
					valid = false
				elseif budget <= 0 then
					valid = false
				else
					budget -= 1
					if water then
						bridges -= 1
					end
				end
			end
		end
		cells[#cells + 1] = { x = x, y = y, valid = valid, existing = existing, hover = hover }
	end
	return cells
end

-- Aperçu des routes à poser : les routes déjà là ne sont pas redessinées.
function InputController:setBuildPreview(list, hover)
	local visible = {}
	for _, cell in ipairs(self:planCells(list, hover)) do
		if not cell.existing then
			visible[#visible + 1] = cell
		end
	end
	self.preview:setCells(visible)
end

-- Effacement : les routes du tracé, en corail (elles vont disparaître).
function InputController:erasePreview()
	local cells = {}
	for _, key in ipairs(self.eraseList) do
		local x, y = Grid.parse(key)
		if x then
			cells[#cells + 1] = { x = x, y = y, valid = false }
		end
	end
	return cells
end

-- Recalcule l'aperçu : le tracé en cours, sinon la case survolée.
function InputController:refreshPreview()
	if self.destroyed then
		return
	end
	if not self.enabled then
		self.preview:clear()
		return
	end

	if self.dragging and self.dragTool == "build" then
		self:setBuildPreview(self.walk, false)
		return
	end
	if self.dragging and self.dragTool == "erase" then
		self.preview:setCells(self:erasePreview())
		return
	end
	if self.dragging or (self.tool ~= "build" and self.tool ~= "erase") then
		self.preview:clear()
		return
	end

	local cell = self.pointer and self:cellAt(self.pointer) or nil
	if not cell then
		self.preview:clear()
		return
	end
	if self.tool == "erase" then
		if self.roads[Grid.key(cell[1], cell[2])] then
			self.preview:setCells({ { x = cell[1], y = cell[2], valid = false, hover = true } })
		else
			self.preview:clear()
		end
	else
		self:setBuildPreview({ cell }, true)
	end
end

-- Envoie le tracé. Une case refusée coupe le tracé : chaque suite de cases
-- posables part dans sa propre requête, pour que le ruban serveur ne relie
-- jamais deux morceaux par-dessus une case refusée (spec 3.4).
function InputController:commitBuild(walk)
	if not self.callbacks.onDraw then
		return
	end
	local run = {}
	local runHasNew = false
	for _, cell in ipairs(self:planCells(walk, false)) do
		if cell.valid then
			run[#run + 1] = { cell.x, cell.y }
			runHasNew = runHasNew or not cell.existing
		else
			self:sendRun(run, runHasNew)
			run = {}
			runHasNew = false
		end
	end
	self:sendRun(run, runHasNew)
end

-- Envoie une suite continue par lots. Un lot n'a jamais plus de
-- MaxCellsPerRequest cases ; deux lots se chevauchent d'une case pour que le
-- ruban serveur reste continu. Une suite sans case neuve n'est pas envoyée.
function InputController:sendRun(run, hasNew)
	if not hasNew or #run == 0 then
		return
	end
	local maxCells = math.max(2, RoadConfig.Input.MaxCellsPerRequest)
	local count = #run
	local first = 1
	while true do
		local last = math.min(first + maxCells - 1, count)
		local chunk = {}
		for index = first, last do
			chunk[#chunk + 1] = run[index]
		end
		self.callbacks.onDraw(chunk)
		if last >= count then
			break
		end
		first = last
	end
end

function InputController:commitErase(keys)
	if #keys == 0 then
		return
	end
	if self.callbacks.onEraseMany then
		local maxCells = math.max(1, RoadConfig.Input.MaxCellsPerRequest)
		for first = 1, #keys, maxCells do
			local last = math.min(first + maxCells - 1, #keys)
			local chunk = {}
			for index = first, last do
				chunk[#chunk + 1] = keys[index]
			end
			self.callbacks.onEraseMany(chunk)
		end
	elseif self.callbacks.onErase then
		for _, key in ipairs(keys) do
			self.callbacks.onErase(key)
		end
	end
end

function InputController:resetStroke()
	self.dragging = false
	self.dragTool = nil
	self.dragButton = nil
	self.dragTouch = nil
	self.lastCell = nil
	self.dragAxis = nil
	self.axisX = 0
	self.axisY = 0
	self.walk = {}
	self.walkIndex = {}
	self.eraseList = {}
	self.eraseSet = {}
end

-- Fin normale : le tracé part au serveur, puis le geste est oublié.
function InputController:endDrag()
	if not self.dragging then
		return
	end
	local tool = self.dragTool
	local walk = self.walk
	local keys = self.eraseList
	self:resetStroke()
	if tool == "build" then
		self:commitBuild(walk)
	elseif tool == "erase" then
		self:commitErase(keys)
	end
	self:refreshPreview()
	self:updateGridVisibility()
end

-- Annulation (Échap, changement d'outil, fenêtre perdue) : rien n'est envoyé.
function InputController:cancelDrag()
	if not self.dragging then
		return
	end
	self:resetStroke()
	self:refreshPreview()
	self:updateGridVisibility()
end

function InputController:touchBegan(input)
	if not self.enabled then
		return
	end
	-- Un doigt dont la fin n'est jamais arrivée (interruption système) ne doit
	-- pas bloquer le tracé pour le reste de la partie : on l'oublie ici.
	self:forgetEndedTouches()
	-- Un doigt de plus pendant qu'un autre est suivi : geste de caméra, jamais
	-- un tracé. Le tracé du premier doigt est annulé, sans rien envoyer.
	if countEntries(self.touches) > 0 then
		self.touches[input] = pointerFrom(input)
		self:cancelDrag()
		self:startGesture()
		return
	end
	self.touches[input] = pointerFrom(input)
	self.pointer = self.touches[input]
	self:pressTool(nil, input, self.pointer)
end

-- Retire les doigts que Roblox donne déjà pour terminés ou annulés.
function InputController:forgetEndedTouches()
	for input in pairs(self.touches) do
		local state = input.UserInputState
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			self.touches[input] = nil
			if self.dragTouch == input then
				self:cancelDrag()
			end
		end
	end
	if countEntries(self.touches) < 2 then
		self.gesture = nil
	end
end

function InputController:touchEnded(input)
	if self.touches[input] == nil then
		return
	end
	self.touches[input] = nil
	if countEntries(self.touches) == 0 then
		self.gesture = nil
		self.pointer = nil
	else
		self:startGesture()
	end
	if self.dragging and self.dragTouch == input then
		self:endDrag()
	end
end

-- Geste à deux doigts : le centre déplace la vue, l'écart la zoome. Une
-- base est reprise à chaque changement de nombre de doigts, pour qu'un doigt
-- qui se lève ne fasse pas sauter la caméra.
function InputController:startGesture()
	if countEntries(self.touches) < 2 then
		self.gesture = nil
		return
	end
	local cx, cy, spread = gestureMetrics(self.touches)
	self.gesture = { x = cx, y = cy, spread = spread }
end

function InputController:updateGesture()
	local previous = self.gesture
	local cx, cy, spread = gestureMetrics(self.touches)
	self.gesture = { x = cx, y = cy, spread = spread }
	if self.callbacks.onPan then
		self.callbacks.onPan(cx - previous.x, cy - previous.y)
	end
	if self.callbacks.onZoom and previous.spread > 0 and spread > 0 then
		local delta = (spread / previous.spread - 1) * RoadConfig.Input.PinchZoomGain
		if delta ~= 0 then
			self.callbacks.onZoom(delta)
		end
	end
end

-- Position de l'outil de rond-point : suit le curseur, ne change que si la
-- case change.
function InputController:updateGhost()
	if not self.enabled or self.tool ~= "roundabout" or not self.pointer then
		self.ghost.Transparency = 1
		self.ghostKey = nil
		return
	end
	local cell = self:cellAt(self.pointer)
	if not cell then
		self.ghost.Transparency = 1
		self.ghostKey = nil
		return
	end
	local key = Grid.key(cell[1], cell[2])
	if key ~= self.ghostKey then
		self.ghostKey = key
		self.ghost.CFrame = CFrame.new(self:cellCenter(cell[1], cell[2], GHOST_HEIGHT))
	end
	self.ghost.Transparency = GHOST_TRANSPARENCY
end

function InputController:cellCenter(x, y, height)
	return Vector3.new(
		self.origin.X + (x + 0.5) * self.tile,
		self.origin.Y + height,
		self.origin.Z + (y + 0.5) * self.tile
	)
end

-- Grille : plus visible pendant la construction (outil routes ou tracé en
-- cours), discrète sinon. Réglée une seule fois à chaque changement d'état.
function InputController:updateGridVisibility()
	local building = self.gridPinned or (self.enabled and (self.tool == "build" or (self.dragging and self.dragTool ~= "camera")))
	local grid = findGrid(self.origin)
	if building == self.gridActive and grid == self.gridFolder then
		return
	end
	self.gridActive = building
	self.gridFolder = grid
	if not grid then
		return
	end
	local value = grid:GetAttribute(building and "ActiveTransparency" or "BaseTransparency")
	if type(value) ~= "number" then
		return
	end
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("BasePart") then
			child.Transparency = value
		end
	end
end

-- Réglage « grid » du HUD : grille toujours visible, ou règle automatique
-- (visible seulement pendant la construction).
function InputController:setGridPinned(value)
	if self.destroyed then
		return
	end
	self.gridPinned = value == true
	self:updateGridVisibility()
end

function InputController:setWorld(origin, size, tile)
	if self.destroyed then
		return
	end
	self:cancelDrag()
	self.origin = origin or Vector3.zero
	self.size = size or Config.Grid.Size
	self.tile = tile or Config.Grid.TileSize
	-- Nouvelle partie : le réseau attend le RoadState de ce monde.
	self.roads = {}
	self.buildingSet = {}
	-- Une case identique dans un autre monde ne doit pas garder l'ancienne place du fantôme.
	self.ghostKey = nil
	self.ghost.Size = Vector3.new(self.tile * GHOST_SCALE, 0.04, self.tile * GHOST_SCALE)
	self.preview:setWorld(self.origin, self.tile)
	self:updateGridVisibility()
	self:refreshPreview()
end

function InputController:setMapId(mapId)
	if self.destroyed then
		return
	end
	self.map = Maps.getById(mapId)
	self:refreshPreview()
end

function InputController:setEnabled(value)
	if self.destroyed then
		return
	end
	self.enabled = value == true
	if not self.enabled then
		-- Aucun geste ne survit à la désactivation (fin, choix de semaine).
		self:cancelDrag()
		self.touches = {}
		self.gesture = nil
		self.pointer = nil
		self.ghost.Transparency = 1
		self.ghostKey = nil
	end
	self:updateGridVisibility()
	self:refreshPreview()
end

function InputController:setTool(tool)
	if self.destroyed then
		return
	end
	if self.dragging then
		self:cancelDrag()
	end
	self.tool = tool
	self.ghostKey = nil
	if tool ~= "roundabout" then
		self.ghost.Transparency = 1
	end
	self:updateGridVisibility()
	self:refreshPreview()
end

-- Le serveur envoie l'état réel du réseau après chaque modification.
function InputController:applyRoadState(data)
	if type(data) ~= "table" then
		return
	end

	local roads = {}
	for _, key in ipairs(data.roads or {}) do
		roads[key] = true
	end
	local buildings = {}
	for _, key in ipairs(data.buildings or {}) do
		buildings[key] = true
	end

	self.roads = roads
	self.buildingSet = buildings
	self.preview:setRoads(roads)
	self.budget = tonumber(data.budget) or self.budget
	self.bridgesLeft = tonumber(data.bridgesLeft) or self.bridgesLeft
	self:refreshPreview()
end

-- Case sous une position écran (repère de pointerFrom), ou nil hors carte. La
-- visée coupe le plan PICK_HEIGHT ; les cases partent du coin de l'origine,
-- comme Grid.center.
function InputController:cellAt(position)
	if self.destroyed or typeof(position) ~= "Vector2" then
		return nil
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	-- ScreenPointToRay déduit la barre supérieure, comme les positions des
	-- InputObject : le rayon passe exactement sous le curseur ou le doigt.
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	local direction = ray.Direction
	if math.abs(direction.Y) < 0.0001 then
		return nil
	end

	local distance = (self.origin.Y + PICK_HEIGHT - ray.Origin.Y) / direction.Y
	if distance <= 0 then
		return nil
	end

	local hit = ray.Origin + direction * distance
	-- Grid.cellFromWorld suppose la taille de case de Config.Grid, celle que le
	-- serveur envoie dans GameStarted.
	local x, y = Grid.cellFromWorld(self.origin, hit)
	if not Grid.inBounds(x, y) then
		return nil
	end
	return { x, y }
end

-- Libère tout : connexions, fantôme, aperçu. Le contrôleur ne sert plus après.
function InputController:destroy()
	if self.destroyed then
		return
	end
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
	self.destroyed = true
	self.enabled = false
	self:resetStroke()
	self.touches = {}
	self.gesture = nil
	self.preview:destroy()
	self.ghost:Destroy()
	self.ghost = nil
	self:updateGridVisibility()
end

return InputController
