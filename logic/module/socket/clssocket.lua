clsSocket = clsModuleBase:Inherit{__ClassType = "socket"}

function clsSocket:__init__()
	Super(clsSocket).__init__(self)
	
	--服务器IP
	self.host = nil

	--服务器端口
	self.port = nil

	--服务器socket reserve_id
	self.reserve_id = nil

	--是否已成功连接
	self.connect = false

	--代理服务池
	self.agents = {}

	--agent池缓存数量
	self.agent_cache = 50

	--agent池每次添加数量
	self.agent_cache_add = 50
end

--agent池
function clsSocket:check_agent_slot()
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

--获取一个agent
function clsSocket:s2s_socket_agent_id()
	if #self.agents <= 0 then return end
	return table.remove(self.agents, 1)
end

--定时检查agent池
local function time_check_agent()
	check_agent_slot()
	server.timeout(100, time_check_agent)
end

--启动服务器socket
function clsSocket:listen(host, port, backlog)
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
function clsSocket:connectf(id, _, addr)
	assert(self.reserve_id==id)
	self.connect = true
	server.error("LogicServer running............"..self.port)
end

--socket关闭
function clsSocket:closef(id)
	if self.reserve_id ~= id then return end
	server.error("LogicServer close............"..self.port)
end

--有客户端socket连入, 转给 login 服务
function clsSocket:acceptf(serverid, clientid, clientaddr)
	server.send(".login", "lua", {
		["_func"] = "s2s_login_begin",
		["reserve_id"] = clientid,
		["addr"] = clientaddr,
	})
end

--启动服务器socket失败
function clsSocket:errorf(id)
	assert(self.reserve_id==id)
	assert(false, "LogicServer error............")
end