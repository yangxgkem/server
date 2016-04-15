MysqlObj = clsMysql:New()

server.start(function()
	server.register(".mysql")
	assert(MysqlObj:connect())

	server.dispatch("lua", function(session, source, params)
        if (params._call) then
        	local msg = MysqlObj[params._func](MysqlObj, params)
        	server.ret(source, session, server.pack(msg))
        else
        	MysqlObj[params._func](MysqlObj, params)
        end
    end)
end)