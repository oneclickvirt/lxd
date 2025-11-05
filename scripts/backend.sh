#!/bin/bash
# by https://github.com/oneclickvirt/lxd
# 2023.09.05

# 服务管理兼容性函数
service_manager() {
    local action=$1
    local service_name=$2
    local success=false
    
    case "$action" in
        enable)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl enable "$service_name" 2>/dev/null && success=true
            fi
            if command -v rc-update >/dev/null 2>&1; then
                rc-update add "$service_name" default 2>/dev/null && success=true
            fi
            if command -v update-rc.d >/dev/null 2>&1; then
                update-rc.d "$service_name" defaults 2>/dev/null && success=true
            fi
            ;;
        start)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl start "$service_name" 2>/dev/null && success=true
            fi
            if ! $success && command -v rc-service >/dev/null 2>&1; then
                rc-service "$service_name" start 2>/dev/null && success=true
            fi
            if ! $success && command -v service >/dev/null 2>&1; then
                service "$service_name" start 2>/dev/null && success=true
            fi
            if ! $success && [ -x "/etc/init.d/$service_name" ]; then
                /etc/init.d/"$service_name" start 2>/dev/null && success=true
            fi
            ;;
    esac
    
    $success && return 0 || return 1
}

# 环境安装
# 安装vnstat
if command -v apt >/dev/null 2>&1; then
    apt update
    apt install wget sudo curl -y
elif command -v apk >/dev/null 2>&1; then
    apk update
    apk add --no-cache wget sudo curl
elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm wget sudo curl
elif command -v yum >/dev/null 2>&1; then
    yum update -y
    yum install -y wget sudo curl
elif command -v dnf >/dev/null 2>&1; then
    dnf update -y
    dnf install -y wget sudo curl
fi
# apt install linux-headers-$(uname -r) -y
# wget https://github.com/vergoh/vnstat/releases/download/v2.10/vnstat-2.10.tar.gz
# # gd gd-devel
# apt install build-essential libsqlite3-dev -y
# tar -xvf vnstat-2.10.tar.gz
# cd vnstat-2.10/
# sudo ./configure --prefix=/usr --sysconfdir=/etc
# sudo make
# sudo make install
# cp -v examples/systemd/vnstat.service /etc/systemd/system/
# systemctl enable vnstat
# systemctl start vnstat
# cp -v examples/init.d/redhat/vnstat /etc/init.d/
# sudo sed -i '/deb http:\/\/archive.ubuntu.com\/ubuntu\/ trusty main universe restricted multiverse/d' /etc/apt/sources.list
# grep -q "deb http://archive.ubuntu.com/ubuntu/ trusty main universe restricted multiverse" /etc/apt/sources.list || echo "deb http://archive.ubuntu.com/ubuntu/ trusty main universe restricted multiverse" >>/etc/apt/sources.list
# apt install chkconfig -y
# if [ $? -ne 0 ]; then
#     apt install sysv-rc-conf -y
#     if [ $? -ne 0 ]; then
#         apt update && apt install sysv-rc-conf -y
#     fi
# fi
# ! chkconfig vnstat on && echo "replace chkconfig with sysv-rc-conf" && sysv-rc-conf vnstat on
# service vnstat start
# vnstat -v
# vnstatd -v
# ! vnstati -v && echo "vnstat 编译安装无vnstati工具，如需使用请使用命令 apt install vnstati -y 覆盖安装apt源版本"
if command -v apt >/dev/null 2>&1; then
    apt install make gcc libc6-dev libsqlite3-0 libsqlite3-dev libgd3 libgd-dev -y
elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache make gcc libc-dev sqlite-dev gd-dev
elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm make gcc sqlite gd
elif command -v yum >/dev/null 2>&1; then
    yum install -y make gcc glibc-devel sqlite-devel gd-devel
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y make gcc glibc-devel sqlite-devel gd-devel
fi
cd /usr/src
wget https://humdi.net/vnstat/vnstat-2.11.tar.gz
chmod 777 vnstat-2.11.tar.gz
tar zxvf vnstat-2.11.tar.gz
cd vnstat-2.11
./configure --prefix=/usr --sysconfdir=/etc && make && make install
cp -v examples/systemd/vnstat.service /etc/systemd/system/
service_manager enable vnstat
service_manager start vnstat
pgrep -c vnstatd
vnstat -v
vnstatd -v
vnstati -v

