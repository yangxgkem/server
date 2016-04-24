SocketServerObj = clsSocketServer:new()

function func_call.s2s_socket_agent_id(protomsg)
    return SocketServerObj:get_agent_id()
end

server.start(function()
	server.register(".socket")
    harbor_cache(".socket")

	server.dispatch("lua", function(session, source, params)
        if (params._call) then
        	local msg = func_call[params._func](params, session, source)
            server.ret(source, session, server.pack(msg))
        else
        	func_call[params._func](params, session, source)
        end
    end)

	SocketServerObj:create_agent_slot()
	SocketServerObj:listen("0.0.0.0", cfgData.serverport, nil)
end)
