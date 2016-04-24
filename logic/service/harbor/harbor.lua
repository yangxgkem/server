SocketHarborObj = clsSocketHarbor:new()

server.start(function()
    server.register(".harbor")
    harbor.start()

    server.dispatch("lua", function(session, source, params)
        if (params._call) then
            local msg = func_call[params._func](params, session, source)
            server.ret(source, session, server.pack(msg))
        else
            func_call[params._func](params, session, source)
        end
    end)

    --把本地服务消息转发到其他港口服务
    server.dispatch("harbor", function(session, source, handle, typename, params, psz)
        HARBOR.send(session, source, handle, typename, params, psz)
    end)

    SocketHarborObj:listen("0.0.0.0", cfgData.harborport, nil)
    HARBOR.check_send_cache()
end)
