dofile("./logic/base/preload.lua")

local OpenAgentNum = 5 --启动代理服务个数
local OpenClientNum = 5 --启动distribute_client 服务个数
local ContentMaxNum = 256 --最大连接数

local DISTRIBUTE = {}
DISTRIBUTE.host = nil --服务器IP
DISTRIBUTE.port = nil --服务器端口
DISTRIBUTE.reserve_id = nil --服务器socket reserve_id
DISTRIBUTE.connect = false --是否已成功连接
DISTRIBUTE.cmds = {} --消息函数
DISTRIBUTE.agents = {} --代理服务列表
DISTRIBUTE.harbors = {} --harbor对应的service, 此处可以是:distribute_client, distribute_agent


--注册socket消息处理函数
function DISTRIBUTE.dispatch()

	--服务器socket启动成功
	local function connectf(id, _, addr)
		assert(DISTRIBUTE.reserve_id==id)
		server.error("DistributeServer running............"..DISTRIBUTE.port)
		DISTRIBUTE.connect = true
	end

	--socket关闭,有可能是远程端id回调到这里
	local function closef(id)
		if id ~= DISTRIBUTE.reserve_id then return end
		server.error("DistributeServer close............"..DISTRIBUTE.port)
		DISTRIBUTE.clear()
	end

	--有远程端socket连入
	local function acceptf(serverid, clientid, clientaddr)
		for id,data in pairs(DISTRIBUTE.agents) do
			if data.num < math.ceil(ContentMaxNum/OpenAgentNum) then
				data.num = data.num + 1
				data.clients[clientid] = clientaddr
				server.send(id, "lua", server.pack({
					["funcname"] = "accept",
					["reserve_id"] = clientid,
					["addr"] = clientaddr,
				}))
				return
			end
		end
		--远程端连接数量已达上限,直接关闭
		server.error("DistributeServer over............"..clientaddr)
		socket.close(clientid)
	end

	--启动服务器socket失败
	local function errorf(id)
		assert(DISTRIBUTE.reserve_id==id)
		server.error("DistributeServer error!!!")
	end

	socket.dispatch(nil, connectf, closef, acceptf, errorf)
end

--启动服务器socket
function DISTRIBUTE.listen(params)
	assert(not DISTRIBUTE.reserve_id)
	local host = params.host
	local port = params.port
	local backlog = params.backlog
	local id = socket.listen(host, port, backlog)
	assert(id ~= nil)

	DISTRIBUTE.reserve_id = id
	DISTRIBUTE.host = host
	DISTRIBUTE.port = port

	socket.start(id)
end

--某远程端关闭
function DISTRIBUTE.cmds.clientclose(params, source)
	local reserve_id = params.reserve_id
	local data = DISTRIBUTE.agents[source]
	data.num = data.num - 1
	data.clients[reserve_id] = nil
	server.error("distribute close client:", reserve_id)
end

--注册某harbor对应service
function DISTRIBUTE.cmds.addharbor(params, source)
	local harborid = params.harborid
	local reserve_id = params.reserve_id
	assert(not DISTRIBUTE.harbors[harborid])
	DISTRIBUTE.harbors[harborid] = {
		["service_id"] = source,
		["reserve_id"] = reserve_id,
	}
	server.error("harbor add:", harborid, source)
end

--删除某harbor
function DISTRIBUTE.cmds.delharbor(params, source)
	local harborid = params.harborid
	DISTRIBUTE.harbors[harborid] = nil
	server.error("harbor close:", harborid, source)
end

server.start(function()
	server.register(".distribute")
	harbor.start()
	DISTRIBUTE.dispatch()
	
	--把本地服务消息转发到其他机器服务
	server.dispatch("lua", function(msg, sz, session, source)
		local handle, params, psz = harbor.unpack(msg)
		local harborid
		if type(handle)==mSTRINGTYPE then
			harborid = distributeData2[handle]
		else
			harborid = harbor.getharbor(handle)
		end

		assert(DISTRIBUTE.harbors[harborid], string.format("harbor not content %d", harborid))
		local service_id = DISTRIBUTE.harbors[harborid].service_id
		local reserve_id = DISTRIBUTE.harbors[harborid].reserve_id
		server.send(service_id, "lua", server.pack({
			["funcname"] = "harborsend",
			["handle"] = handle, --接收方handleid or handlename
			["source"] = source, --发送方handleid
			["session"] = session, --发送方会话id
			["reserve_id"] = reserve_id, --接收方harbor socket
			["harborid"] = harborid, --接收方harborid
			["msg"] = params, --发送数据
			["sz"] = psz, --发送数据大小
		}))
	end)

	--处理本地服务发给自己的消息
	server.dispatch("harbor", function(msg, sz, session, source, retfunc)
		local params = server.unpack(msg, sz)
		if retfunc then
			return retfunc(params)
		end
		local funcname = params.funcname
		DISTRIBUTE.cmds[funcname](params, source)
	end)

	--注册代理服务
	for i=1,OpenAgentNum do
		local id = server.newservice("snlua distribute_agent")
		DISTRIBUTE.agents[id] = {
			num = 0,
			clients = {},
		}
	end
	--注册客户端服务
	for i=1,OpenClientNum do
		local minharborid = (i-1)*50
		local maxharborid = i*50
		local id = server.newservice(string.format("snlua distribute_client %s %s",minharborid, maxharborid))
		DISTRIBUTE.agents[id] = {
			["maxharborid"] = maxharborid,
		}
	end

	--启动服务器socket
	local harbordata = distributeData[(cfgData.harbor)]
	DISTRIBUTE.listen({
		host = "0.0.0.0",
		port = harbordata.port,
		backlog = nil,
	})
end)