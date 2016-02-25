dofile("./logic/base/preload.lua")

local OpenAgentNum = 100 --启动代理服务个数
local ContentMaxNum = 10000 --最大连接数

local LOGIC_SOCKET = {}
LOGIC_SOCKET.host = nil --服务器IP
LOGIC_SOCKET.port = nil --服务器端口
LOGIC_SOCKET.reserve_id = nil --服务器socket reserve_id
LOGIC_SOCKET.connect = false --是否已成功连接
LOGIC_SOCKET.cmds = {} --消息函数
LOGIC_SOCKET.agents = {} --代理服务列表


--注册socket消息处理函数
function LOGIC_SOCKET.dispatch()
	--服务器socket启动成功
	local function connectf(id, _, addr)
		assert(LOGIC_SOCKET.reserve_id==id)
		server.error("LogicServer running............"..LOGIC_SOCKET.port)
		LOGIC_SOCKET.connect = true
	end

	--socket关闭,有可能是客户端id回调到这里,客户端数量已达上限,主动关闭后回调此函数
	local function closef(id)
		if id ~= LOGIC_SOCKET.reserve_id then return end
		server.error("LogicServer close............"..LOGIC_SOCKET.port)
	end

	--有客户端socket连入
	local function acceptf(serverid, clientid, clientaddr)
		for id,data in pairs(LOGIC_SOCKET.agents) do
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
		--客户端连接数量已达上限,直接关闭
		server.error("LogicServer over............"..clientaddr)
		socket.close(clientid)
	end

	--启动服务器socket失败
	local function errorf(id)
		assert(LOGIC_SOCKET.reserve_id==id)
		assert(false, "LogicServer error............")
	end

	socket.dispatch(nil, connectf, closef, acceptf, errorf)
end

--启动服务器socket
function LOGIC_SOCKET.listen(params)
	assert(not LOGIC_SOCKET.reserve_id)
	local host = params.host
	local port = params.port
	local backlog = params.backlog

	local id = socket.listen(host, port, backlog)
	assert(id ~= nil)

	LOGIC_SOCKET.reserve_id = id
	LOGIC_SOCKET.host = host
	LOGIC_SOCKET.port = port

	socket.start(id)
end

--某客户端关闭
function LOGIC_SOCKET.cmds.clientclose(params, source)
	local reserve_id = params.reserve_id
	local data = LOGIC_SOCKET.agents[source]
	data.num = data.num - 1
	data.clients[reserve_id] = nil
end

server.start(function()
	server.register(".logicsocket")
	LOGIC_SOCKET.dispatch()

	server.dispatch("lua", function(msg, sz, session, source, retfunc)
		local params = server.unpack(msg, sz)
		if retfunc then
			return retfunc(params)
		end
		local funcname = params.funcname
		LOGIC_SOCKET.cmds[funcname](params, source)
	end)

	--注册代理服务
	for i=1,OpenAgentNum do
		local id = server.newservice("snlua logicsocket_agent")
		LOGIC_SOCKET.agents[id] = {
			num = 0,
			clients = {},
		}
	end

	--启动服务器socket
	LOGIC_SOCKET.listen({
		host = "0.0.0.0",
		port = cfgData.serverport,
		backlog = nil,
	})
end)