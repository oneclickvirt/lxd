#!/bin/bash
apt update
apt install curl wget sudo dos2unix ufw -y
ufw disable
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/swap2.sh -o swap2.sh && chmod +x swap2.sh && bash swap2.sh
apt -y install zfsutils || apt -y install zfs
apt install snapd -y
snap install lxd
# 存储盘大小
SIZE = "$1"
/snap/bin/lxd init --auto --storage-backend=zfs --storage-create-loop="SIZE"
# 判断是否安装成功lxc
! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
sleep 1
! lxc -h >/dev/null 2>&1 && echo 'Failed install lxc' && exit
lxc config unset images.auto_update_interval
lxc config set images.auto_update_interval 0
rm -rf init.sh
wget https://github.com/spiritLHLS/lxc/raw/main/init.sh
chmod 777 init.sh
apt install dos2unix -y
dos2unix init.sh
# 生成的小鸡服务器名称前缀 数量
./init.sh "$2" "$3"
# 删除母本
lxc delete -f "$2"
