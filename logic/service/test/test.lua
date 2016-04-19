function func_call.s2c_user_enter_info(vfd, protomsg)
    _RUNTIME(vfd)
    table.dump(protomsg)
end

function demo()
    local client_obj = clsSocketClient:new()
    client_obj:on_connect("127.0.0.1", 6001)

    local protoinfo = {}
    protoinfo.account = "hehege"
    protoinfo.passwd = "123456"
    pbc_send_msg(client_obj.reserve_id, "c2s_login_corp_account", protoinfo)
end

server.start(function()
	server.register(".test")
    server.timeout(300, demo)
end)
