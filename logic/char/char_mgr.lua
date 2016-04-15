local string = string
local table = table
local pairs = pairs

local CHAR_MGR = {}

CHAR_MGR.CharIdMap = {} --[runid]=charObj

ObjRuntimeId = 0 --运行期所有对象的ID分配,不断累加

--获取一个新的运行id
function NewId()
	ObjRuntimeId = ObjRuntimeId + 1
	local Id = ObjRuntimeId
	return Id
end

--添加对象
function AddCharId(charId, charObj)
	if not charId then 
		_RUNTIME_ERROR("AddCharId id is nil", charObj:GetId(), debug.traceback())
		return 
	end 
	local OldObj = CharIdMap[charId]
	if OldObj then
		_RUNTIME_ERROR("AddCharId add obj twice", charId, debug.traceback())
		return 
	end
	
	CharIdMap[charId] = charObj
end

--根据ID删除对象
function RemoveCharId(charId)
	if not charId then 
		return 
	end
	CharIdMap[charId] = nil
end

--根据ID找出对象
function GetCharById(charId)
	if not charId then 
		return nil 
	end 
	return CharIdMap[charId]
end