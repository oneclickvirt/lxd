#!/bin/bash

#./backend.sh 内存大小以MB计算 硬盘大小以GB计算

# 安装vnstat
apt update
apt install wget sudo curl -y
apt install linux-headers-$(uname -r) -y
wget https://github.com/vergoh/vnstat/releases/download/v2.10/vnstat-2.10.tar.gz
# gd gd-devel 
apt install build-essential libsqlite3-dev -y
tar -xvf vnstat-2.10.tar.gz
cd vnstat-2.10/
sudo ./configure --prefix=/usr --sysconfdir=/etc
sudo make
sudo make install
cp -v examples/systemd/vnstat.service /etc/systemd/system/
systemctl enable vnstat
systemctl start vnstat
cp -v examples/init.d/redhat/vnstat /etc/init.d/
! apt install chkconfig -y && ! apt install sysv-rc-conf -y && echo "deb http://archive.ubuntu.com/ubuntu/ trusty main universe restricted multiverse" >> /etc/apt/sources.list && apt update && apt install sysv-rc-conf -y
! chkconfig vnstat on && sysv-rc-conf vnstat on 
service vnstat start

# # 内存设置
# apt install dos2unix ufw -y
# curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/swap2.sh -o swap2.sh && chmod +x swap2.sh
# ./swap2.sh "$1"
# # lxd安装，硬盘设置
# apt -y install zfsutils || apt -y install zfs
# apt install snapd -y
# snap remove lxd -y >/dev/null 2>&1
# ! snap install lxd -y && snap install core -y
# snap install lxd -y
# /snap/bin/lxd init --storage-backend zfs --storage-create-loop "$2" --storage-pool default --auto
# ! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
# export PATH=$PATH:/snap/bin
# ! lxc -h >/dev/null 2>&1 && echo 'Failed install lxc' && exit
# # 设置镜像不更新
# lxc config unset images.auto_update_interval
# lxc config set images.auto_update_interval 0
