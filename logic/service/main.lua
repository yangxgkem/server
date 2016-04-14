server = require "server"

server.start(function()
	server.register(".mainservice")
    server.newservice("snlua logic logicsocket/logicsocket")
end)
