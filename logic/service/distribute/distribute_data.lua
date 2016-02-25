local harbor1 = {
	host = "127.0.0.1",
	port = 6002,
	services = {"#scene","#chat"},
}

local harbor2 = {
	host = "127.0.0.1",
	port = 6004,
	services = {"#db"},
}


local distribute_data = {
	[1] = harbor1,
	[2] = harbor2,
}
local distribute_data2 = {}
for _harbor,_data in pairs(distribute_data) do
	for _,_service in pairs(_data.services) do
		distribute_data2[_service] = _harbor
	end
end

return distribute_data, distribute_data2