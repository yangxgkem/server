local xpcall = xpcall
local string = string
local type = type
local os = os
local table = table
local tonumber = tonumber
local unpack = unpack
local debug = debug

function TryCall(Func, ...)
	local arg = {...}
	local flag,err = xpcall(function () return Func(unpack(arg)) end , debug.excepthook)
	if not flag then
		_RUNTIME_ERROR("try call err:", err)
	end
	return flag, err
end


----------------时间管理，常用函数---------------

local sub_time = 0

--获得活动时间(用于时间测试)
function GetPartyTime()
	return (server.time() - sub_time)
end

--设置活动时间（用于时间调试）
function SetPartyTime(year,mon,day,hour,min,sec)
	sub_time = server.time() - TIME.MkTime(year,mon,day,hour,min,sec)
	return (server.time() - sub_time)
end

--将时间变成秒数
function MkTime(year,mon,day,hour,min,sec)
	local tbl = {["year"] = year, ["month"] = mon, ["day"] = day, ["hour"] = hour, ["min"] = min, ["sec"] = sec} 
    return os.time(tbl)
end

--把秒数换成字窜
function ShortTime(TimeSec)
	TimeSec = TimeSec or server.time()
	return os.date("%Y-%m-%d %H:%M:%S", TimeSec)
end

--取时间表
function GetTimeTbl(TimeSec)
	TimeSec = TimeSec or server.time()
	local TimeTbl = {year = os.date("%Y", TimeSec),
			month = os.date("%m", TimeSec),
			day = os.date("%d", TimeSec),
			hour = os.date("%H", TimeSec),
			min = os.date("%M", TimeSec),
			sec = os.date("%S", TimeSec), }
	return TimeTbl
end

--获取今天是星期几
function GetRelaDayOfWeekNo()
	local now_time = GetPartyTime()
	if now_time then
		return os.date("*t",now_time).wday
	else
		return os.date("*t").wday
	end
end