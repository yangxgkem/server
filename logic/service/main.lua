dofile("./logic/base/preload.lua")

function test()
	local msg,sz = server.call(".test", "lua", server.pack({
		cmd = "socket",
		funcname = "print",
	}))
    local params = server.unpack(msg, sz)
    _RUNTIME(params)
end

server.start(function()
	server.register(".mainservice")

    server.newservice("snlua test")

	server.timeout(300, test)
end)
