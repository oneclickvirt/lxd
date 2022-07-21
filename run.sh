#!/bin/bash

red(){ echo -e "\033[31m\033[01m$1$2\033[0m"; }
green(){ echo -e "\033[32m\033[01m$1$2\033[0m"; }
yellow(){ echo -e "\033[33m\033[01m$1$2\033[0m"; }
reading(){ read -rp "$(green "$1")" "$2"; }
red "使用须知：本脚本建议在干净的系统下使用，如果已经初始化安装了lxd并开了小鸡，请耐心等待小鸡卸载和删除，本脚本只会覆盖开小鸡而不会新增"
[ -z $SIZE ] && reading "请输入磁盘大小，无单位:（空闲磁盘大小的90%比较好）" SIZE
[ -z $QJ ] && reading "请输入生成小鸡的名称前缀：" QJ
[ -z $NUM ] && reading "请输入生成小鸡的数量：" NUM
[ -z $OP ] && reading "确认是否填写正确，选择N将退出安装程序：(y/n)" OP
case "$OP" in
    N ) exit 1;;
    n ) exit 1;;
    Y ) echo "Start";;
    y ) echo "Start";;
    * ) exit 1;;
esac
echo "删除旧小鸡"
snap remove lxd >/dev/null 2>&1
echo "删除完毕"
apt update
sleep 0.5
apt install curl wget sudo dos2unix ufw -y
sleep 0.5
ufw disable
sleep 0.5
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/swap2.sh -o swap2.sh && chmod +x swap2.sh && dos2unix swap2.sh
sleep 0.5
bash swap2.sh
sleep 0.5
apt -y install zfsutils || apt -y install zfs
sleep 0.5
apt install snapd -y
sleep 0.5
snap install lxd --channel=5.2/stable
sleep 0.5
# 存储盘大小
/snap/bin/lxd init --storage-backend zfs --storage-create-loop "$SIZE" --storage-pool default --auto
# 判断是否安装成功lxc
! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
sleep 1
! lxc -h >/dev/null 2>&1 && echo 'Failed install lxc' && exit
lxc config unset images.auto_update_interval
sleep 0.5
lxc config set images.auto_update_interval 0
sleep 0.5
rm -rf init2.sh
curl -L https://github.com/spiritLHLS/lxc/raw/main/init.sh -o init2.sh
chmod 777 init2.sh
apt install dos2unix -y
dos2unix init2.sh
sleep 0.5
# 生成的小鸡服务器名称前缀 数量
./init2.sh "$QJ" "$NUM"
# 删除母本
lxc delete -f "$QJ"
rm -rf swap2.sh
rm -rf init2.sh
