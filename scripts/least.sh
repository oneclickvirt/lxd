#!/usr/bin/env bash
# from
# https://github.com/oneclickvirt/lxd
# cd /root
# ./least.sh NAT服务器前缀 数量
# 2026.02.28

cd /root >/dev/null 2>&1
if [ ! -d "/usr/local/bin" ]; then
    mkdir -p "/usr/local/bin"
fi

# 检测防火墙后端：优先nftables，回退iptables
detect_firewall_backend() {
    FW_BACKEND=""
    if command -v nft >/dev/null 2>&1; then
        FW_BACKEND="nft"
        return 0
    fi
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y nftables >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y nftables >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y nftables >/dev/null 2>&1
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --noconfirm nftables >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache nftables >/dev/null 2>&1
    fi
    if command -v nft >/dev/null 2>&1; then
        FW_BACKEND="nft"
        return 0
    fi
    FW_BACKEND="ipt"
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >/dev/null 2>&1
    fi
    return 0
}

save_firewall_rules() {
    if [ "$FW_BACKEND" = "nft" ]; then
        nft list ruleset > /etc/nftables.conf 2>/dev/null
        if command -v systemctl >/dev/null 2>&1; then
            systemctl enable nftables >/dev/null 2>&1
        fi
    else
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null
        ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save >/dev/null 2>&1
        fi
    fi
}

check_china() {
    echo "IP area being detected ......"
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 6 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            echo "根据ipapi.co提供的信息，当前IP可能在中国，使用中国镜像完成相关组件安装"
            CN=true
        fi
    fi
}

check_china
rm -rf log
lxc init opsmaru:debian/12 "$1" -c limits.cpu=1 -c limits.memory=128MiB -s default
if [ -f /usr/local/bin/lxd_storage_type ]; then
    storage_type=$(cat /usr/local/bin/lxd_storage_type)
else
    storage_type="btrfs"
fi
lxc storage create "$1" "$storage_type" size=1GB >/dev/null 2>&1
lxc config device override "$1" root size=1GB
lxc config device set "$1" root limits.max 1GB
lxc config device set "$1" root limits.read 500MB
lxc config device set "$1" root limits.write 500MB
lxc config device set "$1" root limits.read 5000iops
lxc config device set "$1" root limits.write 5000iops
lxc config device override "$1" eth0 limits.egress=300Mbit \
  limits.ingress=300Mbit \
  limits.max=300Mbit
lxc config set "$1" limits.cpu.priority 0
lxc config set "$1" limits.cpu.allowance 50%
lxc config set "$1" limits.cpu.allowance 25ms/100ms
lxc config set "$1" limits.memory.swap true
lxc config set "$1" limits.memory.swap.priority 1
lxc config set "$1" security.nesting true
# if [ "$(uname -a | grep -i ubuntu)" ]; then
#   # Set the security settings
#   lxc config set "$1" security.syscalls.intercept.mknod true
#   lxc config set "$1" security.syscalls.intercept.setxattr true
# fi
# 屏蔽端口
detect_firewall_backend
blocked_ports=(3389 8888 54321 65432)
if [ "$FW_BACKEND" = "nft" ]; then
    nft list table inet lxd_block >/dev/null 2>&1 || nft add table inet lxd_block
    nft flush chain inet lxd_block forward_block 2>/dev/null
    nft list chain inet lxd_block forward_block >/dev/null 2>&1 || \
        nft 'add chain inet lxd_block forward_block { type filter hook forward priority 0; policy accept; }'
    for port in "${blocked_ports[@]}"; do
        nft add rule inet lxd_block forward_block oifname "eth0" tcp dport "$port" drop
        nft add rule inet lxd_block forward_block oifname "eth0" udp dport "$port" drop
    done
else
    for port in "${blocked_ports[@]}"; do
        iptables -C FORWARD -o eth0 -p tcp --dport "$port" -j DROP 2>/dev/null || \
            iptables -I FORWARD -o eth0 -p tcp --dport "$port" -j DROP
        iptables -C FORWARD -o eth0 -p udp --dport "$port" -j DROP 2>/dev/null || \
            iptables -I FORWARD -o eth0 -p udp --dport "$port" -j DROP
    done
fi
save_firewall_rules
if [ ! -f /usr/local/bin/ssh_bash.sh ]; then
    curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_bash.sh -o /usr/local/bin/ssh_bash.sh
    chmod 777 /usr/local/bin/ssh_bash.sh
    dos2unix /usr/local/bin/ssh_bash.sh
fi
cp /usr/local/bin/ssh_bash.sh /root
if [ ! -f /usr/local/bin/config.sh ]; then
    curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/config.sh -o /usr/local/bin/config.sh
    chmod 777 /usr/local/bin/config.sh
    dos2unix /usr/local/bin/config.sh
fi
cp /usr/local/bin/config.sh /root
# 批量创建容器
for ((a = 1; a <= "$2"; a++)); do
    name="$1"$a
    lxc copy "$1" "$name"
    sshn=$((20000 + a))
    ori=$(date | md5sum)
    passwd=${ori:2:9}
    lxc start "$name"
    sleep 1
    echo "Waiting for the container to start. Attempting to retrieve the container's IP address..."
    max_retries=3
    delay=5
    for ((i=1; i<=max_retries; i++)); do
        echo "Attempt $i: Waiting $delay seconds before retrieving container info..."
        sleep $delay
        container_ip=$(lxc list "$name" --format json | jq -r '.[0].state.network.eth0.addresses[]? | select(.family=="inet") | .address')
        if [[ -n "$container_ip" ]]; then
            echo "Container IPv4 address: $container_ip"
            break
        fi
        delay=$((delay * 2))
    done
    if [[ -z "$container_ip" ]]; then
        echo "Error: Container failed to start or no IP address was assigned."
        lxc delete --force "$name" 2>/dev/null || true
        exit 1
    fi
    ipv4_address=$(ip addr show | awk '/inet .*global/ && !/inet6/ {print $2}' | sed -n '1p' | cut -d/ -f1)
    echo "Host IPv4 address: $ipv4_address"
    if [[ "${CN}" == true ]]; then
        lxc exec "$name" -- apt-get install curl -y --fix-missing
        lxc exec "$name" -- curl -lk https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh -o ChangeMirrors.sh
        lxc exec "$name" -- chmod 777 ChangeMirrors.sh
        lxc exec "$name" -- ./ChangeMirrors.sh --source mirrors.tuna.tsinghua.edu.cn --web-protocol http --intranet false --backup true --updata-software false --clean-cache false --ignore-backup-tips
        lxc exec "$name" -- rm -rf ChangeMirrors.sh
    fi
    lxc exec "$name" -- sudo apt-get update -y
    lxc exec "$name" -- sudo apt-get install curl -y --fix-missing
    lxc exec "$name" -- sudo apt-get install -y --fix-missing dos2unix
    lxc file push /root/ssh_bash.sh "$name"/root/
    lxc exec "$name" -- chmod 777 ssh_bash.sh
    lxc exec "$name" -- dos2unix ssh_bash.sh
    lxc exec "$name" -- sudo ./ssh_bash.sh $passwd
    lxc file push /root/config.sh "$name"/root/
    lxc exec "$name" -- chmod +x config.sh
    lxc exec "$name" -- dos2unix config.sh
    lxc exec "$name" -- bash config.sh
    if ! lxc config device override "$name" eth0 ipv4.address="$container_ip" 2>/dev/null; then
        if ! lxc config device set "$name" eth0 ipv4.address "$container_ip" 2>/dev/null; then
            echo "Error: Failed to set ipv4.address for device 'eth0' in container '$name'." >&2
            lxc delete --force "$name" 2>/dev/null || true
            exit 1
        fi
    fi
    lxc config device add "$name" ssh-port proxy listen=tcp:$ipv4_address:$sshn connect=tcp:0.0.0.0:22 nat=true
    lxc config set "$name" user.description "$name $sshn $passwd"
    echo "$name $sshn $passwd" >>log
done
rm -rf ssh_bash.sh config.sh ssh_sh.sh
