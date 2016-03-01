dofile("./logic/base/preload.lua")

local test = {}

function test.print(params, source)
    return "hello"
end

server.start(function()
	server.register("#test")

    server.dispatch("lua", function(msg, sz, session, source)
        local params = server.unpack(msg, sz)
        local funcname = params.funcname
        local msg = test[funcname](params, source)
        server.ret(source, session, server.pack(msg))
    end)

end)
