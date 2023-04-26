#!/bin/bash
# by https://github.com/spiritLHLS/lxc
# 2023.04.26
# 预检测本机是否符合开设小鸡的要求

_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }

# 必须以root身份运行脚本，且脚本必须在/root目录下
if [[ $(id -u) != 0 ]]; then
    _yellow "必须以root身份运行脚本，请切换到root权限再使用本套脚本。"
    exit 1
elif [[ $(pwd) != /root* ]]; then
    _yellow "脚本必须在/root目录下，请在/root目录下运行本脚本。"
    exit 1
else
    _green "本机路径符合要求"
fi

# 必须是全虚拟化的架构
virtcheck=$(systemd-detect-virt)
case "$virtcheck" in
  kvm ) VIRT='kvm';;
  openvz ) VIRT='openvz';;
  lxc ) VIRT='lxc';;
  * ) VIRT='kvm';;
esac
if [ $VIRT == @(openvz|lxc) ]; then
  _yellow "openvz或lxc架构无法使用本套脚本，请使用别的虚拟化的服务器做母鸡，如KVM"
  exit 1
else
  _green "本机架构符合要求"
fi

# 检查系统版本是否符合要求
if [ -n "$(command -v lsb_release)" ]; then
    distro=$(lsb_release -is)
    codename=$(lsb_release -cs)
else
    distro=$(cat /etc/*release | grep -E '^ID=' | awk -F= '{ print $2 }' | tr -d \")
    codename=$(cat /etc/*release | grep -E '^VERSION_CODENAME=' | awk -F= '{ print $2 }' | tr -d \")
fi

if [[ ! $distro == @(Ubuntu|ubuntu|Debian|debian) ]]; then
    _yellow "本机系统不符合要求，需要 Ubuntu 或 Debian 8+"
    exit 1
else
    _green "本机系统符合要求"
fi

# 检查内存大小是否符合要求
mem=$(awk '/MemTotal/{print $2}' /proc/meminfo)
if [ $mem -lt 524288 ]; then
    _yellow "内存大小不符合要求，需要至少512MB。"
    exit 1
else
    _green "本机内存符合要求"
fi

# 检查磁盘空间是否符合要求
disk=$(df / | awk '/\//{print $4}')
if [ $disk -lt 10485760 ]; then
    _yellow "本机硬盘空间不符合要求，需要至少10G。"
    exit 1
else
    _green "本机硬盘符合要求"
fi

# 检查网络是否符合要求
if ! ping -c 1 -w 6 raw.githubusercontent.com >/dev/null 2>&1; then
    _yellow "本机网络无法连接Github的raw页面，请检查网络连接"
    exit 1
else
    _green "本机网络连通性符合要求"
fi

ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -f1 -d'/')
if [ -z "$ip" ]; then
    _yellow "本机无法找到独立的IPv4地址，请检查网络连接"
    exit 1
else
  _green "本机IP符合要求"
fi

_green "本机符合作为母鸡的要求"
