--[[
	HUDResponsive.luau
	Seul endroit qui connaît les points de rupture : format portrait (téléphone)
	ou paysage, écran court, et la mise à l'échelle des cartes modales.
	Mixin : ajoute isPortrait, isShort, applyResponsive et getSafeInsets à HUD.
]]

local Theme = require(script.Parent.Theme)

local L = Theme.Layout

-- Largeur sous laquelle l'écran est traité comme un téléphone.
local PORTRAIT_WIDTH = 760
local PORTRAIT_RATIO = 0.9
-- Hauteur sous laquelle la ligne d'aide est masquée et les outils passent en bandeau.
local SHORT_HEIGHT = 700
-- Fraction de l'écran qu'une carte modale peut occuper.
local MODAL_WIDTH_RATIO = 0.92
local MODAL_HEIGHT_RATIO = 0.9
local MIN_MODAL_SCALE = 0.35

local function fitScale(width, height, cardWidth, cardHeight)
	return math.max(
		MIN_MODAL_SCALE,
		math.min(1, (width * MODAL_WIDTH_RATIO) / cardWidth, (height * MODAL_HEIGHT_RATIO) / cardHeight)
	)
end

-- Rectangle absolu (x, y, largeur, hauteur) d'un enfant direct de l'interface,
-- calculé comme le moteur : position en échelle et décalage, moins AnchorPoint.
local function rectOf(frame, width, height)
	local size = frame.Size
	local position = frame.Position
	local anchor = frame.AnchorPoint
	local w = width * size.X.Scale + size.X.Offset
	local h = height * size.Y.Scale + size.Y.Offset
	local x = width * position.X.Scale + position.X.Offset - anchor.X * w
	local y = height * position.Y.Scale + position.Y.Offset - anchor.Y * h
	return x, y, w, h
end

return function(HUD)
	function HUD:isPortrait()
		local size = self.gui.AbsoluteSize
		return size.X < PORTRAIT_WIDTH or size.X < size.Y * PORTRAIT_RATIO
	end

	function HUD:isShort()
		return self.gui.AbsoluteSize.Y < SHORT_HEIGHT
	end

	-- La barre du haut et les compteurs ont la même mise en page partout (voir
	-- Theme.Layout) : seuls les outils, l'aide, le toast et l'échelle des cartes
	-- dépendent du format.
	function HUD:applyResponsive()
		local viewport = self.gui.AbsoluteSize
		local width = viewport.X
		local height = viewport.Y
		if width < 2 or height < 2 then
			return
		end

		local portrait = self:isPortrait()
		self.hint.Visible = self.hintShown and not self:isShort()
		self:layoutToolPill()

		-- Le toast passe sous la rangée des contrôles du temps : il ne touche ni la
		-- jauge (même rangée, à gauche) ni le score, quel que soit le format.
		local toastY = L.Margin + L.PanelHeight + L.Gap + L.ControlsHeight + L.Gap
		self.toastLabel.Position = UDim2.new(0.5, 0, 0, toastY)
		self.toastLabel.Size = UDim2.new(portrait and 0.9 or 0.6, 0, 0, L.ControlsHeight - 2)

		-- Les cartes gardent leur taille de conception (HUDOverlays) ; l'échelle s'y applique.
		self.pauseScale.Scale = fitScale(width, height, self.pauseCard.Size.X.Offset, self.pauseCard.Size.Y.Offset)
		self.overScale.Scale = fitScale(width, height, self.overCard.Size.X.Offset, self.overCard.Size.Y.Offset)
		self.choiceScale.Scale = fitScale(width, height, self.choiceCard.Size.X.Offset, self.choiceCard.Size.Y.Offset)
	end

	-- Marges couvertes par l'interface, en pixels, dans l'ordre haut, droite,
	-- bas, gauche (c'est l'ordre attendu par Main pour CameraController). Un
	-- élément large (plus large que haut) occupe le haut ou le bas de l'écran,
	-- un élément haut le côté le plus proche de son centre.
	function HUD:getSafeInsets()
		local width = self.gui.AbsoluteSize.X
		local height = self.gui.AbsoluteSize.Y
		local top, right, bottom, left = 0, 0, 0, 0
		if width < 2 or height < 2 then
			return top, right, bottom, left
		end

		local regions = {
			self.backButton,
			self.scorePanel,
			self.circulation,
			self.controls,
			self.toolPill,
			self.resources,
			self.hint,
		}
		for _, frame in ipairs(regions) do
			if frame.Visible then
				local x, y, w, h = rectOf(frame, width, height)
				if w >= h then
					if y + h / 2 < height / 2 then
						top = math.max(top, y + h)
					else
						bottom = math.max(bottom, height - y)
					end
				elseif x + w / 2 < width / 2 then
					left = math.max(left, x + w)
				else
					right = math.max(right, width - x)
				end
			end
		end
		return math.ceil(top), math.ceil(right), math.ceil(bottom), math.ceil(left)
	end
end
