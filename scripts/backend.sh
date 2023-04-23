#!/bin/bash
# by https://github.com/spiritLHLS/lxc

# 环境安装
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
sudo sed -i '/deb http:\/\/archive.ubuntu.com\/ubuntu\/ trusty main universe restricted multiverse/d' /etc/apt/sources.list
grep -q "deb http://archive.ubuntu.com/ubuntu/ trusty main universe restricted multiverse" /etc/apt/sources.list || echo "deb http://archive.ubuntu.com/ubuntu/ trusty main universe restricted multiverse" >> /etc/apt/sources.list
apt install chkconfig -y
if [ $? -ne 0 ]; then
    apt install sysv-rc-conf -y
    if [ $? -ne 0 ]; then
        apt update && apt install sysv-rc-conf -y
    fi
fi
! chkconfig vnstat on && echo "replace chkconfig with sysv-rc-conf" && sysv-rc-conf vnstat on 
service vnstat start
# apt install vnstati -y
vnstat -v
vnstatd -v
! vnstati -v && echo "vnstat 编译安装无vnstati工具，如需使用请使用命令 apt install vnstati -y 覆盖安装apt源版本"

