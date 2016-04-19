local string = string
local table = table
local pairs = pairs

local module_mgr = {}

--[runid]=module_obj
module_mgr.module_id_map = {}

--运行期所有对象的ID分配,不断累加
module_mgr.obj_runtime_id = 0

--获取一个新的运行id
function module_mgr.newid()
	module_mgr.obj_runtime_id = module_mgr.obj_runtime_id + 1
	local id = module_mgr.obj_runtime_id
	return id
end

--添加对象
function module_mgr.add_module_id(moduleid, module_obj)
	if not moduleid then
		_RUNTIME_ERROR("add_module_id id is nil", module_obj:get_id(), debug.traceback())
		return
	end
	local oldobj = module_mgr.module_id_map[moduleid]
	if oldobj then
		_RUNTIME_ERROR("add_module_id add obj twice", moduleid, debug.traceback())
		return
	end

	module_mgr.module_id_map[moduleid] = module_obj
end

--根据ID删除对象
function module_mgr.remove_module_id(moduleid)
	if not moduleid then
		return
	end
	module_mgr.module_id_map[moduleid] = nil
end

--根据ID找出对象
function module_mgr.get_module_by_id(moduleid)
	if not moduleid then
		return nil
	end
	return module_mgr.module_id_map[moduleid]
end

return module_mgr
