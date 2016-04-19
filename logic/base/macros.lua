--protobuff int32 最大数
mMAX_NUMBER = 2000000000

--字符串类型
mSTRINGTYPE = type("string")

--数字类型
mNUMBERTYPE = type(1)

--数组类型
mTABLETYPE =  type({})

--服务器承载玩家数量
mMAX_ONLINE_USER = 65535

--常用时间定义, 秒数
mONE_WEEK = 604800
mONE_DAY = 86400
mONE_HOUR = 3600

--玩家所处状态
mST_UNKNOWN = 101            --未知状态
mST_LOGIN = 201              --正在登录
mST_RESTORE = 202            --数据恢复
mST_ENTER_GAME = 203         --数据恢复已经成功, 正在处理登陆逻辑, 但还没有完全进入场景。
mST_ENTER_SCENE = 204        --已经进入场景。
mST_GAME_OK = 205            --游戏正常。
mST_KEEP_IN_FIGHT = 206      --战斗中下线。
mST_LOGOUT = 999             --已经登出。
