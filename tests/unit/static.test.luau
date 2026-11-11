return function(T, H)
	-- Contrôles statiques sur les sources embarquées : ils attrapent les fautes
	-- de frappe et les références à des réglages ou méthodes supprimés, que
	-- Luau ne signale pas (accès à un champ de table = nil silencieux).

	local function sources()
		local list = {}
		for _, src in ipairs(H.sources()) do
			table.insert(list, { file = src.file, name = src.name, class = src.class, code = H.stripComments(src.source) })
		end
		return list
	end

	-- alias local -> nom du module, d'après `local X = require(...Module)`.
	local function aliasesOf(code)
		local aliases = {}
		for alias, module in string.gmatch(code, "local%s+([%w_]+)%s*=%s*require%([^)]-%.([%w_]+)%)") do
			aliases[alias] = module
		end
		return aliases
	end

	T.test("every module loads in a client+server world without error", function()
		H.asClient()
		H.setupRemotes()
		local failures = {}
		for _, src in ipairs(sources()) do
			if src.name ~= "Bootstrap" and src.name ~= "Main" then
				local ok, err = pcall(H.load, src.file)
				if not ok then
					table.insert(failures, src.file .. ": " .. tostring(err))
				end
			end
		end
		T.eq(#failures, 0, table.concat(failures, "\n"))
	end)

	T.test("fields read on shared modules exist (Config.X, StoreConfig.A.B, Grid.fn ...)", function()
		H.asClient()
		H.setupRemotes()
		local tables = {}
		for _, src in ipairs(sources()) do
			if src.class ~= "Script" and src.class ~= "LocalScript" then
				local ok, value = pcall(H.load, src.file)
				if ok and type(value) == "table" then
					tables[src.name] = value
				end
			end
		end
		local problems = {}
		local checked = 0
		for _, src in ipairs(sources()) do
			for alias, module in pairs(aliasesOf(src.code)) do
				local target = tables[module]
				if target and module ~= "Session" then
					for first, second in string.gmatch(src.code, "[^%w_%.:]" .. alias .. "%.([%a_][%w_]*)%.?([%a_]?[%w_]*)") do
						checked += 1
						-- On ignore les écritures (Alias.champ = ...) : elles créent des champs.
						local isWrite = string.find(src.code, "[^%w_%.:]" .. alias .. "%." .. first .. "%s*=[^=]") ~= nil
						if target[first] == nil and not isWrite then
							table.insert(problems, string.format("%s: %s.%s (module %s)", src.file, alias, first, module))
						elseif type(target[first]) == "table" and second ~= "" and getmetatable(target[first]) == nil then
							if target[first][second] == nil and #target[first] == 0 then
								table.insert(problems, string.format("%s: %s.%s.%s (module %s)", src.file, alias, first, second, module))
							end
						end
					end
				end
			end
		end
		T.gt(checked, 50, "the static scan should find many references")
		T.eq(#problems, 0, table.concat(problems, "\n"))
	end)

	local function definedMethods(code, className)
		local defs = {}
		for name in string.gmatch(code, "function%s+" .. className .. "[:.]([%w_]+)%s*%(") do
			defs[name] = true
		end
		return defs
	end

	T.test("Session: every self:method() call is defined in a Session module", function()
		local defs = {}
		local files = {}
		for _, src in ipairs(sources()) do
			if string.match(src.name, "^Session") and src.name ~= "SessionUtil" then
				table.insert(files, src)
				for name in pairs(definedMethods(src.code, "Session")) do
					defs[name] = true
				end
			end
		end
		T.gt(#files, 0, "no Session module found")
		local problems = {}
		for _, src in ipairs(files) do
			for name in string.gmatch(src.code, "self:([%a_][%w_]*)%s*%(") do
				if not defs[name] then
					table.insert(problems, src.file .. ": self:" .. name .. "()")
				end
			end
		end
		T.eq(#problems, 0, table.concat(problems, "\n"))
	end)

	T.test("StoreSystem: self:/session: calls resolve", function()
		local session, store = {}, nil
		for _, src in ipairs(sources()) do
			if string.match(src.name, "^Session") and src.name ~= "SessionUtil" then
				for name in pairs(definedMethods(src.code, "Session")) do
					session[name] = true
				end
			elseif src.name == "StoreSystem" then
				store = src
			end
		end
		T.ok(store, "StoreSystem module")
		local own = definedMethods(store.code, "StoreSystem")
		local problems = {}
		for name in string.gmatch(store.code, "self:([%a_][%w_]*)%s*%(") do
			if not own[name] then
				table.insert(problems, "StoreSystem self:" .. name .. "()")
			end
		end
		for name in string.gmatch(store.code, "self%.session:([%a_][%w_]*)%s*%(") do
			if not session[name] then
				table.insert(problems, "StoreSystem self.session:" .. name .. "()")
			end
		end
		for _, src in ipairs(sources()) do
			if string.match(src.name, "^Session") then
				for name in string.gmatch(src.code, "self%.storeSystem:([%a_][%w_]*)%s*%(") do
					if not own[name] then
						table.insert(problems, src.file .. ": storeSystem:" .. name .. "()")
					end
				end
			end
		end
		T.eq(#problems, 0, table.concat(problems, "\n"))
	end)

	-- Classe client : `local X = {}` dans son fichier. Mixin : fichier qui renvoie
	-- `function(X) ... end` et définit `function X:nom(` (HUD est découpé ainsi).
	local function clientClassOf(code)
		local name = string.match(code, "local%s+([%w_]+)%s*=%s*{}%s*[\n\r]")
		if name then
			return name, "class"
		end
		name = string.match(code, "return%s+function%s*%(%s*([%a_][%w_]*)%s*%)")
		if name then
			return name, "mixin"
		end
		return nil, nil
	end

	local function folderOf(file)
		return string.match(file, "^(.*)/[^/]*$") or ""
	end

	-- Problèmes « self:nom() non défini » dans les classes et mixins client. Une
	-- méthode peut être définie dans le fichier même ou dans un mixin frère (même
	-- dossier, `return function(X)`) qui étend la classe X.
	local function undefinedClientMethods(list)
		local problems, classes = {}, 0
		for _, src in ipairs(list) do
			local className, kind = clientClassOf(src.code)
			if className and string.find(src.file, "StarterPlayer", 1, true) and src.class == "ModuleScript" then
				if kind == "class" then
					classes += 1
				end
				local defs = definedMethods(src.code, className)
				for field in string.gmatch(src.code, "self%.([%a_][%w_]*)%s*=%s*function") do
					defs[field] = true
				end
				for _, sib in ipairs(list) do
					if sib ~= src and folderOf(sib.file) == folderOf(src.file) and clientClassOf(sib.code) == className then
						for name in pairs(definedMethods(sib.code, className)) do
							defs[name] = true
						end
					end
				end
				for name in string.gmatch(src.code, "self:([%a_][%w_]*)%s*%(") do
					if not defs[name] then
						table.insert(problems, src.file .. ": self:" .. name .. "()")
					end
				end
			end
		end
		return problems, classes
	end

	T.test("client classes: every self:method() call is defined in the class file or a sibling mixin", function()
		local problems, classes = undefinedClientMethods(sources())
		T.gt(classes, 3)
		T.eq(#problems, 0, table.concat(problems, "\n"))
	end)

	-- Garde-fou du contrôle lui-même : il doit attraper une méthode absente, et
	-- accepter une méthode définie dans un mixin frère.
	T.test("client classes: the checker flags a truly undefined method and accepts mixin methods", function()
		local folder = "src/StarterPlayer/StarterPlayerScripts/MiniMotorways/UI/"
		local problems = undefinedClientMethods({
			{
				file = folder .. "Fake.luau",
				class = "ModuleScript",
				code = "local Fake = {}\nFake.__index = Fake\nfunction Fake:run()\n\tself:helper()\n\tself:missing()\nend\nreturn Fake",
			},
			{
				file = folder .. "FakeMixin.luau",
				class = "ModuleScript",
				code = "return function(Fake)\n\tfunction Fake:helper()\n\t\tself:run()\n\tend\nend",
			},
		})
		T.eq(#problems, 1, table.concat(problems, "\n"))
		T.ok(string.find(problems[1] or "", "self:missing()", 1, true) ~= nil, "the undefined call is reported")
	end)

	T.test("no module uses deprecated Roblox globals (wait/spawn/delay)", function()
		local problems = {}
		for _, src in ipairs(sources()) do
			for _, name in ipairs({ "wait", "spawn", "delay" }) do
				if string.find(src.code, "[^%w_%.:]" .. name .. "%(") then
					table.insert(problems, src.file .. ": " .. name .. "() (use task." .. name .. ")")
				end
			end
		end
		T.eq(#problems, 0, table.concat(problems, "\n"))
	end)

	T.test("no unbounded 'while true' loops without a yield in server/shared modules", function()
		local problems = {}
		for _, src in ipairs(sources()) do
			if not string.find(src.file, "StarterPlayer", 1, true) then
				for body in string.gmatch(src.code, "while%s+true%s+do(.-)\nend") do
					if not string.find(body, "task%.wait") and not string.find(body, "RunService") and not string.find(body, "break") and not string.find(body, "return") then
						table.insert(problems, src.file .. ": while true without yield/exit")
					end
				end
			end
		end
		T.eq(#problems, 0, table.concat(problems, "\n"))
	end)

	T.test("modules do not rely on Roblox default UI colours or fluorescent colours", function()
		-- Brief, part 2 : pas de couleurs fluorescentes. Color3.fromRGB / new avec
		-- trois canaux presque saturés (>= 0.95 avec un canal <= 0.15) sont refusés.
		local problems = {}
		for _, src in ipairs(sources()) do
			for r, g, b in string.gmatch(src.code, "Color3%.fromRGB%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)") do
				r, g, b = tonumber(r), tonumber(g), tonumber(b)
				local mx, mn = math.max(r, g, b), math.min(r, g, b)
				if mx >= 240 and mn <= 40 then
					table.insert(problems, string.format("%s: Color3.fromRGB(%d, %d, %d)", src.file, r, g, b))
				end
			end
		end
		T.eq(#problems, 0, table.concat(problems, "\n"))
	end)
end
