#!/bin/bash
# by https://github.com/spiritLHLS/lxc
# 2023.04.27

# curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/lxdinstall.sh -o lxdinstall.sh && chmod +x lxdinstall.sh
# ./lxdinstall.sh 内存大小以MB计算 硬盘大小以GB计算

_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading(){ read -rp "$(_green "$1")" "$2"; }
utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "utf8|UTF-8")
if [[ -z "$utf8_locale" ]]; then
  _yellow "No UTF-8 locale found"
else
  export LC_ALL="$utf8_locale"
  export LANG="$utf8_locale"
  export LANGUAGE="$utf8_locale"
  _green "Locale set to $utf8_locale"
fi

apt-get update
if ! command -v sudo > /dev/null; then
  apt-get install sudo -y
fi
if ! command -v wget > /dev/null; then
  apt-get install wget -y
fi
if ! command -v curl > /dev/null; then
  apt-get install curl -y
fi
export DEBIAN_FRONTEND=noninteractive

cd /root >/dev/null 2>&1
# lxd安装
lxd_snap=`dpkg -l |awk '/^[hi]i/{print $2}' | grep -ow snap`
lxd_snapd=`dpkg -l |awk '/^[hi]i/{print $2}' | grep -ow snapd`
if [[ "$lxd_snap" =~ ^snap.* ]]&&[[ "$lxd_snapd" =~ ^snapd.* ]]
then
  _green "snap已安装"
else
  _green "开始安装snap"
  apt-get update
#   apt-get -y install snap
  apt-get -y install snapd
fi
snap_core=`snap list core`
snap_lxd=`snap list lxd`
if [[ "$snap_core" =~ core.* ]]&&[[ "$snap_lxd" =~ lxd.* ]]
then
  _green "lxd已安装"
  lxd_lxc_detect=`lxc list`
  if [[ "$lxd_lxc_detect" =~ "snap-update-ns failed with code1".* ]]
  then
    systemctl restart apparmor
    snap restart lxd
  else
    _green "环境检测无问题"
  fi
else
  _green "开始安装LXD"
  snap install core
  snap install lxd
  ! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
  export PATH=$PATH:/snap/bin
  ! lxc -h >/dev/null 2>&1 && _yellow 'lxc路径有问题，请检查修复' && exit
  _green "LXD安装完成"        
fi

# # 类型设置-硬盘
# SUPPORTED_BACKENDS=("zfs" "lvm" "btrfs" "ceph" "dir")
# STORAGE_BACKEND=""
# for backend in "${SUPPORTED_BACKENDS[@]}"; do
#     if command -v $backend >/dev/null; then
#         STORAGE_BACKEND=$backend
#         _green "使用 $STORAGE_BACKEND 存储类型"
#         break
#     fi
# done
# if [ -z "$STORAGE_BACKEND" ]; then
#     _yellow "无可支持的存储类型，请联系脚本维护者"
#     exit
# fi

# 读取母鸡配置
while true; do
    reading "母鸡需要开设多少虚拟内存？(虚拟内存SWAP会占用硬盘空间，自行计算，注意是MB为单位，需要1G虚拟内存则输入1024)：" memory_nums
    if [[ "$memory_nums" =~ ^[1-9][0-9]*$ ]]; then
        break
    else
        _yellow "输入无效，请输入一个正整数。"
    fi
done
while true; do
    reading "母鸡需要开设多大的存储池？(存储池就是小鸡硬盘之和的大小，推荐SWAP和存储池加起来达到母鸡硬盘的95%空间，注意是GB为单位，需要10G存储池则输入10)：" disk_nums
    if [[ "$disk_nums" =~ ^[1-9][0-9]*$ ]]; then
        break
    else
        _yellow "输入无效，请输入一个正整数。"
    fi
done

# 资源池设置-硬盘
# /snap/bin/lxd init --storage-backend zfs --storage-create-loop "$disk_nums" --storage-pool default --auto
# zfs检测与安装
temp=$(/snap/bin/lxd init --storage-backend zfs --storage-create-loop "$disk_nums" --storage-pool default --auto)
if [[ $? -ne 0 ]]; then
  status=false
else
  status=true
fi
echo "$temp"
if echo "$temp" | grep -q "lxd.migrate" && [[ $status == false ]]; then
  /snap/bin/lxd.migrate
  temp=$(/snap/bin/lxd init --storage-backend zfs --storage-create-loop "$disk_nums" --storage-pool default --auto)
  if [[ $? -ne 0 ]]; then
    status=false
  else
    status=true
  fi
  echo "$temp"
fi
if echo "$temp" | grep -q "'zfs' isn't available" && [[ $status == false ]]; then
  _green "zfs模块调用失败，尝试编译zfs模块加载入内核..."
  apt-get install -y linux-headers-amd64
  codename=$(lsb_release -cs)
  echo "deb http://deb.debian.org/debian ${codename}-backports main contrib non-free"|sudo tee -a /etc/apt/sources.list && apt-get update
  apt-get install -y linux-headers-amd64
  apt-get install -y ${codename}-backports 
  apt-get install -y zfsutils-linux
  apt-get install -y zfs-dkms
  echo "deb http://deb.debian.org/debian bullseye-backports main contrib" > /etc/apt/sources.list.d/bullseye-backports.list
  echo "deb-src http://deb.debian.org/debian bullseye-backports main contrib" >> /etc/apt/sources.list.d/bullseye-backports.list
echo "Package: src:zfs-linux
Pin: release n=bullseye-backports
Pin-Priority: 990" > /etc/apt/preferences.d/90_zfs
  apt-get update
  apt-get install -y dpkg-dev linux-headers-generic linux-image-generic
  _green "请重启本机(执行 reboot 重启)再次执行本脚本以加载新内核，重启后需要再次输入你需要的配置"
  exit 1
fi

# 虚拟内存设置
apt install dos2unix ufw -y
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/swap2.sh -o swap2.sh && chmod +x swap2.sh
./swap2.sh "$memory_nums"

# if [ "$STORAGE_BACKEND" = "zfs" ]; then
#     /snap/bin/lxd init --storage-backend "$STORAGE_BACKEND" --storage-create-loop "$disk_nums" --storage-pool default --auto
# elif [ "$STORAGE_BACKEND" = "dir" ]; then
#     _green "由于无zfs，使用默认dir类型无限定存储池大小"
#     /snap/bin/lxd init --storage-backend "$STORAGE_BACKEND" --auto
# elif [ "$STORAGE_BACKEND" = "lvm" ]; then
#     _green "由于无zfs，使用默认lvm类型无限定存储池大小"
#     DISK=$(lsblk -p -o NAME,TYPE | awk '$2=="disk"{print $1}')
#     /snap/bin/lxd init --storage-backend lvm --storage-create-device $DISK --storage-pool lvm_pool --auto
# else
#     /snap/bin/lxd init --storage-backend "$STORAGE_BACKEND" --storage-create-device "$disk_nums" --storage-pool default --auto
# fi
  
sleep 2
! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
export PATH=$PATH:/snap/bin
! lxc -h >/dev/null 2>&1 && _yellow '使用 lxc -h 检测到路径有问题，请手动查看LXD是否安装成功' && exit 1
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
