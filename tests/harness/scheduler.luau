--!nocheck
--[[
	scheduler.luau  (harnais de test)
	Horloge virtuelle + implémentation de task.spawn / defer / delay / wait.
	Rien ne s'exécute tout seul : le temps n'avance que via Scheduler.advance
	(H.advance dans les tests). task.wait appelé hors d'une tâche du
	scheduler (par exemple dans le corps d'un test) avance simplement l'horloge.
]]

local Scheduler = {}

Scheduler.now = 0
Scheduler.onError = function(message, traceback)
	print("[scheduler] error: " .. tostring(message) .. "\n" .. tostring(traceback))
end

local queue = {}
local seq = 0
local managed = setmetatable({}, { __mode = "k" })

function Scheduler.reset()
	Scheduler.now = 0
	queue = {}
	seq = 0
end

function Scheduler.pending()
	return #queue
end

local function report(co, err)
	local ok, trace = pcall(debug.traceback, co, tostring(err))
	Scheduler.onError(err, ok and trace or "")
end

local function resumeThread(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		report(co, err)
	end
	return ok
end

local function toThread(target)
	if type(target) == "thread" then
		return target
	end
	local co = coroutine.create(target)
	managed[co] = true
	return co
end

local function schedule(time, co, args)
	seq += 1
	table.insert(queue, { time = time, seq = seq, co = co, args = args })
end

function Scheduler.spawn(target, ...)
	local co = toThread(target)
	managed[co] = true
	resumeThread(co, ...)
	return co
end

function Scheduler.defer(target, ...)
	local co = toThread(target)
	schedule(Scheduler.now, co, table.pack(...))
	return co
end

function Scheduler.delay(seconds, target, ...)
	local co = toThread(target)
	schedule(Scheduler.now + (tonumber(seconds) or 0), co, table.pack(...))
	return co
end

function Scheduler.cancel(co)
	for i = #queue, 1, -1 do
		if queue[i].co == co then
			table.remove(queue, i)
		end
	end
end

function Scheduler.isManaged(co)
	return managed[co] == true
end

-- Réveille un thread plus tard (utilisé par WaitForChild / Signal:Wait).
function Scheduler.resumeSoon(co, ...)
	schedule(Scheduler.now, co, table.pack(...))
end

function Scheduler.wait(seconds)
	seconds = tonumber(seconds) or 1 / 60
	local co = coroutine.running()
	if managed[co] then
		local started = Scheduler.now
		schedule(started + seconds, co, table.pack())
		coroutine.yield()
		return Scheduler.now - started
	end
	Scheduler.advance(seconds)
	return seconds
end

-- Exécute toutes les tâches dues jusqu'à now + dt, dans l'ordre du temps.
function Scheduler.advance(dt)
	local target = Scheduler.now + dt
	while true do
		local bestIndex, best = nil, nil
		for i, item in ipairs(queue) do
			if item.time <= target and (not best or item.time < best.time or (item.time == best.time and item.seq < best.seq)) then
				bestIndex, best = i, item
			end
		end
		if not best then
			break
		end
		table.remove(queue, bestIndex)
		if best.time > Scheduler.now then
			Scheduler.now = best.time
		end
		if coroutine.status(best.co) == "suspended" then
			managed[best.co] = true
			resumeThread(best.co, table.unpack(best.args, 1, best.args.n))
		end
	end
	Scheduler.now = target
end

return Scheduler
