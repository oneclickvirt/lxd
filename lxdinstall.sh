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
fi
/snap/bin/lxd init --storage-backend zfs --storage-create-loop "$2" --storage-pool default --auto
! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
export PATH=$PATH:/snap/bin
! lxc -h >/dev/null 2>&1 && echo 'Failed install lxc' && exit
# 设置镜像不更新
lxc config unset images.auto_update_interval
lxc config set images.auto_update_interval 0
