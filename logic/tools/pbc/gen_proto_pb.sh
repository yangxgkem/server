#!/bin/sh

################################
#将proto协议文件，编译成pb文件
#环境依赖：
#1)wget http://protobuf.googlecode.com/files/protobuf-2.4.1.tar.gz
#2)tar zxf protobuf-2.4.1.tar.gz
#3)cd protobuf-2.4.1
#4)./configure && make && make install
################################

logic_path="../.."
cd $logic_path
echo $logic_path
mkdir -p protocol/pbc

#delete all pb file first,for svn manage
for pbfile in `find protocol/pbc -name "*.pb"`
do
	echo "delete $pbfile"
done

cd common/proto
for protofile in `find ./ -name "*.proto"`
do
	echo $protofile
	
	out_path=`dirname "$protofile"`
	bname=`basename "$protofile"`
	bname=`echo $bname|sed 's/\.proto/\.pb/'`
	mkdir -p $logic_path/protocol/pbc/$out_path
	protoc -o$logic_path/protocol/pbc/$out_path/$bname $protofile
	if [ "$?" != "0" ];then
		echo "编译协议文件出错"
		exit 1;
	fi
done

