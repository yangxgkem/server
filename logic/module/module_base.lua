--所有实体对象基类
clsModuleBase = clsObject:Inherit({__ClassType = "<module_base>"})

function clsModuleBase:Inherit(o)
	o = o or {}
	setmetatable(o, {__index = self})
	o.__SuperClass = self
	return o
end

function clsModuleBase:__init__(OCI)
	Super(clsModuleBase).__init__(self, OCI)
	self.__data = {}
	self.__tmp = {}
	self.__var = {}
	self.__init_time = os.time() --对象初始化时间
	local Id = MODULE_MGR.NewId()
	self.__ID = Id
	MODULE_MGR.AddModuleId(Id, self) 
end

function clsModuleBase:GetId()
	return self.__ID
end

function clsModuleBase:SetId(Id)
	 self.__ID = Id
	 return Id
end

function clsModuleBase:GetName()
	assert("should add in subclass")
end

--销毁对象
function clsModuleBase:Destroy()
	Super(clsModuleBase).Destroy(self)
	local Id = self:GetId()
	MODULE_MGR.RemoveCharId(Id)
end

function clsModuleBase:SetSave(Key, Value)
	self.__data[Key] = Value
	return Value
end

function clsModuleBase:GetSave(Key, Default)
	return self.__data[Key] or Default
end

function clsModuleBase:SetTmp(Key, Value)
	self.__tmp[Key] = Value
	return Value
end
function clsModuleBase:GetTmp(Key, Default)
	return self.__tmp[Key] or Default
end

function clsModuleBase:SetPairs(VarsTable)
	for k,v in pairs(VarsTable) do
		self['Set'..k](self, v)
	end
end

function clsModuleBase:GetSaveData()
	assert("should add in subclass")
end

function clsModuleBase:Save()
	assert("should add in subclass")
end