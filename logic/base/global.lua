--char base
Import("./logic/char/char_base.lua")
CHAR_MGR = Import("./logic/char/char_mgr.lua")

--module base
Import("./logic/module/module_base.lua")
MODULE_MGR = Import("./logic/module/module_mgr.lua")

--socket
SOCKET_MGR = Import("./logic/module/socket/socket_mgr.lua")
Import("./logic/module/socket/clssocket_base.lua")
Import("./logic/module/socket/clssocket_server.lua")
Import("./logic/module/socket/clssocket_agent.lua")
Import("./logic/module/socket/clssocket_client.lua")
Import("./logic/module/socket/clssocket_login.lua")

--db
Import("./logic/module/db/clsdb.lua")
Import("./logic/module/db/clsmysql.lua")
DB_OBJ = clsDb:New()

--login
LOGIN = Import("./logic/module/login/login.lua")


--声明全局对象,在适当服务里进行创建
DbObj = nil
LoginObj = nil
SocketClientObj = nil
SocketObj = nil
