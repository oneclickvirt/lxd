#!/bin/bash
# by https://github.com/spiritLHLS/lxc
# 2023.02.27

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
subnet=$(ip -6 addr show | grep -E 'inet6.*global' | awk '{print $2}' | awk -F'/' '{print $1}' | head -n 1)
if [ -z "$subnet" ]; then
    echo "没有IPV6子网，无法自动配置IPV6子网使容器自动配置IPV6地址"
    exit 1
    # 下载预制文件
    curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/ssh.sh -o ssh.sh
    curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/config.sh -o config.sh
fi
cidr=$(echo $subnet | awk -F':' '{print $1":"$2":"$3":"$4":1:0:0:0/64"}')
lxc network set lxdbr0 ipv6.dhcp false
lxc network set lxdbr0 ipv6.dhcp.stateful false
lxc network set lxdbr0 ipv6.nat true
lxc network set lxdbr0 ipv6.routing true
lxc network set lxdbr0 ipv6.firewall false
lxc network set lxdbr0 ipv6.address $cidr
# 下载预制文件
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/ssh.sh -o ssh.sh
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/config.sh -o config.sh
