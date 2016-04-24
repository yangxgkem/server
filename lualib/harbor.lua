local harborcore = require "harbor.core"
local server = require "server"


local harbor = {}

function harbor.start()
	return harborcore.start()
end

function harbor.unpack(msg)
	return harborcore.unpack(msg)
end

server.register_protocol({
    name = "harbor",
    ptype = server.ptypes.PTYPE_HARBOR,
    unpack = harbor.unpack,
})

return harbor
