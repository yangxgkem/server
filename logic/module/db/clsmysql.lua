clsMysql = clsModuleBase:Inherit{__ClassType = "mysql"}

function clsMysql:__init__()
    Super(clsMysql).__init__(self)

    --服务器IP
    self.host = "127.0.0.1"

    --服务器端口
    self.port = 3306

    --账号
    self.username = "root"

    --密码
    self.password = "root"

    --链接数据库
    self.database = "demo"

    --设置编码方式
    self.char_set = "utf8"

    --链接成功 client 对象
    self.client = nil

    --已连接成功
    self._connect = false

    --最近一次查询结果 result 对象
    self.result = nil

    --条件拼凑
    self._query = ""

    --缓存指令,定时执行
    self.cache_query = {}
end

--链接数据库
function clsMysql:connect()
    local dbarg = {
        host = self.host,
        port = self.port,
        user = self.username,
        password = self.password,
        db = self.database,
    }
    local client,errmsg = mysql.newclient(dbarg)
    if (errmsg) then
        _RUNTIME_ERROR(errmsg)
        return
    end
    self.client = client
    self._connect = true
    mysql.setcharset(self.client, self.char_set)
    mysql.selectdb(self.client, self.database)
    server.error("Mysql connect running............"..self.database)
    return true
end

--是否已经连接
function clsMysql:is_connect()
    return self._connect and true or false
end

--设置数据库
function clsMysql:selectdb(database)
    if self.database == database then return end
    mysql.selectdb(self.client, database)
    self.database = database
end

--查询数据
function clsMysql:query(query, escape, cache)
    if escape then
        query = mysql.escape(self.client, query)
    end
    if cache then
        table.insert(self.cache_query, query)
        return true
    end
    if self.result then
        mysql.gc_result(self.client)
        self.result = nil
    end
    local ret,errmsg = mysql.query(self.client, query)
    if not ret and errmsg then
        _RUNTIME_ERROR(errmsg)
        return
    elseif ret and errmsg then
        local data = {}
        data.size = ret
        return data
    end
    self.result = true
    --开始整合数据
    local data = {}
    data.size = mysql.size(self.client)
    data.fieldnamelist = mysql.fieldnamelist(self.client)
    data.record_list = mysql.record_list(self.client)
    return data
end

--转义字符
function clsMysql:escape(query)
    return mysql.escape(self.client, query)
end

--执行多少条缓存指令
function clsMysql:run_cache_query(num)
    num = num or 1
    if num < 1 or #self.cache_query < 0 then return end
    if num > #self.cache_query then
        num = #self.cache_query
    end
    local query
    for i=1,num do
        query = table.remove(self.cache_query, 1)
        self:query(query)
    end
end

--获取待执行 query
function clsMysql:get_query()
    return self._query
end

--清空待执行 query
function clsMysql:clean_query()
    self._query = ""
end

--根据 self._query 执行指令
function clsMysql:run_query(escape, cache)
    local query = self._query
    self:clean_query()
    if self._connect then
        return self:query(query, escape, cache)
    else
        local params = {["query"]=query, ["escape"]=escape, ["cache"]=cache}
        return service_logic_call(".db", "s2s_db_query", params)
    end
end

-- get
function clsMysql:get(tbl, limit, offset)
    if limit and offset then
        self._query = string.format("select * from %s limit %s,%s", tbl, offset, limit)
    else
        self._query = string.format("select * from %s", tbl)
    end
    return self
end

-- get_where
function clsMysql:get_where(tbl, wheres, limit, offset)
    self._query = string.format("select * from %s", tbl)
    local index = 1
    for field, filter in pairs(wheres) do
        if index == 1 then
            self._query = string.format("%s where %s = '%s'", self._query, field, filter)
        else
            self._query = string.format("%s and %s = '%s'", self._query, field, filter)
        end
    end
    if limit and offset then
        self._query = string.format("%s limit %s,%s", self._query, offset, limit)
    end
    return self
end

--拼凑 count 条件
function clsMysql:count_all(tbl)
    self._query = string.format("select count(*) from %s", tbl)
    return self
end

--拼凑 where 条件
function clsMysql:where(wheres)
    for field, filter in pairs(wheres) do
        if string.find(self._query, "where") then
            self._query = string.format("%s and %s = '%s'", self._query, field, filter)
        else
            self._query = string.format("%s where %s = '%s'", self._query, field, filter)
        end
    end
    return self
end

--拼凑 or_where 条件
function clsMysql:or_where(wheres)
    for field, filter in pairs(wheres) do
        if string.find(self._query, " or ") then
            self._query = string.format("%s and %s = '%s'", self._query, field, filter)
        else
            self._query = string.format("%s or %s = '%s'", self._query, field, filter)
        end
    end
    return self
end

--拼凑 where_in 条件
function clsMysql:where_in(wheres)
    for field, filter in pairs(wheres) do
        if string.find(self._query, "where") then
            self._query = string.format("%s and %s in (%s)", self._query, field, table.concat(filter, ","))
        else
            self._query = string.format("%s where %s in (%s)", self._query, field, table.concat(filter, ","))
        end
    end
    return self
end

--拼凑 or_where_in 条件
function clsMysql:or_where_in(wheres)
    for field, filter in pairs(wheres) do
        if string.find(self._query, " or ") then
            self._query = string.format("%s and %s in (%s)", self._query, field, table.concat(filter, ","))
        else
            self._query = string.format("%s or %s in (%s)", self._query, field, table.concat(filter, ","))
        end
    end
    return self
end

--拼凑 limit
function clsMysql:limit(limit, offset)
    self._query = string.format("%s limit %s,%s", self._query, offset, limit)
    return self
end

--拼凑插入数据
function clsMysql:insert(tbl, data)
    local key = ""
    local value = ""
    for k,v in pairs(data) do
        if key == "" then
            key = string.format("%s", k)
        else
            key = string.format("%s, %s", key, k)
        end
        if value == "" then
            value = string.format("'%s'", v)
        else
            value = string.format("%s, '%s'", value, v)
        end
    end
    self._query = string.format("insert into %s (%s) value (%s)", tbl, key, value)
    return self
end

--拼凑更新数据
function clsMysql:update(tbl, data)
    local msg = ""
    for k,v in pairs(data) do
        if msg == "" then
            msg = string.format("%s = '%s'", k, v)
        else
            msg = string.format("%s, %s = '%s'", msg, k, v)
        end
    end
    self._query = string.format("update %s set %s", tbl, msg)
    return self
end

--拼凑删除数据
function clsMysql:delete(tbl)
    self._query = string.format("delete from %s", tbl)
    return self
end
