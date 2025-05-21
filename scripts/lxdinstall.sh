#!/bin/bash
# by https://github.com/oneclickvirt/lxd
# 2025.05.20

# curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/lxdinstall.sh -o lxdinstall.sh && chmod +x lxdinstall.sh && bash lxdinstall.sh

cd /root >/dev/null 2>&1
REGEX=("debian|astra" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "arch" "freebsd")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Arch" "FreeBSD")
CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')" "$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(uname -s)")
SYS="${CMD[0]}"
[[ -n $SYS ]] || exit 1
for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}"
        [[ -n $SYSTEM ]] && break
    fi
done
TRIED_STORAGE_FILE="/usr/local/bin/incus_tried_storage"
INSTALLED_STORAGE_FILE="/usr/local/bin/incus_installed_storage"
if [ ! -d "/usr/local/bin" ]; then
    mkdir -p /usr/local/bin
fi

_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }

cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")

set_locale() {
    utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "utf8|UTF-8")
    export DEBIAN_FRONTEND=noninteractive
    if [[ -z "$utf8_locale" ]]; then
        _yellow "No UTF-8 locale found"
    else
        export LC_ALL="$utf8_locale"
        export LANG="$utf8_locale"
        export LANGUAGE="$utf8_locale"
        _green "Locale set to $utf8_locale"
    fi
}

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

check_cdn() {
    local o_url=$1
    local shuffled_cdn_urls=($(shuf -e "${cdn_urls[@]}"))
    for cdn_url in "${shuffled_cdn_urls[@]}"; do
        if curl -sL -k "$cdn_url$o_url" --max-time 6 | grep -q "success" >/dev/null 2>&1; then
            export cdn_success_url="$cdn_url"
            return
        fi
        sleep 0.5
    done
    export cdn_success_url=""
}

check_cdn_file() {
    check_cdn "https://raw.githubusercontent.com/spiritLHLS/ecs/main/back/test"
    if [ -n "$cdn_success_url" ]; then
        echo "CDN available, using CDN"
    else
        echo "No CDN available, no use CDN"
    fi
}

statistics_of_run_times() {
    COUNT=$(curl -4 -ksm1 "https://hits.spiritlhl.net/lxd?action=hit&title=Hits&title_bg=%23555555&count_bg=%2324dde1&edge_flat=false" 2>/dev/null ||
        curl -6 -ksm1 "https://hits.spiritlhl.net/lxd?action=hit&title=Hits&title_bg=%23555555&count_bg=%2324dde1&edge_flat=false" 2>/dev/null)
    TODAY=$(echo "$COUNT" | grep -oP '"daily":\s*[0-9]+' | sed 's/"daily":\s*\([0-9]*\)/\1/')
    TOTAL=$(echo "$COUNT" | grep -oP '"total":\s*[0-9]+' | sed 's/"total":\s*\([0-9]*\)/\1/')
}

rebuild_cloud_init() {
    if [ -f "/etc/cloud/cloud.cfg" ]; then
        chattr -i /etc/cloud/cloud.cfg
        if grep -q "preserve_hostname: true" "/etc/cloud/cloud.cfg"; then
            :
        else
            sed -E -i 's/preserve_hostname:[[:space:]]*false/preserve_hostname: true/g' "/etc/cloud/cloud.cfg"
            echo "change preserve_hostname to true"
        fi
        if grep -q "disable_root: false" "/etc/cloud/cloud.cfg"; then
            :
        else
            sed -E -i 's/disable_root:[[:space:]]*true/disable_root: false/g' "/etc/cloud/cloud.cfg"
            echo "change disable_root to false"
        fi
        chattr -i /etc/cloud/cloud.cfg
        content=$(cat /etc/cloud/cloud.cfg)
        line_number=$(grep -n "^system_info:" "/etc/cloud/cloud.cfg" | cut -d ':' -f 1)
        if [ -n "$line_number" ]; then
            lines_after_system_info=$(echo "$content" | sed -n "$((line_number + 1)),\$p")
            if [ -n "$lines_after_system_info" ]; then
                updated_content=$(echo "$content" | sed "$((line_number + 1)),\$d")
                echo "$updated_content" >"/etc/cloud/cloud.cfg"
            fi
        fi
        sed -i '/^\s*- set-passwords/s/^/#/' /etc/cloud/cloud.cfg
        chattr +i /etc/cloud/cloud.cfg
    fi
}

get_available_space() {
    local available_space
    available_space=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
    echo "$available_space"
}

install_base_packages() {
    apt-get update
    apt-get autoremove -y
    install_package wget
    install_package curl
    install_package sudo
    install_package dos2unix
    install_package ufw
    install_package jq
    install_package uidmap
    install_package ipcalc
    install_package unzip
}

install_lxd() {
    lxd_snap=$(dpkg -l | awk '/^[hi]i/{print $2}' | grep -ow snap)
    lxd_snapd=$(dpkg -l | awk '/^[hi]i/{print $2}' | grep -ow snapd)
    if [[ "$lxd_snap" =~ ^snap.* ]] && [[ "$lxd_snapd" =~ ^snapd.* ]]; then
        _green "snap is installed"
        _green "snap已安装"
    else
        _green "start installation of snap"
        _green "开始安装snap"
        apt-get update
        install_package snapd
    fi
    snap_core=$(snap list core)
    snap_lxd=$(snap list lxd)
    if [[ "$snap_core" =~ core.* ]] && [[ "$snap_lxd" =~ lxd.* ]]; then
        _green "lxd is installed"
        _green "lxd已安装"
        lxd_lxc_detect=$(lxc list)
        if [[ "$lxd_lxc_detect" =~ "snap-update-ns failed with code1".* ]]; then
            systemctl restart apparmor
            snap restart lxd
        else
            _green "No problems with environmental testing"
            _green "环境检测无问题"
        fi
    else
        _green "Start installation of LXD"
        _green "开始安装LXD"
        snap install lxd
        if [[ $? -ne 0 ]]; then
            snap remove lxd
            snap install core
            snap install lxd
        fi
        ! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >>/root/.bashrc && source /root/.bashrc
        export PATH=$PATH:/snap/bin
        ! lxc -h >/dev/null 2>&1 && _yellow 'lxc路径有问题，请检查修复' && exit
        _green "LXD installation complete"
        _green "LXD安装完成"
    fi
    snap set lxd lxcfs.loadavg=true
    snap set lxd lxcfs.pidfd=true
    snap set lxd lxcfs.cfs=true
    systemctl restart snap.lxd.daemon
}

configure_resources() {
    if [ "${noninteractive:-false}" = true ]; then
        available_space=$(get_available_space)
        memory_nums=1024
        disk_nums=$((available_space - 1))
    else
        while true; do
            _green "How much virtual memory does the host need to open? (Virtual memory SWAP will occupy hard disk space, calculate by yourself, note that it is MB as the unit, need 1G virtual memory then enter 1024):"
            reading "宿主机需要开设多少虚拟内存？(虚拟内存SWAP会占用硬盘空间，自行计算，注意是MB为单位，需要1G虚拟内存则输入1024)：" memory_nums
            if [[ "$memory_nums" =~ ^[1-9][0-9]*$ ]]; then
                break
            else
                _yellow "Invalid input, please enter a positive integer."
                _yellow "输入无效，请输入一个正整数。"
            fi
        done
        while true; do
            _green "How large a storage pool does the host need to open? (The storage pool is the size of the sum of the ct's hard disk, it is recommended that the SWAP and storage pool add up to 95% of the space of the hen's hard disk, note that it is in GB, enter 10 if you need 10G storage pool):"
            reading "宿主机需要开设多大的存储池？(存储池就是容器硬盘之和的大小，推荐SWAP和存储池加起来达到母鸡硬盘的95%空间，注意是GB为单位，需要10G存储池则输入10)：" disk_nums
            if [[ "$disk_nums" =~ ^[1-9][0-9]*$ ]]; then
                break
            else
                _yellow "Invalid input, please enter a positive integer."
                _yellow "输入无效，请输入一个正整数。"
            fi
        done
    fi
}

get_available_space() {
    local available_space
    available_space=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
    echo "$available_space"
}

record_tried_storage() {
    local storage_type="$1"
    echo "$storage_type" >>"$TRIED_STORAGE_FILE"
}

record_installed_storage() {
    local storage_type="$1"
    echo "$storage_type" >>"$INSTALLED_STORAGE_FILE"
}

is_storage_tried() {
    local storage_type="$1"
    for tried in "${TRIED_STORAGE[@]}"; do
        if [ "$tried" = "$storage_type" ]; then
            return 0
        fi
    done
    return 1
}

is_storage_installed() {
    local storage_type="$1"
    for installed in "${INSTALLED_STORAGE[@]}"; do
        if [ "$installed" = "$storage_type" ]; then
            return 0
        fi
    done
    return 1
}

init_storage_backend() {
    local backend="$1"
    if is_storage_tried "$backend"; then
        _yellow "已经尝试过 $backend，跳过"
        _yellow "Already tried $backend, skipping"
        return 1
    fi
    if [ "$backend" = "dir" ]; then
        _green "使用默认dir类型无限定存储池大小"
        _green "Using default dir type with unlimited storage pool size"
        echo "dir" >/usr/local/bin/lxd_storage_type
        /snap/bin/lxd init --storage-backend "$backend" --auto
        record_tried_storage "$backend"
        return $?
    fi
    _green "尝试使用 $backend 类型，存储池大小为 $disk_nums"
    _green "Trying to use $backend type with storage pool size $disk_nums"
    local need_reboot=false
    if [ "$backend" = "btrfs" ] && ! is_storage_installed "btrfs" ] && ! command -v btrfs >/dev/null; then
        _yellow "正在安装 btrfs-progs..."
        _yellow "Installing btrfs-progs..."
        install_package btrfs-progs
        record_installed_storage "btrfs"
        modprobe btrfs || true
        _green "无法加载btrfs模块。请重启本机再次执行本脚本以加载btrfs内核。"
        _green "btrfs module could not be loaded. Please reboot the machine and execute this script again."
        echo "$backend" >/usr/local/bin/lxd_reboot
        need_reboot=true
    elif [ "$backend" = "lvm" ] && ! is_storage_installed "lvm" ] && ! command -v lvm >/dev/null; then
        _yellow "正在安装 lvm2..."
        _yellow "Installing lvm2..."
        install_package lvm2
        record_installed_storage "lvm"
        modprobe dm-mod || true
        _green "无法加载LVM模块。请重启本机再次执行本脚本以加载LVM内核。"
        _green "LVM module could not be loaded. Please reboot the machine and execute this script again."
        echo "$backend" >/usr/local/bin/lxd_reboot
        need_reboot=true
    elif [ "$backend" = "zfs" ] && ! is_storage_installed "zfs" ] && ! command -v zfs >/dev/null; then
        _yellow "正在安装 zfsutils-linux..."
        _yellow "Installing zfsutils-linux..."
        install_package zfsutils-linux
        record_installed_storage "zfs"
        modprobe zfs || true
        _green "无法加载ZFS模块。请重启本机再次执行本脚本以加载ZFS内核。"
        _green "ZFS module could not be loaded. Please reboot the machine and execute this script again."
        echo "$backend" >/usr/local/bin/lxd_reboot
        need_reboot=true
    elif [ "$backend" = "ceph" ] && ! is_storage_installed "ceph" ] && ! command -v ceph >/dev/null; then
        _yellow "正在安装 ceph-common..."
        _yellow "Installing ceph-common..."
        install_package ceph-common
        record_installed_storage "ceph"
    fi
    if [ "$backend" = "btrfs" ] && is_storage_installed "btrfs" ] && ! grep -q btrfs /proc/filesystems; then
        modprobe btrfs || true
    elif [ "$backend" = "lvm" ] && is_storage_installed "lvm" ] && ! grep -q dm-mod /proc/modules; then
        modprobe dm-mod || true
    elif [ "$backend" = "zfs" ] && is_storage_installed "zfs" ] && ! grep -q zfs /proc/filesystems; then
        modprobe zfs || true
    fi
    if [ "$need_reboot" = true ]; then
        exit 1
    fi
    local temp
    if [ "$backend" = "lvm" ]; then
        temp=$(/snap/bin/lxd init --storage-backend lvm --storage-create-loop "$disk_nums" --storage-pool lvm_pool --auto 2>&1)
    else
        temp=$(/snap/bin/lxd init --storage-backend "$backend" --storage-create-loop "$disk_nums" --storage-pool default --auto 2>&1)
    fi
    local status=$?
    _green "Init storage:"
    echo "$temp"
    if echo "$temp" | grep -q "lxd.migrate" && [ $status -ne 0 ]; then
        /snap/bin/lxd.migrate
        if [ "$backend" = "lvm" ]; then
            temp=$(/snap/bin/lxd init --storage-backend lvm --storage-create-loop "$disk_nums" --storage-pool lvm_pool --auto 2>&1)
        else
            temp=$(/snap/bin/lxd init --storage-backend "$backend" --storage-create-loop "$disk_nums" --storage-pool default --auto 2>&1)
        fi
        status=$?
        echo "$temp"
    fi
    record_tried_storage "$backend"
    if [ $status -eq 0 ]; then
        _green "使用 $backend 初始化成功"
        _green "Successfully initialized using $backend"
        echo "$backend" >/usr/local/bin/lxd_storage_type
        return 0
    else
        _yellow "使用 $backend 初始化失败，尝试下一个选项"
        _yellow "Initialization with $backend failed, trying next option"
        return 1
    fi
}

setup_storage() {
    if [ -f "/usr/local/bin/lxd_reboot" ]; then
        REBOOT_BACKEND=$(cat /usr/local/bin/lxd_reboot)
        _green "检测到系统重启，尝试继续使用 $REBOOT_BACKEND"
        _green "System reboot detected, trying to continue with $REBOOT_BACKEND"
        rm -f /usr/local/bin/lxd_reboot
        if [ "$REBOOT_BACKEND" = "btrfs" ]; then
            modprobe btrfs || true
        elif [ "$REBOOT_BACKEND" = "lvm" ]; then
            modprobe dm-mod || true
        elif [ "$REBOOT_BACKEND" = "zfs" ]; then
            modprobe zfs || true
        fi
        if init_storage_backend "$REBOOT_BACKEND"; then
            return 0
        fi
    fi
    local BACKENDS=("btrfs" "lvm" "zfs" "ceph" "dir")
    for backend in "${BACKENDS[@]}"; do
        if init_storage_backend "$backend"; then
            return 0
        fi
    done
    _yellow "所有存储类型尝试失败，使用 dir 作为备选"
    _yellow "All storage types failed, using dir as fallback"
    echo "dir" >/usr/local/bin/lxd_storage_type
    /snap/bin/lxd init --storage-backend dir --auto
}

setup_swap() {
    install_package uidmap
    curl -sLk "${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/swap2.sh" -o swap2.sh && chmod +x swap2.sh
    ./swap2.sh "$memory_nums"
    sleep 2
}

configure_lxd_network() {
    ! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >>/root/.bashrc && source /root/.bashrc
    export PATH=$PATH:/snap/bin
    ! lxc -h >/dev/null 2>&1 && _yellow '使用 lxc -h 检测到路径有问题，请手动查看LXD是否安装成功' && exit 1
    lxc config unset images.auto_update_interval
    lxc config set images.auto_update_interval 0
    lxc remote add opsmaru https://images.opsmaru.dev/spaces/9bfad87bd318b8f06012059a --public --protocol simplestreams
    lxc network set lxdbr0 ipv6.address auto
}

download_preset_files() {
    files=(
        "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_bash.sh"
        "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_sh.sh"
        "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/config.sh"
        "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/buildone.sh"
    )
    for file in "${files[@]}"; do
        filename=$(basename "$file")
        rm -rf "$filename"
        curl -sLk "${cdn_success_url}${file}" -o "$filename"
        chmod 777 "$filename"
        dos2unix "$filename"
    done
    cp /root/ssh_sh.sh /usr/local/bin
    cp /root/ssh_bash.sh /usr/local/bin
    cp /root/config.sh /usr/local/bin
}

configure_system() {
    sysctl net.ipv4.ip_forward=1
    sysctl_path=$(which sysctl)
    if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        if grep -q "^#net.ipv4.ip_forward=1" /etc/sysctl.conf; then
            sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
        fi
    else
        echo "net.ipv4.ip_forward=1" >>/etc/sysctl.conf
    fi
    lxc network set lxdbr0 raw.dnsmasq dhcp-option=6,8.8.8.8,8.8.4.4
    lxc network set lxdbr0 dns.mode managed
    lxc network set lxdbr0 ipv4.dhcp true
    lxc network set lxdbr0 ipv6.dhcp true
    ${sysctl_path} -p
}

remove_system_limits() {
    if [ -f "/etc/security/limits.conf" ]; then
        if ! grep -q "*          hard    nproc       unlimited" /etc/security/limits.conf; then
            echo '*          hard    nproc       unlimited' | sudo tee -a /etc/security/limits.conf
        fi
        if ! grep -q "*          soft    nproc       unlimited" /etc/security/limits.conf; then
            echo '*          soft    nproc       unlimited' | sudo tee -a /etc/security/limits.conf
        fi
    fi
    if [ -f "/etc/systemd/logind.conf" ]; then
        if ! grep -q "UserTasksMax=infinity" /etc/systemd/logind.conf; then
            echo 'UserTasksMax=infinity' | sudo tee -a /etc/systemd/logind.conf
        fi
    fi
    ufw disable
}

install_dns_check() {
    if [ ! -f /usr/local/bin/check-dns.sh ]; then
        wget ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/check-dns.sh -O /usr/local/bin/check-dns.sh
        chmod +x /usr/local/bin/check-dns.sh
    else
        echo "Script already exists. Skipping installation."
    fi
    if [ ! -f /etc/systemd/system/check-dns.service ]; then
        wget ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/check-dns.service -O /etc/systemd/system/check-dns.service
        chmod +x /etc/systemd/system/check-dns.service
        systemctl daemon-reload
        systemctl enable check-dns.service
        systemctl start check-dns.service
    else
        echo "Service already exists. Skipping installation."
    fi
}

setup_network_preferences() {
    sed -i 's/.*precedence ::ffff:0:0\/96.*/precedence ::ffff:0:0\/96  100/g' /etc/gai.conf && systemctl restart networking
    install_package iptables
    install_package iptables-persistent
    iptables -t nat -A POSTROUTING -j MASQUERADE
}

show_completion_info() {
    _green "脚本当天运行次数:${TODAY}，累计运行次数:${TOTAL}"
    _green "LXD Version: $(lxc --version)"
    _green "If you need to turn on more than 100 cts, it is recommended to wait for a few minutes before performing a reboot to reboot the machine to make the settings take effect"
    _green "The reboot will ensure that the DNS detection mechanism takes effect, otherwise the batch opening process may cause the host's DNS to be overwritten by the merchant's preset"
    _green "如果你需要开启超过100个LXC容器，建议等待几分钟后执行 reboot 重启本机以使得设置生效"
    _green "重启后可以保证DNS的检测机制生效，否则批量开启过程中可能导致宿主机的DNS被商家预设覆盖，所以最好重启系统一次"
}

main() {
    set_locale
    install_base_packages
    check_cdn_file
    rebuild_cloud_init
    apt-get remove cloud-init -y
    statistics_of_run_times
    install_lxd
    configure_resources
    setup_storage
    setup_swap
    configure_lxd_network
    download_preset_files
    configure_system
    remove_system_limits
    install_dns_check
    setup_network_preferences
    show_completion_info
}

main
