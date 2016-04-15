LoginObj = clsLogin:New()

server.start(function()
	server.register(".login")
	LoginObj:dispatch()

	server.dispatch("lua", function(session, source, params)
        if (params._call) then
        	local msg = LoginObj[params._func](LoginObj, params)
        	server.ret(source, session, server.pack(msg))
        else
        	LoginObj[params._func](LoginObj, params)
        end
    end)
end)