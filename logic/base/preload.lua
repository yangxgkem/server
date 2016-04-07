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

cfgData = dofile("./config.lua")

func_call = {} --协议处理


--模块的载入顺序是敏感的
--大家尽量少使用dofile，那是必须全局载入的相对模块
--此Table会被其他模块访问，这些模块不允许被Import
DOFILELIST =
{
	"./logic/base/macros.lua",
	"./logic/base/class.lua",
	"./logic/base/import.lua",
	"./logic/base/extend.lua",
	"./logic/base/efun.lua",
	"./logic/base/time.lua",
	"./logic/base/log.lua",
	"./logic/protocol/protocol.lua",
	"./logic/base/global.lua",
}

local function OnStart()
	--播下随机种子
	math.randomseed(tostring(os.time()):reverse():sub(1, 6))
end

local function do_preload()
	for _,file in pairs(DOFILELIST) do
		dofile(file)
	end
end

function perform_gc()
	collectgarbage("step", 512)
	server.timeout(500, perform_gc)
end

OnStart()
do_preload()
perform_gc()
