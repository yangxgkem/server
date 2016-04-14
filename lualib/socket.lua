local assert = assert
local driver = require "socketdriver"
local server = require "server"

SERVER_SOCKET_TYPE_DATA = 1
SERVER_SOCKET_TYPE_CONNECT = 2
SERVER_SOCKET_TYPE_CLOSE = 3
SERVER_SOCKET_TYPE_ACCEPT = 4
SERVER_SOCKET_TYPE_ERROR = 5

local socket = {}
socket.dispatchs = {}

--注册消息处理
function socket.dispatch(dataf, connectf, closef, acceptf, errorf)
	--socket数据(reserve_id, 数据大小, 数据) (id, size, data)
	socket.dispatchs[SERVER_SOCKET_TYPE_DATA] = dataf
	--socket连接成功(reserve_id, 占位符, 地址) (id, _, addr)
	socket.dispatchs[SERVER_SOCKET_TYPE_CONNECT] = connectf
	--socket关闭(reserve_id, 占位符, 占位符) (id)
	socket.dispatchs[SERVER_SOCKET_TYPE_CLOSE] = closef
	--有socket连入(服务器reserve_id, 客户端reserve_id, 客户端地址) (serverid, clientid, clientaddr)
	socket.dispatchs[SERVER_SOCKET_TYPE_ACCEPT] = acceptf
	--socket出现错误(reserve_id, 占位符, 占位符) (id)
	socket.dispatchs[SERVER_SOCKET_TYPE_ERROR] = errorf

	local function func(session, source, socktype, id, size, data)
		socket.dispatchs[socktype](id,size,data)
	end
	server.dispatch(server.ptypes.PTYPE_SOCKET, func)
end

--客户端连接服务器,返回reserve_id
function socket.open(addr, port)
	local id = driver.connect(addr,port)
	return id
end

--常用句柄fd有3个:0(stdin 标准输入), 1(stdout 标准输出), 2(stderr 标准错误输出)
function socket.bind(os_fd)
	local id = driver.bind(os_fd)
	return id
end

--启动服务器socket,或客户端socket
function socket.start(id)
	return driver.start(id)
end

--关闭socket
function socket.close(id)
	return driver.close(id)
end

--往高优先级写数据,如果data为字符串,size可为空
function socket.send(id, data, size)
	driver.send(id, data, size)
end

--往低优先级写数据,如果data为字符串,size可为空
function socket.lsend(id, data, size)
	driver.send(id, data, size)
end

--启动服务器socket,执行socket,bind,listen最后返回 reserve_id
--backlog 最大维护待处理连接队列个数
function socket.listen(host, port, backlog)
	if port == nil then
		host, port = string.match(host, "([^:]+):(.+)$")
		port = tonumber(port)
	end
	return driver.listen(host, port, backlog)
end

--解包底层server socket数据
function socket.unpack(msg, size)
	return driver.unpack(msg, size)
end

--主动注册消息事件
server.register_protocol({
	name = "socket",
	ptype = server.ptypes.PTYPE_SOCKET,
	unpack = driver.unpack,
})

return socket