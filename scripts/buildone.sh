#!/bin/bash
# from
# https://github.com/spiritLHLS/lxc
# 2023.06.13

# cd /root
# 输入
# ./buildone.sh 服务器名称 内存大小 硬盘大小 SSH端口 外网起端口 外网止端口 下载速度 上传速度 是否启用IPV6(Y or N) 系统(留空则为debian11)
# 如果 外网起端口 外网止端口 都设置为0则不做区间外网端口映射了，只映射基础的SSH端口，注意不能为空，不进行映射需要设置为0

# 创建容器
name="${1:-test}"
memory="${2:-256}"
disk="${3:-2}"
sshn="${4:-20001}"
nat1="${5:-20002}"
nat2="${6:-20025}"
in="${7:-300}"
out="${8:-300}"
system="${10:-debian11}"
a="${system%%[0-9]*}"
b="${system##*[!0-9]}"
output=$(lxc image list images:${a}/${b})
sys_bit=""
sysarch="$(uname -m)"
case "${sysarch}" in
    "x86_64"|"x86"|"amd64"|"x64") sys_bit="x86_64";;
    "i386"|"i686") sys_bit="i686";;
    "aarch64"|"armv8"|"armv8l") sys_bit="aarch64";;
    "armv7l") sys_bit="armv7l";;
    "s390x") sys_bit="s390x";;
#     "riscv64") sys_bit="riscv64";;
    "ppc64le") sys_bit="ppc64le";;
#     "ppc64") sys_bit="ppc64";;
    *) sys_bit="x86_64";;
esac
if echo "$output" | grep -q "${a}/${b}"; then
    system=$(lxc image list images:${a}/${b} --format=json | jq -r --arg ARCHITECTURE "$sys_bit" '.[] | select(.type == "container" and .architecture == $ARCHITECTURE) | .aliases[0].name' | head -n 1)
    echo "匹配的镜像存在，将使用 images:${system} 进行创建"
else
    echo "未找到匹配的镜像，请执行"
    echo "lxc image list images:系统/版本号"
    echo "查询是否存在对应镜像"
    exit 1
fi
rm -rf "$name"
lxc init images:${system} "$name" -c limits.cpu=1 -c limits.memory="$memory"MiB 
# --config=user.network-config="network:\n  version: 2\n  ethernets:\n    eth0:\n      nameservers:\n        addresses: [8.8.8.8, 8.8.4.4]"
if [ $? -ne 0 ]; then
  echo "容器创建失败，请检查前面的输出信息"
  exit 1
fi
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
/usr/local/bin/check-dns.sh
if echo "$system" | grep -qiE "centos|almalinux"; then
    lxc exec "$name" -- sudo yum update -y
    lxc exec "$name" -- sudo yum install -y curl
    lxc exec "$name" -- sudo yum install -y dos2unix
else
    lxc exec "$name" -- sudo apt-get update -y
    lxc exec "$name" -- sudo apt-get install curl -y --fix-missing
    lxc exec "$name" -- sudo apt-get install dos2unix -y --fix-missing
fi
lxc file push /root/ssh.sh "$name"/root/
# lxc exec "$name" -- curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/ssh.sh -o ssh.sh
lxc exec "$name" -- chmod 777 ssh.sh
lxc exec "$name" -- dos2unix ssh.sh
lxc exec "$name" -- sudo ./ssh.sh $passwd
lxc file push /root/config.sh "$name"/root/
# lxc exec "$name" -- curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/config.sh -o config.sh
lxc exec "$name" -- chmod +x config.sh
lxc exec "$name" -- dos2unix config.sh
lxc exec "$name" -- bash config.sh
lxc exec "$name" -- history -c
lxc config device add "$name" ssh-port proxy listen=tcp:0.0.0.0:$sshn connect=tcp:127.0.0.1:22
# 是否要创建V6地址
if [ -n "$9" ]; then
  if [ "$9" == "Y" ]; then
    if [ ! -f "./build_ipv6_network.sh" ]; then
      # 如果不存在，则从指定 URL 下载并添加可执行权限
      curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/build_ipv6_network.sh -o build_ipv6_network.sh && chmod +x build_ipv6_network.sh > /dev/null 2>&1
    fi
    ./build_ipv6_network.sh "$name" > /dev/null 2>&1
  fi
fi
if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
  lxc config device add "$name" nattcp-ports proxy listen=tcp:0.0.0.0:$nat1-$nat2 connect=tcp:127.0.0.1:$nat1-$nat2
  lxc config device add "$name" natudp-ports proxy listen=udp:0.0.0.0:$nat1-$nat2 connect=udp:127.0.0.1:$nat1-$nat2
  # 生成的小鸡信息写入log并打印
  echo "$name $sshn $passwd $nat1 $nat2" >> "$name"
  echo "$name $sshn $passwd $nat1 $nat2"
  exit 1
fi
if [ "$nat1" == "0" ] && [ "$nat2" == "0" ]; then
  echo "$name $sshn $passwd" >> "$name"
  echo "$name $sshn $passwd" 
fi
