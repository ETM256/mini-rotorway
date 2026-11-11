return function(T, H)
	local Theme = H.load("UI/Theme")
	local Icons = H.load("UI/HUDIcons")
	local NAMES = { "pen", "trash", "roundabout", "road", "pan", "bridge" }

	-- Tous les descendants d'un objet, parcours en profondeur.
	local function descendants(root, list)
		list = list or {}
		for _, child in ipairs(root:GetChildren()) do
			table.insert(list, child)
			descendants(child, list)
		end
		return list
	end

	-- Traits d'un pictogramme : les Frame directs du carré, pas le carré lui-même.
	local function strokes(holder)
		local list = {}
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("Frame") then
				table.insert(list, child)
			end
		end
		return list
	end

	-- Boîte englobante des traits, en pixels du carré, avec la rotation de chacun.
	local function glyphBox(holder)
		local side = holder.Size.X.Offset
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		for _, frame in ipairs(strokes(holder)) do
			local cx = frame.Position.X.Scale * side
			local cy = frame.Position.Y.Scale * side
			local w = frame.Size.X.Scale * side
			local h = frame.Size.Y.Scale * side
			local angle = math.rad(frame.Rotation)
			local cos, sin = math.abs(math.cos(angle)), math.abs(math.sin(angle))
			local halfX = (w * cos + h * sin) / 2
			local halfY = (w * sin + h * cos) / 2
			minX = math.min(minX, cx - halfX)
			maxX = math.max(maxX, cx + halfX)
			minY = math.min(minY, cy - halfY)
			maxY = math.max(maxY, cy + halfY)
		end
		return minX, minY, maxX, maxY
	end

	T.test("every pictogram is drawn in a square of the same size, centred in its parent", function()
		for _, name in ipairs(NAMES) do
			local holder = Icons[name](Instance.new("Frame"))
			T.eq(holder.Size.X.Offset, 24, name .. " width")
			T.eq(holder.Size.Y.Offset, 24, name .. " height")
			T.eq(holder.Size.X.Scale, 0, name .. " width has no scale part")
			T.eq(holder.AnchorPoint.X, 0.5, name .. " anchor X")
			T.eq(holder.AnchorPoint.Y, 0.5, name .. " anchor Y")
			T.eq(holder.Position.X.Scale, 0.5, name .. " position X")
			T.eq(holder.Position.Y.Scale, 0.5, name .. " position Y")
		end
	end)

	T.test("the drawing of each pictogram is centred in its square and stays inside it", function()
		for _, name in ipairs(NAMES) do
			local holder = Icons[name](Instance.new("Frame"))
			local minX, minY, maxX, maxY = glyphBox(holder)
			T.near((minX + maxX) / 2, 12, 0.05, name .. " horizontal centre")
			T.near((minY + maxY) / 2, 12, 0.05, name .. " vertical centre")
			T.ge(minX, -0.5, name .. " left edge inside the square")
			T.ge(minY, -0.5, name .. " top edge inside the square")
			T.le(maxX, 24.5, name .. " right edge inside the square")
			T.le(maxY, 24.5, name .. " bottom edge inside the square")
		end
	end)

	T.test("a size argument scales the square and keeps the drawing centred", function()
		for _, name in ipairs(NAMES) do
			local holder = Icons[name](Instance.new("Frame"), nil, 46)
			T.eq(holder.Size.X.Offset, 46, name .. " scaled width")
			local minX, _, maxX = glyphBox(holder)
			T.near((minX + maxX) / 2, 23, 0.05, name .. " centred at 46 px")
		end
	end)

	T.test("a requested colour paints the filled strokes and the outlines", function()
		local red = Color3.new(1, 0, 0)
		for _, name in ipairs(NAMES) do
			local holder = Icons[name](Instance.new("Frame"), red)
			for _, child in ipairs(descendants(holder)) do
				if child:IsA("Frame") and child.BackgroundTransparency == 0 then
					T.eq(child.BackgroundColor3, red, name .. " filled stroke colour")
				elseif child:IsA("UIStroke") then
					T.eq(child.Color, red, name .. " outline colour")
				end
			end
		end
	end)

	T.test("the default colour is the light one used on dark chips", function()
		local holder = Icons.pen(Instance.new("Frame"))
		local barrel = strokes(holder)[1]
		T.eq(barrel.BackgroundColor3, Theme.White, "pen barrel colour")
	end)

	T.test("pictograms are built from frames, corners and strokes only, with no text", function()
		for _, name in ipairs(NAMES) do
			local holder = Icons[name](Instance.new("Frame"))
			for _, child in ipairs(descendants(holder)) do
				T.falsy(child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("ImageLabel"), name .. " has no text or image")
				if child:IsA("UIStroke") then
					T.eq(child.Thickness, Theme.Stroke.Max, name .. " outline keeps the shared thickness")
				end
			end
		end
	end)
end
