function demo()
    local clientObj = clsSocketClient:New()
    clientObj:on_connect("127.0.0.1", 6001)

    local protoinfo = {}
    protoinfo.account = "hehege"
    protoinfo.passwd = "123456"
    pbc_send_msg(clientObj.reserve_id, "c2s_login_corp_account", protoinfo)
end

server.start(function()
	server.register(".test")
    server.timeout(300, demo)
end)
