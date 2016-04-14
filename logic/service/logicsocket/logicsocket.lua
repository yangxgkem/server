local AgentCacheNum = 500 --agent池缓存数量
local AgentCacheAdd = 50 --agent池每次添加数量

local lg_socket = {}

--服务器IP
lg_socket.host = nil

--服务器端口
lg_socket.port = nil

--服务器socket reserve_id
lg_socket.reserve_id = nil

--是否已成功连接
lg_socket.connect = false

--代理服务池
lg_socket.agents = {}

--agent池
local function check_agent_slot()
	local num = #lg_socket.agents
	local new_num = 0

	if num < AgentCacheNum then
		new_num = (AgentCacheNum-num)+AgentCacheAdd
	end

	if new_num > 0 then
		for i=1, new_num do
			local id = server.newservice("snlua logic logicsocket/logicsocket_agent")
			table.insert(lg_socket.agents, id)
		end
	end
end

--获取一个agent
local function get_one_agent()
	if #lg_socket.agents <= 0 then return end
	return table.remove(lg_socket.agents, 1)
end

--定时检查agent池
local function time_check_agent()
	check_agent_slot()
	server.timeout(100, time_check_agent)
end

--启动服务器socket
local function listen(host, port, backlog)
	assert(not lg_socket.reserve_id)

	local id = socket.listen(host, port, backlog)
	assert(id ~= nil)

	lg_socket.reserve_id = id
	lg_socket.host = host
	lg_socket.port = port

	socket.start(id)
end

--注册socket消息处理函数
function lg_socket.dispatch()
	--服务器socket启动成功
	local function connectf(id, _, addr)
		assert(lg_socket.reserve_id==id)
		lg_socket.connect = true
		server.error("LogicServer running............"..lg_socket.port)
	end

	--socket关闭
	local function closef(id)
		if lg_socket.reserve_id ~= id then return end
		server.error("LogicServer close............"..lg_socket.port)
	end

	--有客户端socket连入
	local function acceptf(serverid, clientid, clientaddr)
		local id = get_one_agent()
		if not id then return socket.close(clientid) end
		server.send(id, "lua", {
			["_func"] = "accept",
			["reserve_id"] = clientid,
			["addr"] = clientaddr,
		})
	end

	--启动服务器socket失败
	local function errorf(id)
		assert(lg_socket.reserve_id==id)
		assert(false, "LogicServer error............")
	end

	socket.dispatch(nil, connectf, closef, acceptf, errorf)
end


server.start(function()
	server.register(".logicsocket")
	lg_socket.dispatch()

	server.dispatch("lua", function(session, source, params)
        if (params._call) then
        	local msg = lg_socket[params._func](params)
        	server.ret(source, session, server.pack(msg))
        else
        	lg_socket[params._func](params)
        end
    end)

	time_check_agent()
	listen("0.0.0.0", cfgData.serverport, nil)
end)