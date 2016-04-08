dofile("./logic/base/preload.lua")

function test()
	local msg = server.call(".test", "lua", {
		addmsg = "main service",
		funcname = "print",
	})
    _RUNTIME(msg)
end

server.start(function()
	server.register(".mainservice")

    server.newservice("snlua test")
    server.newservice("snlua test_aoi")

	server.timeout(100, test)
end)
