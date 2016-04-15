SocketObj = clsSocket:New()

--定时检查agent池
local function time_check_agent()
	SocketObj:check_agent_slot()
	server.timeout(100, time_check_agent)
end

server.start(function()
	server.register(".socket")
	SocketObj:dispatch()

	server.dispatch("lua", function(session, source, params)
        if (params._call) then
        	local msg = SocketObj[params._func](SocketObj, params)
        	server.ret(source, session, server.pack(msg))
        else
        	SocketObj[params._func](SocketObj, params)
        end
    end)

	time_check_agent()
	SocketObj:listen("0.0.0.0", cfgData.serverport, nil)
end)