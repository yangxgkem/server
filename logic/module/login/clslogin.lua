clsLogin = clsObject:Inherit()

function clsLogin:__init__()
	--待登录客户端列表
	self.clients = {}
end

--注册socket消息处理函数
function clsLogin:dispatch()
	--socket数据 4+2+data
	local function dataf(id, size, data)
		local clientObj = self.clients[id]
		clientObj:dataf(id, size, data)
	end

	--socket连接成功
	local function connectf(id, _, addr)
		local clientObj = self.clients[id]
		clientObj:connectf(id, _, addr)
	end

	--socket关闭
	local function closef(id)
		local clientObj = self.clients[id]
		clientObj:closef(id)
		self.clients[id] = nil
	end
	
	--socket出现错误,此时socket已经被底层关闭
	local function errorf(id)
		local clientObj = self.clients[id]
		clientObj:errorf(id)
		self.clients[id] = nil
	end

	socket.dispatch(dataf, connectf, closef, nil, errorf)
end

--有客户端接入,转给login临时管理,登录成功后再转回给agent
function clsLogin:s2s_login_begin(protomsg)
	local reserve_id = protomsg.reserve_id
	local addr = protomsg.addr
	clientObj = clsLoginClient:New()
	clientObj:accept(reserve_id, addr)
	self.clients[reserve_id] = clientObj
end

--登录
function clsLogin:c2s_login_corp_account(vfd, protomsg)
	local clientObj = self.clients[vfd]
	if not clientObj then return end
	if clientObj.islogin then return end

	local acct = protomsg.acct --账号
	local passwd = protomsg.passwd --密码

	local userdata = server.call(".mysql", "lua", {
		_func = "s2s_mysql_get",
		_call = true,
		query = "select * from user where acct="..acct,
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
		["addr"] = client.addr,
	})
end