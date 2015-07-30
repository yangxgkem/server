local server = require "server"
local socket = require "socket"
local cmemory = require "cmemory"

server.start(function()
	local startService = server.getenv("start")
	local id = pcall(server.newservice(startService))
	server.exit()
end)
