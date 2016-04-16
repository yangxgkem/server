local string = string
local table = table
local pairs = pairs

local char_mgr = {}

--[runid]=charObj
char_mgr.CharIdMap = {}

--运行期所有对象的ID分配,不断累加
char_mgr.ObjRuntimeId = 0

--获取一个新的运行id
function char_mgr.NewId()
	char_mgr.ObjRuntimeId = char_mgr.ObjRuntimeId + 1
	local Id = char_mgr.ObjRuntimeId
	return Id
end

--添加对象
function char_mgr.AddCharId(charId, charObj)
	if not charId then 
		_RUNTIME_ERROR("AddCharId id is nil", charObj:GetId(), debug.traceback())
		return 
	end 
	local OldObj = char_mgr.CharIdMap[charId]
	if OldObj then
		_RUNTIME_ERROR("AddCharId add obj twice", charId, debug.traceback())
		return 
	end
	
	char_mgr.CharIdMap[charId] = charObj
end

--根据ID删除对象
function char_mgr.RemoveCharId(charId)
	if not charId then 
		return 
	end
	char_mgr.CharIdMap[charId] = nil
end

--根据ID找出对象
function char_mgr.GetCharById(charId)
	if not charId then 
		return nil 
	end 
	return char_mgr.CharIdMap[charId]
end