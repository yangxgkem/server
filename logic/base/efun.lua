local xpcall = xpcall
local string = string
local type = type
local os = os
local table = table
local tonumber = tonumber
local unpack = unpack
local debug = debug

function TryCall(Func, ...)
	local arg = {...}
	local flag,err = xpcall(function () return Func(unpack(arg)) end , debug.excepthook)
	if not flag then
		_RUNTIME_ERROR("try call err:", err)
	end
	return flag, err
end

function service_logic_send(addr, proto_name, msg)
	msg._func = proto_name
	server.send(addr, "lua", msg)
end

function service_logic_call(addr, proto_name, msg)
	msg._func = proto_name
	msg._call = true
	return server.call(addr, "lua", msg)
end