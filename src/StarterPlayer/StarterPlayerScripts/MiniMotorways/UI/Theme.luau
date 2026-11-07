--[[
	Theme.luau
	Petits constructeurs d'interface + palette commune.
	Tout est dessiné en code : aucun asset à importer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local C = Config.Colors

local Theme = {}

Theme.Ink = C.Ink
Theme.InkSoft = C.InkSoft
Theme.Teal = C.Teal
Theme.TealDark = C.TealDark
Theme.Orange = C.Orange
Theme.White = C.White
Theme.Cream = C.Cream
Theme.Background = C.Background
Theme.GridLine = C.GridLine
Theme.LobbyBackground = C.LobbyBackground or C.Background
Theme.LobbyGrid = C.LobbyGrid or C.GridLine
Theme.LobbyButton = C.LobbyButton or C.Teal
Theme.LobbyButtonDark = C.LobbyButtonDark or C.TealDark
Theme.LobbyOrange = C.LobbyOrange or C.Orange
Theme.LobbyRoad = C.LobbyRoad or C.White
Theme.LobbyRoadShadow = C.LobbyRoadShadow or C.CardShadow
Theme.CardShadow = C.CardShadow
Theme.Danger = C.Danger
Theme.Panel = C.Panel
Theme.PanelSoft = C.PanelSoft
Theme.PanelDark = C.PanelDark
Theme.Border = C.Border
Theme.BorderStripe = C.BorderStripe
Theme.Paper = C.Paper
Theme.Water = C.Water
Theme.Grass = C.Grass
Theme.Land = C.Land
Theme.Road = C.Road

Theme.Font = Enum.Font.Gotham
Theme.FontBold = Enum.Font.GothamBold
Theme.FontBlack = Enum.Font.GothamBlack

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

function Theme.corner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
	return corner
end

function Theme.stroke(instance, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Ink
	stroke.Thickness = thickness or 2
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
	Theme.corner(button, cornerRadius or 4)

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
			TweenService:Create(button, TweenInfo.new(0.14), {
				BackgroundColor3 = currentBaseColor():Lerp(Color3.new(0, 0, 0), 0.09),
			}):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.14), {
			BackgroundColor3 = currentBaseColor(),
		}):Play()
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

return Theme
