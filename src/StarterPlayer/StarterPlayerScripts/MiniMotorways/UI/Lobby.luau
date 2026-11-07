--[[
	Lobby.luau
	Menu principal + sélection de carte + options + records.
	Reproduit l'ambiance des captures : fond quadrillé clair, titre,
	boutons turquoise, cartes colorées avec aperçu circulaire.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Theme = require(script.Parent.Theme)
local MapPreview = require(script.Parent.MapPreview)

local Lobby = {}
Lobby.__index = Lobby

local CARD_WIDTH = 320
local CARD_HEIGHT = 470
local CARD_GAP = 24

local function addShadow(parent, radius)
	local shadow = Theme.new("Frame", {
		Parent = parent,
		Position = UDim2.fromOffset(7, 9),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.CardShadow,
		BorderSizePixel = 0,
		ZIndex = 1,
	})
	Theme.corner(shadow, radius or 12)
	return shadow
end

-- Point d'une spline de Catmull-Rom : sert à dessiner une route douce avec
-- des segments arrondis, sans image ni mesh.
local function catmullRomPoint(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return (p1 * 2
			+ (p2 - p0) * t
			+ (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
			+ (p1 * 3 - p0 - p2 * 3 + p3) * t3)
		* 0.5
end

local function samplePath(controls, stepsPerSegment)
	local points = {}
	for i = 1, #controls - 1 do
		local p0 = controls[math.max(1, i - 1)]
		local p1 = controls[i]
		local p2 = controls[i + 1]
		local p3 = controls[math.min(#controls, i + 2)]
		for step = 0, stepsPerSegment - 1 do
			table.insert(points, catmullRomPoint(p0, p1, p2, p3, step / stepsPerSegment))
		end
	end
	table.insert(points, controls[#controls])
	return points
end

function Lobby.new(callbacks)
	local self = setmetatable({}, Lobby)
	self.callbacks = callbacks or {}
	self.profile = {}
	self.cards = {}
	self.recordLabels = {}
	self.selectedId = (Maps.getById("los_angeles") or Maps.all()[1]).id
	self.lastClickId = nil
	self.lastClickAt = 0
	self.toastToken = 0
	self.modalScales = {}
	self:build()
	self:updateResponsive()
	self.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:updateResponsive()
	end)
	return self
end

function Lobby:build()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "MM_Lobby"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	self.gui = gui

	local background = Theme.new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.LobbyBackground,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 0,
	})
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromHex("F5F9F9"), Color3.fromHex("DDE8EA"))
	gradient.Parent = background

	-- La grille est construite à part pour garder des cases carrées, même
	-- sur un écran large, comme sur la capture de référence.
	self.lobbyGrid = Theme.new("Frame", {
		Name = "LobbyGrid",
		Parent = background,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 0,
	})

	local main = Theme.new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 1,
	})
	self.mainPage = main

	local mapPage = Theme.new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		Active = false,
		ZIndex = 2,
	})
	self.mapPage = mapPage

	self:buildDecoration(main)
	self:buildMain(main)
	self:buildMapPage(mapPage)
	self:buildOptions()
	self:buildRecords()
	self:buildGarage()
	self:buildStats()
	self:buildAbout()
	self:buildToast()
	self:select(self.selectedId)
end

function Lobby:buildDecoration(page)
	local decoration = Theme.new("Frame", {
		Parent = page,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 1,
	})
	self.decoration = decoration
	self.decorRoadSegments = {}
	self.decorCars = {}

	local function pill(frame)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = frame
		return corner
	end

	-- Tracés de la route : une grande courbe qui descend à droite, puis une
	-- branche qui rejoint la petite maison du bas. Les points sont normalisés
	-- et échantillonnés en spline pour obtenir des virages doux.
	local mainControls = {
		Vector2.new(0.735, -0.06),
		Vector2.new(0.735, 0.25),
		Vector2.new(0.735, 0.38),
		Vector2.new(0.760, 0.465),
		Vector2.new(0.795, 0.525),
		Vector2.new(0.805, 0.610),
		Vector2.new(0.803, 0.690),
		Vector2.new(0.780, 0.755),
		Vector2.new(0.720, 0.815),
		Vector2.new(0.650, 0.875),
		Vector2.new(0.570, 0.940),
		Vector2.new(0.470, 1.045),
	}
	local branchControls = {
		Vector2.new(0.797, 0.665),
		Vector2.new(0.790, 0.725),
		Vector2.new(0.760, 0.780),
		Vector2.new(0.720, 0.835),
		Vector2.new(0.700, 0.880),
		Vector2.new(0.700, 0.945),
	}
	local mainSamples = samplePath(mainControls, 7)
	local branchSamples = samplePath(branchControls, 8)
	self.decorCarRoutes = { mainSamples, branchSamples }

	local function addRoadPath(samples, factor)
		for i = 1, #samples - 1 do
			local a = samples[i]
			local b = samples[i + 1]
			local shadow = Theme.new("Frame", {
				Parent = decoration,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(0, 0),
				BackgroundColor3 = Theme.LobbyRoadShadow,
				BackgroundTransparency = 0.38,
				BorderSizePixel = 0,
				ZIndex = 1,
			})
			pill(shadow)
			table.insert(self.decorRoadSegments, {
				frame = shadow,
				a = a,
				b = b,
				factor = factor * 1.04,
				offset = Vector2.new(5, 7),
			})

			local road = Theme.new("Frame", {
				Parent = decoration,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(0, 0),
				BackgroundColor3 = Theme.LobbyRoad,
				BorderSizePixel = 0,
				ZIndex = 2,
			})
			pill(road)
			table.insert(self.decorRoadSegments, {
				frame = road,
				a = a,
				b = b,
				factor = factor,
				offset = Vector2.new(0, 0),
			})
		end
	end

	addRoadPath(mainSamples, 1)
	addRoadPath(branchSamples, 0.82)

	-- Grande destination orange avec épingle, comme sur la capture.
	local destination = Theme.new("Frame", {
		Parent = decoration,
		Position = UDim2.fromScale(0.790, 0.155),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(170, 170),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10,
	})
	self.decorDestination = destination

	Theme.corner(Theme.new("Frame", {
		Parent = destination,
		Position = UDim2.fromScale(0.10, 0.12),
		Size = UDim2.fromScale(0.84, 0.84),
		BackgroundColor3 = Theme.CardShadow,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 11,
	}), 22)

	local destinationOutline = Theme.new("Frame", {
		Parent = destination,
		Position = UDim2.fromScale(0.04, 0.02),
		Size = UDim2.fromScale(0.88, 0.88),
		BackgroundColor3 = Theme.LobbyRoad,
		BorderSizePixel = 0,
		ZIndex = 12,
	})
	Theme.corner(destinationOutline, 22)

	local destinationDark = Theme.new("Frame", {
		Parent = destination,
		Position = UDim2.fromScale(0.10, 0.10),
		Size = UDim2.fromScale(0.76, 0.76),
		BackgroundColor3 = Color3.fromHex("C56F42"),
		BorderSizePixel = 0,
		ZIndex = 13,
	})
	Theme.corner(destinationDark, 14)

	local destinationOrange = Theme.new("Frame", {
		Parent = destination,
		Position = UDim2.fromScale(0.10, 0.06),
		Size = UDim2.fromScale(0.76, 0.76),
		BackgroundColor3 = Color3.fromHex("F3B65D"),
		BorderSizePixel = 0,
		ZIndex = 14,
	})
	Theme.corner(destinationOrange, 14)

	-- Épingle blanche : cercle, pointe en losange et petit trou sombre.
	Theme.circle(destination, 42, Theme.CardShadow, {
		Position = UDim2.fromScale(0.5, 0.43),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 13,
	})
	local pinDarkTail = Theme.new("Frame", {
		Parent = destination,
		Position = UDim2.fromScale(0.5, 0.54),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(36, 36),
		Rotation = 45,
		BackgroundColor3 = Theme.Ink,
		BorderSizePixel = 0,
		ZIndex = 14,
	})
	Theme.corner(pinDarkTail, 5)
	local pinTail = Theme.new("Frame", {
		Parent = destination,
		Position = UDim2.fromScale(0.5, 0.532),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(28, 28),
		Rotation = 45,
		BackgroundColor3 = Theme.LobbyRoad,
		BorderSizePixel = 0,
		ZIndex = 15,
	})
	Theme.corner(pinTail, 4)
	Theme.circle(destination, 38, Theme.Ink, {
		Position = UDim2.fromScale(0.5, 0.43),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 16,
	})
	Theme.circle(destination, 31, Theme.LobbyRoad, {
		Position = UDim2.fromScale(0.5, 0.43),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 17,
	})
	Theme.circle(destination, 12, Theme.Ink, {
		Position = UDim2.fromScale(0.5, 0.43),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 18,
	})

	-- Petite maison corail/jaune au bout de la branche.
	local house = Theme.new("Frame", {
		Parent = decoration,
		Position = UDim2.fromScale(0.700, 0.885),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(96, 96),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10,
	})
	self.decorHouse = house

	Theme.corner(Theme.new("Frame", {
		Parent = house,
		Position = UDim2.fromScale(0.10, 0.12),
		Size = UDim2.fromScale(0.84, 0.84),
		BackgroundColor3 = Theme.CardShadow,
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		ZIndex = 11,
	}), 12)

	local houseOutline = Theme.new("Frame", {
		Parent = house,
		Position = UDim2.fromScale(0.04, 0.02),
		Size = UDim2.fromScale(0.88, 0.88),
		BackgroundColor3 = Theme.LobbyRoad,
		BorderSizePixel = 0,
		ZIndex = 12,
	})
	Theme.corner(houseOutline, 12)

	local houseBase = Theme.new("Frame", {
		Parent = house,
		Position = UDim2.fromScale(0.09, 0.09),
		Size = UDim2.fromScale(0.78, 0.78),
		BackgroundColor3 = Color3.fromHex("E7825F"),
		BorderSizePixel = 0,
		ZIndex = 13,
	})
	Theme.corner(houseBase, 8)

	local houseRoofDark = Theme.new("Frame", {
		Parent = house,
		Position = UDim2.fromScale(0.08, 0.06),
		Size = UDim2.fromScale(0.76, 0.62),
		BackgroundColor3 = Color3.fromHex("C56F42"),
		BorderSizePixel = 0,
		ZIndex = 13,
	})
	Theme.corner(houseRoofDark, 8)

	local houseRoof = Theme.new("Frame", {
		Parent = house,
		Position = UDim2.fromScale(0.11, 0.03),
		Size = UDim2.fromScale(0.70, 0.58),
		BackgroundColor3 = Color3.fromHex("F4C25C"),
		BorderSizePixel = 0,
		ZIndex = 14,
	})
	Theme.corner(houseRoof, 7)

	for i = -1, 1 do
		local chimney = Theme.new("Frame", {
			Parent = house,
			Position = UDim2.fromScale(0.5 + i * 0.19, 0.065),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(10, 11),
			BackgroundColor3 = Color3.fromHex("F4C25C"),
			BorderSizePixel = 0,
			ZIndex = 15,
		})
		Theme.corner(chimney, 2)
	end

	-- Deux voitures : une sur le grand trajet, une sur la branche. Elles
	-- suivent réellement la courbe et sont orientées dans le sens du trajet.
	local carSettings = {
		{ path = 1, offset = 0.10, speed = 0.072, hiddenEnds = false, color = Color3.fromHex("F4B95F") },
		{ path = 2, offset = 0.12, speed = 0.115, hiddenEnds = true, color = Color3.fromHex("F8D27A") },
	}
	for _, setting in ipairs(carSettings) do
		local shadow = Theme.new("Frame", {
			Parent = decoration,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = Theme.CardShadow,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 3,
		})
		pill(shadow)

		local body = Theme.new("Frame", {
			Parent = decoration,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = setting.color,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 4,
		})
		pill(body)
		Theme.stroke(body, Theme.LobbyRoad, 1.2, 0.08)

		local cabin = Theme.new("Frame", {
			Parent = body,
			Position = UDim2.fromScale(0.64, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0.32, 0.62),
			BackgroundColor3 = Theme.LobbyRoad,
			BorderSizePixel = 0,
			ZIndex = 1,
		})
		Theme.corner(cabin, 3)

		table.insert(self.decorCars, {
			body = body,
			shadow = shadow,
			cabin = cabin,
			path = setting.path,
			offset = setting.offset,
			speed = setting.speed,
			hiddenEnds = setting.hiddenEnds,
		})
	end

	decoration:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:updateDecorationLayout()
	end)
	task.defer(function()
		self:updateDecorationLayout()
	end)

	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		if not self.gui.Enabled or not self.mainPage.Visible or not self.decoration.Visible then
			return
		end
		elapsed += dt
		self:updateDecorationCars(elapsed)
	end)
end

function Lobby:updateDecorationLayout()
	local decoration = self.decoration
	if not decoration then
		return
	end
	local size = decoration.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		return
	end

	local roadThickness = math.clamp(size.X * 0.030, 18, 64)
	for _, segment in ipairs(self.decorRoadSegments or {}) do
		local ax = segment.a.X * size.X
		local ay = segment.a.Y * size.Y
		local bx = segment.b.X * size.X
		local by = segment.b.Y * size.Y
		local dx = bx - ax
		local dy = by - ay
		local length = math.sqrt(dx * dx + dy * dy)
		if length > 0.1 then
			segment.frame.Position = UDim2.fromOffset(
				(ax + bx) * 0.5 + segment.offset.X,
				(ay + by) * 0.5 + segment.offset.Y
			)
			segment.frame.Size = UDim2.fromOffset(
				length + roadThickness * 1.15,
				roadThickness * segment.factor
			)
			segment.frame.Rotation = math.deg(math.atan2(dy, dx))
			segment.frame.Visible = true
		else
			segment.frame.Visible = false
		end
	end
end

function Lobby:updateDecorationCars(elapsed)
	local decoration = self.decoration
	local routes = self.decorCarRoutes
	local cars = self.decorCars
	if not decoration or not routes or not cars then
		return
	end

	local width = decoration.AbsoluteSize.X
	local height = decoration.AbsoluteSize.Y
	if width < 2 or height < 2 then
		return
	end

	local carThickness = math.clamp(width * 0.0105, 7, 13)
	local carLength = carThickness * 2.05

	for _, car in ipairs(cars) do
		local points = routes[car.path]
		if points and #points > 1 then
			local lengths = {}
			local total = 0
			for i = 1, #points - 1 do
				local a = points[i]
				local b = points[i + 1]
				local dx = (b.X - a.X) * width
				local dy = (b.Y - a.Y) * height
				local length = math.sqrt(dx * dx + dy * dy)
				lengths[i] = length
				total += length
			end

			if total > 0 then
				local progress = (elapsed * car.speed + car.offset) % 1
				local distance = progress * total
				local x = points[#points].X
				local y = points[#points].Y
				local angle = 0

				for i = 1, #lengths do
					if distance <= lengths[i] then
						local a = points[i]
						local b = points[i + 1]
						local fraction = distance / lengths[i]
						x = a.X + (b.X - a.X) * fraction
						y = a.Y + (b.Y - a.Y) * fraction
						angle = math.deg(math.atan2((b.Y - a.Y) * height, (b.X - a.X) * width))
						break
					end
					distance -= lengths[i]
				end

				local px = x * width
				local py = y * height
				local visible = not (car.hiddenEnds and (progress < 0.045 or progress > 0.93))
				car.body.Position = UDim2.fromOffset(px, py)
				car.body.Size = UDim2.fromOffset(carLength, carThickness)
				car.body.Rotation = angle
				car.body.Visible = visible
				car.shadow.Position = UDim2.fromOffset(px + 3, py + 4)
				car.shadow.Size = UDim2.fromOffset(carLength, carThickness)
				car.shadow.Rotation = angle
				car.shadow.Visible = visible
			end
		end
	end
end

function Lobby:buildMain(page)
	local titleHolder = Theme.new("Frame", {
		Parent = page,
		Position = UDim2.fromScale(0.21, 0.165),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
	})
	self.titleHolder = titleHolder

	local titleScale = Instance.new("UIScale")
	titleScale.Parent = titleHolder
	self.titleScale = titleScale

	local titleSize = 92
	Theme.label(titleHolder, Config.GameName, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Font = Theme.FontBlack,
		TextSize = titleSize,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})

	local bounds = TextService:GetTextSize(
		Config.GameName,
		titleSize,
		Theme.FontBlack,
		Vector2.new(3000, 300)
	)
	for index = 1, 3 do
		Theme.circle(titleHolder, 24, Theme.LobbyOrange, {
			Position = UDim2.fromOffset(bounds.X + 22 + (index - 1) * 34, 52),
			ZIndex = 4,
		})
	end

	local buttons = Theme.new("Frame", {
		Parent = page,
		Position = UDim2.fromScale(0.21, 0.43),
		Size = UDim2.fromScale(0.19, 0.30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 3,
	})
	self.menuButtons = buttons
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Parent = buttons

	Theme.button(buttons, "Jouer", {
		Size = UDim2.new(0.72, 0, 0.28, 0),
		LayoutOrder = 1,
		BackgroundColor3 = Theme.LobbyButton,
		TextColor3 = Theme.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 30,
		CornerRadius = 0,
	}, function()
		if self.callbacks.onPlay then
			self.callbacks.onPlay()
		end
	end)

	Theme.button(buttons, "Options", {
		Size = UDim2.new(0.92, 0, 0.28, 0),
		LayoutOrder = 2,
		BackgroundColor3 = Theme.LobbyButton,
		TextColor3 = Theme.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 30,
		CornerRadius = 0,
	}, function()
		self.optionsOverlay.Visible = true
	end)

	Theme.button(buttons, "Sortir", {
		Size = UDim2.new(0.68, 0, 0.28, 0),
		LayoutOrder = 3,
		BackgroundColor3 = Theme.LobbyButton,
		TextColor3 = Theme.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 30,
		CornerRadius = 0,
	}, function()
		if self.callbacks.onQuit then
			self.callbacks.onQuit()
		end
	end)

	for _, button in ipairs(buttons:GetChildren()) do
		if button:IsA("TextButton") then
			Theme.padding(button, 0, 8, 0, 22)
		end
	end

	-- Bouton info circulaire, avec une petite icône de document en blanc.
	local infoButton = Theme.button(page, "", {
		Position = UDim2.fromScale(0.955, 0.925),
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(74, 74),
		BackgroundColor3 = Theme.LobbyButton,
		TextSize = 1,
		CornerRadius = 37,
		ZIndex = 10,
	}, function()
		self.aboutOverlay.Visible = true
	end)
	self.infoButton = infoButton

	local document = Theme.new("Frame", {
		Parent = infoButton,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(30, 36),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 11,
	})
	Theme.corner(document, 4)
	for index = 1, 3 do
		Theme.new("Frame", {
			Parent = document,
			Position = UDim2.fromScale(0.5, 0.16 + (index - 1) * 0.18),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(17, 3),
			BackgroundColor3 = Theme.LobbyButton,
			BorderSizePixel = 0,
			ZIndex = 12,
		})
	end

	self.infoDot = Theme.circle(page, 16, Theme.LobbyOrange, {
		Position = UDim2.fromScale(0.912, 0.855),
		ZIndex = 11,
	})
end

function Lobby:buildMapPage(page)
	self.mapTitle = Theme.label(page, "Choisissez une ville", {
		Position = UDim2.fromScale(0.5, 0.040),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.5, 0.06),
		Font = Theme.FontBlack,
		TextSize = 38,
		TextColor3 = Theme.Ink,
		ZIndex = 3,
	})
	Theme.textScaled(self.mapTitle, 38, 16)

	self.mapSubtitle = Theme.label(page, "Six villes à explorer  ·  choisissez votre prochaine destination", {
		Position = UDim2.fromScale(0.5, 0.103),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.62, 0.028),
		TextSize = 15,
		TextColor3 = Theme.InkSoft,
		ZIndex = 3,
	})
	Theme.textScaled(self.mapSubtitle, 15, 8)

	self.backButton = Theme.button(page, "‹  Retour", {
		Position = UDim2.fromScale(0.03, 0.048),
		Size = UDim2.fromOffset(118, 42),
		BackgroundColor3 = Theme.Panel,
		TextColor3 = Theme.Ink,
		TextSize = 16,
		CornerRadius = 8,
		ZIndex = 4,
	}, function()
		self:showMain()
	end)
	Theme.stroke(self.backButton, Theme.LobbyGrid, 1, 0.1)

	local scroller = Theme.new("ScrollingFrame", {
		Parent = page,
		Position = UDim2.fromScale(0.09, 0.145),
		Size = UDim2.fromScale(0.86, 0.665),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.LobbyButton,
		ClipsDescendants = true,
		ZIndex = 5,
	})
	self.scroller = scroller

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroller

	local maps = Maps.all()
	for index, map in ipairs(maps) do
		self:buildCard(scroller, map, index)
	end

	local function updateCanvas()
		local contentWidth = #maps * (CARD_WIDTH + CARD_GAP) + CARD_GAP
		local viewportWidth = scroller.AbsoluteSize.X
		local contentHeight = math.max(CARD_HEIGHT + 18, scroller.AbsoluteSize.Y)
		scroller.CanvasSize = UDim2.fromOffset(math.max(contentWidth, viewportWidth), contentHeight)
		layout.HorizontalAlignment = contentWidth <= viewportWidth
				and Enum.HorizontalAlignment.Center
			or Enum.HorizontalAlignment.Left
	end
	updateCanvas()
	scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvas)

	-- Rail d'icônes à gauche, pour retrouver garage, records et statistiques.
	local rail = Theme.new("Frame", {
		Parent = page,
		Position = UDim2.fromScale(0.024, 0.34),
		Size = UDim2.fromOffset(58, 300),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 20,
	})
	self.rail = rail
	local railLayout = Instance.new("UIListLayout")
	railLayout.FillDirection = Enum.FillDirection.Vertical
	railLayout.Padding = UDim.new(0, 10)
	railLayout.SortOrder = Enum.SortOrder.LayoutOrder
	railLayout.Parent = rail

	local railItems = {
		{ symbol = "◉", active = true, action = function() end },
		{ symbol = "▤", active = false, action = function()
			self:showGarage()
		end },
		{ symbol = "★", active = false, action = function()
			self:showRecords()
		end },
		{ symbol = "▥", active = false, action = function()
			self:showStats()
		end },
	}
	for index, item in ipairs(railItems) do
		local button = Theme.button(rail, item.symbol, {
			Size = UDim2.fromOffset(56, 56),
			LayoutOrder = index,
			BackgroundColor3 = item.active and Theme.LobbyButton or Theme.Panel,
			TextSize = 24,
			CornerRadius = 8,
			ZIndex = 21,
		}, item.action)
		button.TextColor3 = item.active and Theme.White or Theme.InkSoft
		if not item.active then
			Theme.stroke(button, Theme.LobbyGrid, 1, 0.1)
		end
	end

	self.playButton = Theme.button(page, "Jouer  ·  " .. maps[1].name, {
		Position = UDim2.fromScale(0.5, 0.855),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0.8, 0, 0, 64),
		BackgroundColor3 = Theme.LobbyButton,
		TextColor3 = Theme.White,
		TextSize = 24,
		CornerRadius = 0,
		ZIndex = 20,
	}, function()
		self:startSelected()
	end)
	Theme.maxSize(self.playButton, 340, 64)

	self.mapHint = Theme.label(page, "Cliquez sur une ville pour la sélectionner  ·  double-cliquez pour jouer", {
		Position = UDim2.fromScale(0.5, 0.952),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0.8, 0, 0, 20),
		TextSize = 13,
		TextColor3 = Theme.InkSoft,
		ZIndex = 20,
	})
	Theme.textScaled(self.mapHint, 13, 8)
	Theme.maxSize(self.mapHint, 560, 22)
end

function Lobby:buildCard(parent, map, order)
	local holder = Theme.new("Frame", {
		Parent = parent,
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = order,
		ZIndex = 2,
	})

	local shadow = addShadow(holder, 14)
	shadow.BackgroundColor3 = Theme.CardShadow
	shadow.BackgroundTransparency = 0.05

	local card = Theme.new("Frame", {
		Parent = holder,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2,
	})
	Theme.corner(card, 12)

	local header = Theme.new("Frame", {
		Parent = card,
		Size = UDim2.new(1, 0, 0.45, 0),
		BackgroundColor3 = map.header,
		BorderSizePixel = 0,
		ZIndex = 2,
	})
	local headerGradient = Instance.new("UIGradient")
	headerGradient.Rotation = 90
	headerGradient.Color = ColorSequence.new(map.header:Lerp(Theme.White, 0.16), map.header)
	headerGradient.Parent = header

	MapPreview.create(header, map, 178, UDim2.fromScale(0.5, 0.035), Vector2.new(0.5, 0))

	local modeBadge = Theme.label(card, string.upper(map.mode), {
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(96, 22),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.12,
		TextSize = 11,
		Font = Theme.FontBold,
		TextColor3 = map.header:Lerp(Theme.Ink, 0.55),
		ZIndex = 12,
	})
	Theme.corner(modeBadge, 11)

	Theme.label(card, map.name, {
		Position = UDim2.fromScale(0.5, 0.475),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0.9, 0, 0.07, 0),
		Font = Theme.FontBlack,
		TextSize = 24,
		TextColor3 = Theme.Ink,
		ZIndex = 4,
	})

	local bestLabel = Theme.label(card, "Meilleur : —", {
		Position = UDim2.fromScale(0.5, 0.548),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0.9, 0, 0.04, 0),
		TextSize = 15,
		TextColor3 = Theme.InkSoft,
		ZIndex = 4,
	})

	Theme.new("Frame", {
		Parent = card,
		Position = UDim2.fromScale(0.1, 0.605),
		Size = UDim2.new(0.8, 0, 0, 2),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		ZIndex = 4,
	})

	Theme.label(card, map.description, {
		Position = UDim2.fromScale(0.1, 0.635),
		Size = UDim2.new(0.8, 0, 0.24, 0),
		TextSize = 14,
		TextColor3 = Theme.InkSoft,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})

	local selectedBadge = Theme.label(card, "SÉLECTIONNÉE", {
		Position = UDim2.fromScale(0.5, 0.905),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(146, 26),
		BackgroundColor3 = Theme.LobbyOrange,
		BackgroundTransparency = 0,
		TextSize = 11,
		Font = Theme.FontBold,
		TextColor3 = Theme.Ink,
		Visible = false,
		ZIndex = 4,
	})
	Theme.corner(selectedBadge, 13)

	local stroke = Theme.stroke(card, Theme.Ink, 3, 1)

	local hit = Theme.new("TextButton", {
		Parent = card,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Active = true,
		Selectable = true,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		ZIndex = 20,
	})
	local lastHit = 0
	local function activateCard()
		local now = os.clock()
		if now - lastHit < 0.12 then
			return
		end
		lastHit = now
		if self.selectedId == map.id
			and self.lastClickId == map.id
			and now - self.lastClickAt < 0.45
		then
			self:startSelected()
		else
			self:select(map.id)
			self.lastClickId = map.id
			self.lastClickAt = now
		end
	end
	hit.Activated:Connect(activateCard)
	hit.MouseButton1Click:Connect(activateCard)

	self.cards[map.id] = {
		holder = holder,
		card = card,
		header = header,
		stroke = stroke,
		shadow = shadow,
		bestLabel = bestLabel,
		selectedBadge = selectedBadge,
		map = map,
	}
end

function Lobby:buildOptions()
	local overlay, card = self:makeModal("Options", 500, 430)
	self.optionsOverlay = overlay

	Theme.label(card, "Commandes", {
		Position = UDim2.fromOffset(30, 78),
		Size = UDim2.fromOffset(440, 30),
		TextSize = 17,
		Font = Theme.FontBold,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 52,
	})

	Theme.label(
		card,
		"Glissez avec la souris (ou le doigt) pour tracer une route.\n"
			.. "Clic droit pour effacer.  ·  Touches 1 / 2 : route / gomme.\n"
			.. "P : pause.  ·  Chaque semaine, choisissez une amélioration.\n\n"
			.. "Les voitures livrent aux bâtiments de la même couleur.\n"
			.. "Si la jauge de trafic atteint zéro, la partie se termine.",
		{
			Position = UDim2.fromOffset(30, 112),
			Size = UDim2.fromOffset(440, 150),
			TextSize = 14,
			TextColor3 = Theme.InkSoft,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 52,
		}
	)

	local reset
	reset = Theme.button(card, "Réinitialiser mes records", {
		Position = UDim2.fromOffset(30, 285),
		Size = UDim2.fromOffset(440, 50),
		BackgroundColor3 = Theme.PanelSoft,
		TextColor3 = Theme.Danger,
		TextSize = 17,
		CornerRadius = 4,
		ZIndex = 52,
	}, function()
		if reset.Text == "Confirmer ?" then
			reset.Text = "Réinitialiser mes records"
			reset.BackgroundColor3 = Theme.PanelSoft
			reset.TextColor3 = Theme.Danger
			reset:SetAttribute("BaseColor", Theme.PanelSoft)
			if self.callbacks.onResetRecords then
				self.callbacks.onResetRecords()
			end
		else
			reset.Text = "Confirmer ?"
			reset.BackgroundColor3 = Theme.Danger
			reset.TextColor3 = Theme.White
			reset:SetAttribute("BaseColor", Theme.Danger)
			task.delay(3, function()
				if reset.Parent then
					reset.Text = "Réinitialiser mes records"
					reset.BackgroundColor3 = Theme.PanelSoft
					reset.TextColor3 = Theme.Danger
					reset:SetAttribute("BaseColor", Theme.PanelSoft)
				end
			end)
		end
	end)
	Theme.stroke(reset, Theme.Danger, 2, 0.4)

	Theme.button(card, "Fermer", {
		Position = UDim2.fromOffset(30, 350),
		Size = UDim2.fromOffset(440, 50),
		BackgroundColor3 = Theme.Teal,
		TextColor3 = Theme.White,
		TextSize = 18,
		CornerRadius = 4,
		ZIndex = 52,
	}, function()
		overlay.Visible = false
	end)
end

function Lobby:buildRecords()
	local overlay, card = self:makeModal("Palmarès", 470, 500)
	self.recordsOverlay = overlay

	local maps = Maps.all()
	for index, map in ipairs(maps) do
		local y = 82 + (index - 1) * 54
		Theme.circle(card, 14, map.header, {
			Position = UDim2.fromOffset(30, y + 10),
			ZIndex = 52,
		})
		Theme.label(card, map.name, {
			Position = UDim2.fromOffset(56, y),
			Size = UDim2.fromOffset(220, 34),
			TextSize = 17,
			TextColor3 = Theme.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 52,
		})
		local best = Theme.label(card, "—", {
			Position = UDim2.fromOffset(280, y),
			Size = UDim2.fromOffset(160, 34),
			TextSize = 17,
			Font = Theme.FontBold,
			TextColor3 = Theme.Ink,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 52,
		})
		self.recordLabels[map.id] = best

		Theme.new("Frame", {
			Parent = card,
			Position = UDim2.fromOffset(30, y + 42),
			Size = UDim2.fromOffset(410, 1),
			BackgroundColor3 = Theme.Border,
			BorderSizePixel = 0,
			ZIndex = 52,
		})
	end

	Theme.button(card, "Fermer", {
		Position = UDim2.fromOffset(30, 430),
		Size = UDim2.fromOffset(410, 48),
		BackgroundColor3 = Theme.Teal,
		TextColor3 = Theme.White,
		TextSize = 18,
		CornerRadius = 4,
		ZIndex = 52,
	}, function()
		overlay.Visible = false
	end)
end

function Lobby:buildGarage()
	local overlay, card = self:makeModal("Garage", 520, 430)
	self.garageOverlay = overlay

	Theme.label(card, "Votre collection de voitures", {
		Position = UDim2.fromOffset(30, 82),
		Size = UDim2.fromOffset(460, 26),
		TextSize = 16,
		Font = Theme.FontBold,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 52,
	})

	local colors = Config.HouseColors
	for index = 1, #colors do
		local col = (index - 1) % 4
		local row = math.floor((index - 1) / 4)
		local x = 38 + col * 115
		local y = 128 + row * 96
		local slot = Theme.new("Frame", {
			Parent = card,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(96, 76),
			BackgroundColor3 = Theme.PanelSoft,
			BorderSizePixel = 0,
			ZIndex = 52,
		})
		Theme.corner(slot, 8)
		local body = Theme.new("Frame", {
			Parent = slot,
			Position = UDim2.fromScale(0.5, 0.42),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(42, 24),
			BackgroundColor3 = colors[index].color,
			BorderSizePixel = 0,
			ZIndex = 53,
		})
		Theme.corner(body, 5)
		Theme.new("Frame", {
			Parent = body,
			Position = UDim2.fromScale(0.5, 0.36),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0.62, 0.42),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 54,
		})
		Theme.label(slot, colors[index].name, {
			Position = UDim2.fromScale(0, 0.78),
			Size = UDim2.fromScale(1, 0.18),
			TextSize = 10,
			Font = Theme.FontBold,
			TextColor3 = Theme.InkSoft,
			ZIndex = 53,
		})
	end

	Theme.button(card, "Fermer", {
		Position = UDim2.fromOffset(30, 360),
		Size = UDim2.fromOffset(460, 48),
		BackgroundColor3 = Theme.Teal,
		TextColor3 = Theme.White,
		TextSize = 18,
		CornerRadius = 4,
		ZIndex = 52,
	}, function()
		overlay.Visible = false
	end)
end

function Lobby:buildStats()
	local overlay, card = self:makeModal("Statistiques", 500, 430)
	self.statsOverlay = overlay

	local stats = {
		{ label = "Meilleur score total", value = "0" },
		{ label = "Villes jouées", value = "0" },
		{ label = "Meilleure ville", value = "—" },
		{ label = "Moyenne des records", value = "—" },
	}
	self.statsLabels = {}
	for index, stat in ipairs(stats) do
		local y = 88 + (index - 1) * 64
		Theme.label(card, stat.label, {
			Position = UDim2.fromOffset(30, y),
			Size = UDim2.fromOffset(250, 26),
			TextSize = 15,
			TextColor3 = Theme.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 52,
		})
		self.statsLabels[index] = Theme.label(card, stat.value, {
			Position = UDim2.fromOffset(280, y - 4),
			Size = UDim2.fromOffset(190, 34),
			TextSize = 22,
			Font = Theme.FontBlack,
			TextColor3 = Theme.Ink,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 52,
		})
		Theme.new("Frame", {
			Parent = card,
			Position = UDim2.fromOffset(30, y + 38),
			Size = UDim2.fromOffset(440, 1),
			BackgroundColor3 = Theme.Border,
			BorderSizePixel = 0,
			ZIndex = 52,
		})
	end

	Theme.button(card, "Fermer", {
		Position = UDim2.fromOffset(30, 360),
		Size = UDim2.fromOffset(440, 48),
		BackgroundColor3 = Theme.Teal,
		TextColor3 = Theme.White,
		TextSize = 18,
		CornerRadius = 4,
		ZIndex = 52,
	}, function()
		overlay.Visible = false
	end)
end

function Lobby:buildAbout()
	local overlay, card = self:makeModal("À propos", 520, 380)
	self.aboutOverlay = overlay

	Theme.label(
		card,
		Config.GameName .. " — prototype Roblox\n\n"
			.. "Inspiré du jeu de gestion de trafic Mini Motorways.\n"
			.. "Tous les visuels (villes, routes, voitures, interface)\n"
			.. "sont générés en code dans Roblox Studio : aucune image importée.\n\n"
			.. "Tracez des routes entre les maisons et les bâtiments de la même couleur.\n"
			.. "Livrez le plus de trajets possible, semaine après semaine, sans\n"
			.. "laisser le trafic s'effondrer.",
		{
			Position = UDim2.fromOffset(30, 82),
			Size = UDim2.fromOffset(460, 210),
			TextSize = 15,
			TextColor3 = Theme.InkSoft,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 52,
		}
	)

	Theme.button(card, "Fermer", {
		Position = UDim2.fromOffset(30, 310),
		Size = UDim2.fromOffset(460, 48),
		BackgroundColor3 = Theme.Teal,
		TextColor3 = Theme.White,
		TextSize = 18,
		CornerRadius = 4,
		ZIndex = 52,
	}, function()
		overlay.Visible = false
	end)
end

function Lobby:buildToast()
	self.toastLabel = Theme.label(self.gui, "", {
		Position = UDim2.fromScale(0.5, 0.025),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0.8, 0, 0, 38),
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.08,
		TextSize = 14,
		TextColor3 = Theme.White,
		Visible = false,
		ZIndex = 60,
	})
	Theme.corner(self.toastLabel, 19)
	Theme.textScaled(self.toastLabel, 14, 8)
	Theme.maxSize(self.toastLabel, 420, 38)
end

function Lobby:makeModal(titleText, width, height)
	local overlay = Theme.new("Frame", {
		Parent = self.gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
		ZIndex = 50,
	})

	local card = Theme.new("Frame", {
		Parent = overlay,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ZIndex = 51,
	})
	Theme.corner(card, 10)
	Theme.stroke(card, Theme.Border, 2, 0.1)

	local scale = Instance.new("UIScale")
	scale.Parent = card
	table.insert(self.modalScales, { scale = scale, width = width, height = height })

	local title = Theme.label(card, titleText, {
		Position = UDim2.fromOffset(30, 22),
		Size = UDim2.new(1, -60, 0, 42),
		Font = Theme.FontBlack,
		TextSize = 30,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 52,
	})
	Theme.textScaled(title, 30, 14)

	return overlay, card
end

function Lobby:refreshLobbyGrid(width, height)
	local grid = self.lobbyGrid
	if not grid then
		return
	end
	local key = tostring(math.floor(width)) .. ":" .. tostring(math.floor(height))
	if self.lobbyGridKey == key then
		return
	end
	self.lobbyGridKey = key
	grid:ClearAllChildren()

	-- Cases carrées : la grille reste identique à la capture, même quand
	-- la fenêtre change de proportions.
	local step = math.max(90, width / 10)
	for x = step, width, step do
		Theme.new("Frame", {
			Parent = grid,
			Position = UDim2.fromOffset(math.floor(x), 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = Theme.LobbyGrid,
			BackgroundTransparency = 0.58,
			BorderSizePixel = 0,
			ZIndex = 0,
		})
	end
	for y = step, height, step do
		Theme.new("Frame", {
			Parent = grid,
			Position = UDim2.fromOffset(0, math.floor(y)),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.LobbyGrid,
			BackgroundTransparency = 0.58,
			BorderSizePixel = 0,
			ZIndex = 0,
		})
	end
end

function Lobby:updateResponsive()
	local viewport = self.gui.AbsoluteSize
	local width = viewport.X
	local height = viewport.Y
	if width < 2 or height < 2 then
		return
	end

	local portrait = width < 760 or width < height * 0.9
	local short = height < 700

	self:refreshLobbyGrid(width, height)

	if self.decoration then
		self.decoration.Visible = not portrait
		if not portrait then
			self:updateDecorationLayout()
		end
	end
	if self.rail then
		self.rail.Visible = not portrait
	end
	if self.titleHolder then
		self.titleHolder.Position = UDim2.fromScale(
			portrait and 0.08 or 0.21,
			portrait and 0.115 or 0.165
		)
	end
	if self.titleScale then
		local base = portrait and width / 720 or width / 1600
		self.titleScale.Scale = math.clamp(base, 0.42, 1)
	end

	if self.menuButtons then
		self.menuButtons.Position = UDim2.fromScale(
			portrait and 0.08 or 0.21,
			portrait and 0.36 or 0.43
		)
		self.menuButtons.Size = UDim2.fromScale(
			portrait and 0.84 or 0.19,
			portrait and (short and 0.34 or 0.32) or 0.30
		)
	end

	if self.decorDestination then
		local size = math.clamp(height * 0.16, 100, 190)
		self.decorDestination.Size = UDim2.fromOffset(size, size)
	end
	if self.decorHouse then
		local size = math.clamp(height * 0.095, 66, 112)
		self.decorHouse.Size = UDim2.fromOffset(size, size)
	end

	if self.infoButton then
		local size = portrait and 60 or math.clamp(height * 0.068, 52, 74)
		local x = portrait and 0.94 or 0.955
		local y = portrait and 0.94 or 0.925
		self.infoButton.Size = UDim2.fromOffset(size, size)
		self.infoButton.Position = UDim2.fromScale(x, y)
		if self.infoDot then
			self.infoDot.Position = UDim2.fromOffset(
				x * width - size - 8,
				y * height - size - 6
			)
		end
	end

	if self.mapTitle then
		self.mapTitle.Position = UDim2.fromScale(
			0.5,
			portrait and 0.090 or 0.040
		)
		self.mapTitle.Size = UDim2.fromScale(portrait and 0.72 or 0.5, 0.06)
	end
	if self.mapSubtitle then
		self.mapSubtitle.Position = UDim2.fromScale(0.5, portrait and 0.150 or 0.103)
		self.mapSubtitle.Size = UDim2.fromScale(portrait and 0.8 or 0.62, 0.028)
	end

	if self.backButton then
		self.backButton.Position = UDim2.fromScale(0.03, portrait and 0.028 or 0.048)
		self.backButton.Size = UDim2.fromOffset(
			portrait and math.min(96, width * 0.28) or 118,
			portrait and 34 or 42
		)
	end

	if self.scroller then
		self.scroller.Position = UDim2.fromScale(portrait and 0.06 or 0.09, portrait and 0.190 or 0.145)
		self.scroller.Size = UDim2.fromScale(
			portrait and 0.90 or 0.86,
			portrait and (short and 0.56 or 0.60) or 0.665
		)
	end

	if self.playButton then
		self.playButton.Position = UDim2.fromScale(
			0.5,
			short and 0.79 or (portrait and 0.83 or 0.855)
		)
	end

	if self.mapHint then
		self.mapHint.Visible = not short
	end

	for _, entry in ipairs(self.modalScales) do
		local fit = math.min(1, (width * 0.92) / entry.width, (height * 0.9) / entry.height)
		entry.scale.Scale = math.max(0.35, fit)
	end
end

function Lobby:select(mapId)
	if not mapId or not self.cards[mapId] then
		return
	end
	self.selectedId = mapId

	for id, card in pairs(self.cards) do
		local selected = id == mapId
		card.stroke.Transparency = selected and 0 or 1
		card.shadow.BackgroundColor3 = Theme.CardShadow
		card.shadow.BackgroundTransparency = selected and 0.02 or 0.08
		if card.selectedBadge then
			card.selectedBadge.Visible = selected
		end
	end

	local map = Maps.getById(mapId)
	if map and self.playButton then
		self.playButton.Text = "Jouer  ·  " .. map.name
	end
end

function Lobby:startSelected()
	if self.callbacks.onStartMap then
		self.callbacks.onStartMap(self.selectedId)
	end
end

function Lobby:show()
	self.gui.Enabled = true
	self.mainPage.Visible = true
	self.mapPage.Visible = false
	self.optionsOverlay.Visible = false
	self.recordsOverlay.Visible = false
	self.garageOverlay.Visible = false
	self.statsOverlay.Visible = false
	self.aboutOverlay.Visible = false
	self:updateResponsive()
end

function Lobby:hide()
	self.gui.Enabled = false
end

function Lobby:showMaps()
	self.mainPage.Visible = false
	self.mapPage.Visible = true
	self:select(self.selectedId)
	self:updateResponsive()
end

function Lobby:showMain()
	self.mapPage.Visible = false
	self.mainPage.Visible = true
end

function Lobby:showRecords()
	self.recordsOverlay.Visible = true
end

function Lobby:showGarage()
	if self.garageOverlay then
		self.garageOverlay.Visible = true
	end
end

function Lobby:showStats()
	if self.statsOverlay then
		self.statsOverlay.Visible = true
	end
end

function Lobby:setProfile(profile)
	self.profile = profile or {}
	local total = 0
	local played = 0
	local bestMap = nil
	local bestScore = 0
	for id, card in pairs(self.cards) do
		local best = tonumber(self.profile[id]) or 0
		total += best
		if best > 0 then
			played += 1
		end
		if best > bestScore then
			bestScore = best
			bestMap = card.map
		end
		card.bestLabel.Text = "Meilleur : " .. (best > 0 and tostring(best) or "—")
	end
	for id, label in pairs(self.recordLabels) do
		local best = tonumber(self.profile[id]) or 0
		label.Text = best > 0 and tostring(best) or "—"
	end
	if self.statsLabels then
		self.statsLabels[1].Text = tostring(total)
		self.statsLabels[2].Text = tostring(played)
		self.statsLabels[3].Text = bestMap and bestMap.name or "—"
		self.statsLabels[4].Text = played > 0
				and string.format("%.1f", total / played)
			or "—"
	end
end

function Lobby:toast(text)
	if not self.toastLabel then
		return
	end
	self.toastToken += 1
	local token = self.toastToken
	self.toastLabel.Text = text
	self.toastLabel.Visible = true
	task.delay(2.4, function()
		if self.toastToken == token then
			self.toastLabel.Visible = false
		end
	end)
end

return Lobby
