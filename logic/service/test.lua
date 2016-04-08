dofile("./logic/base/preload.lua")

local test = {}

function test.print(params, source)
    return "hello " .. params.addmsg
end

server.start(function()
	server.register(".test")

    server.dispatch("lua", function(session, source, params)
        local funcname = params.funcname
        local msg = test[funcname](params, source)
        server.ret(source, session, server.pack(msg))
    end)
end)
