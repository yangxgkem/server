--逻辑层超级父类


--获取一个class的父类
function Super(TmpClass)
	return TmpClass.__SuperClass
end

--暂时没有一个比较好的方法来防止将Class的table当成一个实例来使用
--大家命名一个Class的时候一定要和其产生的实例区别开来。
clsObject = {
	--用于区别是否是一个对象 or Class or 普通table
	__ClassType = "<base class>"
}

--类继承接口
function clsObject:Inherit(o)	
	o = o or {}
	
	--给clsObject添加一个子类
	if not self.__SubClass then
		self.__SubClass = {}
		setmetatable(self.__SubClass, {__mode="v"})
	end
	table.insert(self.__SubClass, o)
	
	--把父类 clsObject 各个属性接口继承给子类
	--没有对 clsObject 属性做深拷贝,只有对类的一级属性做拷贝
	--此处不能使用 setmetatable(o, {__index = self}),要设置 metatable 必须放到子类里去弄,原因是当
	--父类某属性更新后,它会去不断寻找它的子类更新此属性,子类又会去找属于它自己的子类,如果子类
	--的 __SubClass 为nil,那么根据元表 __index 定义,它就会去取父类的 __SubClass ,最后就会出现死循环
	for k, v in pairs(self) do
		if not o[k] then
			o[k]=v
		end
	end
	o.__SubClass = nil
	--设置子类的父类为 clsObject
	o.__SuperClass = self

	return o
end

function clsObject:AttachToClass(Obj)
	setmetatable(Obj, {__ObjectType="<base object>", __index = self})
	return Obj
end

--创建一个对象
function clsObject:New(...)
	local o = {}

	--没有初始化对象的属性，对象属性应该在init函数中显示初始化
	--如果是子类,应该在自己的init函数中先调用父类的init函数

	self:AttachToClass(o)
	if o.__init__ then
		o:__init__(...)
	end
	return o
end

function clsObject:__init__()
end

function clsObject:OnCreate()
end

function clsObject:IsClass()
	return true
end

function clsObject:Destroy()
end

--把父类属性更新到各个子类中,前提条件是:原子类的属性与父类属性一样
function clsObject:Update(OldSelf)
	if not self.__SubClass then
		return
	end
	for _, Sub in pairs(self.__SubClass) do
		local OldSub = UTIL.Copy(Sub) --获取一级属性
		for k, v in pairs(self) do
			if Sub[k] == OldSelf[k] then
				Sub[k] = self[k]
			end
		end
		Sub:Update(OldSub)
	end
end
