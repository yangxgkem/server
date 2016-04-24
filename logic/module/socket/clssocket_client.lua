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

	SOCKET_MGR.add_socket_id(id, self)
end

function clsSocketClient:connectf(id, _, addr)
    assert(self.reserve_id==id)
    Super(clsSocketClient).connectf(self, id, _, addr)
    server.error("clsSocketClient running............"..self.addr)
end

function clsSocketClient:closef(id)
    if self.reserve_id ~= id then return end
    Super(clsSocketClient).closef(self, id)
    server.error("clsSocketClient close............"..self.addr)
end

function clsSocketClient:errorf(id)
    assert(self.reserve_id==id)
    Super(clsSocketClient).errorf(self, id)
    self:destroy()
end
