dofile("./logic/base/preload.lua")

local test = {}

function test.print(params)
    return "hello " .. params.addmsg
end

server.start(function()
	server.register(".test")

    server.dispatch("lua", function(session, source, params)
        if (params._call) then
        	local msg = test[params._func](params)
        	server.ret(source, session, server.pack(msg))
        else
        	test[params._func](params)
        end
    end)
end)
