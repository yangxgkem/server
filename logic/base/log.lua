local function FileInfo()
	local dinfo = debug.getinfo(3, 'Sl')
	local CallFile = dinfo.short_src
	local CurLine = dinfo.currentline
	return CallFile.." line:"..CurLine
end

function _RUNTIME(...)
	local arg = {...}
    for k,v in pairs(arg) do
        arg[k] = tostring(v)
    end
    local msg = table.concat(arg, "\t")
	local TimeStr = string.format("[%s]", os.date("%F %T", os.time()))
	server.error("[RUNTIME]",TimeStr,FileInfo(),msg,"\n")
end

function _RUNTIME_ERROR(...)
	local arg = {...}
    for k,v in pairs(arg) do
        arg[k] = tostring(v)
    end
    local msg = table.concat(arg, "\t")
	local TimeStr = string.format("[%s]", os.date("%F %T", os.time()))
	server.error("[RUNTIME_ERROR]",TimeStr,FileInfo(),msg,"\n")
end

function _DEBUG(...)
	local arg = {...}
    for k,v in pairs(arg) do
        arg[k] = tostring(v)
    end
    local msg = table.concat(arg, "\t")
	local TimeStr = string.format("[%s]", os.date("%F %T", os.time()))
	server.error("[_DEBUG]",TimeStr,FileInfo(),msg,"\n")
end
