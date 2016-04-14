# server
一个轻量级的actor模式框架，改自云风skynet

修改云风skynet框架，命名为server，简化了底层，抛弃了大量.so功能，也抛弃了内存分配jemalloc，保留核心部分.

logic是业务层代码，当前只做了业务tcp服务logicsocket

当前框架只用于linux，并不支持mac

编译 make linux

skynet：https://github.com/cloudwu/skynet

lua5.3doc：http://cloudwu.github.io/lua53doc/manual.html

----------------------------------------
2016.4.8

添加场景aoi

开发笔记 (13) : AOI 服务的设计与实现： http://blog.codingnow.com/2012/03/dev_note_13.html

开发笔记(26) : AOI 以及移动模块： http://blog.codingnow.com/2012/09/dev_note_26.html

开发笔记(28) : 重构优化： http://blog.codingnow.com/2012/11/dev_note_28.html

----------------------------------------
2016.4.13

添加 mysql