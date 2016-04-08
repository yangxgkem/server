dofile("./logic/base/preload.lua")
aoi = require "aoi"

local test = {}

local function demo()
    -- 创建场景与实体
    local spacelist = {}
    for i=1,10 do
        spacelist[i] = aoi.create(1000+i, 1024, 1024)
        for ii=1,1000 do
            local x = math.random(1,1000)
            local y = math.random(1,1000)
            aoi.update(spacelist[i], ii, "wm", x, y, 0)
        end
        aoi.message(spacelist[i])
    end
    server.sleep(100)
    print("begin aoi perf")
    -- 开始进行测试
    for i=1,10 do
        local id,x,y
        for ii=1,100 do
            id = math.random(1,1000)
            x = math.random(1,1000)
            y = math.random(1,1000)
            aoi.update(spacelist[i], id, "wm", x, y, 0)
        end
        local data = aoi.message(spacelist[i])
        for iii=1,data.num do
            if iii == data.num then
                print(data[iii].m)
            end
        end
        print((data.end_time - data.begin_time)/1000000, data.num)
    end

end

server.start(function()
	server.register(".test_aoi")
    demo()

    server.dispatch("lua", function(session, source, params)
        local funcname = params.funcname
        local msg = test[funcname](params, source)
        server.ret(source, session, server.pack(msg))
    end)

end)
