clsSocketAgent = clsObject:Inherit()

function clsSocketAgent:__init__()
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

	--最大读取数据大小
	self.max_read = 65535

	--启动时间
	self.begintime = os.time()

	--完成验证时间
	self.succtime = nil

	--是否已登录
	self.islogin = false
end

--解析处理pbc数据
function clsSocketAgent:checkpbc(reserve_id, proto_id, proto_data)
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
function clsSocketAgent:sendprotobuf(id)
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

--通知其他业务服务删除了客户端
function clsSocketAgent:close_self(reserve_id)

end

--注册socket消息处理函数
function clsSocketAgent:dispatch()
	--socket数据 4+2+data
	local function dataf(id, size, data)
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
	local function connectf(id, _, addr)
		self.connect = true
	end

	--socket关闭
	local function closef(id)
		self.connect = false
		self:close_self(id)
	end
	
	--socket出现错误,此时socket已经被底层关闭
	local function errorf(id)
		self.connect = false
		self:close_self(id)
	end

	socket.dispatch(dataf, connectf, closef, nil, errorf)
end

--客户端连入服务器
function clsSocketAgent:s2s_login_ok(params)
	assert(self.connect==false)
	self.reserve_id = params.reserve_id
	self.addr = params.addr
	socket.start(params.reserve_id)
end
