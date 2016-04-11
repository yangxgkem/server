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

local function  demo2()
    local space = aoi.create(1000, 1024, 1024)
    local objs = {}
    for i=1,1000 do
        local x = math.random(1,1024)
        local y = math.random(1,1024)
        aoi.update(space, i, "wm", x, y, 0)
        objs[i] = {x,y}
    end
    local data = aoi.message(space)
    for i=1,data.num do
        local w = data[i].w
        local m = data[i].m
        print(string.format("w(%s)=>(%s,%s) , m(%s)=>(%s,%s)", w, objs[w][1], objs[w][2], m, objs[m][1], objs[m][2]))
    end
    print(string.format("num:%s, begin_time:%s, end_time:%s, time:%s", 
        data.num, data.begin_time, data.end_time, (data.end_time-data.begin_time)/1000))
end

server.start(function()
	server.register(".test_aoi")
    demo2()

    server.dispatch("lua", function(session, source, params)
        local funcname = params.funcname
        local msg = test[funcname](params, source)
        server.ret(source, session, server.pack(msg))
    end)

end)
