--[[
	HUDCounters.luau
	Bas de l'écran : cinq pastilles identiques (routes, ponts, rond-points,
	maisons, destinations) et la ligne d'aide. Même hauteur, même arrondi, même
	case de pictogramme et même case de chiffre : seul le pictogramme change.
	Mixin : ajoute ses méthodes à HUD.
]]

local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.HUDIcons)

local L = Theme.Layout

-- Durée d'affichage de l'aide en bas de l'écran, en secondes.
local HINT_DURATION = 22
-- Aide au clavier et à la souris, ou au doigt (sans clavier : pas de clic droit,
-- de molette ni de touche Échap).
local HINT_DESKTOP =
	"Glissez pour tracer  ·  Échap pour annuler  ·  clic droit pour effacer  ·  molette pour zoomer  ·  clic milieu pour déplacer"
local HINT_TOUCH = "Glissez pour tracer  ·  pincez pour zoomer  ·  gomme et main : barre d'outils"

local ICON_SIZE = 20
local CHIP_PADDING = 8
local ICON_GAP = 4
-- Le chiffre occupe le reste de la pastille, après le pictogramme.
local NUMBER_X = CHIP_PADDING + ICON_SIZE + ICON_GAP
local NUMBER_WIDTH = L.ChipWidth - NUMBER_X - CHIP_PADDING + 2

-- Pastilles dans l'ordre d'affichage : nom, champ du HUD qui garde le chiffre,
-- pictogramme et sa couleur, texte avant le premier état serveur (tiret ASCII :
-- le tiret long n'est pas garanti dans la police Roblox). Le fond reste le même
-- pour toutes.
local CHIPS = {
	{ name = "roads", field = "budgetValue", icon = Icons.road, color = Theme.Ink, reset = "-" },
	{ name = "bridges", field = "bridgeValue", icon = Icons.bridge, color = Theme.Bridge, reset = "-" },
	{ name = "roundabouts", field = "roundaboutValue", icon = Icons.roundabout, color = Theme.TealDark, reset = "0" },
	{ name = "houses", field = "houseValue", icon = Icons.house, color = Theme.AccentWarm, reset = "-" },
	{ name = "destinations", field = "storeValue", icon = Icons.store, color = Theme.Ink, reset = "-" },
}

local function makeChip(parent, order, spec)
	local chip = Theme.panel(parent, {
		Name = spec.name,
		Size = UDim2.fromOffset(L.ChipWidth, L.ChipHeight),
		LayoutOrder = order,
		CornerRadius = Theme.Radius.Large,
		-- Active : un clic sur une pastille ne traverse pas l'interface.
		Active = true,
		ZIndex = 43,
	})
	Theme.stroke(chip, Theme.Border, Theme.Stroke.Thin, Theme.Stroke.Transparency)

	-- Case de pictogramme centrée verticalement, à gauche du chiffre.
	local slot = Theme.new("Frame", {
		Parent = chip,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, CHIP_PADDING, 0.5, 0),
		Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 44,
	})
	spec.icon(slot, spec.color)

	-- Chiffre centré dans sa case (Theme.numberLabel centre et borne la taille).
	local value = Theme.numberLabel(chip, "0", {
		Font = Theme.FontBlack,
		TextSize = 15,
		TextColor3 = Theme.Ink,
		ZIndex = 44,
	})
	value.AnchorPoint = Vector2.new(0, 0.5)
	value.Position = UDim2.new(0, NUMBER_X, 0.5, 0)
	value.Size = UDim2.new(0, NUMBER_WIDTH, 1, 0)
	return value
end

-- Écrit un texte seulement s'il change : aucun redessin inutile.
local function setText(label, text)
	if label.Text ~= text then
		label.Text = text
	end
end

return function(HUD)
	-- Compteurs de ressources, en bas au centre.
	function HUD:buildCounters()
		local width = L.ChipCount * L.ChipWidth + (L.ChipCount - 1) * L.ChipGap
		local resources = Theme.new("Frame", {
			Parent = self.gui,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -L.Margin),
			Size = UDim2.fromOffset(width, L.ChipHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 42,
		})
		self.resources = resources
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, L.ChipGap)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = resources

		for order, spec in ipairs(CHIPS) do
			self[spec.field] = makeChip(resources, order, spec)
		end
	end

	-- Aide en bas, au-dessus des compteurs, masquée après quelques secondes.
	function HUD:buildHint()
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		self.hint = Theme.label(
			self.gui,
			touchOnly and HINT_TOUCH or HINT_DESKTOP,
			{
				Position = UDim2.new(0.5, 0, 1, -(L.Margin + L.ChipHeight + L.Gap)),
				AnchorPoint = Vector2.new(0.5, 1),
				Size = UDim2.new(0.9, 0, 0, L.HintHeight),
				TextSize = 12,
				TextColor3 = Theme.InkSoft,
				ZIndex = 42,
			}
		)
		Theme.textScaled(self.hint, 12, 7)
		Theme.maxSize(self.hint, 760, L.HintHeight)
		-- Visible par défaut, comme un Label neuf ; showGame relance le délai.
		self.hintShown = true
	end

	-- Affiche ou masque l'aide. Un redimensionnement ne la fait pas réapparaître
	-- après un masquage ; un écran court la masque aussi (voir applyResponsive).
	function HUD:setHintShown(shown)
		self.hintShown = shown
		self.hint.Visible = shown and not self:isShort()
	end

	function HUD:cancelHintTimer()
		if self.hintTimer then
			task.cancel(self.hintTimer)
			self.hintTimer = nil
		end
	end

	-- Montre l'aide si le réglage « Astuces » l'autorise, puis la retire seule.
	-- Un nouvel appel annule l'ancien délai : l'aide ne reste jamais figée.
	function HUD:flashHint()
		self:cancelHintTimer()
		local allowed = self.settings.hints ~= false
		self:setHintShown(allowed)
		if not allowed then
			return
		end
		self.hintTimer = task.delay(HINT_DURATION, function()
			self.hintTimer = nil
			self:setHintShown(false)
		end)
	end

	function HUD:resetCounters()
		for _, spec in ipairs(CHIPS) do
			setText(self[spec.field], spec.reset)
		end
	end

	-- Chaque chiffre vient de la charge serveur ; un champ absent se lit zéro.
	function HUD:updateCounters(state)
		setText(self.budgetValue, tostring(state.budget or 0))
		setText(self.bridgeValue, tostring(state.bridges or 0))
		setText(self.houseValue, tostring(state.houses or 0))
		setText(self.storeValue, tostring(state.destinations or 0))
	end
end
