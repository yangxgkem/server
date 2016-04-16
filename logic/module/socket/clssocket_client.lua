clsSocketClient = clsSocketBase:Inherit{__ClassType = "socket_client"}

function clsSocketClient:__init__()
	Super(clsSocketClient).__init__(self)
end

--客户端连入服务器
function clsSocketClient:on_connect(addr, port)
	local id = socket.open(addr, port)
	assert(id ~= nil)
	self.reserve_id = id
	self.addr = addr
	self.port = port

	SOCKET_MGR.AddSocketId(id, self)
end