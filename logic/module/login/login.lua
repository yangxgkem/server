local login = {}

--有客户端接入,转给login临时管理,登录成功后再转回给agent
function login.s2s_login_begin(protomsg)
    local reserve_id = protomsg.reserve_id
    local addr = protomsg.addr
    client_obj = clsLoginClient:new(protomsg)
    SOCKET_MGR.add_socket_id(reserve_id, client_obj)
    client_obj:transfer()
end

--发送错误信息给客户端
function login.send_login_err(reserve_id, errno, errmsg)
    local protoinfo = {}
    protoinfo.errno = errno
    protoinfo.errmsg = errmsg
    pbc_send_msg(reserve_id, "s2c_login_error", protoinfo)
end

--登录
function login.c2s_login_corp_account(vfd, protomsg)
    local client_obj = SOCKET_MGR.get_socket_by_id(vfd)
    if not client_obj then return end

    DB_OBJ:set_table("user")
    local userdata = DB_OBJ:get_by({["account"]=protomsg.account})
    if not userdata then
        login.send_login_err(client_obj:get_rid(), 501, "has not user data")
        return
    end
    if userdata.passwd ~= protomsg.passwd then
        login.send_login_err(client_obj:get_rid(), 501, "the user passwd error")
        return
    end

    local agent_id = service_logic_call(".socket", "s2s_socket_agent_id", {})
    if not agent_id then
        login.send_login_err(client_obj:get_rid(), 501, "get agent id error")
        return
    end

    local protoinfo = {}
    protoinfo.reserve_id = vfd
    protoinfo.addr = client_obj:get_addr()
    protoinfo.userdata = userdata
    service_logic_send(agent_id, "s2s_login_check_ok", protoinfo)
    client_obj:destroy()
end

--登录检测成功
function login.s2s_login_check_ok(protomsg)
    local reserve_id = protomsg.reserve_id
    local addr = protomsg.addr
    local userdata = protomsg.userdata
    local agent_obj = clsSocketAgent:new(protomsg)
    SOCKET_MGR.add_socket_id(reserve_id, agent_obj)
    agent_obj:transfer()

    local user_obj = clsUser:new(reserve_id)
    user_obj:set_state(mST_LOGIN)
    user_obj:restore(userdata)
    user_obj:enter_world()
end

function login.__init__()
    func_call.s2s_login_begin = login.s2s_login_begin
    func_call.c2s_login_corp_account = login.c2s_login_corp_account
    func_call.s2s_login_check_ok = login.s2s_login_check_ok
end

return login
