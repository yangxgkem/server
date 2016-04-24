clsSocketHarbor = clsSocketBase:Inherit{__ClassType = "socket_harbor"}

function clsSocketHarbor:__init__()
    Super(clsSocketHarbor).__init__(self)
end

--启动服务器socket
function clsSocketHarbor:listen(host, port, backlog)
    assert(not self.reserve_id)

    local id = socket.listen(host, port, backlog)
    assert(id ~= nil)

    self.reserve_id = id
    self.host = host
    self.port = port

    SOCKET_MGR.add_socket_id(id, self)

    socket.start(id)
end

--服务器socket启动成功
function clsSocketHarbor:connectf(id, _, addr)
    assert(self.reserve_id==id)
    Super(clsSocketHarbor).connectf(self, id, _, addr)
    server.error("HarborServer running............"..self.port)
end

--socket关闭
function clsSocketHarbor:closef(id)
    if self.reserve_id ~= id then return end
    Super(clsSocketHarbor).closef(self, id)
    server.error("HarborServer close............"..self.port)
end

--有客户端socket连入
function clsSocketHarbor:acceptf(serverid, clientid, clientaddr)
    HARBOR.acceptf({["reserve_id"] = clientid, ["addr"] = clientaddr})
end

--启动服务器socket失败
function clsSocketHarbor:errorf(id)
    assert(self.reserve_id==id)
    Super(clsSocketHarbor).errorf(self, id)
    assert(false, "HarborServer error............")
end
