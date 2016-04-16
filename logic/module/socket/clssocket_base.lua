clsSocketBase = clsModuleBase:Inherit{__ClassType = "socket_base"}

function clsSocketBase:__init__()
	Super(clsSocketBase).__init__(self)

	--socket reserve_id
	self.reserve_id = nil

	--地址
	self.addr = ""

	--端口
	self.port = nil
	
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

	--最大读取数据大小
	self.max_read = 65535

	--启动时间
	self.begintime = os.time()
end

--解析处理pbc数据
function clsSocketBase:checkpbc(reserve_id, proto_id, proto_data)
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
	else
		_RUNTIME_ERROR("Func_call Error", reserve_id, proto_name)
	end
end

--给业务服务发送处理数据
function clsSocketBase:sendprotobuf(id)
	local msg = string.sub(self.readdata, 1, self.current_size)
	self.readdata = string.sub(self.readdata, self.current_size+1)
	self.readsize = self.readsize - self.current_size
	assert(#self.readdata == self.readsize)
	local current_pid = self.current_pid
	self.current_pid = 0
	self.current_size = 0

	self:checkpbc(id, current_pid, msg)
end

--socket数据 4+2+data
function clsSocketBase:dataf(id, size, data)
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
function clsSocketBase:connectf(id, _, addr)
	self.connect = true
end

--socket关闭
function clsSocketBase:closef(id)
	self.connect = false
end

--有客户端socket连入
function clsSocketBase:acceptf(serverid, clientid, clientaddr)
	assert("should add in subclass")
end

--socket出现错误,此时socket已经被底层关闭
function clsSocketBase:errorf(id)
	self.connect = false
end

--把消息转移到当前服务处理
function clsSocketBase:transfer()
	socket.start(self.reserve_id)
end