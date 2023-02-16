#!/bin/bash
# by https://github.com/spiritLHLS/lxc
# 2022.12.20

# curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/lxdinstall.sh -o lxdinstall.sh && chmod +x lxdinstall.sh
# ./lxdinstall.sh 内存大小以MB计算 硬盘大小以GB计算

# 内存设置
apt install dos2unix ufw -y
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/swap2.sh -o swap2.sh && chmod +x swap2.sh
./swap2.sh "$1"
# lxd安装
apt -y install zfsutils || apt -y install zfs
apt install snapd -y
snap remove lxd -y >/dev/null 2>&1
! snap install lxd && snap install core && snap install lxd
# 资源池设置-硬盘
# Check if zfs is installed
if ! command -v zfs > /dev/null; then
  # Install zfs if it is not installed
  apt-get update
  apt-get install -y zfsutils-linux
  echo "zfs 安装后需要重启服务器才会启用，请重启服务器再运行本脚本"
  exit 0
fi
/snap/bin/lxd init --storage-backend zfs --storage-create-loop "$2" --storage-pool default --auto
! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
export PATH=$PATH:/snap/bin
! lxc -h >/dev/null 2>&1 && echo 'Failed install lxc' && exit
# 设置镜像不更新
lxc config unset images.auto_update_interval
lxc config set images.auto_update_interval 0
# 设置IPV6子网使容器自动配置IPV6地址
# subnet=$(ip -6 addr show | grep -E 'inet6.*global' | awk '{print $2}' | head -n 1)
# if [ -z "$subnet" ]; then
#     echo "没有IPV6子网，无法自动配置IPV6子网使容器自动配置IPV6地址"
#     exit 1
# fi
# addr=$(echo "$subnet" | cut -d'/' -f1)
# prefixlen=$(echo "$subnet" | cut -d'/' -f2)
# netmask=$(printf "%.*s" $prefixlen "11111111111111111111111111111111")
# netmask="${netmask}$(printf "%0$(32-$prefixlen)s" "")"
# IFS=':' read -r -a addr_parts <<< "$addr"
# IFS=':' read -r -a netmask_parts <<< "$netmask"
# network_addr=""
# for ((i=0; i<8; i++)); do
#     part=$(printf "%x" "$(( 0x${addr_parts[$i]} & 0x${netmask_parts[$i]} ))")
#     network_addr="${network_addr}${part}"
#     if [ $i -lt 7 ]; then
#         network_addr="${network_addr}:"
#     fi
# done
# network_addr="${network_addr}/$prefixlen"
# lxc network set lxdbr0 ipv6.address "$network_addr"
# lxc network set lxdbr0 ipv6.nat true
