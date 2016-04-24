local table=table
local math=math
local pairs=pairs

server = require "server"
socket = require "socket"
harbor = require "harbor"
cmemory = require "cmemory"
lfs = require "lfs"
pbc = dofile("./3rd/pbc/protobuf.lua")
bson = require "bson"
aoi = require "aoi"
mysql = require "luamysql"

cfgData = dofile("./config.lua")

func_call = {} --网络协议处理


--模块的载入顺序是敏感的
--大家尽量少使用dofile，那是必须全局载入的相对模块
--此Table会被其他模块访问，这些模块不允许被Import
DOFILELIST =
{
    "./logic/base/macros.lua",
    "./logic/common/common_const.lua",
    "./logic/base/class.lua",
    "./logic/base/import.lua",
    "./logic/base/extend.lua",
    "./logic/base/efun.lua",
    "./logic/base/log.lua",
    "./logic/protocol/protocol.lua",
    "./logic/base/global.lua",
}

local function on_start()
    --播下随机种子
    math.randomseed(tostring(os.time()):reverse():sub(1, 6))
    --加载全局模块
    for _,file in pairs(DOFILELIST) do
        dofile(file)
    end
end

on_start()
