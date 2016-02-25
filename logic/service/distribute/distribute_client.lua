dofile("./logic/base/preload.lua")

local MinHarborId, MaxHarborId = ...
local MaxReadDataSize = 65535 --最大读取数据大小

local DISTRIBUTE_CLIENT = {}
DISTRIBUTE_CLIENT.cmds = {} --消息函数
DISTRIBUTE_CLIENT.func_call = {} --socket消息处理函数

local HarborClientList = {} --harborid指向socket信息
local ReserveToHarbor = {} --reserve_id 指向 harborid

--处理数据
local function sendprotobuf(id)
	local harborid = ReserveToHarbor[id]
	local client = HarborClientList[harborid]
	local msg = string.sub(client.readdata, 1, client.data_size)
	client.readdata = string.sub(client.readdata, client.data_size+1)
	client.readsize = client.readsize - client.data_size
	assert(#client.readdata == client.readsize)
	
	--解包数据
	local data = server.unpack(msg, client.data_size)
	client.data_size = nil
	print(sys.dump(data))

	if data.funcname then
		DISTRIBUTE_CLIENT.func_call[(data.funcname)](id, data)
		return
	end

	--提取接收方handleid
	local handleid
	if string.find(data.handle, "#") then
		handleid = server.localname(data.handle)
	else
		handleid = tonumber(data.handle)
	end
	assert(handleid and handleid>0, string.format("can not find handle:%s", data.handle))

	--校验harbor
	assert(cfgData.harbor==data.harborid)

	--把数据发送给服务
	server.redirect(handleid, data.source, "lua", data.session, data.msg, data.sz)
end

--注册socket消息处理函数
function DISTRIBUTE_CLIENT.dispatch()
	--socket数据 4+data
	local function dataf(id, size, data)
		local harborid = ReserveToHarbor[id]
		assert(harborid)
		local client = HarborClientList[harborid]
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

	--连接成功
	local function connectf(id, _, addr)
		local harborid = ReserveToHarbor[id]
		assert(harborid)
		HarborClientList[harborid].connect = true
		local protomsg = {}
		protomsg.funcname = "OnHarborInfo"
		protomsg.harborid = cfgData.harbor
		DISTRIBUTE_CLIENT.harborsend2(id, protomsg)
		server.sendname(".distribute", "harbor", server.pack({
			["funcname"] = "addharbor",
			["harborid"] = harborid,
			["reserve_id"] = id,
		}))
	end

	--socket关闭
	local function closef(id)
		local harborid = ReserveToHarbor[id]
		assert(harborid)
		DISTRIBUTE_CLIENT.clientclose(id)
	end

	--socket处理失败
	local function errorf(id)
		local harborid = ReserveToHarbor[id]
		assert(harborid)
		DISTRIBUTE_CLIENT.clientclose(id)
	end

	socket.dispatch(dataf, connectf, closef, nil, errorf)
end

--注册需要连接的harbor
function DISTRIBUTE_CLIENT.registerHarbor()
	local harborid = cfgData.harbor
	for _harbor,_data in pairs(distributeData) do
		--只主动连接比自己habor小的服务器
		if _harbor < harborid and _harbor >= MinHarborId and _harbor <= MaxHarborId then
			print("add har:", _harbor)
			local data = {}
			data.readdata = "" --读取到的数据
			data.readsize = 0 --读取到数据大小
			data.data_size = nil --当前解包数据大小
			data.connect = false --是否已连接成功
			data.addr = _data.host --客户端地址
			data.port = _data.port --端口
			data.reserve_id = nil --客户端reserve_id
			HarborClientList[_harbor] = data
		end
	end
end

--心跳检测连接状态
local function checkconnect()
	for _harbor,_data in pairs(HarborClientList) do
		if not _data.connect and not _data.reserve_id then
			local reserve_id = socket.open(_data.addr, _data.port)
			_data.reserve_id = reserve_id
			ReserveToHarbor[reserve_id] = _harbor
		end
	end
	server.timeout(300, checkconnect)
end

--关闭某socket
function DISTRIBUTE_CLIENT.clientclose(id)
	local harborid = ReserveToHarbor[id]
	ReserveToHarbor[id] = nil
	local data = HarborClientList[harborid]
	data.reserve_id = nil
	if data.connect then
		data.connect = false
		server.sendname(".distribute", "harbor", server.pack({
			funcname = "delharbor",
			harborid = harborid,
		}))
	end
end

--给予远程harbor某服务发送数据
function DISTRIBUTE_CLIENT.cmds.harborsend(params, source)
	local reserve_id = params.reserve_id
	local harborid = params.harborid
	local client = distribute_agent.clients[reserve_id]
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

--给予远端habor发送数据
function DISTRIBUTE_CLIENT.harborsend2(reserve_id, data)
	local msg = server.packstring(data)
	local pack_data = string.pack("<I4", string.len(msg)) .. msg
	socket.send(reserve_id, pack_data)
end

server.start(function()
	DISTRIBUTE_CLIENT.dispatch()
	DISTRIBUTE_CLIENT.registerHarbor()

	server.dispatch("lua", function(msg, sz, session, source)
		local params = server.unpack(msg, sz)
		if retfunc then
			return retfunc(params)
		end
		local funcname = params.funcname
		DISTRIBUTE_CLIENT.cmds[funcname](params, source)
	end)
	
	server.timeout(100, checkconnect)
end)