clsSocketClient = clsModuleBase:Inherit{__ClassType = "socket_client"}

function clsSocketClient:__init__()
	Super(clsSocketClient).__init__(self)
	
	--客户端reserve_id
	self.reserve_id = nil

	--读取到的数据
	self.readdata = ""

	--读取到数据大小
	self.readsize = 0

	--当前解包数据大小
	self.current_size = 0

	--当前解包protobuf id 
	self.current_pid = 0

	--是否已连接成功
	self.connect = false

	--客户端地址
	self.addr = ""

	--端口
	self.port = nil

	--最大读取数据大小
	self.max_read = 65535

	--启动时间
	self.begintime = os.time()
end

--解析处理pbc数据
function clsSocketClient:checkpbc(reserve_id, proto_id, proto_data)
	assert(self.reserve_id == reserve_id)
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

--给业务服务发送处理数据
function clsSocketClient:sendprotobuf(id)
	local msg = string.sub(self.readdata, 1, self.current_size)
	self.readdata = string.sub(self.readdata, self.current_size+1)
	self.readsize = self.readsize - self.current_size
	assert(#self.readdata == self.readsize)
	local current_pid = self.current_pid
	self.current_pid = 0
	self.current_size = 0

	--把数据转发给服务处理
	local service_name = GET_PROTOID_SERVICE(current_pid)
	if service_name then
		server.sendname(service_name, "lua", {
			_func = "checkpbc",
			id = id,
			pid = current_pid,
			pdata = msg,
		})
	else
		self:checkpbc(id, current_pid, msg)
	end
end

--socket数据 4+2+data
function clsSocketClient:dataf(id, size, data)
	self.readdata = self.readdata .. data
	self.readsize = self.readsize + size
	assert(#self.readdata == self.readsize)

	if self.current_pid>0 and self.readsize>=self.current_size then
		self:sendprotobuf(id)
		return
	end

	if self.readsize<6 then return end
	self.current_size = string.unpack("<I4", string.sub(self.readdata, 1, 4)) --data数据大小
	if self.current_size>=self.max_read then
		socket.close(id) --数据有误主动关闭socket
		server.error("logic self read over size:", id, self.addr, self.current_size)
		return
	end
	self.current_pid = string.unpack("<I2", string.sub(self.readdata, 5, 6)) --protobuf id
	self.readdata = string.sub(self.readdata, 7)
	self.readsize = self.readsize - 6

	if self.current_size<=self.readsize then
		self:sendprotobuf(id)
		return
	end
end

--socket连接成功
function clsSocketClient:connectf(id, _, addr)
	print("connectf=================", id,_,addr)
	self.connect = true
end

--socket关闭
function clsSocketClient:closef(id)
	self.connect = false
end

--socket出现错误,此时socket已经被底层关闭
function clsSocketClient:errorf(id)
	self.connect = false
end


--客户端连入服务器
function clsSocketClient:on_connect(addr, port)
	local id = socket.open(addr, port)
	assert(id ~= nil)
	self.reserve_id = id

	SOCKET_MGR.AddSocketId(id, self)

	socket.start(id)
end
