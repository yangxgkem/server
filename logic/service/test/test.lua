function demo()
    local clientObj = clsSocketClient:New()
    clientObj:on_connect("127.0.0.1", 6001)
end

server.start(function()
	server.register(".test")
    server.timeout(500, demo)
end)
