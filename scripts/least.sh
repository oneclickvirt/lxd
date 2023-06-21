#!/bin/bash
# by https://github.com/spiritLHLS/lxc
# cd /root
# ./least.sh NAT服务器前缀 数量
# 2023.06.21

rm -rf log
lxc init images:debian/11 "$1" -c limits.cpu=1 -c limits.memory=128MiB
lxc config device override "$1" root size=200MB
lxc config device set "$1" root limits.read 500MB
lxc config device set "$1" root limits.write 500MB
lxc config device set "$1" root limits.read 5000iops
lxc config device set "$1" root limits.write 5000iops
lxc config device set "$1" root limits.max 300MB
lxc config device override "$1" eth0 limits.egress=300Mbit limits.ingress=300Mbit
lxc config set "$1" limits.cpu.priority 0
lxc config set "$1" limits.cpu.allowance 50%
lxc config set "$1" limits.cpu.allowance 25ms/100ms
lxc config set "$1" limits.memory.swap true
lxc config set "$1" limits.memory.swap.priority 1
lxc config set "$1" security.nesting true
# if [ "$(uname -a | grep -i ubuntu)" ]; then
#   # Set the security settings
#   lxc config set "$1" security.syscalls.intercept.mknod true
#   lxc config set "$1" security.syscalls.intercept.setxattr true
# fi
# 屏蔽端口
blocked_ports=( 3389 8888 54321 65432 )
for port in "${blocked_ports[@]}"; do
  iptables --ipv4 -I FORWARD -o eth0 -p tcp --dport ${port} -j DROP
  iptables --ipv4 -I FORWARD -o eth0 -p udp --dport ${port} -j DROP
done
# 批量创建容器
for ((a=1;a<="$2";a++)); do
  lxc copy "$1" "$1"$a
  name="$1"$a
  sshn=$(( 20000 + a ))
  ori=$(date | md5sum)
  passwd=${ori: 2: 9}
  lxc start "$1"$a
  sleep 1
  lxc exec "$1"$a -- sudo apt-get update -y
  lxc exec "$1"$a -- sudo apt-get install curl -y --fix-missing
  lxc exec "$1"$a -- sudo apt-get install -y --fix-missing dos2unix
  lxc exec "$1"$a -- curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/ssh.sh -o ssh.sh
  lxc exec "$1"$a -- chmod 777 ssh.sh
  lxc exec "$1"$a -- dos2unix ssh.sh
  lxc exec "$1"$a -- sudo ./ssh.sh $passwd
  lxc exec "$1"$a -- curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/config.sh -o config.sh
  lxc exec "$1"$a -- chmod +x config.sh
  lxc exec "$1"$a -- dos2unix config.sh
  lxc exec "$1"$a -- bash config.sh
  lxc config device add "$1"$a ssh-port proxy listen=tcp:0.0.0.0:$sshn connect=tcp:127.0.0.1:22
  echo "$name $sshn $passwd" >> log
done
