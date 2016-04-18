clsSocketServer = clsSocketBase:Inherit{__ClassType = "socket"}

function clsSocketServer:__init__()
	Super(clsSocketServer).__init__(self)
	
	--代理服务池
	self.agents = {}

	--agent池缓存数量
	self.agent_cache = 5

	--agent池每次添加数量
	self.agent_cache_add = 5
end

--agent池
function clsSocketServer:check_agent_slot()
	local num = #self.agents
	local new_num = 0

	if num < self.agent_cache then
		new_num = (self.agent_cache-num)+self.agent_cache_add
	end

	if new_num > 0 then
		for i=1, new_num do
			local id = server.newservice("snlua logic socket/agent")
			table.insert(self.agents, id)
		end
	end
end

--启动服务器socket
function clsSocketServer:listen(host, port, backlog)
	assert(not self.reserve_id)

	local id = socket.listen(host, port, backlog)
	assert(id ~= nil)

	self.reserve_id = id
	self.host = host
	self.port = port

	SOCKET_MGR.AddSocketId(id, self)

	socket.start(id)
end

--服务器socket启动成功
function clsSocketServer:connectf(id, _, addr)
	assert(self.reserve_id==id)
	Super(clsSocketServer).connectf(self, id, _, addr)
	server.error("LogicServer running............"..self.port)
end

--socket关闭
function clsSocketServer:closef(id)
	if self.reserve_id ~= id then return end
	Super(clsSocketServer).closef(self, id)
	server.error("LogicServer close............"..self.port)
end

--有客户端socket连入, 转给 login 服务
function clsSocketServer:acceptf(serverid, clientid, clientaddr)
	service_logic_send(".login", "s2s_login_begin", {["reserve_id"] = clientid, ["addr"] = clientaddr})
end

--启动服务器socket失败
function clsSocketServer:errorf(id)
	assert(self.reserve_id==id)
	Super(clsSocketServer).errorf(self, id)
	assert(false, "LogicServer error............")
end

--获取一个agent
function clsSocketServer:get_agent_id()
	if #self.agents <= 0 then return end
	return table.remove(self.agents, 1)
end