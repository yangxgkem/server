dofile("./logic/base/preload.lua")

function test()
	local msg = server.call(".test", "lua", {
		addmsg = "main service",
		_func = "print",
		_call = true,
	})
    _RUNTIME(msg)
end

server.start(function()
	server.register(".mainservice")

    --server.newservice("snlua test")
    --server.timeout(100, test)
    --server.newservice("snlua test_aoi")
    --server.newservice("snlua test_mysql")
    server.newservice("snlua logicsocket")
	
end)
