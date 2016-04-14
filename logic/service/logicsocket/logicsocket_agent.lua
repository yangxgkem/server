dofile("./logic/base/preload.lua")

local MaxReadDataSize = 65535 --最大读取数据大小

local agent = {}

--客户端reserve_id
agent.reserve_id = reserve_id

--读取到的数据
agent.readdata = ""

--读取到数据大小
agent.readsize = 0

--当前解包数据大小
agent.current_size = 0

--当前解包protobuf id 
agent.current_pid = 0

--是否已连接成功
agent.connect = false

--客户端地址
agent.addr = ""


--解析处理pbc数据
local function checkpbc(reserve_id, proto_id, proto_data)
	assert(agent.reserve_id == reserve_id)
	local proto_name = GET_PROTO_NAME(proto_id)
	if not proto_name then return end
	local protomsg = pbc.decode(proto_name, proto_data)
	if not protomsg then
		_RUNTIME_ERROR("ParseFromString Error", proto_id, proto_name)
		return
	end
	if func_call[proto_name] then
		func_call[proto_name](reserve_id, protomsg)
	end
end

--给业务服务发送处理数据
local function sendprotobuf(id)
	local msg = string.sub(agent.readdata, 1, agent.current_size)
	agent.readdata = string.sub(agent.readdata, agent.current_size+1)
	agent.readsize = agent.readsize - agent.current_size
	assert(#agent.readdata == agent.readsize)
	local current_pid = agent.current_pid
	agent.current_pid = 0
	agent.current_size = 0

	--把数据转发给服务处理
	local service_name = GET_PROTOID_SERVICE(current_pid)
	if service_name then
		server.sendname(service_name, "lua", {
			_func = "checkpbc",
			id = id,
			pid = current_pid,
			pdata = msg,
		})
	else
		checkpbc(id, current_pid, msg)
	end
end

--通知其他业务服务删除了客户端
local function close_agent(reserve_id)

end

--注册socket消息处理函数
function agent.dispatch()
	--socket数据 4+2+data
	local function dataf(id, size, data)
		agent.readdata = agent.readdata .. data
		agent.readsize = agent.readsize + size
		assert(#agent.readdata == agent.readsize)

		if agent.current_pid>0 and agent.readsize>=agent.current_size then
			sendprotobuf(id)
			return
		end

		if agent.readsize<6 then return end
		agent.current_size = string.unpack("<I4", string.sub(agent.readdata, 1, 4)) --data数据大小
		if agent.current_size>=MaxReadDataSize then
			socket.close(id) --数据有误主动关闭socket
			server.error("logic agent read over size:", id, agent.addr, agent.current_size)
			return
		end
		agent.current_pid = string.unpack("<I2", string.sub(agent.readdata, 5, 6)) --protobuf id
		agent.readdata = string.sub(agent.readdata, 7)
		agent.readsize = agent.readsize - 6

		if agent.current_size<=agent.readsize then
			sendprotobuf(id)
			return
		end
	end

	--socket连接成功
	local function connectf(id, _, addr)
		agent.connect = true
	end

	--socket关闭
	local function closef(id)
		agent.connect = false
		close_agent(id)
	end
	
	--socket出现错误,此时socket已经被底层关闭
	local function errorf(id)
		agent.connect = false
		close_agent(id)
	end

	socket.dispatch(dataf, connectf, closef, nil, errorf)
end

--客户端连入服务器
function agent.accept(params)
	assert(agent.connect==false)
	agent.reserve_id = params.reserve_id
	agent.addr = params.addr
	socket.start(params.reserve_id)
end

server.start(function()
	agent.dispatch()
	server.dispatch("lua", function(session, source, params)
		if (params._call) then
        	local msg = agent[params._func](params)
        	server.ret(source, session, server.pack(msg))
        else
        	agent[params._func](params)
        end
	end)
end)