local harbor = {}

--远方client_obj列表
harbor.client_map = {}
setmetatable(harbor.client_map, {__mode = "v"})

--本地client_obj列表
harbor.client_harbor_map = {}
setmetatable(harbor.client_harbor_map, {__mode = "v"})

--远方 handleid/name = client_obj
harbor.harbor_map = {}
setmetatable(harbor.harbor_map, {__mode = "v"})

--本地服务地址
harbor.handle_map = {}

--港口列表
harbor.harbor_list = {
    [1] = "127.0.0.1:6002",
    [2] = "127.0.0.1:6004",
}

--缓存服务地址
function harbor.s2s_harbor_cache(params)
    harbor.handle_map[params.handle] = {
        ["handle"] = params.handle,
        ["name"] = params.name,
    }
end

function harbor.get_client_by_handle(handleid)
    return harbor.harbor_map[handleid]
end

--有港口客户端接入
function harbor.acceptf(protomsg)
    local reserve_id = protomsg.reserve_id
    local addr = protomsg.addr
    local client_obj = clsHarborClient:new(protomsg)
    SOCKET_MGR.add_socket_id(reserve_id, client_obj)
    harbor.client_map[reserve_id] = client_obj
    client_obj:transfer()
end

--将本地服务发送给远方港口
function harbor.send_handle_list(client_obj, full_send)
    local protoinfo = {}
    protoinfo.list = {}
    for handle,info in pairs(harbor.handle_map) do
        if not info.is_send or full_send then
            info.is_send = true
            local tmp = {}
            tmp.handle = handle
            tmp.name = info.name
            table.insert(protoinfo.list, tmp)
        end
    end
    pbc_send_msg(client_obj:get_rid(), "h2h_harbor_handle_list", protoinfo)
end

--把远方港口的服务列表一一对应到 client obj
function harbor.h2h_harbor_handle_list(rid, protomsg)
    local client_obj = SOCKET_MGR.get_socket_by_id(rid)
    assert(client_obj)

    for _,info in pairs(protomsg.list) do
        local handle = info.handle
        harbor.harbor_map[handle] = client_obj
        if info.name then
            assert(not harbor.harbor_map[info.name])
            harbor.harbor_map[info.name] = client_obj
        end
    end
end

--心跳维护,把本地缓存服务发送给其他港口
function harbor.check_send_cache()
    for harborid,addr in pairs(harbor.harbor_list) do
        local client_obj = harbor.client_harbor_map[harborid]
        if client_obj then
            local id = client_obj:get_id()
            _RUNTIME(id)
        end
        if not harbor.client_harbor_map[harborid] and harborid ~= cfgData.harbor then
            local client_obj = clsSocketClient:new()
            client_obj:on_connect(addr)
            harbor.client_harbor_map[harborid] = client_obj
        end
    end

    for rid,client_obj in pairs(harbor.client_map) do
        if client_obj:is_connect() then
            harbor.send_handle_list(client_obj)
        end
    end
    server.timeout(100, harbor.check_send_cache)
end

--向某港口发送数据
--session: 发送方会话id
--source: 发送方handleid
--handle: 接收方handleid or handlename
--typename: 发送类型
--params: 发送的数据 已经过 pack
--psz: 发送数据大小
function harbor.send(session, source, handle, typename, params, psz)
    print(session, source, handle, typename, params, psz)
    local client_obj = harbor.get_client_by_handle(handle)
    --此处一定要发出错误警告, 预防是 call 的请求一直处于等待
    assert(client_obj, string.format("not client_obj:%s, %s, %s, %s", session, source, handle, typename))
    local protoinfo = {}
    protoinfo.session = session
    protoinfo.source = source
    protoinfo.handle = handle
    protoinfo.typename = typename
    protoinfo.params = params
    protoinfo.psz = psz
    pbc_send_msg(client_obj:get_rid(), "h2h_harbor_send", protoinfo)
end

--接收到某港口发送过来的数据, 将数据发送到目标服务
function harbor.h2h_harbor_send(protomsg)
    local session = protomsg.session
    local source = protomsg.source
    local handle = protomsg.handle
    local typename = protomsg.typename
    local params = protomsg.params
    local psz = protomsg.psz

    server.redirect(handle, source, typename, session, params, psz)
end

function harbor.__init__()
    func_call.s2s_harbor_cache = harbor.s2s_harbor_cache
end

return harbor
