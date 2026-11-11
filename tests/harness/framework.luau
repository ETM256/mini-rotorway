--!nocheck
--[[
	framework.luau  (harnais de test)
	Mini framework : T.test, assertions, T.skip. Un fichier de test retourne
	`function(T, H)` et enregistre ses tests avec T.test(nom, fn).
]]

local D = require("./datatypes")

local F = {}

local SKIP = {}
F.SKIP = SKIP

local function repr(value, depth, seen)
	depth = depth or 0
	local t = type(value)
	if t == "string" then
		return string.format("%q", value)
	elseif t == "table" then
		local mt = getmetatable(value)
		if mt and mt.__type then
			return mt.__type .. "(" .. tostring(value) .. ")"
		end
		seen = seen or {}
		if seen[value] then
			return "<cycle>"
		end
		if depth >= 3 then
			return "{...}"
		end
		seen[value] = true
		local parts = {}
		local count = 0
		for k, v in pairs(value) do
			count += 1
			if count > 8 then
				table.insert(parts, "...")
				break
			end
			table.insert(parts, "[" .. repr(k, depth + 1, seen) .. "]=" .. repr(v, depth + 1, seen))
		end
		seen[value] = nil
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end
F.repr = repr

local function deepEqual(a, b, seen)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	local ma, mb = getmetatable(a), getmetatable(b)
	if (ma and ma.__type) or (mb and mb.__type) then
		return false
	end
	seen = seen or {}
	if seen[a] == b then
		return true
	end
	seen[a] = b
	for k, v in pairs(a) do
		if not deepEqual(v, b[k], seen) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function fail(message, level)
	error(message, (level or 1) + 1)
end

function F.newSuite(file)
	local suite = { file = file, tests = {} }
	local T = {}

	function T.test(name, fn)
		if type(name) ~= "string" or type(fn) ~= "function" then
			error("T.test(name, fn): a string and a function are required", 2)
		end
		table.insert(suite.tests, { name = name, fn = fn })
	end

	-- Problème connu et documenté : si fn échoue, le test est compté comme
	-- "skipped" (TODO) ; dès qu'il passe, il échoue pour demander de le
	-- convertir en T.test.
	function T.todo(name, fn)
		table.insert(suite.tests, { name = name, fn = fn, todo = true })
	end

	-- Enregistre un test ignoré (visible dans le résumé).
	function T.skipTest(name, reason)
		table.insert(suite.tests, { name = name, skip = reason or "skipped" })
	end

	-- À l'intérieur d'un test : l'ignore proprement.
	function T.skip(reason)
		error({ [SKIP] = true, reason = reason or "skipped" }, 0)
	end

	function T.skipIf(condition, reason)
		if condition then
			T.skip(reason)
		end
	end

	function T.fail(message)
		fail(message or "explicit failure", 2)
	end

	function T.ok(value, message)
		if not value then
			fail(message or ("expected a truthy value, got " .. repr(value)), 2)
		end
		return value
	end

	function T.falsy(value, message)
		if value then
			fail(message or ("expected a falsy value, got " .. repr(value)), 2)
		end
	end

	function T.eq(actual, expected, message)
		if actual ~= expected then
			fail(string.format("%sexpected %s, got %s", message and (message .. ": ") or "", repr(expected), repr(actual)), 2)
		end
	end

	function T.ne(actual, unexpected, message)
		if actual == unexpected then
			fail(string.format("%sexpected a value different from %s", message and (message .. ": ") or "", repr(unexpected)), 2)
		end
	end

	function T.near(actual, expected, epsilon, message)
		epsilon = epsilon or 1e-6
		if type(actual) ~= "number" or type(expected) ~= "number" or actual ~= actual or math.abs(actual - expected) > epsilon then
			fail(string.format("%sexpected %s ± %s, got %s", message and (message .. ": ") or "", repr(expected), tostring(epsilon), repr(actual)), 2)
		end
	end

	function T.lt(a, b, message)
		if not (a < b) then
			fail(string.format("%sexpected %s < %s", message and (message .. ": ") or "", repr(a), repr(b)), 2)
		end
	end

	function T.le(a, b, message)
		if not (a <= b) then
			fail(string.format("%sexpected %s <= %s", message and (message .. ": ") or "", repr(a), repr(b)), 2)
		end
	end

	function T.gt(a, b, message)
		if not (a > b) then
			fail(string.format("%sexpected %s > %s", message and (message .. ": ") or "", repr(a), repr(b)), 2)
		end
	end

	function T.ge(a, b, message)
		if not (a >= b) then
			fail(string.format("%sexpected %s >= %s", message and (message .. ": ") or "", repr(a), repr(b)), 2)
		end
	end

	function T.deepEq(actual, expected, message)
		if not deepEqual(actual, expected) then
			fail(string.format("%sexpected %s, got %s", message and (message .. ": ") or "", repr(expected), repr(actual)), 2)
		end
	end

	function T.isType(value, typeName, message)
		local actual = D.isKind(value, typeName) and typeName or type(value)
		local mt = type(value) == "table" and getmetatable(value)
		if mt and mt.__type then
			actual = mt.__type
		end
		if actual ~= typeName then
			fail(string.format("%sexpected type %s, got %s (%s)", message and (message .. ": ") or "", typeName, actual, repr(value)), 2)
		end
	end

	-- T.contains("abc", "b") ; T.contains({1,2}, 2)
	function T.contains(container, needle, message)
		local found = false
		if type(container) == "string" then
			found = string.find(container, needle, 1, true) ~= nil
		elseif type(container) == "table" then
			for _, v in pairs(container) do
				if v == needle then
					found = true
					break
				end
			end
		end
		if not found then
			fail(string.format("%sexpected %s to contain %s", message and (message .. ": ") or "", repr(container), repr(needle)), 2)
		end
	end

	-- Attend que fn lève une erreur (dont le message contient `pattern`, lua pattern).
	function T.throws(fn, pattern)
		local ok, err = pcall(fn)
		if ok then
			fail("expected the function to throw, but it returned normally", 2)
		end
		if pattern and not string.find(tostring(err), pattern) then
			fail(string.format("expected error matching %q, got %s", pattern, repr(tostring(err))), 2)
		end
		return tostring(err)
	end

	-- Exécute fn et échoue avec son erreur ; retourne ses résultats.
	function T.noThrow(fn, ...)
		local results = table.pack(pcall(fn, ...))
		if not results[1] then
			fail("unexpected error: " .. tostring(results[2]), 2)
		end
		return table.unpack(results, 2, results.n)
	end

	return T, suite
end

return F
