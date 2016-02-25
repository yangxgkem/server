# server
一个轻量级的actor模式框架，改自云风skynet

修改云风skynet框架，命名为server，简化了底层，抛弃了大量.so功能，也抛弃了内存分配jemalloc，保留核心部分.

logic是业务层代码，当前只做了业务tcp服务logicsocket

当前框架只用于linux，并不支持mac

编译 make linux


skynet：https://github.com/cloudwu/skynet

lua5.3doc：http://cloudwu.github.io/lua53doc/manual.html
