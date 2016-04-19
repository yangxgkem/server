clsDb = clsModuleBase:Inherit{__ClassType = "db"}

function clsDb:__init__()
    Super(clsDb).__init__(self)

    --主键
    self.primary_key = "id"

    --表名称
    self._table = ""

    --数据库对象
    self.mysqlObj = clsMysql:new()
end

--链接数据库
function clsDb:connect()
    return self.mysqlObj:connect()
end

--是否已经连接
function clsDb:is_connect()
    return self.mysqlObj:is_connect()
end

--设置数据库
function clsDb:selectdb(database)
    return self.mysqlObj:selectdb(database)
end

--查询数据
function clsDb:query(query, escape, cache)
    return self.mysqlObj:query(query, escape, cache)
end

--转义字符
function clsDb:escape(query)
    return self.mysqlObj:escape(query)
end

--获取待执行 query
function clsDb:get_query()
    return self.mysqlObj:get_query()
end

--清空待执行 query
function clsDb:clean_query()
    return self.mysqlObj:clean_query()
end

--设置表
function clsDb:set_table(tbl)
    self._table = tbl
end

--设置主键
function clsDb:set_primary_key(primary_key)
    self.primary_key = primary_key
end

--智能拼凑出where条件
function clsDb:_set_where(params)
    for field, filter in pairs(params) do
        if type(filter) == mTABLETYPE then
            self.mysqlObj:where_in({[field]=filter})
        else
            if type(field) == mNUMBERTYPE then
                self:where({[self.primary_key]=filter})
            else
                self.mysqlObj:where({[field]=filter})
            end
        end
    end
end

--根据主键获得单条数据
function clsDb:get(primary_key)
    return self:get_by({[self.primary_key]=primary_key})
end

--根据条件获得单条数据
function clsDb:get_by(wheres)
    self.mysqlObj:get(self._table)
    self:_set_where(wheres)
    local data = self.mysqlObj:run_query()
    if not data or data.size <= 0 then return end
    local ret = {}
    for k,v in pairs(data.record_list[1]) do
        ret[data.fieldnamelist[k]] = v
    end
    return ret
end

--基于主键范围获得多条数据
function clsDb:get_many(primary_keys)
    self.mysqlObj:get(self._table)
    self:_set_where({[self.primary_key]=primary_keys})
    local data = self.mysqlObj:run_query()
    if not data or data.size <= 0 then return end
    local ret = {}
    for k,v in pairs(data.record_list) do
        ret[k] = {}
        for kk,vv in pairs(v) do
            ret[k][data.fieldnamelist[kk]] = vv
        end
    end
    return ret
end

--根据条件获得多条数据
function clsDb:get_many_by(wheres)
    self.mysqlObj:get(self._table)
    self:_set_where(wheres)
    local data = self.mysqlObj:run_query()
    if not data or data.size <= 0 then return end
    local ret = {}
    for k,v in pairs(data.record_list) do
        ret[k] = {}
        for kk,vv in pairs(v) do
            ret[k][data.fieldnamelist[kk]] = vv
        end
    end
    return ret
end

--插入一条记录, 返回已插入条数
function clsDb:insert(data)
    self.mysqlObj:insert(self._table, data)
    local data = self.mysqlObj:run_query()
    if not data then return end
    return data.size
end

--依据主键更新单条数据, 返回已更新条数
function clsDb:update(primary_key, data)
    self.mysqlObj:update(self._table, data)
    self:_set_where({[self.primary_key]=primary_key})
    local data = self.mysqlObj:run_query()
    if not data then return end
    return data.size
end

--根据条件去更新数据, 返回已更新条数
function clsDb:update_by(wheres, data)
    self.mysqlObj:update(self._table, data)
    self:_set_where(wheres)
    local data = self.mysqlObj:run_query()
    if not data then return end
    return data.size
end

--根据主键的值去删除单条数据, 返回已删除条数
function clsDb:delete(primary_key)
    self.mysqlObj:delete(self._table)
    self:_set_where({[self.primary_key]=primary_key})
    local data = self.mysqlObj:run_query()
    if not data then return end
    return data.size
end

--根据条件去删除数据, 返回已删除条数
function clsDb:delete_by(wheres)
    self.mysqlObj:delete(self._table)
    self:_set_where(wheres)
    local data = self.mysqlObj:run_query()
    if not data then return end
    return data.size
end

--获得全部数据的行数
function clsDb:count_all()
    self.mysqlObj:count_all(self._table)
    local data = self.mysqlObj:run_query()
    if not data then return end
    return tonumber(data.record_list[1][1])
end

--根据条件获得数据的行数
function clsDb:count_by(wheres)
    self.mysqlObj:count_all(self._table)
    self:_set_where(wheres)
    local data = self.mysqlObj:run_query()
    if not data then return end
    return tonumber(data.record_list[1][1])
end

--单表查询分页
function clsDb:get_pagination(wheres, current_page, rows_per_page)
    local total_rows = self:count_by(wheres)
    rows_per_page = rows_per_page or 20
    self.mysqlObj:get(self._table)
    self:_set_where(wheres)
    self.mysqlObj:limit(rows_per_page, (current_page-1)*rows_per_page)
    local data = self.mysqlObj:run_query()
    if not data then return end

    local ret = {}
    ret.rows_per_page = rows_per_page
    ret.total_rows = total_rows
    ret.current_page = current_page
    if total_rows%rows_per_page == 0 then
        ret.total_pages = total_rows/rows_per_page
    else
        ret.total_pages = math.ceil(total_rows/rows_per_page)
    end
    ret.pagination_data = {}
    for k,v in pairs(data.record_list) do
        ret.pagination_data[k] = {}
        for kk,vv in pairs(v) do
            ret.pagination_data[k][data.fieldnamelist[kk]] = vv
        end
    end
    return ret
end
