local function fileinfo()
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
	server.error("[RUNTIME]",fileinfo(),msg)
end

function _RUNTIME_ERROR(...)
	local arg = {...}
    for k,v in pairs(arg) do
        arg[k] = tostring(v)
    end
    local msg = table.concat(arg, "\t")
	server.error("[RUNTIME_ERROR]",fileinfo(),msg)
end

function _DEBUG(...)
	local arg = {...}
    for k,v in pairs(arg) do
        arg[k] = tostring(v)
    end
    local msg = table.concat(arg, "\t")
	server.error("[_DEBUG]",fileinfo(),msg)
end
