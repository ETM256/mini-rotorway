--[[
	HUDToolbar.luau
	Panneau d'outils clair : colonne à droite en paysage, bandeau horizontal
	(plus large que haut) au-dessus de l'aide en portrait ou dans le coin bas
	droit sur un écran court. Outils : construction, suppression, rond-point
	(seulement quand il est disponible) et déplacement de la vue. Les identifiants
	sont ceux lus par InputController et Main. Mixin : ajoute ses méthodes à HUD.
]]

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.HUDIcons)

local L = Theme.Layout

-- Outils dans l'ordre d'affichage. Chaque touche reprend InputController (1 à 4).
local TOOLS = {
	{ id = "build", key = "1", icon = Icons.pen },
	{ id = "erase", key = "2", icon = Icons.trash },
	{ id = "roundabout", key = "3", icon = Icons.roundabout },
	{ id = "camera", key = "4", icon = Icons.pan },
}

-- 46 px : au-dessus du minimum tactile de 40 px, avec une marge de chaque côté.
local BUTTON_SIZE = 46
local BUTTON_GAP = 6
local PANEL_PADDING = 6
-- Colonne paysage : la largeur est celle d'un bouton plus les marges.
local PANEL_WIDTH = BUTTON_SIZE + 2 * PANEL_PADDING
-- Un second clic dans ce délai (secondes) est ignoré : pas de double envoi.
local CLICK_DEBOUNCE = 0.15

return function(HUD)
	-- Bouton d'outil : pictogramme centré, touche discrète dans le coin, survol
	-- et clic animés par Theme.motion. Les connexions et les animations sont
	-- rangées dans `parts` pour être libérées avec le panneau.
	local function makeToolButton(self, toolPill, spec, order, parts)
		local button = Theme.new("TextButton", {
			Name = spec.id,
			Parent = toolPill,
			Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
			LayoutOrder = order,
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0,
			Text = "",
			Active = true,
			Selectable = true,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			ZIndex = 47,
		})
		Theme.corner(button, Theme.Radius.Medium)
		spec.icon(button, Theme.Ink)

		local hint = Theme.label(button, spec.key, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4, 1, -3),
			Size = UDim2.fromOffset(12, 12),
			TextSize = 9,
			Font = Theme.FontBold,
			TextColor3 = Theme.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 48,
		})
		table.insert(parts.hints, hint)

		table.insert(parts.motions, Theme.motion(button))

		local lastClick = nil
		local function activate()
			local now = os.clock()
			if lastClick and now - lastClick < CLICK_DEBOUNCE then
				return
			end
			lastClick = now
			-- On signale l'outil réellement actif : setTool peut revenir à « build ».
			self:setTool(spec.id)
			if self.callbacks.onToolChange then
				self.callbacks.onToolChange(self.tool)
			end
		end
		table.insert(parts.connections, button.Activated:Connect(activate))
		return button
	end

	function HUD:buildToolbar()
		local toolPill = Theme.new("Frame", {
			Parent = self.gui,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -L.Margin, 0.5, 0),
			Size = UDim2.fromOffset(PANEL_WIDTH, BUTTON_SIZE),
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			-- Active : les marges et les espaces entre les boutons absorbent aussi le clic.
			Active = true,
			ZIndex = 46,
		})
		self.toolPill = toolPill
		Theme.corner(toolPill, Theme.Radius.Large)
		Theme.stroke(toolPill, Theme.Border, Theme.Stroke.Thin, Theme.Stroke.Transparency)
		Theme.padding(toolPill, PANEL_PADDING, PANEL_PADDING, PANEL_PADDING, PANEL_PADDING)

		local toolLayout = Instance.new("UIListLayout")
		toolLayout.FillDirection = Enum.FillDirection.Vertical
		toolLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		toolLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		toolLayout.Padding = UDim.new(0, BUTTON_GAP)
		toolLayout.SortOrder = Enum.SortOrder.LayoutOrder
		toolLayout.Parent = toolPill
		self.toolLayout = toolLayout

		-- Connexions, animations et touches : rangées ici pour être libérées
		-- d'un coup quand le panneau disparaît.
		local parts = { connections = {}, motions = {}, hints = {} }
		self.toolHints = parts.hints
		for order, spec in ipairs(TOOLS) do
			self.toolButtons[spec.id] = makeToolButton(self, toolPill, spec, order, parts)
		end
		-- Le rond-point n'apparaît qu'avec au moins un rond-point disponible.
		self.toolButtons.roundabout.Visible = false

		toolPill.Destroying:Connect(function()
			for _, connection in ipairs(parts.connections) do
				connection:Disconnect()
			end
			for _, handle in ipairs(parts.motions) do
				handle:destroy()
			end
			table.clear(parts.connections)
			table.clear(parts.motions)
		end)

		self:setTool("build")
		self:layoutToolPill()
	end

	-- Un seul bouton est sélectionné : l'outil demandé, ou « build » s'il n'est
	-- pas disponible (rond-point sans rond-point, identifiant inconnu).
	function HUD:setTool(tool)
		if (tool == "roundabout" and self.roundabouts <= 0) or not self.toolButtons[tool] then
			tool = "build"
		end
		self.tool = tool
		for name, button in pairs(self.toolButtons) do
			Theme.setSelected(button, name == tool)
		end
	end

	-- Taille et place du panneau selon le format. Les touches n'ont de sens
	-- qu'au clavier : elles sont masquées en portrait.
	function HUD:layoutToolPill()
		local pill = self.toolPill
		if not pill or not self.toolLayout then
			return
		end
		local portrait = self:isPortrait()

		local count = 0
		for _, spec in ipairs(TOOLS) do
			local button = self.toolButtons[spec.id]
			if button and button.Visible then
				count += 1
			end
		end
		-- Longueur du panneau : boutons, espaces entre eux et marges intérieures.
		local length = count * BUTTON_SIZE + math.max(count - 1, 0) * BUTTON_GAP + 2 * PANEL_PADDING

		local short = self:isShort()
		-- Le coin bas droit n'est libre que si le bandeau tient à droite de la
		-- rangée de compteurs, centrée : sinon (paysage de téléphone étroit) il
		-- passe au-dessus d'elle, comme en portrait.
		local chipsWidth = L.ChipCount * L.ChipWidth + (L.ChipCount - 1) * L.ChipGap
		local cornerWidth = 2 * (L.Margin + length + L.Gap) + chipsWidth
		local stacked = portrait or (short and self.gui.AbsoluteSize.X < cornerWidth)
		if stacked then
			-- Au-dessus des compteurs ; la place de l'aide est réservée même quand
			-- elle est masquée, pour que le bandeau ne saute pas.
			local above = L.Margin + L.ChipHeight + L.Gap
			if not short then
				above += L.HintHeight + L.Gap
			end
			self.toolLayout.FillDirection = Enum.FillDirection.Horizontal
			pill.AnchorPoint = Vector2.new(0.5, 1)
			pill.Position = UDim2.new(0.5, 0, 1, -(above + L.Gap))
			pill.Size = UDim2.fromOffset(length, PANEL_WIDTH)
		elseif short then
			-- Écran court en paysage : la colonne toucherait les contrôles du temps.
			-- Le bandeau va dans le coin bas droit, à côté des compteurs.
			self.toolLayout.FillDirection = Enum.FillDirection.Horizontal
			pill.AnchorPoint = Vector2.new(1, 1)
			pill.Position = UDim2.new(1, -L.Margin, 1, -L.Margin)
			pill.Size = UDim2.fromOffset(length, PANEL_WIDTH)
		else
			self.toolLayout.FillDirection = Enum.FillDirection.Vertical
			pill.AnchorPoint = Vector2.new(1, 0.5)
			pill.Position = UDim2.new(1, -L.Margin, 0.5, 0)
			pill.Size = UDim2.fromOffset(PANEL_WIDTH, length)
		end
		for _, hint in ipairs(self.toolHints) do
			hint.Visible = not portrait
		end
	end
end
