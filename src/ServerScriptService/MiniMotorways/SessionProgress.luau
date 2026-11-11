--[[
	SessionProgress.luau
	Progression de Session : satisfaction, choix hebdomadaires, récompenses.
	Ajoute ses méthodes à Session ; appelé une seule fois depuis Session.luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

return function(Session)
	function Session:updateSatisfaction(dt)
		local drain = 0
		for _, car in ipairs(self.cars) do
			-- Une voiture sans trajet n'est pas encore "dans le trafic" :
			-- on ne pénalise que les voitures réellement bloquées sur un chemin.
			if car.path and car.waitTime >= Config.Traffic.StuckAfter then
				drain += Config.Traffic.DrainPerStuckCar
			end
		end
		if self.storeSystem then
			drain += self.storeSystem:getOverloadDrain()
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
			self:gameOver()
		end
	end

	function Session:pickWeekChoices()
		-- Comme dans Mini Motorways : une proposition contient un outil spécial
		-- (pont ou rond-point) accompagné de routes, l'autre est un lot de routes.
		-- On ne propose pas un outil déjà au maximum.
		local specials = {}
		if self.bridgesLeft < Config.Roads.MaxBridges then
			table.insert(specials, Config.Rewards.Bridge)
		end
		if self.roundaboutsLeft < Config.Roads.MaxRoundabouts then
			table.insert(specials, Config.Rewards.Roundabout)
		end

		local roadReward = math.random() < 0.25 and Config.Rewards.RoadsLarge or Config.Rewards.Roads
		if #specials == 0 then
			-- Tous les outils sont au maximum : deux lots de routes différents.
			local otherReward = roadReward == Config.Rewards.Roads
				and Config.Rewards.RoadsLarge
				or Config.Rewards.Roads
			local options = { roadReward, otherReward }
			if math.random() < 0.5 then
				options[1], options[2] = options[2], options[1]
			end
			return options
		end

		local specialReward = specials[math.random(1, #specials)]
		local options = { specialReward, roadReward }
		if math.random() < 0.5 then
			options[1], options[2] = options[2], options[1]
		end
		return options
	end

	function Session:offerWeekChoice()
		self.awaitingChoice = true
		self.paused = true
		self.choice = {
			week = self.week,
			options = self:pickWeekChoices(),
		}
		Remotes.get("WeekChoice"):FireClient(self.player, self.choice)
		self:sendState()
	end

	function Session:chooseReward(optionId)
		if not self.awaitingChoice or not self.choice then
			return
		end
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

		-- Les outils spéciaux sont toujours accompagnés de routes (20 routes
		-- pour un pont ou un rond-point, comme dans Mini Motorways).
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

		self.awaitingChoice = false
		self.choice = nil
		self.paused = false
		self:sendState()
		local gainText = selected.title or "Amélioration"
		if selected.roads and selected.roads > 0 then
			gainText = gainText .. " + " .. tostring(selected.roads) .. " routes"
		end
		self:toast("Amélioration choisie : " .. gainText .. ".")
	end
end
