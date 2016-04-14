dofile("./logic/base/preload.lua")
mysql = require "luamysql"

local test_mysql = {}

function demo()
    local dbarg = {
        host = "127.0.0.1", -- required
        port = 3306, -- required
        user = "root", -- optional
        password = "root", -- optional
        db = "test", -- optional
    }
    local client,errmsg = mysql.newclient(dbarg)
    mysql.setcharset(client, "utf8")
    mysql.selectdb(client, "test")
    local ret,errmsg = mysql.query(client, "select * from item")
    print(ret, errmsg)
    print(mysql.size(client))
    for k,v in pairs(mysql.fieldnamelist(client)) do
        print(k,v)
    end
    for k,v in pairs(mysql.record_list(client)) do
        print(k,v[1],v[2])
    end
    mysql.gc_result(client)
    local ret,errmsg = mysql.query(client, "select * from item")
    print(ret, errmsg)
end

server.start(function()
	server.register(".test_mysql")

	demo()

    server.dispatch("lua", function(session, source, params)
        local funcname = params.funcname
        local msg = test_mysql[funcname](params, source)
        server.ret(source, session, server.pack(msg))
    end)
end)
