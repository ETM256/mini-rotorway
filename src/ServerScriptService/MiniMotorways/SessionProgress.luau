--[[
	SessionProgress.luau
	Progression de Session : satisfaction, surcharge, choix hebdomadaires,
	récompenses et amélioration de la circulation.
	Ajoute ses méthodes à Session ; appelé une seule fois depuis Session.luau.

	Surcharge (formule) : tant qu'au moins un magasin est critique, la
	satisfaction baisse de
	    StoreSystem:getOverloadDrain() × pression
	    pression = 1 + min(OverloadMaxExtra, tempsCritique / OverloadRampSeconds)
	où tempsCritique est le temps passé en critique par le magasin le plus
	négligé. Dès que ce magasin n'est plus plein (une livraison l'a libéré),
	son compteur repart de zéro. Au départ, le drain
	est celui de StoreConfig : la pression ne fait que croître doucement, et
	plafonne à deux fois le drain de base.
	Les voitures bloquées (Config.Traffic) s'ajoutent sans multiplicateur.
	Tout est gelé pendant la pause et pendant un choix de récompense.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Progression = Config.Progression

-- Bonus de routes d'une semaine : nul en semaine 1, puis par paliers réguliers
-- et plafonné. Les lots restent proches de leurs valeurs de base.
local function roadBonus(week)
	local steps = math.floor((week - 1) / Progression.RoadsWeeksPerStep)
	return math.min(Progression.RoadsMaxBonus, steps * Progression.RoadsPerStep)
end

-- Le texte de Config contient le lot de base : on remplace son premier nombre
-- par le montant réel de la semaine.
local function withAmount(text, amount)
	return (string.gsub(text, "%d+", tostring(amount), 1))
end

-- Copie d'une récompense pour la proposition : les montants de la semaine sont
-- figés au moment de l'offre, et Config n'est jamais modifiée.
local function makeOption(reward, week)
	local bonus = roadBonus(week)
	local option = {
		id = reward.id,
		kind = reward.kind,
		amount = reward.amount,
		roads = reward.roads,
		trafficFactor = reward.trafficFactor,
		title = reward.title,
		description = reward.description,
	}
	if option.kind == "roads" then
		option.amount = reward.amount + bonus
		option.title = withAmount(reward.title, option.amount)
		option.description = withAmount(reward.description, option.amount)
	elseif option.roads then
		option.roads = reward.roads + bonus
		option.description = withAmount(reward.description, option.roads)
	end
	return option
end

-- Pression de surcharge selon le temps passé en critique (voir l'en-tête).
local function overloadPressure(seconds)
	return 1 + math.min(Progression.OverloadMaxExtra, seconds / Progression.OverloadRampSeconds)
end

return function(Session)
	-- Temps passé en surcharge critique, par magasin (clé = magasin). Il ne
	-- s'accumule que pendant la simulation, donc pas pendant une pause.
	function Session:trackCriticalStores(dt)
		local times = self.criticalTimes or {}
		self.criticalTimes = times
		for _, store in ipairs(self.destinations) do
			if store.critical then
				times[store] = (times[store] or 0) + dt
			else
				times[store] = nil
			end
		end
	end

	-- Résumé de la surcharge en données simples (HUD, écran de fin). Le magasin
	-- « worst » est celui qui est critique depuis le plus longtemps.
	function Session:getOverloadSummary()
		local summary = {
			criticalCount = 0,
			pressure = 1,
			seconds = 0,
			storeId = nil,
			colorIndex = nil,
			colorName = nil,
		}
		local times = self.criticalTimes or {}
		local worst = nil
		for _, store in ipairs(self.destinations) do
			if store.critical then
				summary.criticalCount += 1
				local seconds = times[store] or 0
				if worst == nil or seconds > summary.seconds then
					worst = store
					summary.seconds = seconds
				end
			end
		end
		if worst then
			summary.storeId = worst.id
			summary.colorIndex = worst.colorIndex
			local color = Config.HouseColors[worst.colorIndex]
			summary.colorName = color and color.name
		end
		summary.pressure = overloadPressure(summary.seconds)
		return summary
	end

	-- Multiplicateur de la distance de sécurité des voitures (1 = inchangé).
	-- Le trafic le lit pour raccourcir l'espacement après une amélioration.
	function Session:getTrafficMultiplier()
		return self.upgrades and self.upgrades.traffic or 1
	end

	-- Jauge de satisfaction : baisse avec les voitures bloquées et la surcharge,
	-- et ne remonte que lorsque le trafic coule.
	function Session:updateSatisfaction(dt)
		-- Pause, choix de récompense ou partie finie : rien ne bouge.
		if self.over or self.paused or self.awaitingChoice or not self.running then
			return
		end

		local drain = 0
		for _, car in ipairs(self.cars) do
			-- Une voiture sans trajet n'est pas encore "dans le trafic" :
			-- on ne pénalise que les voitures réellement bloquées sur un chemin.
			if car.path and car.waitTime >= Config.Traffic.StuckAfter then
				drain += Config.Traffic.DrainPerStuckCar
			end
		end

		self:trackCriticalStores(dt)
		local overload = self:getOverloadSummary()
		if self.storeSystem then
			drain += self.storeSystem:getOverloadDrain() * overload.pressure
		end

		if drain > 0 then
			self.satisfaction -= drain * dt
		else
			self.satisfaction = math.min(
				Config.Traffic.SatisfactionMax,
				self.satisfaction + Config.Traffic.RegenPerSecond * dt
			)
		end

		if self.satisfaction <= 0 then
			self.satisfaction = 0
			-- La cause reste disponible pour l'écran de fin. Un magasin critique
			-- l'emporte sur les voitures bloquées.
			if overload.storeId then
				self.gameOverReason = {
					kind = "overload",
					storeId = overload.storeId,
					colorIndex = overload.colorIndex,
					colorName = overload.colorName,
					seconds = overload.seconds,
				}
			else
				self.gameOverReason = { kind = "traffic" }
			end
			self:gameOver()
		end
	end

	-- Deux propositions différentes : une carte spéciale (pont, rond-point ou
	-- amélioration de circulation, seulement si elle n'est pas au maximum) et
	-- un lot de routes. Sans carte spéciale disponible, deux lots différents.
	function Session:pickWeekChoices()
		local rng = self.random or math
		local specials = {}
		if self.bridgesLeft < Config.Roads.MaxBridges then
			table.insert(specials, Config.Rewards.Bridge)
		end
		if self.roundaboutsLeft < Config.Roads.MaxRoundabouts then
			table.insert(specials, Config.Rewards.Roundabout)
		end
		if self:getTrafficMultiplier() > Progression.TrafficMinFactor then
			table.insert(specials, Config.Rewards.Traffic)
		end

		local first, second
		if #specials == 0 then
			first = Config.Rewards.Roads
			second = Config.Rewards.RoadsLarge
		else
			first = specials[rng.random(1, #specials)]
			second = rng.random() < 0.25 and Config.Rewards.RoadsLarge or Config.Rewards.Roads
		end

		local options = { makeOption(first, self.week), makeOption(second, self.week) }
		if rng.random() < 0.5 then
			options[1], options[2] = options[2], options[1]
		end
		return options
	end

	function Session:offerWeekChoice()
		if self.over or self.awaitingChoice then
			return
		end
		self.awaitingChoice = true
		self.paused = true
		self.choice = {
			week = self.week,
			options = self:pickWeekChoices(),
		}
		-- La proposition arrive à la fin de la semaine qui vient de se terminer.
		if self.recordStat then
			self:recordStat("weeksCompleted", 1)
		end
		if self.player then
			Remotes.get("WeekChoice"):FireClient(self.player, self.choice)
		end
		self:sendState()
	end

	function Session:chooseReward(optionId)
		if not self.awaitingChoice or not self.choice then
			return
		end
		-- Seules les options proposées cette semaine sont acceptées.
		local selected = nil
		for _, option in ipairs(self.choice.options or {}) do
			if option.id == optionId then
				selected = option
				break
			end
		end
		if not selected then
			return
		end

		-- Les outils spéciaux sont accompagnés de routes (20 routes pour un pont
		-- ou un rond-point, comme dans Mini Motorways).
		local roadGain = selected.roads or 0
		if selected.kind == "roads" then
			roadGain += selected.amount
		elseif selected.kind == "bridges" then
			self.bridgesLeft = math.min(Config.Roads.MaxBridges, self.bridgesLeft + selected.amount)
		elseif selected.kind == "roundabouts" then
			self.roundaboutsLeft = math.min(Config.Roads.MaxRoundabouts, self.roundaboutsLeft + selected.amount)
		end
		if roadGain > 0 then
			self.budget = math.min(Config.Roads.MaxBudget, self.budget + roadGain)
		end
		if selected.trafficFactor then
			self.upgrades = self.upgrades or {}
			self.upgrades.traffic = math.max(
				Progression.TrafficMinFactor,
				self:getTrafficMultiplier() * selected.trafficFactor
			)
		end

		-- Choix consommé une seule fois : la proposition est close avant tout
		-- envoi, donc un second appel ne peut plus rien accorder.
		self.awaitingChoice = false
		self.choice = nil
		self.paused = false
		if self.recordStat then
			self:recordStat("rewardsChosen", 1)
		end
		self:sendState()
		self:sendRoadState()

		local gainText = selected.title or "Amélioration"
		if selected.roads and selected.roads > 0 then
			gainText = gainText .. " + " .. tostring(selected.roads) .. " routes"
		end
		self:toast("Amélioration choisie : " .. gainText .. ".")
	end
end
