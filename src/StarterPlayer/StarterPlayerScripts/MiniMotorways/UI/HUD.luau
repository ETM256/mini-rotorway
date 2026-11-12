--[[
	HUD.luau
	Point d'entrée de l'interface de jeu. Les méthodes sont réparties par
	responsabilité dans des modules voisins (même principe que Session) :
	  HUDTopBar      score, jour, mois, horloge, contrôles du temps, jauge de trafic
	  HUDToolbar     colonne d'outils à droite
	  HUDCounters    compteurs du bas et aide
	  HUDOverlays    pause, fin de partie, choix hebdomadaire, toast
	  HUDResponsive  mise en page selon la taille de l'écran, marges de sécurité
	  HUDIcons       pictogrammes dessinés en Frame
	Ce module reçoit l'état serveur et le répartit entre ces parties.

	Callbacks de HUD.new(callbacks), tous optionnels : onPause, onResume,
	onRestart, onMenu, onToolChange(tool), onSpeed(value), onChooseReward(id) et
	onSetting(name, value) avec name « grid » ou « hints ». Le HUD gère lui-même
	l'affichage de l'aide : onSetting « hints » ne demande aucune action.
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)

local HUD = {}
HUD.__index = HUD

require(script.Parent.HUDTopBar)(HUD)
require(script.Parent.HUDToolbar)(HUD)
require(script.Parent.HUDCounters)(HUD)
require(script.Parent.HUDOverlays)(HUD)
require(script.Parent.HUDResponsive)(HUD)

-- Chaque mise à jour regroupe les champs de l'état serveur qui la concernent :
-- elle n'est rejouée que si l'un d'eux a changé depuis le dernier état reçu.
-- Les actions passent par `self:` pour rester remplaçables dans les tests.
local UPDATES = {
	{
		fields = { "score" },
		apply = function(self, state)
			local text = tostring(state.score or 0)
			if self.scoreValue.Text ~= text then
				self.scoreValue.Text = text
			end
		end,
	},
	{
		fields = { "week", "weekProgress", "day", "dayOfWeek", "dayProgress", "month", "monthName", "monthWeek", "monthProgress" },
		apply = function(self, state)
			self:setCalendar(state)
		end,
	},
	{
		fields = { "budget", "bridges", "houses", "destinations" },
		apply = function(self, state)
			self:updateCounters(state)
		end,
	},
	{
		fields = { "roundabouts" },
		apply = function(self, state)
			self:setRoundabouts(state.roundabouts or 0)
		end,
	},
	{
		fields = { "satisfaction" },
		apply = function(self, state)
			self:setSatisfaction(state.satisfaction or 0)
		end,
	},
	{
		fields = { "speed" },
		apply = function(self, state)
			self:setSpeed(state.speed or 1)
		end,
	},
	{
		-- Pendant le choix hebdomadaire le serveur est en pause : la carte de choix
		-- l'explique déjà, la barre n'affiche pas de pause en plus.
		fields = { "paused", "awaitingChoice" },
		apply = function(self, state)
			self:setPaused(state.paused == true and not state.awaitingChoice)
		end,
	},
	{
		-- La fin de partie retire l'aide ; seul l'état « over » compte ici.
		fields = { "over" },
		apply = function(self, state)
			if state.over then
				self:setHintShown(false)
			end
		end,
	},
}

-- Vrai si un champ de la liste diffère entre l'état reçu et le précédent.
local function anyChanged(state, previous, fields)
	for _, field in ipairs(fields) do
		if state[field] ~= previous[field] then
			return true
		end
	end
	return false
end

function HUD.new(callbacks)
	local self = setmetatable({}, HUD)
	self.callbacks = callbacks or {}
	self.tool = "build"
	self.toolButtons = {}
	self.mapName = ""
	self.speed = 1
	self.roundabouts = 0
	self.choiceWeek = nil
	self.choiceDismissedWeek = nil
	self.destroyed = false
	self:build()
	return self
end

function HUD:build()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "MM_HUD"
	-- Le HUD survit à la mort du personnage : une partie de gestion n'en dépend pas.
	gui.ResetOnSpawn = false
	-- La vue couvre tout l'écran, barre de Roblox comprise : AbsoluteSize et la
	-- taille de la caméra partagent alors la même origine, et les marges de
	-- getSafeInsets se transmettent telles quelles à CameraController. Le coin
	-- haut gauche reste libre pour le bouton de menu de Roblox, qui subsiste même
	-- quand les CoreGui sont masqués (Theme.Layout.TopLeftInset).
	gui.IgnoreGuiInset = true
	-- Au-dessus du menu d'accueil (20) : les deux ne sont jamais affichés ensemble.
	gui.DisplayOrder = 30
	-- Les éléments frères s'empilent selon leur ZIndex, puis leur ordre de création.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui
	self.gui = gui

	-- L'ordre de construction fixe l'ordre des enfants de gui, donc l'empilement
	-- des éléments de même ZIndex : il ne doit pas changer sans raison.
	self:buildTopBar()
	self:buildCounters()
	self:buildToast()
	self:buildHint()
	self:buildToolbar()
	self:buildOverlays()
	self:applyResponsive()
	self.sizeConnection = self.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:applyResponsive()
	end)
end

function HUD:showGame(data, map)
	self.gui.Enabled = true
	-- Une nouvelle partie réaffiche tous les champs au premier état reçu.
	self.applied = nil
	self.choiceWeek = nil
	self.choiceDismissedWeek = nil
	self:hideModals()
	self:clearToasts()
	self:resetTopBar()
	self:resetCounters()
	self.mapName = map and map.name or tostring(data.mapId)
	self:setTool("build")
	self:setSatisfaction(100)
	self:setSpeed(1)
	self:setRoundabouts(data.roundabouts or 0)
	self:applyResponsive()
	-- Le réglage « Astuces » survit à une nouvelle partie de la même session.
	self:flashHint()
end

function HUD:hide()
	self.gui.Enabled = false
end

-- Libère les connexions, les délais, les animations et l'interface. Sans effet
-- au second appel.
function HUD:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:cancelHintTimer()
	self:clearToasts()
	if self.sizeConnection then
		self.sizeConnection:Disconnect()
		self.sizeConnection = nil
	end
	self:releaseOverlays()
	-- Les tweens de Theme encore en cours sur l'interface sont annulés : leur
	-- connexion de fin se libère avec eux.
	Theme.stopTweens(self.gui)
	for _, descendant in ipairs(self.gui:GetDescendants()) do
		Theme.stopTweens(descendant)
	end
	self.gui:Destroy()
end

function HUD:setState(state)
	if not state or self.destroyed then
		return
	end
	local previous = self.applied
	local first = previous == nil
	previous = previous or {}
	local snapshot = {}
	for _, update in ipairs(UPDATES) do
		local changed = first or anyChanged(state, previous, update.fields)
		for _, field in ipairs(update.fields) do
			snapshot[field] = state[field]
		end
		if changed then
			update.apply(self, state)
		end
	end
	self.applied = snapshot

	if state.choice
		and state.choice.options
		and state.choice.week ~= self.choiceDismissedWeek
		and not self.choiceOverlay.Visible
	then
		self:showWeekChoice(state.choice)
	end
end

-- Le rond-point n'est un outil que s'il en reste au moins un.
function HUD:setRoundabouts(value)
	self.roundabouts = tonumber(value) or 0
	local text = tostring(self.roundabouts)
	if self.roundaboutValue.Text ~= text then
		self.roundaboutValue.Text = text
	end
	self.toolButtons.roundabout.Visible = self.roundabouts > 0
	self:layoutToolPill()
	if self.tool == "roundabout" and self.roundabouts <= 0 then
		self:setTool("build")
		if self.callbacks.onToolChange then
			self.callbacks.onToolChange("build")
		end
	end
end

return HUD
