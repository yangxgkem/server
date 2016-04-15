SocketAgentObj = clsSocketAgent:New()

server.start(function()
	SocketAgentObj:dispatch()
	server.dispatch("lua", function(session, source, params)
		if (params._call) then
        	local msg = SocketAgentObj[params._func](SocketAgentObj, params)
        	server.ret(source, session, server.pack(msg))
        else
        	SocketAgentObj[params._func](SocketAgentObj, params)
        end
	end)
end)