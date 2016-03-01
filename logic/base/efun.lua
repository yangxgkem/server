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