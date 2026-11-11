--[[
	SessionUtil.luau
	Petites fonctions partagées par les modules de Session (pièces, cartes
	arrondies, animations). Aucune dépendance sur l'état d'une partie.
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
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth

	local parent = nil
	for key, value in pairs(props) do
		if key == "Parent" then
			parent = value
		else
			p[key] = value
		end
	end
	if parent then
		p.Parent = parent
	end
	return p
end

-- Carte plate à coins arrondis, construite avec des primitives : deux
-- traverses qui se croisent et quatre petits disques aux coins. Cela donne
-- l'aspect « icône vectorielle » des maisons de la référence, sans mesh.
local CARD_CYLINDER_ROTATION = CFrame.Angles(0, 0, math.rad(90))

local function addRoundedCard(model, name, center, width, depth, height, y, color, options)
	options = options or {}
	local radius = math.min(width, depth) * (options.radius or 0.16)
	local position = center * CFrame.Angles(0, options.angle or 0, 0) * CFrame.new(0, y, 0)
	if options.offset then
		position = position * CFrame.new(options.offset.X, 0, options.offset.Z)
	end

	local transparency = options.transparency or 0
	local firstPart = nil
	local function add(props)
		props.Name = name
		props.Parent = model
		props.Color = color
		props.Transparency = transparency
		props.CastShadow = false
		local p = makePart(props)
		firstPart = firstPart or p
		return p
	end

	-- Les deux traverses se recouvrent au centre. On rend la verticale très
	-- légèrement plus haute pour éviter un clignotement de faces coplanaires.
	if width - radius * 2 > 0.02 then
		add({
			Size = Vector3.new(width - radius * 2, height, depth),
			CFrame = position,
		})
	end
	if depth - radius * 2 > 0.02 then
		add({
			Size = Vector3.new(width, height + 0.004, depth - radius * 2),
			CFrame = position,
		})
	end

	local xs = { 0 }
	local zs = { 0 }
	if width - radius * 2 > 0.02 then
		xs = { -(width * 0.5 - radius), width * 0.5 - radius }
	end
	if depth - radius * 2 > 0.02 then
		zs = { -(depth * 0.5 - radius), depth * 0.5 - radius }
	end
	for _, sx in ipairs(xs) do
		for _, sz in ipairs(zs) do
			add({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(height + 0.006, radius * 2, radius * 2),
				CFrame = position * CFrame.new(sx, 0, sz) * CARD_CYLINDER_ROTATION,
			})
		end
	end

	return firstPart
end

-- Petite apparition de la route : la pièce grandit et devient opaque.
-- Le délai permet de faire apparaître les cases l'une après l'autre quand
-- le joueur trace un trait continu.
local function animateRoadPart(part, finalSize, delay)
	local startSize = Vector3.new(
		math.max(0.04, finalSize.X * 0.52),
		math.max(0.04, finalSize.Y * 0.52),
		math.max(0.04, finalSize.Z * 0.52)
	)
	part.Size = startSize
	part.Transparency = 0.45

	TweenService:Create(part, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay), {
		Size = finalSize,
		Transparency = 0,
	}):Play()
end

-- Anime un Model entier autour de son WorldPivot. Sert à l'apparition d'un
-- magasin et à sa transformation petit carré -> grand cercle. On passe par
-- une NumberValue pour pouvoir tween une valeur puis appeler Model:ScaleTo.
local function animateModelScale(model, fromScale, toScale, duration)
	if not model or not model.ScaleTo then
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

	local tween = TweenService:Create(
		value,
		TweenInfo.new(duration or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = toScale }
	)
	tween.Completed:Connect(function()
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
	CARD_CYLINDER_ROTATION = CARD_CYLINDER_ROTATION,
	clamp = clamp,
	makePart = makePart,
	addRoundedCard = addRoundedCard,
	animateRoadPart = animateRoadPart,
	animateModelScale = animateModelScale,
}
