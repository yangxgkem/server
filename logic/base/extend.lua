--lua的扩展库

local string=string
local table=table
local math=math
local io=io
local pairs=pairs
local ipairs=ipairs
local tostring=tostring
local tonumber=tonumber

sys = sys or {}

--string的扩展
--一个寻找字串低效的实现，注意不支持Pattern
function string.rfind(str, sub)
	local str1 = string.reverse(str)
	local sub1 = string.reverse(sub)
	local a,b = string.find(str1, sub1, 1, true)
	if a and b then
		return #str-b+1,#str-a+1
	end
end

--判断是否字母或数字
function string.isalpha(n)
	--number
	if n >= 48 and n <= 57 then
		return true
	end
	--a ~ z
	if n >= 97 and n <= 122 then
		return true
	end
	--A ~ Z
	if n >= 65 and n <= 90 then
		return true
	end
	return false
end

--将一个str以del分割为若干个table中的元素
--n为分割次数
function string.split( line, sep, maxsplit )
	if string.len(line) == 0 then
		return {}
	end
	sep = sep or ' '
	maxsplit = maxsplit or 0
	local retval = {}
	local pos = 1   
	local step = 0
	while true do   
		local from, to = string.find(line, sep, pos, true)
		step = step + 1
		if (maxsplit ~= 0 and step > maxsplit) or from == nil then
			local item = string.sub(line, pos)
			table.insert( retval, item )
			break
		else
			local item = string.sub(line, pos, from-1)
			table.insert( retval, item )
			pos = to + 1
		end
	end     
	return retval
end

--删除空白前导空白字符或者指定字符集中的字符
function string.lstrip(str, chars)
	if chars then
		for k=1,#str do
			local sub = string.sub(str,k,k)
			--
			if not string.find(chars, sub, 1, true) then
				return string.sub(str, k)
			end
		end
	else
		return string.gsub(str, "^%s*", "")
	end
end

--删除空白后导空白字符或者指定字符集中的字符
function string.rstrip(str, chars)
	if chars then
		for k=#str,1 do
			local sub = string.sub(str,k,k)
			--
			if not string.find(chars, sub, 1, true) then
				return string.sub(str, 1, k)
			end
		end
	else
		return string.gsub(str, "%s*$", "")
	end
end

--删除空白前后空白字符或者指定字符集中的字符
function string.strip(str, chars)
	return string.rstrip(string.lstrip(str, chars), chars)
end

--判断一个字符串是否以$ends结尾
function string.endswith(str, ends)
	local i, j = string.rfind(str, ends)
	return (i and j == #str)
end

--判断一个字符串是否以$begins开始
function string.beginswith(str, begins)
	local i, j = string.find(str, begins, 1, true)
	return (i and i == 1)
end

local function dodump(value, c)
	local retval = ''
	if type(value) == 'table' then
		c = (c or 0) + 1
		if c >= 100 then error("sys.dump too deep:"..retval) end

		retval = retval .. '{'
		for k, v in pairs(value) do
			retval = retval .. '[' .. dodump(k, c) .. '] = ' ..dodump(v, c) .. ', '
		end
		retval = retval .. '}'
		return retval 
	else
		retval = _normalize(value)
	end
	return retval
end
--为了防止死循环，不让它遍历超过100个结点。谨慎使用。
function sys.dump(value)
	local ni, ret = pcall(dodump, value)
	return ret
end

function table.deepcopy(src)
    if type(src) ~= "table" then
        return src
    end
    local cache = {}
    local function clone_table(t, level)
        if not level then
            level = 0
        end

        if level > 100 then
			return t
        end

        local k, v
        local rel = {}
        for k, v in pairs(t) do
            if type(v) == "table" then
                if cache[v] then
                    rel[k] = cache[v]
                else
                    rel[k] = clone_table(v, level+1)
                    cache[v] = rel[k]
                end
            else
                rel[k] = v
            end
        end
        setmetatable(rel, getmetatable(t))
        return rel
    end
    return clone_table(src)
end

function table.member_key(Table, Value)
	for k,v in pairs(Table) do
		if v == Value then
			return k
		end
	end

	return nil
end

function table.has_key(Table, Key)
	for k,v in pairs(Table) do
		if k == Key then
			return true
		end
	end

	return false
end
--返回所有的key，作为一个数组，效率比较低，不建议频繁调用
function table.keys(Table)
	local Keys = {}
	for k,_ in pairs(Table) do
		table.insert(Keys, k)
	end

	return Keys
end

--返回所有的value，作为一个数组,效率比较低，不建议频繁调用
function table.values(Table)
	local Values = {}
	for _,v in pairs(Table) do
		table.insert(Values, v)
	end

	return Values
end

--返回一个随机的key
function table.random_key(Table)
	local Keys = table.keys(Table)
	local n = table.maxn(Keys)
	if n <= 0 then
		return nil
	end
	return Keys[math.random(1,n)]
end

--从table中随机返回n个value
function table.random_values(Table, n)
	local n = n or 1
	local Values = table.values(Table)
	if n > #Values then
		return Values
	end
	local Ret = {}
	for i=1, n do
		local R = math.random(1, #Values)
		table.insert(Ret, Values[R])
		table.remove(Values, R)
	end
	return Ret
end

--对Array(key)进行随机排序
--不改变参数Array的内容，排序的结果通过返回值返回, 并返回排序前后的key的对应关系
function table.random_sort (Array)
	local n = #Array

	local k = {}
	for i = 1, n do
		k[i] = i
	end 

	local o = {}
	local s = {}
	for i = 1, n do
		local j = math.random (n - i + 1)
		s[k[j]] = i 
		table.insert(o, Array[k[j]])
		table.remove (k, j)
	end

	return o, s 
end

--从一个mapping中随机出几个k,v对组成新的mapping
function table.random_kv(Table, n)
	local n = n or 1
	local Keys = table.keys(Table)
	if n > #Keys then
		return Table
	end
	local Ret = {}
	for i=1, n do
		local Rand = math.random(1, #Keys)
		local RandKey = Keys[Rand]
		--Ret[RandKey] = Table[RandKey]
		table.insert( Ret, Table[RandKey])
		table.remove(Keys, Rand)
	end
	return Ret
end

function table.random_kv2(Table, n)
	local n = n or 1
	local Keys = table.keys(Table)
	if n > #Keys then
		return Table
	end
	local Ret = {}
	for i=1, n do
		local Rand = math.random(1, #Keys)
		local RandKey = Keys[Rand]
		Ret[RandKey] = Table[RandKey]
		table.remove(Keys, Rand)
	end
	return Ret
end


--从table中随机返回1个value
function table.random_value(Table)
	local Values = table.values(Table)
	local n = table.maxn(Values)
	if n <= 0 then
		return nil
	end
	return Values[math.random(1,n)]
end



function table.filter(Tbl, Item)
	for i=1,#Tbl do
		if Tbl[i] == Item then
			table.remove(Tbl, i)
			i = i-1
		end
	end
end

function table.remove_array_value(Tbl,Value)
	for idx, v in ipairs (Tbl) do
		if v == Value then
			table.remove(Tbl, idx)
			return true
		end
	end

	return false
end

function table.remove_by_value(Tbl, Value)
	for k,v in pairs(Tbl) do
		if v == Value then
			Tbl[k] = nil
			return true
		end
	end
	return false
end

function table.add(To, From)
	for k,v in pairs(From) do --不能用ipairs，否则对于非数组型table有问题
		table.insert(To, v)
	end
	return To
end

--返回Array中的最大值
--注意:不是Hash-table
function table.max(Array)
	return math.max (unpack(Array))
end

--返回Array中的最小值
--注意:不是Hash-table
function table.min(Array)
	return math.min (unpack(Array))
end

--返回table的size
function table.size(Table)
	if Table then
		local Ret = 0
		for _,_ in pairs(Table) do
			Ret = Ret + 1
		end
		return Ret
	else
		return 0
	end
end

--返回number型数组的平均值(float)
function table.avg(Array)
	if #Array == 0 then
		return 0
	end
	local All = 0
	local i = 0
	for _, Data in ipairs(Array) do
		assert(type(Data) == "number")
		All = All + Data
		i = i + 1
	end
	return All/i
end

function table.empty(tbl)
--	for k,v in pairs(tbl) do
--		return false
--	end
--	return true
	return next(tbl)==nil
end

function table.clear(tbl)
	if not tbl then return end
	for k,v in pairs(tbl) do
		tbl[k] = nil
	end
end

function table.copy(tbl)
	if not tbl then return nil end
	local ret = {}
	for k,v in pairs(tbl) do
		ret[k] = v
	end
	return ret
end

function table.equal_map(tbl1, tbl2)
	if tbl1 == tbl2 then
		return true
	end
	if not tbl1 or not tbl2 then
		return false
	end
	if table.size(tbl1) ~= table.size(tbl2) then
		return false
	end
	for k,v in pairs(tbl1) do
		if tbl2[k] ~= v then
			return false
		end
	end
	return true
end

--根据权重获取元素
function table.get_value_byweight(tbl, ratekey, sumweight)
	if not tbl or #tbl==0 then return end
	if #tbl==1 then return tbl[1] end
	
	ratekey = ratekey or "Rate"
	if not sumweight then
		sumweight = 0
		for _,_data in ipairs(tbl) do
			sumweight = sumweight+_data[ratekey]
		end
	end
	
	local PreRate = 0
	local size = #tbl
	if size==0 then return end
	local Rate = math.random(sumweight)
	for i=1, size do
		if Rate>PreRate and Rate<=PreRate+tbl[i][ratekey] then
			return tbl[i]
		end
		PreRate = PreRate+tbl[i][ratekey]
	end 
end

function io.readfile(file)
	local fh = io.open(file)
	if not fh then return nil end
	local data = fh:read("*a")
	fh:close()
	return data
end

--根据表中的某个key的值进行排序,返回{k=key,v=data}的数组
function table.sort_by_value_key(tbl,value_key)
	local Keys = table.keys(tbl)
	local Size = #Keys
	for i=1, Size do
		for j=i, Size do
			if tbl[Keys[i]][value_key] and tbl[Keys[j]][value_key] then 
				if tbl[Keys[i]][value_key] > tbl[Keys[j]][value_key] then
					--交换
					local Tmp = Keys[i]
					Keys[i] = Keys[j]
					Keys[j] = Tmp
				end
			end
		end
	end
	local ret = {}
	for i,key in ipairs(Keys) do
		table.insert(ret,{k=key,v=tbl[key]})
	end
	return ret
end

--从table中随机返回n个k,v的table
function table.random_tbl(Tbl)
	local Keys = table.keys(Tbl)
	local n = #Keys
	local ret = {}
	for i=1, n do
		local R = math.random(1, #Keys)
		local key = Keys[R]
		local value = Tbl[key]
		ret[key]=value
		table.remove(Keys, R)
	end
	return ret
end

function table.has_value(Table, Key)
	for k,v in pairs(Table) do
		if v == Key then
			return k
		end
	end
end

function extdata2table(data)
	local ret = {}
	if data then 
		local kvs = string.split(data,"|")
		for _,kvdata in pairs(kvs) do
			local kv = string.split(kvdata,"=") 
			if kv[1] and kv[2] then 
				ret[kv[1]] = kv[2]
			end
		end
	end
	return ret
end

function url2table(data)
	local ret = {}
	if data then 
		local kvs = string.split(data,"&")
		for _,kvdata in pairs(kvs) do
			local kv = string.split(kvdata,"=") 
			if kv[1] and kv[2] then 
				ret[kv[1]] = kv[2]
			end
		end
	end
	return ret
end