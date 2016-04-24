function func_call.s2s_db_query(protomsg)
    assert(DB_OBJ:is_connect())
    local query = protomsg.query
    local escape = protomsg.escape
    local cache = protomsg.cache
    return DB_OBJ:query(query, escape, cache)
end

server.start(function()
    server.register(".db")
    harbor_cache(".db")
    assert(DB_OBJ:connect())

    server.dispatch("lua", function(session, source, params)
        if (params._call) then
            local msg = func_call[params._func](params, session, source)
            server.ret(source, session, server.pack(msg))
        else
            func_call[params._func](params, session, source)
        end
    end)
end)
