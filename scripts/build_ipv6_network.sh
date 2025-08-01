#!/bin/bash
# by https://github.com/oneclickvirt/lxd
# 2025.04.22

# ./build_ipv6_network.sh LXC容器名称 <是否使用iptables进行映射>

# 输出颜色函数
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }

# 设置UTF-8环境
setup_locale() {
    utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "utf8|UTF-8")
    if [[ -z "$utf8_locale" ]]; then
        _yellow "No UTF-8 locale found"
    else
        export LC_ALL="$utf8_locale"
        export LANG="$utf8_locale"
        export LANGUAGE="$utf8_locale"
        _green "Locale set to $utf8_locale"
    fi
}

# 安装依赖包
install_package() {
    package_name=$1
    if command -v $package_name >/dev/null 2>&1; then
        _green "$package_name has been installed"
        _green "$package_name 已经安装"
    else
        apt-get install -y $package_name
        if [ $? -ne 0 ]; then
            apt-get install -y $package_name --fix-missing
        fi
        _green "$package_name has attempted to install"
        _green "$package_name 已尝试安装"
    fi
}

# 检查IPv6地址是否为私有地址
is_private_ipv6() {
    local address=$1
    local temp="0"
    if [[ ! -n $address ]]; then
        temp="1"
    fi
    if [[ -n $address && $address != *":"* ]]; then
        temp="2"
    fi
    if [[ $address == fe80:* ]]; then
        temp="3"
    fi
    if [[ $address == fc00:* || $address == fd00:* ]]; then
        temp="4"
    fi
    if [[ $address == 2001:db8* ]]; then
        temp="5"
    fi
    if [[ $address == ::1 ]]; then
        temp="6"
    fi
    if [[ $address == ::ffff:* ]]; then
        temp="7"
    fi
    if [[ $address == 2002:* ]]; then
        temp="8"
    fi
    if [[ $address == 2001:* ]]; then
        temp="9"
    fi
    if [[ $address == fd42:* ]]; then
        temp="10"
    fi
    if [ "$temp" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# 获取公网IPv6地址
check_ipv6() {
    IPV6=$(ip -6 addr show | grep global | awk '{print length, $2}' | sort -nr | head -n 1 | awk '{print $2}' | cut -d '/' -f1)
    if is_private_ipv6 "$IPV6"; then
        IPV6=""
        API_NET=("ipv6.ip.sb" "https://ipget.net" "ipv6.ping0.cc" "https://api.my-ip.io/ip" "https://ipv6.icanhazip.com")
        for p in "${API_NET[@]}"; do
            response=$(curl -sLk6m8 "$p" | tr -d '[:space:]')
            if [ $? -eq 0 ] && ! (echo "$response" | grep -q "error"); then
                IPV6="$response"
                break
            fi
            sleep 1
        done
    fi
    echo $IPV6 >/usr/local/bin/lxd_check_ipv6
}

# 更新系统配置参数
update_sysctl() {
    sysctl_config="$1"
    if grep -q "^$sysctl_config" /etc/sysctl.conf; then
        if grep -q "^#$sysctl_config" /etc/sysctl.conf; then
            sed -i "s/^#$sysctl_config/$sysctl_config/" /etc/sysctl.conf
        fi
    else
        echo "$sysctl_config" >>/etc/sysctl.conf
    fi
}

# 等待容器状态变更
wait_for_container_status() {
    container_name=$1
    target_status=$2
    timeout=$3
    interval=3
    elapsed_time=0
    while [ $elapsed_time -lt $timeout ]; do
        status=$(lxc info "$container_name" | grep "Status: $target_status")
        if [[ "$status" == *"$target_status"* ]]; then
            return 0
        fi
        echo "Waiting for the container \"$container_name\" to $target_status..."
        echo "${status}"
        sleep $interval
        elapsed_time=$((elapsed_time + interval))
    done
    return 1
}

# 使用网络设备方式映射IPv6
setup_network_device_mapping() {
    install_package sipcalc
    if [ ! -f /usr/local/bin/lxd_check_ipv6 ] || [ ! -s /usr/local/bin/lxd_check_ipv6 ] || [ "$(sed -e '/^[[:space:]]*$/d' /usr/local/bin/lxd_check_ipv6)" = "" ]; then
        check_ipv6
    fi
    IPV6=$(cat /usr/local/bin/lxd_check_ipv6)
    if ip -f inet6 addr | grep -q "he-ipv6"; then
        ipv6_network_name="he-ipv6"
        ip_network_gam=$(ip -6 addr show ${ipv6_network_name} | grep -E "${IPV6}/24|${IPV6}/48|${IPV6}/64|${IPV6}/80|${IPV6}/96|${IPV6}/112" | grep global | awk '{print $2}' 2>/dev/null)
    else
        ipv6_network_name=$(ls /sys/class/net/ | grep -v "$(ls /sys/devices/virtual/net/)")
        ip_network_gam=$(ip -6 addr show ${ipv6_network_name} | grep global | awk '{print $2}' | head -n 1)
    fi
    _yellow "Local IPV6 address: $ip_network_gam"
    if [ -n "$ip_network_gam" ]; then
        update_sysctl "net.ipv6.conf.${ipv6_network_name}.proxy_ndp=1"
        update_sysctl "net.ipv6.conf.all.forwarding=1"
        update_sysctl "net.ipv6.conf.all.proxy_ndp=1"
        sysctl_path=$(which sysctl)
        ${sysctl_path} -p
        ipv6_lala=$(sipcalc ${ip_network_gam} | grep "Compressed address" | awk '{print $4}' | awk -F: '{NF--; print}' OFS=:):
        randbits=$(od -An -N2 -t x1 /dev/urandom | tr -d ' ')
        lxc_ipv6="${ipv6_lala%/*}${randbits}"
        _green "Container $CONTAINER_NAME IPV6:"
        _green "$lxc_ipv6"
        lxc stop "$CONTAINER_NAME"
        sleep 3
        wait_for_container_status "$CONTAINER_NAME" "STOPPED" 24
        lxc config device add "$CONTAINER_NAME" eth1 nic nictype=routed parent=${ipv6_network_name} ipv6.address=${lxc_ipv6}
        sleep 3
        lxc start "$CONTAINER_NAME"
        handle_fe80_gateway
        setup_ipv6_cron
        echo "$lxc_ipv6" >>"$CONTAINER_NAME"_v6
    fi
}

# 处理fe80网关
handle_fe80_gateway() {
    if [[ "${ipv6_gateway_fe80}" == "N" ]]; then
        inter=$(ls /sys/class/net/ | grep -v "$(ls /sys/devices/virtual/net/)")
        del_ip=$(ip -6 addr show dev ${inter} | awk '/inet6 fe80/ {print $2}')
        if [ -n "$del_ip" ]; then
            ip addr del ${del_ip} dev ${inter}
            echo '#!/bin/bash' >/usr/local/bin/remove_route.sh
            echo "ip addr del ${del_ip} dev ${inter}" >>/usr/local/bin/remove_route.sh
            chmod 777 /usr/local/bin/remove_route.sh
            if ! crontab -l | grep -q '/usr/local/bin/remove_route.sh' &>/dev/null; then
                echo '@reboot /usr/local/bin/remove_route.sh' | crontab -
            fi
        fi
    fi
}

# 设置IPv6相关的定时任务
setup_ipv6_cron() {
    if ! crontab -l | grep -q '*/1 * * * * curl -m 6 -s ipv6.ip.sb && curl -m 6 -s ipv6.ip.sb'; then
        echo '*/1 * * * * curl -m 6 -s ipv6.ip.sb && curl -m 6 -s ipv6.ip.sb' | crontab -
    fi
}

# 使用iptables映射IPv6
setup_iptables_mapping() {
    install_package netfilter-persistent
    # 寻找未使用的子网内的一个IPV6地址
    for i in $(seq 3 65535); do
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
        _red "No IPV6 address available, no auto mapping"
        _red "无可用 IPV6 地址，不进行自动映射"
        exit 1
    fi
    # 映射 IPV6 地址到容器的私有 IPV6 地址
    ip addr add "$IPV6"/"$ipv6_length" dev "$interface"
    ip6tables -t nat -A PREROUTING -d $IPV6 -j DNAT --to-destination $CONTAINER_IPV6
    # 设置持久化服务
    setup_persistence_service
    # 保存iptables规则
    save_iptables_rules
    # 测试连通性
    test_ipv6_connectivity "$IPV6"
    # 写入信息
    echo "$IPV6" >>"$CONTAINER_NAME"_v6
}

# 检测CDN
check_cdn() {
    local o_url=$1
    local shuffled_cdn_urls=($(shuf -e "${cdn_urls[@]}")) # 打乱数组顺序
    for cdn_url in "${shuffled_cdn_urls[@]}"; do
        if curl -sL -k "$cdn_url$o_url" --max-time 6 | grep -q "success" >/dev/null 2>&1; then
            export cdn_success_url="$cdn_url"
            return
        fi
        sleep 0.5
    done
    export cdn_success_url=""
}

# 检测CDN可用性
check_cdn_file() {
    check_cdn "https://raw.githubusercontent.com/spiritLHLS/ecs/main/back/test"
    if [ -n "$cdn_success_url" ]; then
        echo "CDN available, using CDN"
    else
        echo "No CDN available, no use CDN"
    fi
}

# 设置持久化服务
setup_persistence_service() {
    if [ ! -f /usr/local/bin/add-ipv6.sh ]; then
        wget ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/add-ipv6.sh -O /usr/local/bin/add-ipv6.sh
        chmod +x /usr/local/bin/add-ipv6.sh
    else
        echo "Script already exists. Skipping installation."
    fi
    if [ ! -f /etc/systemd/system/add-ipv6.service ]; then
        wget ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/add-ipv6.service -O /etc/systemd/system/add-ipv6.service
        chmod +x /etc/systemd/system/add-ipv6.service
        systemctl daemon-reload
        systemctl enable add-ipv6.service
        systemctl start add-ipv6.service
    else
        echo "Service already exists. Skipping installation."
    fi
}

# 保存iptables规则
save_iptables_rules() {
    if [ ! -f "/etc/iptables/rules.v6" ]; then
        touch /etc/iptables/rules.v6
    fi
    ip6tables-save >/etc/iptables/rules.v6
    netfilter-persistent save
    netfilter-persistent reload
    service netfilter-persistent restart
}

# 测试IPv6连通性
test_ipv6_connectivity() {
    local ipv6_addr=$1
    if ping6 -c 3 $ipv6_addr &>/dev/null; then
        _green "$CONTAINER_NAME The external IPV6 address of the container is $ipv6_addr"
        _green "$CONTAINER_NAME 容器的外网IPV6地址为 $ipv6_addr"
    else
        _red "Mapping failure"
        _red "映射失败"
        exit 1
    fi
}

main() {
    if [ ! -d "/usr/local/bin" ]; then
        mkdir -p /usr/local/bin
    fi
    setup_locale
    CONTAINER_NAME="$1"
    use_iptables="${2:-N}"
    use_iptables=$(echo "$use_iptables" | tr '[:upper:]' '[:lower:]')
    # 安装必要的包
    install_package sudo
    install_package lshw
    install_package jq
    install_package net-tools
    install_package cron
    # 查询网卡
    interface=$(lshw -C network | awk '/logical name:/{print $3}' | head -1)
    _yellow "NIC $interface"
    _yellow "网卡 $interface"
    # 等待容器运行
    wait_for_container_status "$CONTAINER_NAME" "RUNNING" 24
    # 获取指定LXC容器的内网IPV6
    CONTAINER_IPV6=$(lxc list $CONTAINER_NAME --format=json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet6") | select(.scope=="global") | .address')
    if [ -z "$CONTAINER_IPV6" ]; then
        _red "Container has no intranet IPV6 address, no auto-mapping"
        _red "容器无内网IPV6地址，不进行自动映射"
        exit 1
    fi
    _blue "The container with the name $CONTAINER_NAME has an intranet IPV6 address of $CONTAINER_IPV6"
    _blue "$CONTAINER_NAME 容器的内网IPV6地址为 $CONTAINER_IPV6"
    # 获取宿主机子网前缀
    SUBNET_PREFIX=$(ip -6 addr show | grep -E 'inet6.*global' | awk '{print $2}' | awk -F'/' '{print $1}' | head -n 1 | cut -d ':' -f1-5):
    # 获取宿主机的IPV6地址
    ipv6_address=$(ip addr show | awk '/inet6.*scope global/ { print $2 }' | head -n 1)
    if [[ $ipv6_address == */* ]]; then
        ipv6_length=$(echo "$ipv6_address" | awk -F '/' '{ print $2 }')
        _green "subnet size: $ipv6_length"
        _green "子网大小: $ipv6_length"
    else
        _green "Subnet size for IPV6 not queried"
        _green "查询不到IPV6的子网大小"
        exit 1
    fi
    # fe80检测
    output=$(ip -6 route show | awk '/default via/{print $3}')
    num_lines=$(echo "$output" | wc -l)
    ipv6_gateway=""
    if [ $num_lines -eq 1 ]; then
        ipv6_gateway="$output"
    elif [ $num_lines -ge 2 ]; then
        non_fe80_lines=$(echo "$output" | grep -v '^fe80')
        if [ -n "$non_fe80_lines" ]; then
            ipv6_gateway=$(echo "$non_fe80_lines" | head -n 1)
        else
            ipv6_gateway=$(echo "$output" | head -n 1)
        fi
    fi
    # 判断fe80是否已加白
    if [[ $ipv6_gateway == fe80* ]]; then
        ipv6_gateway_fe80="Y"
    else
        ipv6_gateway_fe80="N"
    fi
    # 检查是否存在 IPV6
    if [ -z "$SUBNET_PREFIX" ]; then
        _red "No IPV6 subnet, no automatic mapping"
        _red "无 IPV6 子网，不进行自动映射"
        exit 1
    fi
    _blue "The IPV6 subnet prefix is $SUBNET_PREFIX"
    _blue "宿主机的IPV6子网前缀为 $SUBNET_PREFIX"
    # 根据选项决定映射方式
    if [[ $use_iptables == n ]]; then
        setup_network_device_mapping
    else
        cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")
        check_cdn_file
        setup_iptables_mapping
    fi
}

main "$@"
