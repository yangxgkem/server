clsLoginClient = clsSocketBase:Inherit{__ClassType = "login_client"}

function clsLoginClient:__init__()
	Super(clsLoginClient).__init__(self)
end

function clsLoginClient:s2s_login_begin(reserve_id, addr)
	assert(self.connect==false)
	self.reserve_id = reserve_id

	SOCKET_MGR.AddSocketId(reserve_id, self)
	socket.start(reserve_id)
end