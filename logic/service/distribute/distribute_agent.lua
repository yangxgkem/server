dofile("./logic/base/preload.lua")

local MaxReadDataSize = 65535 --最大读取数据大小

local AGENT = {}
AGENT.clients = {} --harbor客户端列表
AGENT.cmds = {} --消息函数
AGENT.func_call = {} --socket消息处理函数

--处理数据
local function sendprotobuf(id)
	local client = AGENT.clients[id]
	local msg = string.sub(client.readdata, 1, client.data_size)
	client.readdata = string.sub(client.readdata, client.data_size+1)
	client.readsize = client.readsize - client.data_size
	assert(#client.readdata == client.readsize)
	
	--解包数据
	local data = server.unpack(msg, client.data_size)
	client.data_size = nil

	if data.funcname then
		AGENT.func_call[(data.funcname)](id, data)
		return
	end

	--提取接收方handleid
	local handleid
	if string.find(data.handle, "#") then
		handleid = server.localname(data.handle)
	else
		handleid = tonumber(data.handle)
	end
	assert(handleid and handleid>0, string.format("can not find handle:", data.handle))

	--校验harbor
	assert(cfgData.harbor==data.harborid)

	--把数据发送给服务
	server.redirect(handleid, data.source, "lua", data.session, data.msg, data.sz)
end

--注册socket消息处理函数
function AGENT.dispatch()
	--socket数据 4+data
	local function dataf(id, size, data)
		local client = AGENT.clients[id]
		assert(client)
		client.readdata = client.readdata .. data
		client.readsize = client.readsize + size
		assert(#client.readdata == client.readsize)

		if client.data_size and client.data_size<=client.readsize then
			sendprotobuf(id)
			return
		end

		if client.readsize<4 then return end
		client.data_size = string.unpack("<I4", string.sub(client.readdata, 1, 4)) --data数据大小

		if client.data_size>=MaxReadDataSize then
			socket.close(id) --数据有误主动关闭socket
			server.error("harbor client read over size:", client.addr, id, client.data_size)
			return
		end
		client.readdata = string.sub(client.readdata, 5)
		client.readsize = client.readsize - 4

		if client.data_size<=client.readsize then
			sendprotobuf(id)
			return
		end
	end

	--socket连接成功
	local function connectf(id, _, addr)
		assert(AGENT.clients[id])
		AGENT.clients[id].connect = true
	end

	--socket关闭
	local function closef(id)
		assert(AGENT.clients[id])
		AGENT.sendclientclose(id)
		AGENT.clients[id] = nil
	end
	
	--socket出现错误,此时socket已经被底层关闭
	local function errorf(id)
		assert(AGENT.clients[id])
		AGENT.sendclientclose(id)
		AGENT.clients[id] = nil
	end

	socket.dispatch(dataf, connectf, closef, nil, errorf)
end

--通知distribute agent已关闭
function AGENT.sendclientclose(reserve_id)
	server.sendname(".distribute", "harbor", server.pack({
		funcname = "clientclose",
		reserve_id = reserve_id,
	}))
	server.sendname(".distribute", "harbor", server.pack({
		funcname = "delharbor",
		harborid = AGENT.clients[reserve_id].harborid,
	}))
end

--给予远程harbor发送数据
function AGENT.cmds.harborsend(params, source)
	local reserve_id = params.reserve_id
	local harborid = params.harborid
	local client = AGENT.clients[reserve_id]
	assert(client and client.harborid==harborid)

	local data = {}
	data.handle = params.handle --接收方handleid or handlename
	data.source = params.source --发送方handleid
	data.harborid = harborid --接收方harborid
	data.session = params.session --发送方会话id
	data.msg = params.msg --发送数据
	data.sz = params.sz --发送数据大小
	local msg = server.packstring(data)

	local pack_data = string.pack("<I4", string.len(msg)) .. msg
	socket.send(reserve_id, pack_data)
end

--有客户端harbor连入本地服务器harbor
function AGENT.cmds.accept(params, source)
	local reserve_id = params.reserve_id
	assert(not AGENT.clients[reserve_id])
	
	local data = {}
	data.readdata = "" --读取到的数据
	data.readsize = 0 --读取到数据大小
	data.data_size = nil --当前解包数据大小
	data.connect = false --是否已连接成功
	data.addr = params.addr --客户端地址
	data.reserve_id = reserve_id --客户端reserve_id
	data.harborid = nil --远程id
	AGENT.clients[reserve_id] = data

	socket.start(reserve_id)
end

--通知harbor信息过来
function AGENT.func_call.OnHarborInfo(reserve_id, data)
	local client = AGENT.clients[reserve_id]
	assert(client)
	client.harborid = data.harborid
	server.sendname(".distribute", "harbor", server.pack({
		["funcname"] = "addharbor",
		["harborid"] = data.harborid,
		["reserve_id"] = reserve_id,
	}))
end

server.start(function()
	AGENT.dispatch()
	server.dispatch("lua", function(msg, sz, session, source, retfunc)
		local params = server.unpack(msg, sz)
		if retfunc then
			return retfunc(params)
		end
		local funcname = params.funcname
		AGENT.cmds[funcname](params, source)
	end)
end)