#!/bin/bash
# from https://github.com/oneclickvirt/lxd
# 2026.04.14

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

# 容器内屏蔽安装包
if command -v apt-get >/dev/null 2>&1; then
    if ! dpkg -s apparmor &>/dev/null; then
        apt-get install -y apparmor 2>/dev/null
    fi
fi

# 容器屏蔽安装包
divert_install_script() {
    local package_name=$1
    local divert_script="/usr/local/sbin/${package_name}-install"
    local install_script="/var/lib/dpkg/info/${package_name}.postinst"
    ln -sf "${divert_script}" "${install_script}"
    sh -c "echo '#!/bin/bash' > ${divert_script}"
    sh -c "echo 'exit 1' >> ${divert_script}"
    chmod +x "${divert_script}"
}

if command -v apt-get >/dev/null 2>&1; then
    echo "Package: zmap nmap masscan medusa apache2-utils hping3
Pin: release *
Pin-Priority: -1" | sudo tee -a /etc/apt/preferences
    apt-get update
fi
divert_install_script "zmap"
divert_install_script "nmap"
divert_install_script "masscan"
divert_install_script "medusa"
divert_install_script "hping3"
divert_install_script "apache2-utils"

# 屏蔽端口流量（不使用 -F FORWARD 以免破坏LXD网络规则）
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
