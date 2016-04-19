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

    --核心数据
    self.__data = {}

    --临时数据
    self.__tmp = {}

    --对象初始化时间
    self.__init_time = os.time()

    --对象运行id, 由 char_mgr 分配
    self.__id = nil

    --对象状态
    self.__state = nil
end

function clsCharBase:get_state()
    return self.__state
end

function clsCharBase:set_state(state)
    self.__state = state
end

function clsCharBase:get_id()
    return self.__id
end

function clsCharBase:set_id(id)
     self.__id = id
     return id
end

function clsCharBase:get_vfd()
    return self.__tmp.vfd
end

function clsCharBase:set_vfd(vfd)
    self.__tmp.vfd = vfd
end

function clsCharBase:get_name()
    assert("should add in subclass")
end

function clsCharBase:on_create(OCI)
    local id = CHAR_MGR.newid()
    self.__id = id
    CHAR_MGR.add_charid(id, self)
end

--销毁对象
function clsCharBase:destroy()
    Super(clsCharBase).Destroy(self)
    local id = self:get_id()
    CHAR_MGR.remove_charid(id)
end

function clsCharBase:set_save(key, value)
    self.__data[key] = value
end

function clsCharBase:get_save(key)
    return self.__data[key]
end

function clsCharBase:set_tmp(key, value)
    self.__tmp[key] = value
end
function clsCharBase:get_tmp(key)
    return self.__tmp[key]
end

function clsCharBase:set_pairs(vars)
    for k,v in pairs(vars) do
        self['set_'..k](self, v)
    end
end

function clsCharBase:get_save_data()
    assert("should add in subclass")
end

function clsCharBase:save()
    assert("should add in subclass")
end
