# server
一个轻量级的actor模式框架，改自云风skynet

修改云风skynet框架，命名为server，简化了底层，抛弃了大量.so功能，也抛弃了内存分配jemalloc，保留核心部分，有些核心是
当前skynet最新版本，有些不是，例如socket，不含udp

logic是业务层代码，当前只做了业务tcp服务logicsocket和自己制定的分布式dirstribute

当前框架只用于linux，并不支持mac

编译 make linux
