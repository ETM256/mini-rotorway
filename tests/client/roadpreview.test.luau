return function(T, H)
	local function newPreview()
		H.asClient()
		local preview = H.load("RoadPreview").new()
		preview:setWorld(Vector3.new(700, 0, 0), 4)
		return preview
	end

	local function visibleParts()
		local n = 0
		for _, part in ipairs(workspace.MM_RoadPreview:GetChildren()) do
			if part.Transparency < 1 then
				n += 1
			end
		end
		return n
	end

	T.test("valid cells are mint, refused cells coral, placed exactly on the cell", function()
		local RoadConfig = H.load("RoadConfig")
		local Grid = H.load("Grid")
		local preview = newPreview()
		preview:setCells({ { x = 2, y = 3, valid = true }, { x = 3, y = 3, valid = false } })
		T.eq(visibleParts(), 2)
		local parts = workspace.MM_RoadPreview:GetChildren()
		T.eq(parts[1].Color, RoadConfig.Visual.PreviewValidColor)
		T.eq(parts[2].Color, RoadConfig.Visual.PreviewInvalidColor)
		local center = Grid.center(Vector3.new(700, 0, 0), 2, 3, RoadConfig.Visual.PreviewY)
		T.near(parts[1].Position.X, center.X, 1e-6)
		T.near(parts[1].Position.Z, center.Z, 1e-6)
		T.le(parts[1].Size.X, 4, "the preview never exceeds a tile")
	end)

	T.test("clearing hides the preview and parts are reused (no growth)", function()
		local preview = newPreview()
		for i = 1, 50 do
			preview:setCells({ { x = i % 10, y = 1 }, { x = (i + 1) % 10, y = 1 } })
		end
		T.le(#workspace.MM_RoadPreview:GetChildren(), 2)
		preview:clear()
		T.eq(visibleParts(), 0)
	end)

	T.test("shrinking the preview hides the extra parts", function()
		local preview = newPreview()
		preview:setCells({ { x = 1, y = 1 }, { x = 2, y = 1 }, { x = 3, y = 1 } })
		T.eq(visibleParts(), 3)
		preview:setCells({ { x = 1, y = 1 } })
		T.eq(visibleParts(), 1)
		preview:setCells(nil)
		T.eq(visibleParts(), 0)
	end)

	T.test("malformed cells are ignored; destroy removes the folder", function()
		local preview = newPreview()
		T.noThrow(function()
			preview:setCells({ "x", 5, {}, { x = 1 } })
		end)
		T.eq(visibleParts(), 0)
		preview:destroy()
		T.eq(workspace:FindFirstChild("MM_RoadPreview"), nil)
	end)

	T.test("preview parts are flat, non-colliding and cast no shadow", function()
		local preview = newPreview()
		preview:setCells({ { x = 1, y = 1 } })
		local part = workspace.MM_RoadPreview:GetChildren()[1]
		T.falsy(part.CanCollide)
		T.falsy(part.CanQuery)
		T.ok(part.Anchored)
		T.le(part.Size.Y, 0.2)
	end)
end
