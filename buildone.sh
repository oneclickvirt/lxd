#!/bin/bash
# from
# https://github.com/spiritLHLS/lxc
# 2023.02.04

# cd /root
# 输入
# ./buildone.sh 服务器名称 内存大小 硬盘大小 SSH端口 外网起端口 外网止端口 下载速度 上传速度
rm -rf log
lxc init images:debian/10 "$1" -c limits.cpu=1 -c limits.memory="$2"MiB
# 硬盘大小
lxc config device override "$1" root size="$3"GB
lxc config device set "$1" root limits.max "$3"GB
# IO
lxc config device set "$1" root limits.read 100MB
lxc config device set "$1" root limits.write 100MB
lxc config device set "$1" root limits.read 100iops
lxc config device set "$1" root limits.write 100iops
# 网速
lxc config device override "$1" eth0 limits.egress="$8"Mbit limits.ingress="$7"Mbit
# cpu
lxc config set "$1" limits.cpu.priority 0
lxc config set "$1" limits.cpu.allowance 50%
lxc config set "$1" limits.cpu.allowance 25ms/100ms
# 内存
lxc config set "$1" limits.memory.swap true
lxc config set "$1" limits.memory.swap.priority 1
# 支持docker虚拟化
lxc config set "$1" security.nesting true
# 安全性防范设置 - 只有Ubuntu支持
# if [ "$(uname -a | grep -i ubuntu)" ]; then
#   # Set the security settings
#   lxc config set "$1" security.syscalls.intercept.mknod true
#   lxc config set "$1" security.syscalls.intercept.setxattr true
# fi
# 创建容器
name="$1"
# 容器SSH端口 外网nat端口起 止
sshn="$4"
nat1="$5"
nat2="$6"
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
lxc exec "$1" -- curl -L https://github.com/spiritLHLS/lxc/raw/main/config.sh -o config.sh 
lxc exec "$1" -- chmod +x config.sh
lxc exec "$1" -- bash config.sh
lxc config device add "$1" ssh-port proxy listen=tcp:0.0.0.0:$sshn connect=tcp:127.0.0.1:22
lxc config device add "$1" nattcp-ports proxy listen=tcp:0.0.0.0:$nat1-$nat2 connect=tcp:127.0.0.1:$nat1-$nat2
lxc config device add "$1" natudp-ports proxy listen=udp:0.0.0.0:$nat1-$nat2 connect=udp:127.0.0.1:$nat1-$nat2
# 生成的小鸡信息写入log并打印
echo "$name $sshn $passwd $nat1 $nat2" >> "$1"
echo "$name $sshn $passwd $nat1 $nat2"
