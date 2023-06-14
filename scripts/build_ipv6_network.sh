#!/bin/bash
# by https://github.com/spiritLHLS/lxc
# 2023.06.14

# ./build_ipv6_network.sh LXC容器名称

set -e

# 字体颜色
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

# 检查所需模块是否存在，如果不存在则安装
install_required_modules() {
    modules=("sudo" "lshw" "jq" "net-tools" "netfilter-persistent")
    for module in "${modules[@]}"
    do
        if command -v $module > /dev/null 2>&1 ; then
            _green "$module 已经安装！"
        else
            apt-get install -y $module
            _green "$module 已成功安装！"
        fi
    done
}
install_required_modules

# 查询网卡
interface=$(lshw -C network | awk '/logical name:/{print $3}' | head -1)
_yellow "网卡 $interface"

# 获取指定LXC容器的内网IPV6
CONTAINER_NAME="$1"
CONTAINER_IPV6=$(lxc list $CONTAINER_NAME --format=json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet6") | select(.scope=="global") | .address')
if [ -z "$CONTAINER_IPV6" ]; then
    _red "容器无内网IPV6地址，不进行自动映射"
    exit 1
fi
_blue "$CONTAINER_NAME 容器的内网IPV6地址为 $CONTAINER_IPV6"

# 获取母鸡子网前缀
SUBNET_PREFIX=$(ip -6 addr show | grep -E 'inet6.*global' | awk '{print $2}' | awk -F'/' '{print $1}' | head -n 1 | cut -d ':' -f1-5):

# 检查是否存在 IPV6 
if [ -z "$SUBNET_PREFIX" ]; then
    _red "无 IPV6 子网，不进行自动映射"
    exit 1
fi
_blue "母鸡的IPV6子网前缀为 $SUBNET_PREFIX"

# 寻找未使用的子网内的一个IPV6地址
for i in $(seq 1 65535); do
    IPV6="${SUBNET_PREFIX}$i"
    if [[ $IPV6 == $CONTAINER_IPV6 ]]; then
        continue
    fi
    if ip -6 addr show dev "$interface" | grep -q $IPV6; then
        continue
    fi
    if ! ping6 -c1 -w1 -q $IPV6 &>/dev/null; then
        if ! ip6tables -t nat -C PREROUTING -d $IPV6 -j DNAT --to-destination $CONTAINER_IPV6 &>/dev/null; then
            _green "$IPV6"
            break
        fi
    fi
    _yellow "$IPV6"
done

# 检查是否找到未使用的 IPV6 地址
if [ -z "$IPV6" ]; then
    _red "无可用 IPV6 地址，不进行自动映射"
    exit 1
fi

# 映射 IPV6 地址到容器的私有 IPV6 地址
ip addr add "$IPV6"/64 dev "$interface"
ip6tables -t nat -A PREROUTING -d $IPV6 -j DNAT --to-destination $CONTAINER_IPV6
# 创建守护进程，避免重启服务器后绑定的IPV6地址丢失
if [ ! -f /usr/local/bin/add-ipv6.sh ]; then
    wget ${cdn_success_url}https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/add-ipv6.sh -O /usr/local/bin/add-ipv6.sh
    chmod +x /usr/local/bin/add-ipv6.sh
else
    echo "Script already exists. Skipping installation."
fi
if [ ! -f /etc/systemd/system/add-ipv6.service ]; then
    wget ${cdn_success_url}https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/add-ipv6.service -O /etc/systemd/system/add-ipv6.service
    chmod +x /etc/systemd/system/add-ipv6.service
    systemctl daemon-reload
    systemctl enable add-ipv6.service
    systemctl start add-ipv6.service
else
    echo "Service already exists. Skipping installation."
fi

if [ ! -f "/etc/iptables/rules.v6" ]; then
    touch /etc/iptables/rules.v6
fi
ip6tables-save > /etc/iptables/rules.v6
netfilter-persistent save
netfilter-persistent reload
service netfilter-persistent restart

# 打印信息并测试是否通畅
if ping6 -c 3 $IPV6 &>/dev/null; then
    _green "$CONTAINER_NAME 容器的外网IPV6地址为 $IPV6"
else
    _red "映射失败"
    exit 1
fi

# 写入信息
echo "$IPV6" >> "$1_v6"
