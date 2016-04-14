local string=string
local table=table
local pairs=pairs

_G._ImportModule = _G._ImportModule or {}
local _ImportModule = _G._ImportModule

local function LoadFile(PathFile, Type)
	local mod = loadfile(PathFile)()
	if mod then
		if Type == "import" and mod.__init__ then
			mod.__init__()
		elseif Type == "update" and mod.__update__ then
			mod.__update__()
		end
	end
	_ImportModule[PathFile] = mod
	return mod
end

function Import(PathFile)
	if _ImportModule[PathFile] then
		return _ImportModule[PathFile]
	end
	return LoadFile(PathFile, "import")
end

function Update(PathFile)
	if _ImportModule[PathFile] then
		local oldmod = _ImportModule[PathFile]
		CALLOUT.RemoveAll(oldmod)
		_ImportModule[PathFile] = nil
	end
	return LoadFile(PathFile, "update")
end