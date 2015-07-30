local tostring = tostring
local tonumber = tonumber
local assert = assert
local pairs = pairs
local pcall = pcall
local servercore = require "server.core"

local server = {}
server.timeoutFuncs = {} --定时器函数
server.callFuncs = {} --向其他服务请求数据回调函数
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
	session = tonumber(session)
	server.timeoutFuncs[session] = func
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

--退出本服务
function server.exit()
	servercore.command("EXIT")
end

--向某服务发送数据
function server.send(addr, typename, msg, sz)
	local p = server.protos[typename]
	return servercore.send(addr, p.ptype, 0 , msg, sz)
end

--根据服务名称发送数据
function server.sendname(addrname, typename, msg, sz)
	local p = server.protos[typename]
	if not server.serviceNameCache[addrname] then
		server.serviceNameCache[addrname] = server.localname(addrname)
	end
	return servercore.send(server.serviceNameCache[addrname] or addrname, p.ptype, 0 , msg, sz)
end

--向某服务发送数据,指定发送方handleid 和 接收方 handleid
function server.redirect(dest, source, typename, session, msg, sz)
	local p = server.protos[typename]
	return servercore.redirect(dest, source, p.ptype, session, msg, sz)
end

--向某服务请求数据
function server.call(addr, typename, msg, sz, func)
	local p = server.protos[typename]
	local session = servercore.send(addr, p.ptype, nil, msg, sz)
	if session == nil then
		error("call to invalid address " .. server.address(addr))
	end
	session = tonumber(session)
	server.callFuncs[session] = {typename, func}
	return session
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
	--server.error(ptype, msg, sz, session, source)
	if server.protos[ptype] then
		local p = server.protos[ptype]
		p.dispatch(msg, sz, session, source)
	elseif ptype == server.ptypes.PTYPE_TEXT then
		server.error(ptype, msg, sz, session, source)
	elseif ptype == server.ptypes.PTYPE_RESPONSE then
		--定时器
		local func = server.timeoutFuncs[session]
		if func then
			func()
			server.timeoutFuncs[session] = nil
			return
		end
		--获取服务消息回调
		func = server.callFuncs[session]
		if func then
			local p = server.protos[(func[1])]
			p.dispatch(msg, sz, session, source, func[2])
			server.callFuncs[session] = nil
		end
		server.error(string.format("Unknown session : %d from %x", session, source))
	else
		server.error(string.format("Has Not protos:%s, session : %d from %x", ptype, session, source))
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
	name = "socket",
	ptype = server.ptypes.PTYPE_SOCKET,
})
server.register_protocol({
	name = "lua",
	ptype = server.ptypes.PTYPE_LOGIC_LUA,
})
server.register_protocol({
	name = "error",
	ptype = server.ptypes.PTYPE_ERROR,
})
server.register_protocol({
	name = "harbor",
	ptype = server.ptypes.PTYPE_HARBOR,
})


return server