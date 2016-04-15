--所有实体对象基类
clsBaseChar = clsObject:Inherit({__ClassType = "<basechar>"})

function clsBaseChar:Inherit(o)
	o = o or {}
	setmetatable(o, {__index = self})
	o.__SuperClass = self
	return o
end

function clsBaseChar:__init__(OCI)
	Super(clsBaseChar).__init__(self, OCI)
	self.__data = {}
	self.__tmp = {}
	self.__var = {}
	self.__init_time = os.time() --对象初始化时间
	self.__ID = nil --对象ID
end

function clsBaseChar:GetId()
	return self.__ID
end

function clsBaseChar:SetId(Id)
	 self.__ID = Id
	 return Id
end

function clsBaseChar:SetVfd(Vfd)
	self.__tmp.Vfd = Vfd
end

function clsBaseChar:GetVfd()
	return self.__tmp.Vfd
end

function clsBaseChar:GetName()
	assert("should add in subclass")
end

function clsBaseChar:OnCreate(OCI)
	local Id = CHAR_MGR.NewId()
	self.__ID = Id
	CHAR_MGR.AddCharId(Id, self) 
end

--销毁对象
function clsBaseChar:Destroy()
	Super(clsBaseChar).Destroy(self)
	local Id = self:GetId()
	CHAR_MGR.RemoveCharId(Id)
end

function clsBaseChar:SetSave(Key, Value)
	self.__data[Key] = Value
	return Value
end

function clsBaseChar:GetSave(Key, Default)
	return self.__data[Key] or Default
end

function clsBaseChar:SetTmp(Key, Value)
	self.__tmp[Key] = Value
	return Value
end
function clsBaseChar:GetTmp(Key, Default)
	return self.__tmp[Key] or Default
end

function clsBaseChar:SetPairs(VarsTable)
	for k,v in pairs(VarsTable) do
		self['Set'..k](self, v)
	end
end

function clsBaseChar:GetSaveData()
	assert("should add in subclass")
end

function clsBaseChar:Save()
	assert("should add in subclass")
end