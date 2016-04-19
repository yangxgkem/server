local string = string
local table = table
local pairs = pairs

local char_mgr = {}

--[runid]=char_obj
char_mgr.char_id_map = {}

--[uid]=user_obj
char_mgr.uid_map = {}
setmetatable(char_mgr.uid_map, {__mode = "v"})

--运行期所有对象的ID分配,不断累加
char_mgr.obj_runtime_id = 0

--获取一个新的运行id
function char_mgr.newid()
	char_mgr.obj_runtime_id = char_mgr.obj_runtime_id + 1
	local id = char_mgr.obj_runtime_id
	return id
end

--添加对象
function char_mgr.add_charid(charid, char_obj)
	if not charid then
		_RUNTIME_ERROR("add_charid id is nil", char_obj:get_id(), debug.traceback())
		return
	end
	local oldobj = char_mgr.char_id_map[charid]
	if oldobj then
		_RUNTIME_ERROR("add_charid add obj twice", charid, debug.traceback())
		return
	end

	char_mgr.char_id_map[charid] = char_obj
end

--根据ID删除对象
function char_mgr.remove_charid(charid)
	if not charid then
		return
	end
	local char_obj = char_mgr.char_id_map[charid]
	if char_obj and char_obj:is_user() then
		char_obj.uid_map[char_obj:get_uid()] = nil
	end
	char_mgr.char_id_map[charid] = nil
end

--根据ID找出对象
function char_mgr.get_char_by_id(charid)
	if not charid then
		return nil
	end
	return char_mgr.char_id_map[charid]
end

--添加Uid玩家对象
function char_mgr.add_uid(uid, user_obj)
	if not uid then
		return
	end
	char_mgr.uid_map[uid] = user_obj
end

--通过UID找玩家
function char_mgr.get_user_by_uid(uid)
	if not uid then
		return nil
	end
	return char_mgr.uid_map[uid]
end

return char_mgr
