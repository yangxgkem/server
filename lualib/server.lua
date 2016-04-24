local tostring = tostring
local tonumber = tonumber
local assert = assert
local pairs = pairs
local pcall = pcall
local servercore = require "server.core"
local serverco = require "serverco"

local watching_session = {} --缓存RPC调用 {addr = session}
local watching_service = {}
local sleep_session = {}
local coroutine_pool = {}
local error_queue = {}
local session_id_coroutine = {}
local session_coroutine_address = {}
local session_coroutine_id = {}
local dead_service = {}

local server = {}
server.protos = {} --消息类型处理函数
server.serviceNameCache = {} --服务名称缓存
server.ptypes = {
	["PTYPE_TEXT"] = 0, --默认普通类型数据
	["PTYPE_RESPONSE"] = 1, --定时器数据
	["PTYPE_SOCKET"] = 2, --socket数据
	["PTYPE_ERROR"] = 3, --错误
	["PTYPE_SYSTEM"] = 4, --系统数据
	["PTYPE_HARBOR"] = 5, --harbor数据
	["PTYPE_LOGIC_LUA"] = 101, --lua数据
}

local function string_to_handle(str)
	return tonumber("0x" .. string.sub(str , 2))
end

local function co_create(f)
	local co = table.remove(coroutine_pool)
	if co == nil then
		co = serverco.create(function(...)
			f(...)
			while true do
				f = nil
				coroutine_pool[#coroutine_pool+1] = co
				f = serverco.yield("EXIT")
				f(serverco.yield())
			end
		end)
	else
		serverco.resume(co, f)
	end
	return co
end

local function yield_call(service, session)
	watching_session[session] = service
	local succ, msg, sz = serverco.yield("CALL", session)
	watching_session[session] = nil
	if not succ then
		error("call failed")
	end
	return msg, sz
end

local function release_watching(address)
	local ref = watching_service[address]
	if ref then
		ref = ref - 1
		if ref > 0 then
			watching_service[address] = ref
		else
			watching_service[address] = nil
		end
	end
end

local function dispatch_error_queue()
	local session = table.remove(error_queue, 1)
	if session then
		local co = session_id_coroutine[session]
		session_id_coroutine[session] = nil
		return suspend(co, serverco.resume(co, false))
	end
end

local function _error_dispatch(error_session, error_source)
	if error_session == 0 then
		-- service is down
		-- Don't remove from watching_service , because user may call dead service
		if watching_service[error_source] then
			dead_service[error_source] = true
		end
		for session, srv in pairs(watching_session) do
			if srv == error_source then
				table.insert(error_queue, session)
			end
		end
	else
		-- capture an error for error_session
		if watching_session[error_session] then
			table.insert(error_queue, error_session)
		end
	end
end

function suspend(co, result, command, param)
	--server.error("suspend......", result, command, param)
	-- coroutine return false
	if not result then
		local session = session_coroutine_id[co]
		if session then
			local addr = session_coroutine_address[co]
			if session ~= 0 then
				servercore.send(addr, server.ptypes.PTYPE_ERROR, session, "") --告诉rpc请求方,我这边出错了,无法返回你想要的信息
			end
			session_coroutine_id[co] = nil
			session_coroutine_address[co] = nil
		end
		error(debug.traceback(co, tostring(command)))
	end

	-- rpc
	if command == "CALL" then
		session_id_coroutine[param] = co
	-- sleep
	elseif command == "SLEEP" then
		session_id_coroutine[param] = co
		sleep_session[co] = param
	-- coroutine exit
	elseif command == "EXIT" then
		local address = session_coroutine_address[co]
		release_watching(address)
		session_coroutine_id[co] = nil
		session_coroutine_address[co] = nil
	-- service exit
	elseif command == "QUIT" then
		return
	else
		error("Unknown command : " .. command .. "\n" .. debug.traceback(co))
	end

	dispatch_error_queue()
end

--lua数据消息打包为userdata
function server.pack(msgtbl)
	return servercore.pack(msgtbl)
end

--userdata消息解包lua
function server.unpack(userdata, sz)
	return servercore.unpack(userdata, sz)
end

--lua数据消息打包为userdata,再打包成lua string
function server.packstring(msgtbl)
	return servercore.packstring(msgtbl)
end

--把userdata打包成lua string
function server.tostring(userdata, sz)
	return servercore.packstring(userdata, sz)
end

--注册消息类型
function server.register_protocol(class)
	local name = class.name
	local ptype = class.ptype
	assert(server.protos[name] == nil)
	assert(type(name) == "string" and type(ptype) == "number" and ptype >=0 and ptype <=255)
	server.protos[name] = class
	server.protos[ptype] = class
end

--注册消息类型处理函数
function server.dispatch(ptype, func)
	local p = assert(server.protos[ptype], tostring(ptype))
	assert(p.dispatch == nil, tostring(ptype))
	p.dispatch = func
end

--定时器
function server.timeout(ti, func)
	local session = servercore.command("TIMEOUT",tostring(ti))
	assert(session)
	local co = co_create(func)
	assert(session_id_coroutine[session] == nil)
	session_id_coroutine[tonumber(session)] = co
end

--将当前 coroutine 挂起 ti 个单位时间
function server.sleep(ti)
	local session = servercore.command("TIMEOUT",tostring(ti))
	assert(session)
	local succ, msg, sz = serverco.yield("SLEEP", tonumber(session))
	sleep_session[coroutine.running()] = nil
	if succ then
		return
	else
		error(ret)
	end
end

--获取当前服务handleid
function server.self()
	return string_to_handle(servercore.command("REG"))
end

--根据服务名称获取handleid
function server.localname(name)
	local addr = servercore.command("QUERY", name)
	if addr then
		return string_to_handle(addr)
	end
end

--获取定时器启动到现在经过了多少(秒*100)
function server.now()
	return tonumber(servercore.command("NOW"))
end

--获取定时器启动时间
function server.starttime()
	return tonumber(servercore.command("STARTTIME"))
end

--获取当前时间
function server.time()
	return server.now()/100 + server.starttime()
end

--获取配置信息
function server.getenv(key)
	local ret = servercore.command("GETENV",key)
	if ret == "" then
		return
	else
		return ret
	end
end

--设置配置信息
function server.setenv(key, value)
	servercore.command("SETENV",key .. " " ..value)
end

--开启某服务日志
function server.openlog(service_name)
	if service_name then
		servercore.command("LOGON", service_name)
	else
		servercore.command("LOGON")
	end
end

--关闭某服务日志
function server.closelog(service_name)
	if service_name then
		servercore.command("LOGOFF", service_name)
	else
		servercore.command("LOGOFF")
	end
end

--退出本服务
function server.exit()
	servercore.command("EXIT")
	serverco.yield("QUIT")
end

--向某服务发送数据
function server.send(addr, typename, msg)
	if type(addr) == type("") then
		server.sendname(addr, typename, msg)
	else
		local p = server.protos[typename]
		return servercore.send(addr, p.ptype, 0, p.pack(msg))
	end
end

--根据服务名称发送数据
function server.sendname(addrname, typename, msg)
	local p = server.protos[typename]
	return servercore.send(addrname, p.ptype, 0, p.pack(msg))
end

--向某服务发送数据,指定发送方handleid 和 接收方 handleid
function server.redirect(dest, source, typename, session, msg, sz)
	local p = server.protos[typename]
	return servercore.redirect(dest, source, p.ptype, session, msg, sz)
end

--向某服务请求数据
function server.call(addr, typename, msg)
	local p = server.protos[typename]
	local session = servercore.send(addr, p.ptype, nil, p.pack(msg))
	if session == nil then
		error("call to invalid address " .. server.address(addr))
	end
	return p.unpack(yield_call(addr, session))
end

--服务返回数据给其他服务
function server.ret(addr, session, msg, sz)
	servercore.send(addr, server.ptypes.PTYPE_RESPONSE, session, msg, sz)
end

--创建一个服务
function server.newservice(parm)
	local handleid = servercore.command("LAUNCH", parm)
	return string_to_handle(handleid)
end

--为服务注册名称
function server.register(name)
	return servercore.command("REG", name)
end

--输出信息
function server.error(...)
	local t = {...}
	for i=1,#t do
		t[i] = tostring(t[i])
	end
	return servercore.error(table.concat(t, " "))
end

--获取当前服务消息个数
function server.mqlen()
	return tonumber(servercore.command("MQLEN"))
end

--消息出来分发
local function raw_dispatch_message(ptype, msg, sz, session, source)
	--server.error("raw_dispatch_message......", ptype, session, source, msg, sz)
	--定时器回调(包括普通定时器和sleep后唤醒定时器) 或 RPC返回数据
	if ptype == server.ptypes.PTYPE_RESPONSE then
		local co = session_id_coroutine[session]
		session_id_coroutine[session] = nil
		suspend(co, serverco.resume(co, true, msg, sz))
	--处理协议
	elseif server.protos[ptype] then
		local p = server.protos[ptype]
		local f = p.dispatch
		local ref = watching_service[source]
		if ref then
			watching_service[source] = ref + 1
		else
			watching_service[source] = 1
		end
		local co = co_create(f)
		session_coroutine_id[co] = session
		session_coroutine_address[co] = source
		suspend(co, serverco.resume(co, session, source, p.unpack(msg, sz)))
	--协议未定义
	else
		server.error(string.format("Unknown request (%s): %s", prototype, server.tostring(msg, sz)))
		error(string.format("Unknown session : %d from %x", session, source))
	end
end

--消息处理入口
function server.dispatch_message(...)
	local succ, err = pcall(raw_dispatch_message,...)
	assert(succ, tostring(err))
end

--服务启动调用此函数
function server.start(start_func)
	servercore.callback(server.dispatch_message)--设置消息处理函数
	server.timeout(0, function()
		local ok, err = xpcall(start_func, debug.traceback)
		if not ok then
			server.error("init service failed: " .. tostring(err))
			server.exit()
		end
	end)
end


--主动注册消息事件
server.register_protocol({
	name = "lua",
	ptype = server.ptypes.PTYPE_LOGIC_LUA,
	pack = server.pack,
	unpack = server.unpack,
})
server.register_protocol({
	name = "error",
	ptype = server.ptypes.PTYPE_ERROR,
	unpack = function(msg, sz) return msg end,
	dispatch = _error_dispatch,
})


return server
