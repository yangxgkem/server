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

	--核心数据
	self.__data = {}

	--临时数据
	self.__tmp = {}

	--对象初始化时间
	self.__init_time = os.time()

	--运行id分配
	local id = MODULE_MGR.newid()
	self.__id = id
	MODULE_MGR.add_module_id(id, self)
end

function clsModuleBase:get_id()
	return self.__id
end

function clsModuleBase:set_id(id)
	 self.__id = id
	 return id
end

function clsModuleBase:get_name()
	assert("should add in subclass")
end

--销毁对象
function clsModuleBase:destroy()
	Super(clsModuleBase).destroy(self)
	local id = self:get_id()
	MODULE_MGR.remove_module_id(id)
end

function clsModuleBase:set_save(key, value)
	self.__data[key] = value
	return value
end

function clsModuleBase:get_save(key)
	return self.__data[key]
end

function clsModuleBase:set_tmp(key, value)
	self.__tmp[key] = value
	return value
end
function clsModuleBase:get_tmp(key)
	return self.__tmp[key]
end
