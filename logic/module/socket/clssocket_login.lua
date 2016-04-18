clsLoginClient = clsSocketBase:Inherit{__ClassType = "login_client"}

function clsLoginClient:__init__(OCI)
	Super(clsLoginClient).__init__(self)

    self.reserve_id = OCI.reserve_id
    self.addr = OCI.addr
end
