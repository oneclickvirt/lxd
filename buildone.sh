#!/bin/bash
# cd /root
# 名字 上一个的SSH端口 上一个的外网截止的端口
rm -rf log
lxc init images:debian/10 "$1" -c limits.cpu=1 -c limits.memory=256MiB
# 硬盘大小
lxc config device override "$1" root size=1GB
lxc config device set "$1" root limits.max 1GB
# IO
lxc config device set "$1" root limits.read 100MB
lxc config device set "$1" root limits.write 100MB
lxc config device set "$1" root limits.read 100iops
lxc config device set "$1" root limits.write 100iops
# 网速
lxc config device override "$1" eth0 limits.egress=300Mbit limits.ingress=300Mbit
# cpu
lxc config set "$1" limits.cpu.priority 0
lxc config set "$1" limits.cpu.allowance 50%
lxc config set "$1" limits.cpu.allowance 25ms/100ms
# 内存
lxc config set "$1" limits.memory.swap true
lxc config set "$1" limits.memory.swap.priority 1
# 批量创建容器
name="$1"
# 容器SSH端口 外网nat端口起 止
sshn=$(( "$2" + 1 ))
nat1=$(( "$3" + 1))
nat2=$(( "$3" + 25 ))
ori=$(date | md5sum)
passwd=${ori: 2: 9}
lxc start "$1"
sleep 1
lxc exec "$1" -- apt update -y
lxc exec "$1" -- sudo dpkg --configure -a
lxc exec "$1" -- sudo apt-get update
lxc exec "$1" -- sudo apt-get install dos2unix curl -y
lxc exec "$1" -- curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/ssh.sh -o ssh.sh
lxc exec "$1" -- chmod 777 ssh.sh
lxc exec "$1" -- dos2unix ssh.sh
lxc exec "$1" -- sudo ./ssh.sh $passwd
lxc config device add "$1" ssh-port proxy listen=tcp:0.0.0.0:$sshn connect=tcp:127.0.0.1:22
lxc config device add "$1" nattcp-ports proxy listen=tcp:0.0.0.0:$nat1-$nat2 connect=tcp:127.0.0.1:$nat1-$nat2
lxc config device add "$1" natudp-ports proxy listen=udp:0.0.0.0:$nat1-$nat2 connect=udp:127.0.0.1:$nat1-$nat2
# 生成的小鸡信息写入log并打印
echo "$name $sshn $passwd $nat1 $nat2" >> log
echo "$name $sshn $passwd $nat1 $nat2"
