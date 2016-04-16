local string = string
local table = table
local pairs = pairs

local module_mgr = {}

--[runid]=moduleObj
module_mgr.ModuleIdMap = {}

--运行期所有对象的ID分配,不断累加
module_mgr.ObjRuntimeId = 0

--获取一个新的运行id
function module_mgr.NewId()
	module_mgr.ObjRuntimeId = module_mgr.ObjRuntimeId + 1
	local Id = module_mgr.ObjRuntimeId
	return Id
end

--添加对象
function module_mgr.AddModuleId(moduleId, moduleObj)
	if not moduleId then 
		_RUNTIME_ERROR("AddCharId id is nil", moduleObj:GetId(), debug.traceback())
		return 
	end 
	local OldObj = module_mgr.ModuleIdMap[moduleId]
	if OldObj then
		_RUNTIME_ERROR("AddCharId add obj twice", moduleId, debug.traceback())
		return 
	end
	
	module_mgr.ModuleIdMap[moduleId] = moduleObj
end

--根据ID删除对象
function module_mgr.RemoveCharId(moduleId)
	if not moduleId then 
		return 
	end
	module_mgr.ModuleIdMap[moduleId] = nil
end

--根据ID找出对象
function module_mgr.GetCharById(moduleId)
	if not moduleId then 
		return nil 
	end 
	return module_mgr.ModuleIdMap[moduleId]
end

return module_mgr