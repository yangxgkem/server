local coroutine = coroutine
local serverco = {}

local server_coroutines = setmetatable({}, { __mode = "kv" })

function serverco.create(f)
	local co = coroutine.create(f)
	server_coroutines[co] = true
	return co
end

function serverco.resume(co, ...)
	local co_status = server_coroutines[co]
	if not co_status then
		if co_status == false then
			-- is running
			return false, "cannot resume a server coroutine suspend by server framework"
		end
		if coroutine.status(co) == "dead" then
			-- always return false, "cannot resume dead coroutine"
			return coroutine.resume(co, ...)
		else
			return false, "cannot resume none server coroutine"
		end
	end
	return coroutine.resume(co, ...)
end

function serverco.yield(...)
	return coroutine.yield(...)
end

return serverco
