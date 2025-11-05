#!/bin/bash
#from https://github.com/oneclickvirt/lxd
# 2025.09.18
set -e

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
        restart)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart "$service_name" 2>/dev/null && success=true
            fi
            if ! $success && command -v rc-service >/dev/null 2>&1; then
                rc-service "$service_name" restart 2>/dev/null && success=true
            fi
            if ! $success && command -v service >/dev/null 2>&1; then
                service "$service_name" restart 2>/dev/null && success=true
            fi
            if ! $success && [ -x "/etc/init.d/$service_name" ]; then
                /etc/init.d/"$service_name" restart 2>/dev/null && success=true
            fi
            ;;
        is-active)
            if command -v systemctl >/dev/null 2>&1; then
                if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                    return 0
                fi
            fi
            if command -v rc-service >/dev/null 2>&1; then
                if rc-service "$service_name" status >/dev/null 2>&1; then
                    return 0
                fi
            fi
            if command -v service >/dev/null 2>&1; then
                if service "$service_name" status >/dev/null 2>&1; then
                    return 0
                fi
            fi
            if [ -x "/etc/init.d/$service_name" ]; then
                if /etc/init.d/"$service_name" status >/dev/null 2>&1; then
                    return 0
                fi
            fi
            return 1
            ;;
    esac
    
    if [ "$action" != "is-active" ]; then
        $success && return 0 || return 1
    fi
}

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
RESOLVED_CONF="/etc/systemd/resolved.conf"

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
    if [ -z "$METRIC" ] || [ "$METRIC" = "--" ]; then
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

check_resolv_conf_symlink() {
    if [ -L "/etc/resolv.conf" ]; then
        local target=$(readlink /etc/resolv.conf)
        echo "/etc/resolv.conf 是软链接，指向 $target"
        # 检查是否指向 systemd-resolved 的 stub
        if [[ "$target" == *"systemd/resolve"* ]]; then
            echo "检测到 systemd-resolved stub 配置"
            return 0
        else
            echo "软链接指向非 systemd-resolved 目标"
            return 1
        fi
    else
        echo "/etc/resolv.conf 不是软链接"
        return 1
    fi
}

# 检查DNS是否已经配置
check_dns_already_configured() {
    local target_ipv4="${DNS_SERVERS_IPV4[0]}"  # 使用第一个IPv4 DNS作为标记
    local target_ipv6="${DNS_SERVERS_IPV6[2]}"  # 使用第三个IPv6 DNS作为标记
    
    # 检查当前DNS解析配置
    if command -v nslookup >/dev/null 2>&1; then
        # 获取当前使用的DNS服务器
        local current_dns=$(nslookup google.com 2>/dev/null | grep -E "Server:|Address:" | head -2 | tail -1 | awk '{print $2}' | cut -d'#' -f1)
        for dns in "${DNS_SERVERS_IPV4[@]}" "${DNS_SERVERS_IPV6[@]}"; do
            if [ "$current_dns" = "$dns" ]; then
                echo "检测到已配置的DNS服务器: $dns"
                return 0
            fi
        done
    fi
    
    # 检查 /etc/resolv.conf 内容
    if [ -f "/etc/resolv.conf" ]; then
        if grep -q "$target_ipv4" /etc/resolv.conf && grep -q "$target_ipv6" /etc/resolv.conf; then
            echo "DNS 配置已存在于 /etc/resolv.conf"
            return 0
        fi
    fi
    
    return 1
}

# 配置 systemd-resolved
configure_systemd_resolved() {
    echo "配置 systemd-resolved..."
    
    # 备份配置文件
    backup_file "$RESOLVED_CONF"
    
    # 构建DNS服务器列表
    local dns_list=("${DNS_SERVERS_IPV4[@]}" "${DNS_SERVERS_IPV6[@]}")
    local fallback_dns_list=("9.9.9.9" "2620:fe::fe")
    
    # 检查是否已经配置了我们的DNS设置
    local current_dns=""
    if [ -f "$RESOLVED_CONF" ] && grep -q "^DNS=" "$RESOLVED_CONF"; then
        current_dns=$(grep "^DNS=" "$RESOLVED_CONF" | cut -d'=' -f2 | tr -s ' ')
    fi
    
    local new_dns=$(join " " "${dns_list[@]}")
    local new_fallback_dns=$(join " " "${fallback_dns_list[@]}")
    
    # 如果当前配置与新配置相同，跳过
    if [ "$current_dns" = "$new_dns" ]; then
        echo "systemd-resolved DNS 配置已是最新，无需修改"
        return 0
    fi
    
    # 创建临时文件进行配置更新
    local temp_file=$(mktemp)
    local updated=false
    local fallback_updated=false
    
    # 读取原配置文件并更新
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^#?DNS= ]]; then
            if ! $updated; then
                echo "DNS=$new_dns" >> "$temp_file"
                updated=true
            fi
        elif [[ "$line" =~ ^#?FallbackDNS= ]]; then
            if ! $fallback_updated; then
                echo "FallbackDNS=$new_fallback_dns" >> "$temp_file"
                fallback_updated=true
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$RESOLVED_CONF"
    
    # 如果没有找到 DNS= 行，添加到 [Resolve] 段落下
    if ! $updated; then
        # 重新处理文件，在 [Resolve] 段落后添加配置
        > "$temp_file"  # 清空临时文件
        local in_resolve_section=false
        local dns_added=false
        
        while IFS= read -r line || [ -n "$line" ]; do
            echo "$line" >> "$temp_file"
            if [[ "$line" == "[Resolve]" ]]; then
                in_resolve_section=true
            elif $in_resolve_section && [[ "$line" =~ ^\[.*\] ]] && [ "$line" != "[Resolve]" ]; then
                # 进入了新的段落，在这之前添加DNS配置
                if ! $dns_added; then
                    echo "DNS=$new_dns" >> "$temp_file"
                    if ! $fallback_updated; then
                        echo "FallbackDNS=$new_fallback_dns" >> "$temp_file"
                    fi
                    dns_added=true
                fi
                in_resolve_section=false
            fi
        done < "$RESOLVED_CONF"
        
        # 如果文件末尾还在 [Resolve] 段落中，添加DNS配置
        if $in_resolve_section && ! $dns_added; then
            echo "DNS=$new_dns" >> "$temp_file"
            if ! $fallback_updated; then
                echo "FallbackDNS=$new_fallback_dns" >> "$temp_file"
            fi
        fi
    fi
    
    # 应用新配置
    mv "$temp_file" "$RESOLVED_CONF"
    
    echo "systemd-resolved 配置已更新"
    echo "新的 DNS 服务器: $new_dns"
    echo "备用 DNS 服务器: $new_fallback_dns"
    
    # 重启 systemd-resolved 服务
    echo "重启 systemd-resolved 服务..."
    service_manager restart systemd-resolved
    
    # 等待服务启动
    sleep 2
    
    echo "systemd-resolved DNS 配置完成"
    return 0
}

write_resolv_conf() {
    # 检查是否是 systemd-resolved 链接
    if check_resolv_conf_symlink; then
        echo "检测到 /etc/resolv.conf 是 systemd-resolved 软链接"
        if service_manager is-active systemd-resolved; then
            echo "systemd-resolved 服务运行中，将通过配置文件设置DNS"
            configure_systemd_resolved
            return 0
        else
            echo "systemd-resolved 服务未运行，启动服务..."
            service_manager start systemd-resolved
            service_manager enable systemd-resolved
            configure_systemd_resolved
            return 0
        fi
    fi
    
    echo "写入 /etc/resolv.conf ..."
    backup_resolv_conf
    
    # 检查文件是否已经包含我们的DNS配置
    local has_our_dns=true
    for dns in "${DNS_SERVERS_IPV4[@]}" "${DNS_SERVERS_IPV6[@]}"; do
        if ! grep -q "nameserver $dns" /etc/resolv.conf 2>/dev/null; then
            has_our_dns=false
            break
        fi
    done
    
    if $has_our_dns; then
        echo "DNS 配置已存在于 /etc/resolv.conf，跳过修改"
        return 0
    fi
    
    # 重写整个文件以避免重复
    {
        echo "# 由 $0 生成，覆盖写入 $(date)"
        for dns in "${DNS_SERVERS_IPV4[@]}"; do
            echo "nameserver $dns"
        done
        for dns in "${DNS_SERVERS_IPV6[@]}"; do
            echo "nameserver $dns"
        done
    } > /etc/resolv.conf
    echo "/etc/resolv.conf 更新完成"
}

# 检查nmcli连接的DNS配置是否已存在
check_nmcli_dns_configured() {
    local CONN_NAME=$1
    local TARGET_IPV4="${DNS_SERVERS_IPV4[0]}"
    local TARGET_IPV6="${DNS_SERVERS_IPV6[2]}"
    
    local CURRENT_IPV4_DNS=$(nmcli connection show "$CONN_NAME" | grep '^ipv4.dns:' | awk '{print $2}')
    local CURRENT_IPV6_DNS=$(nmcli connection show "$CONN_NAME" | grep '^ipv6.dns:' | awk '{print $2}')
    
    # 检查是否包含我们的目标DNS服务器
    if echo "$CURRENT_IPV4_DNS" | grep -qw "$TARGET_IPV4" && echo "$CURRENT_IPV6_DNS" | grep -qw "$TARGET_IPV6"; then
        return 0
    fi
    return 1
}

# 检查resolvectl接口的DNS配置是否已存在  
check_resolvectl_dns_configured() {
    local IFACE=$1
    local TARGET_IPV4="${DNS_SERVERS_IPV4[0]}"
    local TARGET_IPV6="${DNS_SERVERS_IPV6[2]}"
    
    local CURRENT_DNS=$(resolvectl dns "$IFACE" 2>/dev/null || echo "")
    
    # 检查是否包含我们的目标DNS服务器
    if echo "$CURRENT_DNS" | grep -qw "$TARGET_IPV4" && echo "$CURRENT_DNS" | grep -qw "$TARGET_IPV6"; then
        return 0
    fi
    return 1
}

# 主逻辑开始
echo "开始DNS配置..."

# 首先检查是否已经配置过
if check_dns_already_configured; then
    echo "DNS 已正确配置，无需重复设置"
    exit 0
fi

set_ipv4_precedence_gai

if check_nmcli; then
    echo "检测到 NetworkManager，使用 nmcli 设置 DNS 和路由优先"
    CONN_NAME=$(nmcli -t -f NAME,DEVICE connection show --active | head -n1 | cut -d: -f1)
    if [ -z "$CONN_NAME" ]; then
        echo "未检测到活动连接，退出。"
        exit 1
    fi
    echo "活动连接: $CONN_NAME"
    
    if check_nmcli_dns_configured "$CONN_NAME"; then
        echo "DNS 配置已存在于连接 $CONN_NAME，无需修改"
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
elif check_resolvectl && service_manager is-active systemd-resolved; then
    echo "检测到 systemd-resolved，使用 resolvectl 设置 DNS"
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -z "$IFACE" ]; then
        echo "未检测到默认网络接口，退出。"
        exit 1
    fi
    echo "默认接口: $IFACE"
    
    if check_resolvectl_dns_configured "$IFACE"; then
        echo "DNS 配置已存在于接口 $IFACE，无需修改"
    else
        echo "设置 DNS 服务器..."
        resolvectl dns "$IFACE" "${DNS_SERVERS_IPV4[@]}" "${DNS_SERVERS_IPV6[@]}"
        echo "DNS 配置已更新。"
    fi
else
    echo "未检测到 NetworkManager 或活跃的 systemd-resolved，准备配置 DNS 解析"
    write_resolv_conf
fi

echo "DNS 配置脚本执行完成"
