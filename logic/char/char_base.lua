--所有实体对象基类
clsCharBase = clsObject:Inherit({__ClassType = "<char_base>"})

function clsCharBase:Inherit(o)
	o = o or {}
	setmetatable(o, {__index = self})
	o.__SuperClass = self
	return o
end

function clsCharBase:__init__(OCI)
	Super(clsCharBase).__init__(self, OCI)
	self.__data = {}
	self.__tmp = {}
	self.__var = {}
	self.__init_time = os.time() --对象初始化时间
	self.__ID = nil --对象ID
end

function clsCharBase:GetId()
	return self.__ID
end

function clsCharBase:SetId(Id)
	 self.__ID = Id
	 return Id
end

function clsCharBase:SetVfd(Vfd)
	self.__tmp.Vfd = Vfd
end

function clsCharBase:GetVfd()
	return self.__tmp.Vfd
end

function clsCharBase:GetName()
	assert("should add in subclass")
end

function clsCharBase:OnCreate(OCI)
	local Id = CHAR_MGR.NewId()
	self.__ID = Id
	CHAR_MGR.AddCharId(Id, self) 
end

--销毁对象
function clsCharBase:Destroy()
	Super(clsCharBase).Destroy(self)
	local Id = self:GetId()
	CHAR_MGR.RemoveCharId(Id)
end

function clsCharBase:SetSave(Key, Value)
	self.__data[Key] = Value
	return Value
end

function clsCharBase:GetSave(Key, Default)
	return self.__data[Key] or Default
end

function clsCharBase:SetTmp(Key, Value)
	self.__tmp[Key] = Value
	return Value
end
function clsCharBase:GetTmp(Key, Default)
	return self.__tmp[Key] or Default
end

function clsCharBase:SetPairs(VarsTable)
	for k,v in pairs(VarsTable) do
		self['Set'..k](self, v)
	end
end

function clsCharBase:GetSaveData()
	assert("should add in subclass")
end

function clsCharBase:Save()
	assert("should add in subclass")
end