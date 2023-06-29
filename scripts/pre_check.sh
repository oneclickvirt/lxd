#!/bin/bash
# by https://github.com/spiritLHLS/lxc
# 2023.06.29
# 预检测本机是否符合开设小鸡的要求

_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "utf8|UTF-8")
if [[ -z "$utf8_locale" ]]; then
    _yellow "No UTF-8 locale found"
else
    export LC_ALL="$utf8_locale"
    export LANG="$utf8_locale"
    export LANGUAGE="$utf8_locale"
    _green "Locale set to $utf8_locale"
fi

# 必须以root身份运行脚本，且脚本必须在/root目录下
if [[ $(id -u) != 0 ]]; then
    _yellow "You must run the script as root, please switch to root privileges before using this set of scripts."
    _yellow "必须以root身份运行脚本，请切换到root权限再使用本套脚本。"
    exit 1
elif [[ $(pwd) != /root* ]]; then
    _yellow "The script must be in the /root directory, please run this script in the /root directory."
    _yellow "脚本必须在/root目录下，请在/root目录下运行本脚本。"
    exit 1
else
    _green "Local path meets requirements"
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
if [[ $VIRT == @(openvz|lxc) ]]; then
    _yellow "openvz or lxc architecture cannot use this set of scripts, please use another virtualized server as a mother hen, such as KVM"
    _yellow "openvz或lxc架构无法使用本套脚本，请使用别的虚拟化的服务器做母鸡，如KVM"
    exit 1
else
    _green "This machine architecture meets the requirements"
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
    _yellow "The local system does not meet the requirements, Ubuntu or Debian 8+ is required"
    _yellow "本机系统不符合要求，需要 Ubuntu 或 Debian 8+"
    exit 1
else
    _green "This system meets the requirements"
    _green "本机系统符合要求"
fi

# 检查网络是否符合要求
if ! ping -c 1 -w 6 raw.githubusercontent.com >/dev/null 2>&1; then
    _yellow "The local network cannot connect to Github's raw page, please check the network connection"
    _yellow "本机网络无法连接Github的raw页面，请检查网络连接"
    exit 1
else
    _green "Local network connectivity meets requirements"
    _green "本机网络连通性符合要求"
fi

ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -f1 -d'/')
if [ -z "$ip" ]; then
    _yellow "A separate IPv4 address could not be found on this machine, please check the network connection"
    _yellow "本机无法找到独立的IPv4地址，请检查网络连接"
    exit 1
else
    _green "Local IP meets requirements"
    _green "本机IP符合要求"
fi

# 检查内存大小是否符合要求
mem=$(awk '/MemTotal/{print $2}' /proc/meminfo)
if [ $mem -lt 524288 ]; then
    _yellow "memory size does not meet the requirements, need at least 512MB. (The actual smaller is fine, self-judgment, subsequent installation of open virtual memory SWAP can make up for the lack of this piece)"
    _yellow "内存大小不符合要求，需要至少512MB。(实际小点也行，自行判断，后续安装开虚拟内存SWAP可弥补这块的不足)"
    exit 1
else
    _green "Local memory meets requirements"
    _green "本机内存符合要求"
fi

# 检查磁盘空间是否符合要求
disk=$(df / | awk '/\//{print $4}')
if [ $disk -lt 9485760 ]; then
    _yellow "The local hard disk space does not meet the requirements, need at least 10G.(Actually smaller is fine, the installation needs about 500M~2G hard disk space, varies from system to system, the hard disk occupation on Ubuntu is the smallest)"
    _yellow "本机硬盘空间不符合要求，需要至少10G。(实际小点也行，安装大概需要500M~2G硬盘空间，因系统而异，在Ubuntu上的硬盘占用是最小的)"
    exit 1
else
    _green "Local hard drive meets requirements"
    _green "本机硬盘符合要求"
fi

_green "This machine meets the requirements to be used as an LXC hen and can open LXC containers in bulk"
_green "本机符合作为LXC母鸡的要求，可以批量开设LXC容器"
