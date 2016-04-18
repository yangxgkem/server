clsSocketAgent = clsSocketBase:Inherit{__ClassType = "socket_agent"}

function clsSocketAgent:__init__(OCI)
	Super(clsSocketAgent).__init__(self)

	self.reserve_id = OCI.reserve_id
	self.addr = OCI.addr
end

--socket连接成功
function clsSocketAgent:connectf(id, _, addr)
	Super(clsSocketAgent).connectf(self, id, _, addr)
end

--socket关闭
function clsSocketAgent:closef(id)
	Super(clsSocketAgent).closef(self, id)
	self:close_self(id)
end

--socket出现错误,此时socket已经被底层关闭
function clsSocketAgent:errorf(id)
	Super(clsSocketAgent).errorf(self, id)
	self:close_self(id)
end

--通知其他业务服务玩家下线
function clsSocketAgent:close_self(reserve_id)

end

--登录验证成功
function clsSocketAgent:login_ok(params)
	assert(self.connect==false)
	self.reserve_id = params.reserve_id
	self.addr = params.addr

	SOCKET_MGR.AddSocketId(params.reserve_id, self)
	socket.start(params.reserve_id)
end
