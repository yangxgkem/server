server = require "server"


server.start(function()
	server.register(".mainservice")
	server.newservice("snlua logic mysql/mysql")
    server.newservice("snlua logic socket/socket")
    server.newservice("snlua logic login/login")
end)