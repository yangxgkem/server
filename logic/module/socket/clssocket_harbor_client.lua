clsHarborClient = clsSocketBase:Inherit{__ClassType = "harbor_client"}

function clsHarborClient:__init__(OCI)
	Super(clsHarborClient).__init__(self)

    self.reserve_id = OCI.reserve_id
    self.addr = OCI.addr
end
