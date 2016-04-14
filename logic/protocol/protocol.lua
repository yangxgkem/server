function regist_one_pb(proto_file, proto_path)
	local proto_path = proto_path or "./logic/protocol/pbc"
	for v in lfs.dir(proto_path) do
		if v ~= "." and v ~= ".." and v ~= ".svn" then
			local TmpPath = proto_path.."/"..v
			local attr = lfs.attributes(TmpPath)
			if attr.mode == "directory" then
				regist_one_pb(proto_file, TmpPath)
			elseif attr.mode == "file" then
				if string.match(v, "%.pb$") and v==proto_file then
					pbc.register_file(TmpPath)
				end
			end
		end
	end
end

function regist_all_pb(proto_path)
	local proto_path = proto_path or "./logic/protocol/pbc"
	for v in lfs.dir(proto_path) do
		if v ~= "." and v ~= ".." and v ~= ".svn" then
			local TmpPath = proto_path.."/"..v
			local attr = lfs.attributes(TmpPath)
			if attr.mode == "directory" then
				regist_all_pb(TmpPath)
			elseif attr.mode == "file" then
				if string.match(v, "%.pb$") then
					pbc.register_file(TmpPath)
				end
			end
		end
	end
end

Import("./logic/protocol/protocol_data.lua")
Import("./logic/protocol/protocol_service.lua")
function GET_PROTO_NAME(proto_id)
	return PROTOCL_INFO[proto_id]
end

function GET_PROTOID(name)
	return PROTOCL_INFO[name]
end

function GET_PROTOID_SERVICE(proto_id)
	return PROTOCL_SERVICE_INFO[(PROTOCL_INFO[proto_id])]
end

function pbc_send_msg(reserve_ids, proto_name, tbldata, islsend)
	local proto_id = GET_PROTOID(proto_name)
	if not proto_id then return end
	local proto_data = pbc.encode(proto_name, tbldata)
	if not proto_data then return end
	local proto_data_length = string.len(proto_data)
	local pack_data = string.pack("<I4I2",proto_data_length,proto_id)..proto_data
	local send = islsend and socket.lsend or socket.send
	if type(reserve_ids == mTABLETYPE) then
		for _,_rid in pairs(reserve_ids) do
			send(_rid, pack_data)
		end
	else
		send(reserve_ids, pack_data)
	end
end

regist_all_pb()