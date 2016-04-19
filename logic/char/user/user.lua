clsUser = clsCharBase:Inherit({__ClassType = "user"})

function clsUser:get_uid()
    return self.__data["id"]
end

function clsUser:__init__(vfd)
    assert(type(vfd) == mNUMBERTYPE)
    Super(clsUser).__init__(self)
    self:set_vfd(vfd)
end

--玩家数据恢复, 在 LOGIN 里回调此接口
function clsUser:restore(userdata)
    self:set_state(mST_RESTORE)
    local olduser = CHAR_MGR.get_user_by_uid(userdata.id)
    if olduser then
        _RUNTIME_ERROR(string.format("BuildGameData Error: %d(%s) is in the Game!",userdata.id,userdata.account))
        return
    end
    self:before_load()
    self:on_create(userdata)
    self:after_load()
end

--初始化玩家数据时
function clsUser:before_load()

end

--初始化玩家数据完毕后
function clsUser:after_load()

end

function clsUser:on_create(userdata)
    Super(clsUser).on_create(self, userdata)
    CHAR_MGR.add_uid(userdata.id, self)
    self.__data = userdata
    --新人物初始化
    if not userdata.is_init then
        self:on_create_new()
    end
end

--创建新角色,初始化角色数据
function clsUser:on_create_new()
    self:set_save("grade", 0)
    self:set_save("exp", 0)
    self:set_save("register", os.time())
end

--登入场景
function clsUser:enter_world()
    self:set_state(mST_GAME_OK)
    self:login_check()
    self:send_enter_info()
end

--登陆检测
function clsUser:login_check()
    self:set_save("login_time", os.time())
end

--发送登入场景协议给客户端
function clsUser:send_enter_info()
    local protomsg = {}
    protomsg.uid = self:get_uid()
    protomsg.name = self:get_save("name")
    protomsg.sex = self:get_save("sex")
    protomsg.grade = self:get_save("grade")
    pbc_send_msg(self:get_vfd(), "s2c_user_enter_info", protomsg)
end

--心跳重置
function clsUser:reset()
    local nowtime = os.time()
    self:set_tmp("last_reset", nowtime)
    local reset_times = (self:get_tmp("reset_times") or 0) + 1
    self:set_tmp("reset_times", reset_times)
end

--退出保存前处理
function clsUser:before_save()

end

--退出保存后处理
function clsUser:after_save()

end

--玩家需要保存的数据
function clsUser:get_save_data()
    local data = {}
    data.user = self.__data
    return data
end

--保存玩家数据
function clsUser:save()
    self:set_save("save_time", os.time())
    local data = self:get_save_data()
    assert(data)
    local uid = self:get_uid()
end

--销毁一个玩家, 下线处理, 玩家的最后一个步骤
function clsUser:destroy()
    self:before_save()
    self:save()
    self:after_save()
    Super(clsUser).destroy(self)
end

--下线处理
function clsUser:logout()
    local now = os.time()
    --下线时间存储
    self:set_save("logout_time", now)
    --对象数据存储及delete
    self:destroy()
end

--直接踢玩家下线
function clsUser:kick_out()
    CONN.CloseVfd(self:GetVfd())
    self:Logout()
end

function clsUser:notify(msg)
    pbc_send_msg(self:get_vfd(), "s2c_notify_info", {["msg"] = msg})
end
