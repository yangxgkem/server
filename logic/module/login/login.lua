local login = {}

--有客户端接入,转给login临时管理,登录成功后再转回给agent
function login.s2s_login_begin(protomsg)
    local reserve_id = protomsg.reserve_id
    local addr = protomsg.addr
    clientObj = clsLoginClient:New(protomsg)
    SOCKET_MGR.AddSocketId(reserve_id, clientObj)
    clientObj:transfer()
end

--登录
function login.c2s_login_corp_account(vfd, protomsg)
    local clientObj = SOCKET_MGR.GetSocketById(vfd)
    if not clientObj then return end
    if clientObj.islogin then return end

    local account = protomsg.account --账号
    local passwd = protomsg.passwd --密码

    DB_OBJ:set_table("user")
    local userdata = DB_OBJ:get_by({["account"]=account})
    if not userdata then return end
    if userdata.passwd ~= passwd then return end

    local agent_id = service_logic_call(".socket", "s2s_socket_agent_id", {})
    if not agent_id then return end

    service_logic_send(agent_id, "s2s_login_ok", {["reserve_id"] = vfd, ["addr"] = clientObj.addr})
    clientObj:Destroy()
end

--登录成功
function login.s2s_login_ok(protomsg)
    local reserve_id = protomsg.reserve_id
    local addr = protomsg.addr
    local agentObj = clsSocketAgent:New(protomsg)
    SOCKET_MGR.AddSocketId(reserve_id, agentObj)
    agentObj:transfer()
    _RUNTIME("login ok", addr)
end

function login.__init__()
    func_call.s2s_login_begin = login.s2s_login_begin
    func_call.c2s_login_corp_account = login.c2s_login_corp_account
    func_call.s2s_login_ok = login.s2s_login_ok
end

return login
