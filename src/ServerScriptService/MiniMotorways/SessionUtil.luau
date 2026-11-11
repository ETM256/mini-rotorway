--[[
	SessionUtil.luau
	Petites fonctions partagées par les modules de Session (pièces, tweens,
	animations). Aucune dépendance sur l'état d'une partie.
]]

local TweenService = game:GetService("TweenService")

local function clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	elseif value > maxValue then
		return maxValue
	end
	return value
end

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	-- Rendu à plat : aucune ombre dynamique, les ombres sont dessinées en pièces.
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth

	-- La forme d'abord : l'ordre de pairs est arbitraire, et changer Shape après
	-- Size pourrait écraser les dimensions déjà posées.
	if props.Shape then
		p.Shape = props.Shape
	end

	local parent = nil
	for key, value in pairs(props) do
		if key == "Parent" then
			parent = value
		elseif key ~= "Shape" then
			p[key] = value
		end
	end
	if parent then
		p.Parent = parent
	end
	return p
end

-- Enregistre un tween dans `tweens` (table clé = tween, valeur = connexion à
-- Completed) pour pouvoir l'arrêter à la fin de la partie. Sans table, le tween
-- n'est simplement pas suivi.
local function trackTween(tweens, tween)
	if tweens then
		local connection
		connection = tween.Completed:Connect(function()
			tweens[tween] = nil
			connection:Disconnect()
		end)
		tweens[tween] = connection
	end
	return tween
end

-- Arrête tous les tweens suivis puis vide la table. Chaque connexion est coupée
-- avant l'arrêt : rien ne reste branché, même si Completed ne revient pas.
local function cancelTweens(tweens)
	local active = {}
	for tween, connection in pairs(tweens) do
		active[#active + 1] = { tween = tween, connection = connection }
	end
	for _, entry in ipairs(active) do
		entry.connection:Disconnect()
		entry.tween:Cancel()
	end
	for tween in pairs(tweens) do
		tweens[tween] = nil
	end
end

-- Tween d'apparition en cours, par pièce de route (clés faibles : une pièce
-- détruite disparaît de la table sans autre ménage).
local revealTweens = setmetatable({}, { __mode = "k" })

-- Arrête l'apparition d'une pièce qui va être détruite : un tween ne doit pas
-- continuer à écrire sur une cible morte, ni rester dans la table de Session.
local function stopRoadPartReveal(part)
	local tween = revealTweens[part]
	if tween then
		revealTweens[part] = nil
		tween:Cancel()
	end
end

-- Petite apparition de la route : la pièce grandit et devient opaque.
-- Le délai permet de faire apparaître les cases l'une après l'autre quand
-- le joueur trace un trait continu. Chaque pièce animée coûte une réplication
-- de Size et Transparency à chaque frame : l'appelant limite le nombre de cases.
local function animateRoadPart(part, finalSize, delay, tweens)
	local startSize = Vector3.new(
		math.max(0.04, finalSize.X * 0.52),
		math.max(0.04, finalSize.Y * 0.52),
		math.max(0.04, finalSize.Z * 0.52)
	)
	part.Size = startSize
	part.Transparency = 0.45

	local tween = trackTween(tweens, TweenService:Create(
		part,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay),
		{ Size = finalSize, Transparency = 0 }
	))
	revealTweens[part] = tween
	tween:Play()
end

-- Anime un Model entier autour de son WorldPivot. Sert à l'apparition d'un
-- magasin et à sa transformation petit carré -> grand cercle. On passe par
-- une NumberValue pour pouvoir tween une valeur puis appeler Model:ScaleTo.
-- Model:ScaleTo n'existe que sur un Model : indexer la méthode sur une Part
-- lèverait une erreur, d'où le test IsA.
local function animateModelScale(model, fromScale, toScale, duration, tweens)
	if not model or not model:IsA("Model") then
		return
	end

	model:ScaleTo(fromScale)
	local value = Instance.new("NumberValue")
	value.Name = "ScaleAnimation"
	value.Value = fromScale

	local connection
	connection = value.Changed:Connect(function(scale)
		if model.Parent then
			model:ScaleTo(scale)
		end
	end)

	local tween = trackTween(tweens, TweenService:Create(
		value,
		TweenInfo.new(duration or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = toScale }
	))
	local finished
	finished = tween.Completed:Connect(function()
		finished:Disconnect()
		if connection then
			connection:Disconnect()
		end
		if model.Parent then
			model:ScaleTo(toScale)
		end
		value:Destroy()
	end)

	value.Parent = model
	tween:Play()
end

return {
	clamp = clamp,
	makePart = makePart,
	trackTween = trackTween,
	cancelTweens = cancelTweens,
	animateRoadPart = animateRoadPart,
	stopRoadPartReveal = stopRoadPartReveal,
	animateModelScale = animateModelScale,
}
