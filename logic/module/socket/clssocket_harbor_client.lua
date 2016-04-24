clsHarborClient = clsSocketBase:Inherit{__ClassType = "harbor_client"}

function clsHarborClient:__init__(OCI)
	Super(clsHarborClient).__init__(self)

    self.reserve_id = OCI.reserve_id
    self.addr = OCI.addr
end

function clsHarborClient:connectf(id, _, addr)
    assert(self.reserve_id==id)
    Super(clsHarborClient).connectf(self, id, _, addr)
end

function clsHarborClient:closef(id)
    if self.reserve_id ~= id then return end
    Super(clsHarborClient).closef(self, id)
    self:destroy()
end

function clsHarborClient:errorf(id)
    assert(self.reserve_id==id)
    Super(clsHarborClient).errorf(self, id)
    self:destroy()
end
