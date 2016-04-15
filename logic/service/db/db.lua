DbObj = clsDb:New()

server.start(function()
	server.register(".db")
	assert(DbObj:connect())

	server.dispatch("lua", function(session, source, params)
        if (params._call) then
        	local msg = DbObj[params._func](DbObj, params)
        	server.ret(source, session, server.pack(msg))
        else
        	DbObj[params._func](DbObj, params)
        end
    end)
end)