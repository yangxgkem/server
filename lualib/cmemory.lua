local server = require "server"
local memory = require "memory"

local cmemory = {}

function cmemory.dumpinfo()
	memory.dump()
	server.error("Total memory:", memory.total())
	server.error("Total block:", memory.block())
end

return cmemory