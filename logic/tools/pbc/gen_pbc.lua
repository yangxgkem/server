local string = string
local table = table
local os = os
local math = math
local lfs = require "lfs"

local logic_path = "../../"
local protocol_path = logic_path.."protocol/protocol_data.lua"
local proto_conf = logic_path.."common/proto.conf"

local function Touch(PathFile)
	if lfs.attributes(PathFile) then
		return
	end
	local Start = 1
	while 1 do
		local TmpStart, TmpEnd = string.find(PathFile, "%/", Start)
		if TmpStart and TmpEnd then
			local Path = string.sub(PathFile, 1, TmpEnd)
			if not lfs.attributes(Path) then
				lfs.mkdir(Path)
			end
			Start = TmpEnd+1
		else
			break
		end
	end
	if not lfs.attributes(PathFile) then
		local fh = io.open(PathFile, "a+")
		fh:setvbuf("no")
		fh:close()
	end
end

local function GetTmp(File)
	return File..".tmp"
end

local function SaveToFile(File, Data)
	print("save:", File)
	if not lfs.attributes(File) then
		Touch(File)
	end
	local TmpFile = GetTmp(File)
	local fh = io.open(TmpFile, "w+") 
	fh:setvbuf("no")
	fh:write(Data)
	fh:close()
	os.rename(TmpFile, File)
end

function regist_all_pb(proto_path)
	local proto_path = proto_path or "../../logic/protocol/pbc"
	for v in lfs.dir(proto_path) do
		if v ~= "." and v ~= ".." and v ~= ".svn" then
			local TmpPath = proto_path.."/"..v
			local attr = lfs.attributes(TmpPath)
			if attr.mode == "directory" then
				regist_all_pb(TmpPath)
			elseif attr.mode == "file" then
				if string.match(v, "%.pb$") then
					PBC.register_file(TmpPath)
				end
			end
		end
	end
end

local function Serialize(Object)
	local function ConvSimpleType(v)
		if type(v)=="string" then
			return string.format("%q",v)
		end
		return tostring(v)
	end

	local function RealFun(Object, Depth)
		--TODO: gxzou 循环引用没有处理？
		Depth = Depth or 0
		Depth = Depth + 1
		assert(Depth<20, "too long Depth to serialize")

		if type(Object) == 'table' then
			--if Object.__ClassType then return "<Object>" end
			local Ret = {}
			table.insert(Ret,'{\n')
			for k, v in pairs(Object) do
				--print ("serialize:", k, v)
				local _k = ConvSimpleType(k)
				if _k == nil then
					error("key type error: "..type(k))
				end
				table.insert(Ret,'[' .. _k .. ']')
				table.insert(Ret,'=')
				table.insert(Ret,RealFun(v, Depth))
				table.insert(Ret,',\n')
			end
			table.insert(Ret,'\n}')
			return table.concat(Ret)
		else
			return ConvSimpleType(Object)
		end
	end
	
	return RealFun(Object)
end

local ProtoList = {}
local ProtoId = 0
local ProtoStr = ""
function CheckProtocData(PathName, DirPath)
	PathName = PathName or (logic_path.."common")
	DirPath = DirPath or "proto"
	local Path = PathName .. "/" .. DirPath
	for FileName in lfs.dir(Path) do
		if ((FileName ~= ".") and (FileName ~= "..")) then
			local oldDirPath = DirPath
			local DirPath = DirPath.."/"..FileName
			local ListFilePath = PathName .. "/" .. DirPath
			local attr = lfs.attributes(ListFilePath)
			if attr.mode == "directory" then
				CheckProtocData(PathName, DirPath) 
			elseif attr.mode == "file" then
				if string.find(ListFilePath, ".proto") then
					local fd, err = io.open(ListFilePath, "r")
					if not fd then	return nil end
					fd:setvbuf("no")
					for data in fd:lines() do
					  if string.find(data, "message") then
						local s,e = string.find(data, "{")
						data = string.sub(data, 1, s)
						s,e = string.find(data, "message")
						data = string.sub(data, e+1, -1)
						data = string.gsub(data, "[%s{]", "")
						s,e = string.find(DirPath, ".proto")
						local filename = string.sub(DirPath, 1, s)
						s,e = string.find(filename, "proto/")
						filename = string.sub(filename, e+1, -1)
						if not ProtoList[data] then
							ProtoId=ProtoId+1
							ProtoList[ProtoId] = data
							ProtoList[data] = ProtoId
							ProtoStr = string.format("%s%s,%s%s\n", ProtoStr, ProtoId, filename, data)
						end
					  end
					end
				end
			end
		end
	end
end

function GenProtocData()
	local genall = false
	local fd = io.open(protocol_path, "r")
	local fd2 = io.open(proto_conf, "r")
	if fd and fd2 then
		local Data = fd:read("*a")
		loadstring(Data)()
		ProtoList = PROTOCL_INFO
		for _key,_value in pairs(ProtoList) do
			if type(_key)==type(0) and _key>ProtoId then
				ProtoId = _key
			end
		end
		local protonum = 0
		for data in fd2:lines() do
			if string.len(data)>3 then
				protonum=protonum+1
				ProtoStr = ProtoStr..data.."\n"
			end
		end
		if protonum ~= ProtoId then
			ProtoList = {}
			ProtoId = 0
			ProtoStr = ""
			genall = true
		end
	else
		genall = true
	end
	if fd then fd:close() end
	if fd2 then fd2:close() end
	CheckProtocData()
	if genall then
		print("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@gen pbc all@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@")
	else
		print("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@gen pbc Increment@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@")
	end
end

GenProtocData()
SaveToFile(proto_conf, ProtoStr)
local ProtoDataStr = string.format("PROTOCL_INFO = \n%s\n", Serialize(ProtoList))
SaveToFile(protocol_path, ProtoDataStr)
print("gen lua pbc ok!!!")
local cpmailCmd = string.format("sh gen_proto_pb.sh")
os.execute(cpmailCmd)
print("gen proto pbc ok!!!")