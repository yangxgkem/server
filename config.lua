local config = {}

--引擎运行的目录
config["root"] = "./"

--分布式id
config["harbor"] = 1

--启动线程数
config["thread"] = 5

--运行日志
config["logger"] = "runtime.log"

--服务日志
config["logpath"] = "logs"

--C服务.so目录
config["cpath"] = config.root.."cservice/?.so"

--lua服务.so目录
config["lua_cpath"] = config.root.."luaclib/?.so"

--lua脚本目录
config["lua_path"] = config.root.."lualib/?.lua;"

--lua引导载入模块
config["bootstrap"] = "snlua bootstrap"

--lua载入首文件
config["lualoader"] = "lualib/loader.lua"

--业务首个服务脚本名
config["start"] = "snlua main"

--服务器监听端口
config["serverport"] = 6001

--港口监听端口
config["harborport"] = 6002

--lua服务文件集合
luaservice = {}
table.insert(luaservice, config.root.."lualib/?.lua")
table.insert(luaservice, config.root.."logic/service/?.lua")
config["luaservice"] = table.concat(luaservice, ";")


return config
