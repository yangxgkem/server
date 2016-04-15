clsMysql = clsObject:Inherit()

function clsMysql:__init__()
	--服务器IP
	self.host = "127.0.0.1"

	--服务器端口
	self.port = 3306

	--账号
	self.username = "root"

	--密码
	self.password = "root"

	--链接数据库
	self.database = "test"

	--设置编码方式
	self.char_set = "utf8"

	--链接成功 client 对象
	self.client = nil

	--最近一次查询结果 result 对象
	self.result = nil
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
    mysql.setcharset(self.client, self.char_set)
    mysql.selectdb(self.client, self.database)

    return true
end

--设置数据库
function clsMysql:selectdb(database)
	if self.database == database then return end
	mysql.selectdb(self.client, database)
	self.database = database
end

--查询数据
function clsMysql:query(query, escape)
	if self.result then
		mysql.gc_result(self.client)
		self.result = nil
	end
	if escape then 
		query = mysql.escape(self.client, query)
	end
	local ret,errmsg = mysql.query(self.client, query)
	if (errmsg) then
    	_RUNTIME_ERROR(errmsg)
    	return
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