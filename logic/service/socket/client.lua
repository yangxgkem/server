SocketClientObj = clsSocketClient:New()

server.start(function()
	server.dispatch("lua", function(session, source, params)
        if (params._call) then
        	local msg = SocketClientObj[params._func](SocketClientObj, params)
        	server.ret(source, session, server.pack(msg))
        else
        	SocketClientObj[params._func](SocketClientObj, params)
        end
    end)
end)