dofile("./logic/base/preload.lua")

--读取参数
local args = {}
for word in string.gmatch(..., "%S+") do
	table.insert(args, word)
end

local filename = string.format("./logic/service/%s.lua", args[1])
local f, msg = loadfile(filename)
if not f then
	error(msg)
end
f(select(2, table.unpack(args)))
