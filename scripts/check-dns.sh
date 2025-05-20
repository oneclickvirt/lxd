#!/bin/bash
#from https://github.com/oneclickvirt/lxd
# 2025.05.18
set -e

DNS_SERVERS_IPV4=(
    "1.1.1.1"
    "8.8.8.8"
    "8.8.4.4"
)

DNS_SERVERS_IPV6=(
    "2606:4700:4700::1111"
    "2001:4860:4860::8888"
    "2001:4860:4860::8844"
)

GAI_CONF="/etc/gai.conf"

join() {
    local IFS="$1"
    shift
    echo "$*"
}

check_nmcli() {
    command -v nmcli >/dev/null 2>&1
}

check_resolvectl() {
    command -v resolvectl >/dev/null 2>&1
}

backup_file() {
    local file=$1
    local backup_suffix=".bak.original"
    local backup_file="${file}${backup_suffix}"
    if [ ! -f "$backup_file" ]; then
        echo "备份 $file 到 $backup_file"
        cp "$file" "$backup_file"
    else
        echo "备份文件 $backup_file 已存在，跳过备份"
    fi
}

set_ipv4_precedence_gai() {
    echo "配置 IPv4 优先，修改 $GAI_CONF"
    if [ ! -f "$GAI_CONF" ]; then
        touch "$GAI_CONF"
    fi
    if grep -q "^precedence ::ffff:0:0/96  100" "$GAI_CONF"; then
        echo "$GAI_CONF 中 IPv4 优先规则已存在。"
    else
        backup_file "$GAI_CONF"
        echo -e "\n# 增加 IPv4 优先规则，2025.05.18 自动添加" >>"$GAI_CONF"
        echo "precedence ::ffff:0:0/96  100" >>"$GAI_CONF"
        echo "IPv4 优先规则已添加到 $GAI_CONF"
    fi
}

adjust_nmcli_ipv6_route_metric() {
    local CONN_NAME=$1
    echo "调整连接 $CONN_NAME 的 IPv6 路由 metric 以降低 IPv6 优先级"
    # 获取当前 IPv6 路由 metric（没找到用默认100）
    local METRIC=$(nmcli connection show "$CONN_NAME" | grep '^ipv6.route-metric:' | awk '{print $2}')
    if [ -z "$METRIC" ]; then
        METRIC=100
    fi
    # 提高 metric (降低优先级) +100
    local NEW_METRIC=$((METRIC + 100))
    nmcli connection modify "$CONN_NAME" ipv6.route-metric "$NEW_METRIC"
    echo "IPv6 路由 metric 从 $METRIC 调整到 $NEW_METRIC"
}

backup_resolv_conf() {
    local backup_file="/etc/resolv.conf.bak.original"
    if [ ! -f "$backup_file" ]; then
        echo "备份 /etc/resolv.conf 到 $backup_file"
        cp /etc/resolv.conf "$backup_file"
    else
        echo "备份文件 $backup_file 已存在，跳过备份"
    fi
}

write_resolv_conf() {
    echo "写入 /etc/resolv.conf ..."
    {
        echo "# 由 /usr/local/bin/check-dns.sh 生成，覆盖写入"
        echo "search spiritlhl.net"
        for dns in "${DNS_SERVERS_IPV4[@]}"; do
            echo "nameserver $dns"
        done
        for dns in "${DNS_SERVERS_IPV6[@]}"; do
            echo "nameserver $dns"
        done
    } >/etc/resolv.conf
    echo "/etc/resolv.conf 更新完成"
}

set_ipv4_precedence_gai
if check_nmcli; then
    echo "检测到 NetworkManager，使用 nmcli 设置 DNS 和路由优先"
    CONN_NAME=$(nmcli -t -f NAME,DEVICE connection show --active | head -n1 | cut -d: -f1)
    if [ -z "$CONN_NAME" ]; then
        echo "未检测到活动连接，退出。"
        exit 1
    fi
    echo "活动连接: $CONN_NAME"
    TARGET_IPV6="2001:4860:4860::8844"
    CURRENT_IPV6_DNS=$(nmcli connection show "$CONN_NAME" | grep '^ipv6.dns:' | awk '{print $2}')
    if echo "$CURRENT_IPV6_DNS" | grep -qw "$TARGET_IPV6"; then
        echo "IPv6 DNS $TARGET_IPV6 已存在于连接 $CONN_NAME"
    else
        echo "设置 IPv4 DNS: ${DNS_SERVERS_IPV4[*]}"
        echo "设置 IPv6 DNS: ${DNS_SERVERS_IPV6[*]}"
        nmcli connection modify "$CONN_NAME" ipv4.ignore-auto-dns yes
        nmcli connection modify "$CONN_NAME" ipv6.ignore-auto-dns yes
        nmcli connection modify "$CONN_NAME" ipv4.dns "$(join ' ' "${DNS_SERVERS_IPV4[@]}")"
        nmcli connection modify "$CONN_NAME" ipv6.dns "$(join ' ' "${DNS_SERVERS_IPV6[@]}")"
        echo "调整 IPv6 路由 metric"
        adjust_nmcli_ipv6_route_metric "$CONN_NAME"
        echo "重启连接应用配置..."
        nmcli connection down "$CONN_NAME"
        nmcli connection up "$CONN_NAME"
        echo "DNS 和路由优先级配置已更新。"
    fi
elif check_resolvectl && systemctl is-active --quiet systemd-resolved; then
    echo "检测到 systemd-resolved，使用 resolvectl 设置 DNS"
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -z "$IFACE" ]; then
        echo "未检测到默认网络接口，退出。"
        exit 1
    fi
    echo "默认接口: $IFACE"
    TARGET_IPV6="2001:4860:4860::8844"
    CURRENT_DNS=$(resolvectl dns "$IFACE")
    if echo "$CURRENT_DNS" | grep -qw "$TARGET_IPV6"; then
        echo "IPv6 DNS $TARGET_IPV6 已存在于接口 $IFACE"
    else
        echo "设置 DNS 服务器..."
        resolvectl dns "$IFACE" "${DNS_SERVERS_IPV4[@]}" "${DNS_SERVERS_IPV6[@]}"
        resolvectl domain "$IFACE" "spiritlhl.net"
        echo "DNS 配置已更新。"
    fi
else
    echo "未检测到 NetworkManager 或 systemd-resolved，准备直接修改 /etc/resolv.conf"
    backup_resolv_conf
    write_resolv_conf
fi
