#!/bin/bash
# by https://github.com/spiritLHLS/lxc
# 2023.04.26

# curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/lxdinstall.sh -o lxdinstall.sh && chmod +x lxdinstall.sh
# ./lxdinstall.sh 内存大小以MB计算 硬盘大小以GB计算

# 内存设置
apt install dos2unix ufw -y
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/swap2.sh -o swap2.sh && chmod +x swap2.sh
./swap2.sh "$1"
# lxd安装
apt -y install zfsutils || apt -y install zfs
apt install snap -y
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
sleep 2
! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
export PATH=$PATH:/snap/bin
! lxc -h >/dev/null 2>&1 && echo 'Failed install lxc' && exit
# 设置镜像不更新
lxc config unset images.auto_update_interval
lxc config set images.auto_update_interval 0
# 设置自动配置内网IPV6地址
lxc network set lxdbr0 ipv6.address auto
# 下载预制文件
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/ssh.sh -o ssh.sh
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/config.sh -o config.sh
# 加载iptables并设置回源且允许NAT端口转发
apt-get install -y iptables iptables-persistent
iptables -t nat -A POSTROUTING -j MASQUERADE
sysctl net.ipv4.ip_forward=1
sysctl_path=$(which sysctl)
if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
  if grep -q "^#net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
  fi
else
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
${sysctl_path} -p
