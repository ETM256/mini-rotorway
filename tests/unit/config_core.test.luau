-- Réglages de cœur : nom du jeu, accent du menu, borne de frame.
return function(T, H)
	local Config = H.load("Config")
	local RoadConfig = H.load("RoadConfig")

	T.test("the game is named Mini Rotorway and its version is bumped", function()
		T.eq(Config.GameName, "Mini Rotorway", "nom du jeu")
		T.ok(type(Config.Version) == "string" and Config.Version ~= "1.6.0", "version mise à jour")
	end)

	T.test("LobbyAccentDeep is a soft coral: saturation at most 0.5, value at least 0.7", function()
		local _, saturation, value = Config.Colors.LobbyAccentDeep:ToHSV()
		T.le(saturation, 0.5, "saturation (l'ancien C56F42 était à 0.66)")
		T.ge(value, 0.7, "pas sombre")
	end)

	T.test("the per-frame simulation cap is a positive, small duration", function()
		T.gt(Config.Time.MaxFrameDt, 0, "positive")
		T.le(Config.Time.MaxFrameDt, 0.2, "une frame ne fait pas avancer la partie de plus de 0,2 s")
	end)

	T.test("road visual widths come from Config.Dimensions.Road", function()
		T.near(RoadConfig.Visual.RoadWidth, Config.Dimensions.Road.Width, 1e-9, "largeur de route")
		T.near(RoadConfig.Visual.EdgeWidth, Config.Dimensions.Road.Edge, 1e-9, "liseré")
	end)
end
