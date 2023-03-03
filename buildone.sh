#!/bin/bash
# from
# https://github.com/spiritLHLS/lxc
# 2023.02.27

# cd /root
# 输入
# ./buildone.sh 服务器名称 内存大小 硬盘大小 SSH端口 外网起端口 外网止端口 下载速度 上传速度 是否启用IPV6(Y or N)
# 创建容器
name="${1:-test}"
memory="${2:-256}"
disk="${3:-2}"
sshn="${4:-20001}"
nat1="${5:-20002}"
nat2="${6:-20025}"
in="${7:-300}"
out="${8:-300}"
rm -rf "$name"
lxc init images:debian/10 "$name" -c limits.cpu=1 -c limits.memory="$memory"MiB
# 硬盘大小
lxc config device override "$name" root size="$disk"GB
lxc config device set "$name" root limits.max "$disk"GB
# IO
lxc config device set "$name" root limits.read 100MB
lxc config device set "$name" root limits.write 100MB
lxc config device set "$name" root limits.read 100iops
lxc config device set "$name" root limits.write 100iops
# 网速
lxc config device override "$name" eth0 limits.egress="$out"Mbit limits.ingress="$in"Mbit
# cpu
lxc config set "$name" limits.cpu.priority 0
lxc config set "$name" limits.cpu.allowance 50%
lxc config set "$name" limits.cpu.allowance 25ms/100ms
# 内存
lxc config set "$name" limits.memory.swap true
lxc config set "$name" limits.memory.swap.priority 1
# 支持docker虚拟化
lxc config set "$name" security.nesting true
# 安全性防范设置 - 只有Ubuntu支持
# if [ "$(uname -a | grep -i ubuntu)" ]; then
#   # Set the security settings
#   lxc config set "$1" security.syscalls.intercept.mknod true
#   lxc config set "$1" security.syscalls.intercept.setxattr true
# fi
ori=$(date | md5sum)
passwd=${ori: 2: 9}
lxc start "$name"
sleep 1
lxc exec "$name" -- apt update -y
lxc exec "$name" -- sudo dpkg --configure -a
lxc exec "$name" -- sudo apt-get update
lxc exec "$name" -- sudo apt-get install dos2unix curl -y
lxc file push /root/ssh.sh "$1"/root/
# lxc exec "$name" -- curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/ssh.sh -o ssh.sh
lxc exec "$name" -- chmod 777 ssh.sh
lxc exec "$name" -- dos2unix ssh.sh
lxc exec "$name" -- sudo ./ssh.sh $passwd
lxc file push /root/config.sh "$1"/root/
# lxc exec "$name" -- curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/config.sh -o config.sh
lxc exec "$name" -- chmod +x config.sh
lxc exec "$name" -- bash config.sh
lxc exec "$name" -- history -c
lxc config device add "$name" ssh-port proxy listen=tcp:0.0.0.0:$sshn connect=tcp:127.0.0.1:22
lxc config device add "$name" nattcp-ports proxy listen=tcp:0.0.0.0:$nat1-$nat2 connect=tcp:127.0.0.1:$nat1-$nat2
lxc config device add "$name" natudp-ports proxy listen=udp:0.0.0.0:$nat1-$nat2 connect=udp:127.0.0.1:$nat1-$nat2
# 生成的小鸡信息写入log并打印
echo "$name $sshn $passwd $nat1 $nat2" >> "$name"
echo "$name $sshn $passwd $nat1 $nat2"
# 是否要创建V6地址
if [ -n "$9" ]; then
  if [ "$9" == "Y" ]; then
    if [ ! -f "./build_ipv6_network.sh" ]; then
      # 如果不存在，则从指定 URL 下载并添加可执行权限
      curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/build_ipv6_network.sh -o build_ipv6_network.sh && chmod +x build_ipv6_network.sh
    fi
    ./build_ipv6_network.sh "$name"
  fi
fi
