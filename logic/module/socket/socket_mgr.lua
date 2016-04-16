local string = string
local table = table
local pairs = pairs

local socket_mgr = {}

--[reserve_id]=socket
socket_mgr.SocketIdMap = {}

--设置成弱表, 因为 module_mgr 下已经引用了 socket 对象
setmetatable(socket_mgr.SocketIdMap, {__mode = "v"})


--添加对象
function socket_mgr.AddSocketId(reserve_id, socketObj)
	if not reserve_id then 
		_RUNTIME_ERROR("AddCharId id is nil", socketObj:GetId(), debug.traceback())
		return 
	end 
	local OldObj = socket_mgr.SocketIdMap[reserve_id]
	if OldObj then
		_RUNTIME_ERROR("AddCharId add obj twice", reserve_id, debug.traceback())
		return 
	end
	
	socket_mgr.SocketIdMap[reserve_id] = socketObj
end

--根据ID删除对象
function socket_mgr.RemoveCharId(reserve_id)
	if not reserve_id then 
		return 
	end
	socket_mgr.SocketIdMap[reserve_id] = nil
end

--根据ID找出对象
function socket_mgr.GetSocketById(reserve_id)
	if not reserve_id then 
		return nil 
	end 
	return socket_mgr.SocketIdMap[reserve_id]
end

--注册消息分发
--注册socket消息处理函数
function socket_mgr.Dispatch()
	--socket数据
	local function dataf(reserve_id, size, data)
		local socketObj = socket_mgr.GetSocketById(reserve_id)
		assert(socketObj)
		socketObj:dataf(reserve_id, size, data)
	end

	--socket连接成功
	local function connectf(reserve_id, _, addr)
		local socketObj = socket_mgr.GetSocketById(reserve_id)
		assert(socketObj)
		socketObj:connectf(reserve_id, _, addr)
	end

	--socket关闭
	local function closef(reserve_id)
		local socketObj = socket_mgr.GetSocketById(reserve_id)
		assert(socketObj)
		socketObj:closef(reserve_id)
	end

	--有客户端socket连入, 转给 login 服务
	local function acceptf(reserve_id, clientid, clientaddr)
		local socketObj = socket_mgr.GetSocketById(reserve_id)
		assert(socketObj)
		socketObj:acceptf(reserve_id, clientid, clientaddr)
	end
	
	--socket出现错误,此时socket已经被底层关闭
	local function errorf(reserve_id)
		local socketObj = socket_mgr.GetSocketById(reserve_id)
		assert(socketObj)
		socketObj:errorf(reserve_id)
	end

	socket.dispatch(dataf, connectf, closef, acceptf, errorf)
end

function socket_mgr.__init__()
	socket_mgr.Dispatch()
end

return socket_mgr