SocketServerObj = clsSocketServer:New()

--定时检查agent池
local function time_check_agent()
	SocketServerObj:check_agent_slot()
	server.timeout(100, time_check_agent)
end

function func_call.s2s_socket_agent_id(protomsg)
    return SocketServerObj:get_agent_id()
end

server.start(function()
	server.register(".socket")

	server.dispatch("lua", function(session, source, params)
        if (params._call) then
        	local msg = func_call[params._func](params, session, source)
            server.ret(source, session, server.pack(msg))
        else
        	func_call[params._func](params, session, source)
        end
    end)

	time_check_agent()
	SocketServerObj:listen("0.0.0.0", cfgData.serverport, nil)
end)
