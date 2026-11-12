--[[
	Instantané de l'arbre d'interface du HUD.
	Chaque étape (construction, partie, pause, fin de partie, choix hebdomadaire,
	toast, cinq tailles d'écran) est sérialisée (classe, nom, propriétés visuelles,
	ordre des enfants) puis réduite à une empreinte courte.
	Les couleurs sont notées par leur jeton de Theme (et non par leurs valeurs) :
	retoucher la palette ne fait pas bouger GOLDEN. Les helpers de Theme (ex.
	Theme.button) et la mise en page font partie de l'arbre : après une évolution
	volontaire, lancer ce test et reprendre les empreintes « got » dans GOLDEN.
	Rebasé après la refonte de la barre du haut (jour, mois, contrôles du temps),
	des compteurs (cinq pastilles identiques) et du gabarit commun Theme.Layout.
]]

return function(T, H)
	local RESOLUTIONS = { { 1920, 1080 }, { 1366, 768 }, { 1280, 720 }, { 844, 390 }, { 390, 844 } }

	local GUI_PROPS = {
		"Visible",
		"Position",
		"Size",
		"AnchorPoint",
		"Rotation",
		"ZIndex",
		"LayoutOrder",
		"BackgroundTransparency",
		"BackgroundColor3",
		"BorderSizePixel",
		"ClipsDescendants",
	}
	local TEXT_PROPS = {
		"Text",
		"TextColor3",
		"TextSize",
		"Font",
		"TextScaled",
		"TextWrapped",
		"TextXAlignment",
		"TextYAlignment",
	}

	-- Une couleur est notée par le nom de son jeton dans Theme (et non par ses
	-- valeurs RVB) : retoucher la palette ne change pas l'empreinte, réaffecter
	-- un jeton à un autre élément la change.
	local function paletteOf(Theme)
		local tokens = {}
		for name, value in pairs(Theme) do
			if typeof(value) == "Color3" then
				table.insert(tokens, { name = name, value = value })
			end
		end
		table.sort(tokens, function(a, b)
			return a.name < b.name
		end)
		return tokens
	end

	local function colourName(palette, color)
		for _, token in ipairs(palette) do
			local value = token.value
			if value.R == color.R and value.G == color.G and value.B == color.B then
				return "Theme." .. token.name
			end
		end
		return string.format("rgb(%.3f,%.3f,%.3f)", color.R, color.G, color.B)
	end

	local function describe(inst, palette)
		local parts = { inst.ClassName, inst.Name }
		local function add(prop)
			local value = inst[prop]
			if typeof(value) == "Color3" then
				value = colourName(palette, value)
			end
			table.insert(parts, prop .. "=" .. tostring(value))
		end
		if inst:IsA("GuiObject") then
			for _, prop in ipairs(GUI_PROPS) do
				add(prop)
			end
		end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			for _, prop in ipairs(TEXT_PROPS) do
				add(prop)
			end
		end
		if inst:IsA("ScreenGui") then
			for _, prop in ipairs({ "Enabled", "ResetOnSpawn", "IgnoreGuiInset", "DisplayOrder", "ZIndexBehavior" }) do
				add(prop)
			end
		end
		if inst:IsA("UIListLayout") then
			for _, prop in ipairs({ "FillDirection", "HorizontalAlignment", "VerticalAlignment", "Padding", "SortOrder" }) do
				add(prop)
			end
		end
		if inst:IsA("UICorner") then
			add("CornerRadius")
		end
		if inst:IsA("UIStroke") then
			for _, prop in ipairs({ "Color", "Thickness", "Transparency", "ApplyStrokeMode" }) do
				add(prop)
			end
		end
		if inst:IsA("UIScale") then
			add("Scale")
		end
		if inst:IsA("UISizeConstraint") then
			add("MaxSize")
		end
		if inst:IsA("UITextSizeConstraint") then
			add("MaxTextSize")
			add("MinTextSize")
		end
		return table.concat(parts, " ")
	end

	local function walk(inst, depth, out, palette)
		table.insert(out, string.rep(" ", depth) .. describe(inst, palette))
		for _, child in ipairs(inst:GetChildren()) do
			walk(child, depth + 1, out, palette)
		end
	end

	-- Empreinte djb2 sur 32 bits, sans opérateurs binaires : suffisante pour
	-- détecter une dérive de l'arbre, avec la longueur et le nombre de nœuds.
	local function digestOf(root, palette)
		local out = {}
		walk(root, 0, out, palette)
		local text = table.concat(out, "\n")
		local hash = 5381
		for index = 1, #text do
			hash = (hash * 33 + string.byte(text, index)) % 4294967296
		end
		return string.format("%d:%d:%d", #out, #text, hash)
	end

	local function newHud(calls)
		H.asClient()
		local HUD = H.load("HUD")
		local hud = HUD.new({
			onPause = function()
				table.insert(calls, "pause")
			end,
			onResume = function()
				table.insert(calls, "resume")
			end,
			onRestart = function()
				table.insert(calls, "restart")
			end,
			onMenu = function()
				table.insert(calls, "menu")
			end,
			onToolChange = function(tool)
				table.insert(calls, "tool:" .. tostring(tool))
			end,
			onSpeed = function(value)
				table.insert(calls, "speed:" .. tostring(value))
			end,
			onChooseReward = function(id)
				table.insert(calls, "reward:" .. tostring(id))
			end,
		})
		return hud, H.localPlayer.PlayerGui:FindFirstChild("MM_HUD")
	end

	local function started()
		return {
			mapId = "los_angeles",
			origin = Vector3.new(700, 0, 0),
			size = 18,
			tile = 4,
			weekDuration = 60,
			roundabouts = 1,
		}
	end

	local function state()
		return {
			score = 12,
			week = 3,
			weekProgress = 0.4,
			budget = 17,
			bridges = 2,
			roundabouts = 1,
			satisfaction = 80,
			speed = 1,
			paused = false,
			awaitingChoice = false,
			over = false,
			houses = 5,
			destinations = 2,
			largeStores = 0,
			cars = 3,
			roadsBuilt = 9,
		}
	end

	-- Empreintes attendues, une par étape (voir l'en-tête du fichier).
	local GOLDEN = [[build 334:59319:504835204
game 334:59338:2545103729
pause 334:59334:29879568
gameover 334:59380:1563588804
week 410:73716:277678321
toast 410:73726:808565958
screen 1920x1080 334:59338:2545103729
screen 1366x768 334:59338:2545103729
screen 1280x720 334:59338:2545103729
screen 844x390 334:59358:319014549
screen 390x844 334:59383:2648148329]]

	T.test("the HUD tree matches the golden digests at every stage", function()
		local Rewards = H.load("Config").Rewards
		local map = H.load("Maps").getById("los_angeles")
		local palette = paletteOf(H.load("UI/Theme"))
		local lines = {}
		local function record(name, root)
			table.insert(lines, name .. " " .. digestOf(root, palette))
		end

		local hud, gui = newHud({})
		record("build", gui)

		hud:showGame(started(), map)
		hud:setState(state())
		H.advance(1)
		record("game", gui)

		hud:showPause()
		record("pause", gui)
		hud:hidePause()

		hud:showGameOver({ mapId = "los_angeles", score = 57, best = 80, week = 6 })
		record("gameover", gui)
		hud:hideModals()

		hud:showWeekChoice({ week = 2, options = { Rewards.Bridge, Rewards.Roads, Rewards.Roundabout } })
		record("week", gui)
		hud:hideWeekChoice()

		hud:toast("Bonjour")
		record("toast", gui)

		for _, res in ipairs(RESOLUTIONS) do
			H.reset()
			local responsiveHud, responsiveGui = newHud({})
			H.setViewport(res[1], res[2])
			responsiveHud:showGame(started(), map)
			responsiveHud:setState(state())
			H.advance(1)
			responsiveHud:applyResponsive()
			record("screen " .. res[1] .. "x" .. res[2], responsiveGui)
		end

		T.eq(table.concat(lines, "\n"), GOLDEN, "HUD tree digests")
	end)
end
