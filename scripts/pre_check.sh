#!/bin/bash
# by https://github.com/spiritLHLS/lxc
# 2023.04.26
# 预检测本机是否符合开设小鸡的要求

# 必须以root运行脚本
[[ $(id -u) != 0 ]] && echo "必须以root身份执行脚本，请切换到root权限再使用本套脚本" && exit 1

# 必须是全虚拟化的架构
virtcheck=$(systemd-detect-virt)
case "$virtcheck" in
  kvm ) VIRT='kvm';;
  openvz ) VIRT='openvz';;
  * ) VIRT='kvm';;
esac
if [ $VIRT = "openvz" ]; then
  echo "OVZ架构无法使用本套脚本，请使用别的虚拟化的服务器做母鸡，如KVM"
  exit 1
fi

# 检查系统版本是否符合要求
if [ -n "$(command -v lsb_release)" ]; then
    distro=$(lsb_release -is)
    codename=$(lsb_release -cs)
else
    distro=$(cat /etc/*release | grep -E '^ID=' | awk -F= '{ print $2 }' | tr -d \")
    codename=$(cat /etc/*release | grep -E '^VERSION_CODENAME=' | awk -F= '{ print $2 }' | tr -d \")
fi

if [[ $distro != "Ubuntu" && ($distro != "Debian" || $codename -lt "jessie") ]]; then
    echo "系统版本不符合要求，需要Ubuntu或Debian 8+。"
    exit 1
fi

# 检查内存大小是否符合要求
mem=$(awk '/MemTotal/{print $2}' /proc/meminfo)
if [ $mem -lt 524288 ]; then
    echo "内存大小不符合要求，需要至少512MB。"
    exit 1
fi

# 检查磁盘空间是否符合要求
disk=$(df / | awk '/\//{print $4}')
if [ $disk -lt 10485760 ]; then
    echo "磁盘空间不符合要求，需要至少10G。"
    exit 1
fi

# 检查网络是否符合要求
if ! ping -c 1 -w 6 raw.githubusercontent.com >/dev/null 2>&1; then
    echo "网络无法连接Github的raw页面，请检查网络连接。"
    exit 1
fi

ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -f1 -d'/')
if [ -z "$ip" ]; then
    echo "无法找到独立的IPv4地址，请检查网络连接。"
    exit 1
fi

echo "本机符合作为母鸡的要求。"
