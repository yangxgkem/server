clsDb = clsModuleBase:Inherit{__ClassType = "db"}

function clsDb:__init__()
	Super(clsDb).__init__(self)
	
	--数据库对象
	self.mysqlObj = clsMysql:New()
end

--链接数据库
function clsDb:connect()
	return self.mysqlObj:connect()
end

--设置数据库
function clsDb:selectdb(database)
	return self.mysqlObj:selectdb(database)
end

--查询数据
function clsDb:query(query, escape)
	return self.mysqlObj:query(query, escape)
end

--转义字符
function clsDb:escape(query)
	return self.mysqlObj:escape(query)
end

--缓存写入指令,利用定时器定时执行
function clsDb:save(query, escape, now)
	if now then
		return self.mysqlObj:query(query, escape)
	else
		return self.mysqlObj:save_cache(query, escape)
	end
end

function clsDb:s2s_db_query(protomsg)
	local query = protomsg.query
	local escape = protomsg.escape
	return self:query(query, escape)
end