--!nocheck
--[[
	run_all.luau  (harnais de test)
	Lancé par `bash tests/run.sh`, qui génère d'abord
	  tests/harness/_modules.generated.luau  (modules de src/ + arbre mock)
	  tests/_tests.generated.luau            (fichiers *.test.luau)
	Options (après -a) : --verbose | --quiet | --list | <filtre>
	Filtre : sous-chaîne du chemin du fichier de test, ou "chemin::nom du test".
	Sortie : uniquement les échecs (sauf --verbose) puis
	  TESTS: N passed, M failed, K skipped
]]

local loadstring = (getfenv() :: any).loadstring

local H = require("./harness/h")
local F = require("./harness/framework")

local verbose, listOnly, filter = false, false, nil
for _, arg in ipairs({ ... }) do
	if arg == "--verbose" or arg == "-v" then
		verbose = true
	elseif arg == "--quiet" or arg == "-q" then
		verbose = false
	elseif arg == "--list" then
		listOnly = true
	elseif string.sub(arg, 1, 1) ~= "-" then
		filter = arg
	end
end

local fileFilter, nameFilter = nil, nil
if filter then
	local sep = string.find(filter, "::", 1, true)
	if sep then
		fileFilter = string.sub(filter, 1, sep - 1)
		nameFilter = string.sub(filter, sep + 2)
	else
		fileFilter = filter
	end
	if fileFilter == "" then
		fileFilter = nil
	end
end

local passed, failed, skipped = 0, 0, 0
local failureBlocks = {}

local function plainFind(text, needle)
	return string.find(text, needle, 1, true) ~= nil
end

-- Garde les lignes utiles d'une trace : fichiers de src/ et de tests/, hors harnais.
local function cleanTrace(trace)
	local keep = {}
	for line in string.gmatch(trace or "", "[^\n]+") do
		if not plainFind(line, "harness/") and not plainFind(line, "run_all") and not plainFind(line, "[C]") and not plainFind(line, "stack") then
			table.insert(keep, "    " .. line)
			if #keep >= 6 then
				break
			end
		end
	end
	return table.concat(keep, "\n")
end

local function recordFailure(file, name, message, trace)
	failed += 1
	local block = string.format("FAIL %s > %s\n  %s", file, name, string.gsub(tostring(message), "\n", "\n  "))
	local cleaned = cleanTrace(trace)
	if cleaned ~= "" then
		block ..= "\n" .. cleaned
	end
	table.insert(failureBlocks, block)
	if verbose then
		print("  FAIL " .. file .. " > " .. name)
	end
end

local okList, tests = pcall(require, "./_tests.generated")
if not okList then
	print("FAIL runner > tests/_tests.generated.luau missing: run `bash tests/run.sh`")
	print("  " .. tostring(tests))
	print("TESTS: 0 passed, 1 failed, 0 skipped")
	return
end

local function loadSuite(entry)
	local chunk, err = loadstring(entry.source, "=tests/" .. entry.path .. ".luau")
	if not chunk then
		return nil, "syntax error: " .. tostring(err)
	end
	setfenv(chunk, H.testEnv())
	local ok, factory = pcall(chunk)
	if not ok then
		return nil, "load error: " .. tostring(factory)
	end
	if type(factory) ~= "function" then
		return nil, "a test file must `return function(T, H) ... end`"
	end
	local T, suite = F.newSuite(entry.path)
	local okReg, regErr = pcall(function()
		H.reset()
		factory(T, H)
	end)
	if not okReg then
		return nil, "registration error: " .. tostring(regErr)
	end
	return suite
end

local fileCount, matchedTests = 0, 0

for _, entry in ipairs(tests) do
	if not fileFilter or plainFind(entry.path, fileFilter) then
		fileCount += 1
		local suite, loadError = loadSuite(entry)
		if not suite then
			recordFailure(entry.path, "(file could not be loaded)", loadError, "")
		elseif listOnly then
			print(string.format("%s (%d tests)", entry.path, #suite.tests))
			for _, test in ipairs(suite.tests) do
				print("  - " .. test.name .. (test.skip and "  [skipped]" or ""))
				matchedTests += 1
			end
		else
			local filePassed = 0
			for _, test in ipairs(suite.tests) do
				if not nameFilter or plainFind(test.name, nameFilter) then
					matchedTests += 1
					if test.skip then
						skipped += 1
						if verbose then
							print(string.format("  SKIP %s > %s (%s)", entry.path, test.name, test.skip))
						end
					else
						local started = os.clock()
						local okReset, resetErr = pcall(H.reset)
						local ok, err
						if okReset then
							ok, err = xpcall(test.fn, function(e)
								if type(e) == "table" then
									return e
								end
								return { message = tostring(e), trace = debug.traceback("", 2) }
							end)
						else
							ok, err = false, { message = "H.reset failed: " .. tostring(resetErr), trace = "" }
						end
						local elapsed = os.clock() - started
						if test.todo then
							if ok and #H.handlerErrors == 0 then
								recordFailure(entry.path, test.name, "T.todo test now passes: convert it into a regular T.test", "")
							else
								skipped += 1
								if verbose then
									print(string.format("  TODO %s > %s", entry.path, test.name))
								end
							end
						elseif ok then
							if #H.handlerErrors > 0 and not H.handlerErrorsAllowed then
								local first = H.handlerErrors[1]
								recordFailure(entry.path, test.name, "an event handler or task raised an error:\n" .. first.message, first.traceback)
							else
								passed += 1
								filePassed += 1
								if verbose then
									print(string.format("  ok   %s > %s (%.3fs)", entry.path, test.name, elapsed))
								end
							end
						elseif type(err) == "table" and err[F.SKIP] then
							skipped += 1
							if verbose then
								print(string.format("  SKIP %s > %s (%s)", entry.path, test.name, err.reason))
							end
						else
							local message = err.message
							if message == nil then
								message = F.repr(err)
							end
							recordFailure(entry.path, test.name, message, err.trace)
						end
					end
				end
			end
			if verbose then
				print(string.format("%s: %d passed", entry.path, filePassed))
			end
		end
	end
end

if listOnly then
	print(string.format("TESTS: %d tests listed in %d files", matchedTests, fileCount))
	return
end

for _, block in ipairs(failureBlocks) do
	print(block)
end
if fileCount == 0 and filter then
	-- Un filtre qui ne correspond à rien est presque toujours une faute de frappe.
	print(string.format("TESTS: 0 passed, 1 failed, 0 skipped (no test matches the filter '%s')", filter))
	return
end
print(string.format("TESTS: %d passed, %d failed, %d skipped", passed, failed, skipped))
