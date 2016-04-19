local time = {}

time.sub_time = 0

--获得活动时间(用于时间测试)
function time.get_party_time()
	return (server.time() - time.sub_time)
end

--设置活动时间（用于时间调试）
function time.set_party_time(year,mon,day,hour,min,sec)
	time.sub_time = server.time() - time.make_time(year,mon,day,hour,min,sec)
	return time.get_party_time()
end

--将时间变成秒数
function time.make_time(year,mon,day,hour,min,sec)
	local tbl = {["year"] = year, ["month"] = mon, ["day"] = day, ["hour"] = hour, ["min"] = min, ["sec"] = sec}
    return os.time(tbl)
end

--把秒数换成字窜
function time.short_time(time_sec)
	time_sec = time_sec or server.time()
	return os.date("%Y-%m-%d %H:%M:%S", time_sec)
end

--取时间表
function time.get_time_tbl(time_sec)
	time_sec = time_sec or server.time()
	local time_tbl = {year = os.date("%Y", time_sec),
			month = os.date("%m", time_sec),
			day = os.date("%d", time_sec),
			hour = os.date("%H", time_sec),
			min = os.date("%M", time_sec),
			sec = os.date("%S", time_sec), }
	return time_tbl
end

--获取今天是星期几
function time.get_week_no()
	local now_time = time.get_party_time()
	if now_time then
		return os.date("*t",now_time).wday
	else
		return os.date("*t").wday
	end
end

return time
