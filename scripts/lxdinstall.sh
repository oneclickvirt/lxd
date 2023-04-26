#!/bin/bash
# by https://github.com/spiritLHLS/lxc
# 2023.04.26

# curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/lxdinstall.sh -o lxdinstall.sh && chmod +x lxdinstall.sh
# ./lxdinstall.sh 内存大小以MB计算 硬盘大小以GB计算

# 内存设置
apt install dos2unix ufw -y
curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/swap2.sh -o swap2.sh && chmod +x swap2.sh
./swap2.sh "$1"
# zfs
apt-get -y install zfsutils || apt -y install zfs
# lxd安装
lxd_snap=`dpkg -l |awk '/^[hi]i/{print $2}' | grep -ow snap`
lxd_snapd=`dpkg -l |awk '/^[hi]i/{print $2}' | grep -ow snapd`
if [[ "$lxd_snap" =~ ^snap.* ]]&&[[ "$lxd_snapd" =~ ^snapd.* ]]
then
  echo "snap已安装"
else
  echo "开始安装snap"
  apt update
  apt-get -y install snap
  apt-get -y install snapd
fi
snap_core20=`snap list core20`
snap_lxd=`snap list lxd`
if [[ "$snap_core20" =~ core20.* ]]&&[[ "$snap_lxd" =~ lxd.* ]]
then
  echo "lxd已安装"
  lxd_lxc_detect=`lxc list`
  if [[ "$lxd_lxc_detect" =~ "snap-update-ns failed with code1".* ]]
  then
    systemctl restart apparmor
    snap restart lxd
  else
    echo "环境检测无问题"
  fi
else
  echo "开始安装LXD"
  snap install core
  snap install lxd
  echo "LXD安装完成"        
  echo "需要重启母鸡才能使用后续脚本"
  echo "重启后请再次执行本脚本"
  exit 0
fi
# 资源池设置-硬盘
SUPPORTED_BACKENDS=("zfs" "lvm" "btrfs" "ceph" "dir")
STORAGE_BACKEND=""
for backend in "${SUPPORTED_BACKENDS[@]}"; do
    if command -v $backend >/dev/null; then
        STORAGE_BACKEND=$backend
        echo "Using $STORAGE_BACKEND storage backend"
        break
    fi
done
if [ -z "$STORAGE_BACKEND" ]; then
    echo "无可支持的存储类型，尝试进行zfs安装"
    if ! command -v zfs > /dev/null; then
      apt-get update
      apt-get install -y zfsutils-linux
      echo "zfs 安装后需要重启服务器才会启用，请重启服务器再运行本脚本"
      exit 0
    fi
fi
# /snap/bin/lxd init --storage-backend zfs --storage-create-loop "$2" --storage-pool default --auto
if [ "$STORAGE_BACKEND" = "zfs" ]; then
    /snap/bin/lxd init --storage-backend "$STORAGE_BACKEND" --storage-create-loop "$2" --storage-pool default --auto
else
    /snap/bin/lxd init --storage-backend "$STORAGE_BACKEND" --storage-create-device "$2" --storage-pool default --auto
fi
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
