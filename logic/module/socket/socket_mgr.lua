local string = string
local table = table
local pairs = pairs

local socket_mgr = {}

--[reserve_id]=socket
--设置成弱表, 因为 module_mgr 下已经引用了 socket 对象
socket_mgr.socket_id_map = {}
setmetatable(socket_mgr.socket_id_map, {__mode = "v"})


--添加对象
function socket_mgr.add_socket_id(reserve_id, socket_obj)
	if not reserve_id then
		_RUNTIME_ERROR("add_socket_id id is nil", socket_obj:GetId(), debug.traceback())
		return
	end
	local OldObj = socket_mgr.socket_id_map[reserve_id]
	if OldObj then
		_RUNTIME_ERROR("add_socket_id add obj twice", reserve_id, debug.traceback())
		return
	end

	socket_mgr.socket_id_map[reserve_id] = socket_obj
end

--根据ID删除对象
function socket_mgr.remove_socketid(reserve_id)
	if not reserve_id then
		return
	end
	socket_mgr.socket_id_map[reserve_id] = nil
end

--根据ID找出对象
function socket_mgr.get_socket_by_id(reserve_id)
	if not reserve_id then
		return nil
	end
	return socket_mgr.socket_id_map[reserve_id]
end

--注册消息分发
--注册socket消息处理函数
function socket_mgr.dispatch()
	--socket数据
	local function dataf(reserve_id, size, data)
		local socket_obj = socket_mgr.get_socket_by_id(reserve_id)
		assert(socket_obj)
		socket_obj:dataf(reserve_id, size, data)
	end

	--socket连接成功
	local function connectf(reserve_id, _, addr)
		local socket_obj = socket_mgr.get_socket_by_id(reserve_id)
		assert(socket_obj)
		socket_obj:connectf(reserve_id, _, addr)
	end

	--socket关闭
	local function closef(reserve_id)
		local socket_obj = socket_mgr.get_socket_by_id(reserve_id)
		assert(socket_obj)
		socket_obj:closef(reserve_id)
	end

	--有客户端socket连入, 转给 login 服务
	local function acceptf(reserve_id, clientid, clientaddr)
		local socket_obj = socket_mgr.get_socket_by_id(reserve_id)
		assert(socket_obj)
		socket_obj:acceptf(reserve_id, clientid, clientaddr)
	end

	--socket出现错误,此时socket已经被底层关闭
	local function errorf(reserve_id)
		local socket_obj = socket_mgr.get_socket_by_id(reserve_id)
		assert(socket_obj)
		socket_obj:errorf(reserve_id)
	end

	socket.dispatch(dataf, connectf, closef, acceptf, errorf)
end

function socket_mgr.__init__()
	socket_mgr.dispatch()
end

return socket_mgr
