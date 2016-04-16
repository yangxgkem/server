clsLogin = clsModuleBase:Inherit{__ClassType = "login"}

function clsLogin:__init__()
	Super(clsLogin).__init__(self)
end

--有客户端接入,转给login临时管理,登录成功后再转回给agent
function clsLogin:s2s_login_begin(protomsg)
	local reserve_id = protomsg.reserve_id
	local addr = protomsg.addr
	clientObj = clsLoginClient:New()
	clientObj:accept(reserve_id, addr)
end

--登录
function clsLogin:c2s_login_corp_account(vfd, protomsg)
	local clientObj = SOCKET_MGR.GetSocketById(vfd)
	if not clientObj then return end
	if clientObj.islogin then return end

	local account = protomsg.account --账号
	local passwd = protomsg.passwd --密码

	local userdata = server.call(".db", "lua", {
		_func = "s2s_db_query",
		_call = true,
		query = "select * from user where account="..account,
	})
	if not userdata then return end
	if userdata.passwd ~= passwd then return end

	clientObj.islogin = true
	clientObj.succtime = os.time()

	local agent_id = server.call(".socket", "lua", {
		_func = "s2s_socket_agent_id",
		_call = true,
	})
	if not agent_id then return end

	server.send(agent_id, "lua", {
		["_func"] = "s2s_login_ok",
		["reserve_id"] = vfd,
		["addr"] = clientObj.addr,
	})

	clientObj:Destroy()
end