dofile("./logic/base/preload.lua")

function test()
	server.sendname("#db", "lua", server.pack({
		cmd = "socket",
		funcname = "checkpbc",
	}))
	server.timeout(300, test)
end

server.start(function()
	server.register(".mainservice")
	--分布式服务
	server.newservice("snlua distribute")
	--网关服务
	server.newservice("snlua logicsocket")

	--server.timeout(300, test)
end)