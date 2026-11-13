--[[
	Theme.luau
	Jetons de design et petits constructeurs d'interface, partagés par le menu,
	le HUD et l'aperçu des cartes. Tout est dessiné en code : aucun asset.

	Les couleurs viennent uniquement de Config.Colors : changer la palette là-bas
	suffit. Rayons, contours et durées viennent de Config.Style ; les espacements
	et les échelles de mouvement sont définis ici, pour que l'interface reste
	cohérente d'un écran à l'autre.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local C = Config.Colors
local S = Config.Style

local Theme = {}

-- Couleurs existantes : les modules UI les lisent directement.
Theme.Ink = C.Ink
Theme.InkSoft = C.InkSoft
Theme.Teal = C.Teal
Theme.TealDark = C.TealDark
Theme.Orange = C.Orange
Theme.White = C.White
Theme.Cream = C.Cream
Theme.Background = C.Background
Theme.LobbyBackground = C.LobbyBackground
Theme.LobbyGrid = C.LobbyGrid
Theme.LobbyButton = C.LobbyButton
Theme.LobbyButtonDark = C.LobbyButtonDark
Theme.LobbyOrange = C.LobbyOrange
Theme.LobbyRoad = C.LobbyRoad
Theme.LobbyRoadShadow = C.LobbyRoadShadow
Theme.CardShadow = C.CardShadow
Theme.Danger = C.Danger
Theme.Panel = C.Panel
Theme.PanelSoft = C.PanelSoft
Theme.PanelDark = C.PanelDark
Theme.Border = C.Border

-- Jetons d'usage : chacun désigne un rôle, pas une teinte. Ils ne pointent
-- que vers Config.Colors, donc une seule palette pilote toute l'interface.
Theme.LightGrey = C.Background -- fond général, gris très clair
Theme.OffWhite = C.White -- surfaces et cartes, blanc cassé
Theme.Anthracite = C.Ink -- texte principal
Theme.Accent = C.Teal -- accent pastel principal
Theme.AccentDark = C.TealDark -- liseré d'état
Theme.AccentWarm = C.Orange -- accent chaud, rappel doux
Theme.Selected = C.Orange -- fond d'un outil sélectionné
Theme.Bridge = C.BridgeChip -- pastille « pont » (compteur, choix hebdomadaire)

-- Typographie : familles modernes et lisibles. Les trois graisses servent
-- au texte courant, aux titres et aux chiffres.
Theme.Font = Enum.Font.BuilderSansMedium
Theme.FontBold = Enum.Font.BuilderSansBold
Theme.FontBlack = Enum.Font.BuilderSansExtraBold

-- Échelles. Toute valeur d'interface devrait venir d'ici plutôt que d'un
-- nombre écrit en dur dans un module d'écran.
Theme.Radius = {
	Small = S.CornerRadius.Small,
	Medium = S.CornerRadius.Medium,
	Large = S.CornerRadius.Large,
	-- Coins entièrement arrondis, quelle que soit la taille du bouton.
	Pill = 999,
}
Theme.Space = { XS = 4, S = 8, M = 12, L = 16, XL = 24 }
-- Contours fins et clairs : jamais de gros contour noir.
Theme.Stroke = { Thin = S.Outline.Thin, Max = S.Outline.Max, Transparency = 0.2 }
-- Ombre douce : un cadre décalé et très transparent, sans UIStroke.
Theme.Shadow = { Offset = 3, Transparency = 0.6 }
-- Gabarit commun du HUD, en pixels. Les modules HUDTopBar, HUDCounters,
-- HUDToolbar et HUDResponsive s'y réfèrent : une valeur change ici, et les
-- quatre régions (barre du haut, outils, compteurs, aide) restent alignées.
Theme.Layout = {
	Margin = Theme.Space.L,
	Gap = Theme.Space.S,
	-- Main masque les CoreGui, mais le bouton de menu de Roblox (coin haut
	-- gauche, environ 12 + 44 px) reste affiché : aucun CoreGuiType ne le retire.
	-- Les éléments de ce coin commencent plus à droite pour ne pas le recouvrir.
	TopLeftInset = 60,
	BackSize = 40,
	PanelWidth = 264,
	PanelHeight = 52,
	ControlsWidth = 142,
	ControlsHeight = 36,
	GaugeWidth = 160,
	GaugeHeight = 30,
	-- Compteurs : cinq pastilles identiques tiennent dans 390 px (téléphone).
	ChipWidth = 66,
	ChipHeight = 40,
	ChipGap = 5,
	ChipCount = 5,
	HintHeight = 18,
}
-- Échelles de survol et de clic (Hover, Press, Max) et durées en secondes :
-- Duration est la durée du survol, Fast et Standard servent aux transitions
-- plus longues. Max borne toute échelle à 1.04 pour rester discret.
Theme.Motion = {
	Hover = 1.03,
	Press = 0.97,
	Max = 1.04,
	Duration = S.Motion.Hover,
	Fast = S.Motion.Fast,
	Standard = S.Motion.Standard,
}

function Theme.new(className, props)
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			else
				instance[key] = value
			end
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Arrondi en pixels, ou UDim pour un arrondi relatif (pastille : UDim.new(1, 0)).
function Theme.corner(instance, radius)
	local corner = Instance.new("UICorner")
	if type(radius) == "number" or radius == nil then
		corner.CornerRadius = UDim.new(0, radius or Theme.Radius.Medium)
	else
		corner.CornerRadius = radius
	end
	corner.Parent = instance
	return corner
end

-- Contour fin. L'épaisseur est bornée à Theme.Stroke.Max : un contour plus
-- épais se verrait comme une ligne noire autour des bâtiments et des boutons.
function Theme.stroke(instance, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Border
	stroke.Thickness = math.min(thickness or Theme.Stroke.Thin, Theme.Stroke.Max)
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

function Theme.padding(instance, top, right, bottom, left)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingRight = UDim.new(0, right)
	padding.PaddingBottom = UDim.new(0, bottom)
	padding.PaddingLeft = UDim.new(0, left)
	padding.Parent = instance
	return padding
end

function Theme.textScaled(instance, maxTextSize, minTextSize)
	instance.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxTextSize
	limit.MinTextSize = minTextSize or 8
	limit.Parent = instance
	return limit
end

function Theme.maxSize(instance, maxX, maxY)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(maxX, maxY)
	limit.Parent = instance
	return limit
end

function Theme.label(parent, text, props)
	local p = props or {}
	p.Parent = parent
	p.Text = text
	p.BackgroundTransparency = p.BackgroundTransparency or 1
	p.BorderSizePixel = 0
	p.Font = p.Font or Theme.Font
	p.TextColor3 = p.TextColor3 or Theme.Ink
	p.TextSize = p.TextSize or 16
	return Theme.new("TextLabel", p)
end

-- Libellé centré dans son parent : ancrage au milieu, alignements centrés et
-- taille bornée. Sert aux chiffres des compteurs, qui doivent rester centrés
-- quelle que soit la résolution.
function Theme.numberLabel(parent, text, props)
	local p = props or {}
	local maxTextSize = p.TextSize or 16
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.5)
	p.Size = p.Size or UDim2.fromScale(1, 1)
	p.TextXAlignment = Enum.TextXAlignment.Center
	p.TextYAlignment = Enum.TextYAlignment.Center
	p.Font = p.Font or Theme.FontBold
	local label = Theme.label(parent, text, p)
	Theme.textScaled(label, maxTextSize, 8)
	return label
end

-- Ombre douce sans UIStroke : un cadre décalé, très transparent, posé juste
-- derrière la cible. Une ombre enfant serait dessinée par-dessus le fond de
-- la cible, d'où le choix d'un frère placé en ZIndex inférieur.
-- L'ombre suit la cible (ancrage, position, taille, visibilité, ZIndex) et
-- disparaît avec elle. Limites : c'est un frère de la cible, donc à éviter dans
-- un parent à UIListLayout ou UIGridLayout (elle y occuperait sa propre place) ;
-- elle ne suit pas un changement de parent de la cible.
function Theme.shadow(target, radius, offset)
	local parent = target.Parent
	if not parent then
		return nil
	end
	local lift = offset or Theme.Shadow.Offset
	local shadow = Theme.new("Frame", {
		Name = "Shadow",
		Parent = parent,
		BackgroundColor3 = C.CardShadow,
		BackgroundTransparency = Theme.Shadow.Transparency,
		BorderSizePixel = 0,
	})
	Theme.corner(shadow, radius or Theme.Radius.Medium)

	local function follow()
		shadow.AnchorPoint = target.AnchorPoint
		shadow.Position = target.Position + UDim2.fromOffset(0, lift)
		shadow.Size = target.Size
		shadow.Visible = target.Visible
		shadow.ZIndex = target.ZIndex - 1
	end
	follow()

	-- Les changements de la cible sont suivis par des connexions légères, pas par
	-- une boucle : elles sont toutes coupées avec la cible.
	local connections = {}
	for _, property in ipairs({ "AnchorPoint", "Position", "Size", "Visible", "ZIndex" }) do
		table.insert(connections, target:GetPropertyChangedSignal(property):Connect(follow))
	end
	-- L'ombre disparaît avec sa cible, sinon elle resterait affichée seule.
	table.insert(connections, target.Destroying:Connect(function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		shadow:Destroy()
	end))
	return shadow
end

-- Carte claire et arrondie. Les options CornerRadius et Shadow ne sont pas
-- des propriétés Roblox : elles sont retirées avant Theme.new.
function Theme.panel(parent, props)
	local p = props or {}
	local radius = p.CornerRadius or Theme.Radius.Large
	local withShadow = p.Shadow
	p.CornerRadius = nil
	p.Shadow = nil
	p.Parent = parent
	p.BackgroundColor3 = p.BackgroundColor3 or Theme.Panel
	p.BorderSizePixel = 0
	local panel = Theme.new("Frame", p)
	Theme.corner(panel, radius)
	if withShadow then
		Theme.shadow(panel, radius)
	end
	return panel
end

-- Pastille : libellé centré sur fond clair, coins entièrement arrondis.
function Theme.pill(parent, text, props)
	local p = props or {}
	p.BackgroundColor3 = p.BackgroundColor3 or Theme.Panel
	p.BackgroundTransparency = p.BackgroundTransparency or 0
	local label = Theme.numberLabel(parent, text, p)
	Theme.corner(label, Theme.Radius.Pill)
	return label
end

-- Tweens. Un nouveau tween remplace celui qui tourne encore pour la même
-- propriété (slot) : deux animations ne se disputent jamais une valeur.
-- Une table à clés faibles évite de retenir les instances détruites ; l'entrée
-- est retirée dès que le tween se termine ou est annulé.
local activeTweens = setmetatable({}, { __mode = "k" })

function Theme.tween(instance, goal, slot, duration)
	-- Sans slot, un emplacement commun : une clé nil ferait échouer la table.
	slot = slot or "default"
	local slots = activeTweens[instance]
	if not slots then
		slots = {}
		activeTweens[instance] = slots
	end
	local previous = slots[slot]
	if previous then
		previous:Cancel()
	end
	local info = TweenInfo.new(duration or Theme.Motion.Duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(instance, info, goal)
	slots[slot] = tween
	local connection
	connection = tween.Completed:Connect(function()
		connection:Disconnect()
		if slots[slot] == tween then
			slots[slot] = nil
		end
	end)
	tween:Play()
	return tween
end

-- Annule les tweens de Theme.tween encore actifs sur instance.
function Theme.stopTweens(instance)
	local slots = activeTweens[instance]
	if not slots then
		return
	end
	activeTweens[instance] = nil
	for _, tween in pairs(slots) do
		tween:Cancel()
	end
end

-- Annule le tween d'un seul emplacement (les autres animations de la cible continuent).
local function cancelSlot(instance, slot)
	local slots = activeTweens[instance]
	local tween = slots and slots[slot]
	if tween then
		slots[slot] = nil
		tween:Cancel()
	end
end

-- Remises à zéro du survol, par cible. Une cible cachée par un ancêtre (couche
-- fermée, page changée) ne signale pas toujours MouseLeave : sans ce rappel
-- elle réapparaîtrait en état de survol. Theme.motion et Theme.button y
-- inscrivent chacun la leur ; l'entrée disparaît avec la cible. addHoverReset
-- renvoie la fonction qui retire l'inscription (et sa connexion, si c'était la
-- dernière).
local hoverResets = setmetatable({}, { __mode = "k" })

local function addHoverReset(target, reset)
	local entry = hoverResets[target]
	if not entry then
		entry = { list = {} }
		entry.connection = target.Destroying:Connect(function()
			hoverResets[target] = nil
		end)
		hoverResets[target] = entry
	end
	table.insert(entry.list, reset)
	return function()
		local index = table.find(entry.list, reset)
		if index then
			table.remove(entry.list, index)
		end
		if #entry.list == 0 and hoverResets[target] == entry then
			entry.connection:Disconnect()
			hoverResets[target] = nil
		end
	end
end

-- Ramène à l'état de repos, sans animation, le survol de root et de tous ses
-- descendants (à appeler quand une couche ou une page est cachée).
function Theme.resetHover(root)
	local function reset(instance)
		local entry = hoverResets[instance]
		if entry then
			-- Copie : une remise à zéro ne doit pas modifier la liste qu'on parcourt.
			for _, fn in ipairs(table.clone(entry.list)) do
				fn()
			end
		end
	end
	reset(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		reset(descendant)
	end
end

-- Un doigt qui se relève ne déclenche pas toujours MouseLeave : la fin du
-- toucher remet donc le survol à zéro.
local function isTouch(input)
	return input.UserInputType == Enum.UserInputType.Touch
end

-- Survol et clic : une échelle (UIScale enfant) animée en Quad, jamais au-delà
-- de Theme.Motion.Max. Un même objet ne reçoit qu'un seul moteur d'animation ;
-- handle:destroy() coupe les connexions, annule les tweens et retire l'échelle.
-- Ne pas l'appliquer à une cible qui a déjà un UIScale de mise à l'échelle
-- d'écran : deux UIScale sur un même objet se disputent la taille.
local motions = setmetatable({}, { __mode = "k" })

function Theme.motion(target, options)
	local existing = motions[target]
	if existing then
		return existing
	end
	local hoverScale = math.min((options and options.hover) or Theme.Motion.Hover, Theme.Motion.Max)
	local pressScale = math.min((options and options.press) or Theme.Motion.Press, Theme.Motion.Max)
	local scale = Theme.new("UIScale", { Name = "MotionScale", Parent = target })
	local hovered = false
	local pressed = false
	local connections = {}
	local destroyed = false

	local function refresh()
		local goal = 1
		if pressed then
			goal = pressScale
		elseif hovered then
			goal = hoverScale
		end
		Theme.tween(scale, { Scale = goal }, "scale")
	end

	table.insert(connections, target.MouseEnter:Connect(function()
		hovered = true
		refresh()
	end))
	table.insert(connections, target.MouseLeave:Connect(function()
		hovered = false
		pressed = false
		refresh()
	end))
	-- Seuls les boutons ont un clic ; un simple cadre garde survol et sortie.
	if target:IsA("GuiButton") then
		table.insert(connections, target.MouseButton1Down:Connect(function()
			pressed = true
			refresh()
		end))
		table.insert(connections, target.MouseButton1Up:Connect(function()
			pressed = false
			refresh()
		end))
	end

	-- Une cible cachée ou sortie de l'arbre ne reçoit plus de MouseLeave : sans
	-- ces liens, son survol resterait figé. On réagit au changement de Visible et
	-- de parent, sans surveiller l'interface à chaque image.
	local function clearState()
		hovered = false
		pressed = false
		refresh()
	end
	table.insert(connections, target:GetPropertyChangedSignal("Visible"):Connect(function()
		if not target.Visible then
			clearState()
		end
	end))
	table.insert(connections, target.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clearState()
		end
	end))
	table.insert(connections, target.InputEnded:Connect(function(input)
		if isTouch(input) then
			clearState()
		end
	end))
	local removeReset = addHoverReset(target, function()
		hovered = false
		pressed = false
		Theme.stopTweens(scale)
		scale.Scale = 1
	end)

	local handle = {}
	function handle:destroy()
		if destroyed then
			return
		end
		destroyed = true
		removeReset()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
		Theme.stopTweens(scale)
		scale:Destroy()
		motions[target] = nil
	end
	-- Sans ce lien, la table faible garderait la cible vivante (la fermeture du
	-- handle la référence) tant que destroy n'est pas appelé.
	table.insert(connections, target.Destroying:Connect(function()
		handle:destroy()
	end))
	motions[target] = handle
	return handle
end

-- État sélectionné d'un bouton d'outil : fond d'accent et liseré fin. La
-- couleur de repos est mémorisée au premier appel, puis restaurée.
function Theme.setSelected(button, selected)
	local ring = button:FindFirstChild("SelectionRing")
	if not ring then
		ring = Theme.stroke(button, Theme.AccentDark, Theme.Stroke.Thin, 1)
		ring.Name = "SelectionRing"
	end
	local idle = button:GetAttribute("IdleColor")
	if not idle then
		idle = button.BackgroundColor3
		button:SetAttribute("IdleColor", idle)
	end
	local color = selected and Theme.Selected or idle
	-- BaseColor sert à Theme.button : le survol repart de la couleur courante.
	button:SetAttribute("BaseColor", color)
	Theme.tween(button, { BackgroundColor3 = color }, "color")
	Theme.tween(ring, { Transparency = selected and 0 or 1 }, "ring")
end

function Theme.button(parent, text, props, onClick)
	local p = props or {}
	local cornerRadius = p.CornerRadius
	p.CornerRadius = nil
	p.Parent = parent
	p.Text = text
	p.Active = true
	p.Selectable = true
	p.AutoButtonColor = false
	p.BorderSizePixel = 0
	p.Font = p.Font or Theme.FontBold
	p.TextColor3 = p.TextColor3 or Theme.White
	p.TextSize = p.TextSize or 24
	p.BackgroundColor3 = p.BackgroundColor3 or Theme.Teal

	local maxTextSize = p.TextSize or 24
	local button = Theme.new("TextButton", p)
	Theme.corner(button, cornerRadius or Theme.Radius.Medium)

	button.TextScaled = true
	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MaxTextSize = maxTextSize
	textLimit.MinTextSize = 9
	textLimit.Parent = button

	local baseColor = button.BackgroundColor3
	button:SetAttribute("BaseColor", baseColor)

	local function currentBaseColor()
		return button:GetAttribute("BaseColor") or baseColor
	end

	button.MouseEnter:Connect(function()
		if button.Active then
			Theme.tween(button, {
				BackgroundColor3 = currentBaseColor():Lerp(Color3.new(0, 0, 0), 0.09),
			}, "color")
		end
	end)
	button.MouseLeave:Connect(function()
		Theme.tween(button, { BackgroundColor3 = currentBaseColor() }, "color")
	end)
	-- Un bouton caché pendant le survol ne reçoit pas de MouseLeave : sa couleur
	-- repart de la base dès qu'il disparaît, sans attendre le pointeur.
	button:GetPropertyChangedSignal("Visible"):Connect(function()
		if not button.Visible then
			Theme.tween(button, { BackgroundColor3 = currentBaseColor() }, "color")
		end
	end)
	button.InputEnded:Connect(function(input)
		if isTouch(input) then
			Theme.tween(button, { BackgroundColor3 = currentBaseColor() }, "color")
		end
	end)
	addHoverReset(button, function()
		cancelSlot(button, "color")
		button.BackgroundColor3 = currentBaseColor()
	end)
	-- Activated couvre souris / tactile / manette. MouseButton1Click sert de
	-- filet de sécurité sur certaines versions de Studio ; le debounce évite
	-- qu'un même clic déclenche deux fois l'action.
	local lastActivation = 0
	local function activate()
		local now = os.clock()
		if now - lastActivation < 0.12 then
			return
		end
		lastActivation = now
		if onClick then
			onClick()
		end
	end
	button.Activated:Connect(activate)
	button.MouseButton1Click:Connect(activate)

	return button
end

function Theme.circle(parent, diameter, color, props)
	local p = props or {}
	p.Parent = parent
	p.BackgroundColor3 = color
	p.Size = p.Size or UDim2.fromOffset(diameter, diameter)
	p.BorderSizePixel = 0
	local circle = Theme.new("Frame", p)
	Theme.corner(circle, diameter / 2)
	return circle
end

function Theme.grid(parent, step, color, transparency)
	local container = Theme.new("Frame", {
		Name = "GridPattern",
		Parent = parent,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	for i = 1, math.floor(1 / step) - 1 do
		Theme.new("Frame", {
			Parent = container,
			Position = UDim2.fromScale(i * step, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency or 0.4,
			BorderSizePixel = 0,
		})
		Theme.new("Frame", {
			Parent = container,
			Position = UDim2.fromScale(0, i * step),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency or 0.4,
			BorderSizePixel = 0,
		})
	end
	return container
end

-- Valeur numérique sûre : nil, NaN et infini donnent la valeur de repli.
function Theme.numberOr(value, fallback)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

-- Entier avec espaces de milliers : 1 234 567. Une valeur absente ou invalide
-- compte pour 0 ; le nombre est arrondi à l'entier inférieur. Le HUD (fin de
-- partie) et le lobby (records) l'utilisent : un même score s'écrit pareil dans
-- les deux.
function Theme.formatNumber(value)
	local n = math.floor(Theme.numberOr(value, 0))
	local sign = ""
	if n < 0 then
		sign = "-"
		n = -n
	end
	local digits = tostring(n)
	local groups = ""
	while #digits > 3 do
		groups = " " .. string.sub(digits, -3) .. groups
		digits = string.sub(digits, 1, -4)
	end
	return sign .. digits .. groups
end

return Theme
