server.start(function()
    server.register(".login")

    server.dispatch("lua", function(session, source, params)
        if (params._call) then
            local msg = func_call[params._func](params, session, source)
            server.ret(source, session, server.pack(msg))
        else
            func_call[params._func](params, session, source)
        end
    end)
end)
