--lua的扩展库

local string=string
local table=table
local math=math
local io=io
local pairs=pairs
local ipairs=ipairs
local tostring=tostring
local tonumber=tonumber

local function tableprint(data, index, cv)
	index = index or 0
	cv = cv or "    "
	index = index + 1
	if index > 1 then
		cv = cv.."    "
	else
		print('["table.dump"] = {')
	end
	if index > 20 then 
		error("table data is deep")
		return
	end

	for k, v in pairs(data) do    
		local msg = ""
		if (type(k) == "string") then
			msg = string.format('["%s"] = ', k);
		elseif (type(k) == "number") then
			msg = string.format('[%s] = ', k);
		else
			msg = string.format('[%s] = ', tostring(k));
		end

		if (type(v) == "table") then  
			print(string.format('%s%s{', cv, msg));
			tableprint(v, index, cv);
		elseif (type(v)=="string") then
			print(string.format('%s%s"%s",', cv, msg, v));
		elseif (type(v)=="number") then
			print(string.format('%s%s%s,', cv, msg, v));
		else
			print(string.format('%s%s%s,', cv, msg, tostring(v)));
		end
	end
	if index == 1 then
		print("}")
	else
		cv = string.sub(cv, 5)
		print(string.format("%s},", cv))
	end
end

table.dump = function(data)  
	print("\n############# table dump #############\n");
    tableprint(data);
    print("\n############# table dump #############\n");  
end