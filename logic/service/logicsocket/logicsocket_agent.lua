dofile("./logic/base/preload.lua")

local MaxReadDataSize = 65535 --最大读取数据大小

local AGENT = {}
AGENT.clients = {} --客户端列表
AGENT.cmds = {} --消息函数

function pbc_send_msg(reserve_ids, proto_name, tbldata, islsend)
	local proto_id = GET_PROTOID(proto_name)
	if not proto_id then return end
	local proto_data = pbc.encode(proto_name, tbldata)
	if not proto_data then return end
	local proto_data_length = string.len(proto_data)
	local pack_data = string.pack("<I4I2",proto_data_length,proto_id)..proto_data
	local send = params.lsend and socket.lsend or socket.send
	for _,_rid in pairs(reserve_ids) do
		send(_rid, pack_data)
	end
end

--给业务服务发送处理数据
local function sendprotobuf(id)
	local client = AGENT.clients[id]
	local msg = string.sub(client.readdata, 1, client.current_size)
	client.readdata = string.sub(client.readdata, client.current_size+1)
	client.readsize = client.readsize - client.current_size
	assert(#client.readdata == client.readsize)
	local current_pid = client.current_pid
	client.current_pid = 0
	client.current_size = 0

	--把数据转发给服务处理
	local service_name = GET_PROTOID_SERVICE(current_pid)
	if service_name then
		server.sendname(service_name, "lua", server.pack({
			funcname = "checkpbc",
			reserve_id = client.reserve_id,
			proto_id = current_pid,
			proto_data = msg,
		}))
	else
		AGENT.checkpbc(id, current_pid, msg)
	end
end

--注册socket消息处理函数
function AGENT.dispatch()
	--socket数据 4+2+data
	local function dataf(id, size, data)
		assert(AGENT.clients[id])
		local client = AGENT.clients[id]
		client.readdata = client.readdata .. data
		client.readsize = client.readsize + size
		assert(#client.readdata == client.readsize)

		if client.current_pid>0 and client.readsize>=client.current_size then
			sendprotobuf(id)
			return
		end

		if client.readsize<6 then return end
		client.current_size = string.unpack("<I4", string.sub(client.readdata, 1, 4)) --data数据大小
		if client.current_size>=MaxReadDataSize then
			socket.close(id) --数据有误主动关闭socket
			server.error("logic client read over size:", id, client.addr, client.current_size)
			return
		end
		client.current_pid = string.unpack("<I2", string.sub(client.readdata, 5, 6)) --protobuf id
		client.readdata = string.sub(client.readdata, 7)
		client.readsize = client.readsize - 6

		if client.current_size<=client.readsize then
			sendprotobuf(id)
			return
		end
	end

	--socket连接成功
	local function connectf(id, _, addr)
		assert(AGENT.clients[id])
		AGENT.clients[id].connect = true
	end

	--socket关闭
	local function closef(id)
		assert(AGENT.clients[id])
		AGENT.sendclientclose(id)
		AGENT.clients[id] = nil
	end
	
	--socket出现错误,此时socket已经被底层关闭
	local function errorf(id)
		assert(AGENT.clients[id])
		AGENT.sendclientclose(id)
		AGENT.clients[id] = nil
	end

	socket.dispatch(dataf, connectf, closef, nil, errorf)
end

--通知其他业务服务删除了客户端
function AGENT.sendclientclose(reserve_id)
	--通知其他服务
	local params = {
		funcname = "clientclose",
		reserve_id = reserve_id,
	}
	server.sendname(".logicsocket", "lua", server.pack(params))
end

--客户端连入服务器
function AGENT.cmds.accept(params, source)
	local reserve_id = params.reserve_id
	assert(not AGENT.clients[reserve_id])
	
	local data = {}
	data.readdata = "" --读取到的数据
	data.readsize = 0 --读取到数据大小
	data.current_size = 0 --当前解包数据大小
	data.current_pid = 0 --当前解包protobuf id
	data.connect = false --是否已连接成功
	data.addr = params.addr --客户端地址
	data.reserve_id = reserve_id --客户端reserve_id
	AGENT.clients[reserve_id] = data
	
	socket.start(reserve_id)
end

--发送数据
function AGENT.cmds.send(params, source)
	local reserve_ids = params.reserve_ids
	local data = params.data
	local send = params.lsend and socket.lsend or socket.send
	for _,_rid in pairs(reserve_ids) do
		send(_rid, data)
	end
end

--解析处理pbc数据
function AGENT.checkpbc(reserve_id, proto_id, proto_data)
	assert(AGENT.clients[reserve_id])
	local proto_name = GET_PROTO_NAME(proto_id)
	if not proto_name then return end
	local protomsg = pbc.decode(proto_name, proto_data)
	if not protomsg then
		_RUNTIME_ERROR("ParseFromString Error", proto_id, proto_name)
		return
	end
	if func_call[proto_name] then
		func_call[proto_name](reserve_id, protomsg)
	end
end

server.start(function()
	AGENT.dispatch()
	server.dispatch("lua", function(msg, sz, session, source, retfunc)
		local params = server.unpack(msg, sz)
		if retfunc then
			return retfunc(params)
		end
		local funcname = params.funcname
		AGENT.cmds[funcname](params, source)
	end)
end)