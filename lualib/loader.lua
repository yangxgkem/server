--读取参数
local args = {}
for word in string.gmatch(..., "%S+") do
	table.insert(args, word)
end
SERVICE_NAME = args[1]

--读取服务启动首次加载脚本
local main, pattern
local err = {}
for pat in string.gmatch(LUA_SERVICE, "([^;]+);*") do
	local filename = string.gsub(pat, "?", SERVICE_NAME)
	local f, msg = loadfile(filename)--加载脚本返回chunk,但不执行
	if not f then
		table.insert(err, msg)
	else
		pattern = pat
		main = f
		break
	end
end
if not main then
	error(table.concat(err, "\n"))
end

--设置配置
package.path = LUA_PATH
package.cpath = LUA_CPATH

local service_path = string.match(pattern, "(.*/)[^/?]+$")
if service_path then
	service_path = string.gsub(service_path, "?", args[1])
	package.path = service_path .. "?.lua;" .. package.path
end

--执行首次脚本
main(select(2, table.unpack(args)))