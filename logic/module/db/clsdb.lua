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
function clsDb:query(query, escape, cache)
	return self.mysqlObj:query(query, escape, cache)
end

--转义字符
function clsDb:escape(query)
	return self.mysqlObj:escape(query)
end