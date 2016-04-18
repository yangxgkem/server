server = require "server"

server.start(function()
    server.register(".mainservice")
    server.newservice("snlua logic db/db")
    server.newservice("snlua logic socket/socket")
    server.newservice("snlua logic login/login")

    server.newservice("snlua logic test/test")
end)
