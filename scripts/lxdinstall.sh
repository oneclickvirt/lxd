#!/bin/bash
# by https://github.com/oneclickvirt/lxd
# 2025.08.26

# curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/lxdinstall.sh -o lxdinstall.sh && chmod +x lxdinstall.sh && bash lxdinstall.sh

cd /root >/dev/null 2>&1
REGEX=("debian|astra" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "arch|manjaro" "alpine" "freebsd")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Arch" "Alpine" "FreeBSD")
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

sed_compatible() {
    if echo "test" | sed -E 's/test/ok/' >/dev/null 2>&1; then
        sed -E "$@"
    else
        sed -r "$@"
    fi
}

service_manager() {
    local action=$1
    local service_name=$2
    local success=false
    case "$action" in
        enable)
            if command -v systemctl >/dev/null 2>&1; then
                if systemctl enable "$service_name" 2>/dev/null; then
                    success=true
                fi
            fi
            if command -v rc-update >/dev/null 2>&1; then
                if rc-update add "$service_name" default 2>/dev/null; then
                    success=true
                fi
            fi
            if command -v chkconfig >/dev/null 2>&1; then
                if chkconfig "$service_name" on 2>/dev/null; then
                    success=true
                fi
            fi
            if command -v update-rc.d >/dev/null 2>&1; then
                if update-rc.d "$service_name" defaults 2>/dev/null || update-rc.d "$service_name" enable 2>/dev/null; then
                    success=true
                fi
            fi
            ;;
        disable)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl disable "$service_name" 2>/dev/null && success=true
            fi
            if command -v rc-update >/dev/null 2>&1; then
                rc-update del "$service_name" default 2>/dev/null && success=true
            fi
            if command -v chkconfig >/dev/null 2>&1; then
                chkconfig "$service_name" off 2>/dev/null && success=true
            fi
            if command -v update-rc.d >/dev/null 2>&1; then
                update-rc.d "$service_name" disable 2>/dev/null && success=true
            fi
            ;;
        start)
            if command -v systemctl >/dev/null 2>&1; then
                if systemctl start "$service_name" 2>/dev/null; then
                    success=true
                fi
            fi
            if ! $success && command -v rc-service >/dev/null 2>&1; then
                if rc-service "$service_name" start 2>/dev/null; then
                    success=true
                fi
            fi
            if ! $success && command -v service >/dev/null 2>&1; then
                if service "$service_name" start 2>/dev/null; then
                    success=true
                fi
            fi
            if ! $success && [ -x "/etc/init.d/$service_name" ]; then
                if /etc/init.d/"$service_name" start 2>/dev/null; then
                    success=true
                fi
            fi
            ;;
        stop)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl stop "$service_name" 2>/dev/null && success=true
            fi
            if ! $success && command -v rc-service >/dev/null 2>&1; then
                rc-service "$service_name" stop 2>/dev/null && success=true
            fi
            if ! $success && command -v service >/dev/null 2>&1; then
                service "$service_name" stop 2>/dev/null && success=true
            fi
            if ! $success && [ -x "/etc/init.d/$service_name" ]; then
                /etc/init.d/"$service_name" stop 2>/dev/null && success=true
            fi
            ;;
        restart)
            if command -v systemctl >/dev/null 2>&1; then
                if systemctl restart "$service_name" 2>/dev/null; then
                    success=true
                fi
            fi
            if ! $success && command -v rc-service >/dev/null 2>&1; then
                if rc-service "$service_name" restart 2>/dev/null; then
                    success=true
                fi
            fi
            if ! $success && command -v service >/dev/null 2>&1; then
                if service "$service_name" restart 2>/dev/null; then
                    success=true
                fi
            fi
            if ! $success && [ -x "/etc/init.d/$service_name" ]; then
                if /etc/init.d/"$service_name" restart 2>/dev/null; then
                    success=true
                fi
            fi
            ;;
        daemon-reload)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl daemon-reload 2>/dev/null && success=true
            else
                success=true
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
        if [ "$SYSTEM" = "Alpine" ] && command -v apk >/dev/null 2>&1; then
            apk add --no-cache $package_name
        elif [ "$SYSTEM" = "Arch" ] && command -v pacman >/dev/null 2>&1; then
            pacman -S --noconfirm --needed $package_name
        elif command -v apt-get >/dev/null 2>&1; then
            apt-get install -y $package_name
            if [ $? -ne 0 ]; then
                apt-get install -y $package_name --fix-missing
            fi
        elif command -v yum >/dev/null 2>&1; then
            yum install -y $package_name
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y $package_name
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache $package_name
        elif command -v pacman >/dev/null 2>&1; then
            pacman -S --noconfirm --needed $package_name
        else
            _yellow "No supported package manager found"
            _yellow "未找到支持的包管理器"
            return 1
        fi
        _green "$package_name has attempted to install"
        _green "$package_name 已尝试安装"
    fi
}

check_cdn() {
    local o_url=$1
    local shuffled_cdn_urls=($(shuf -e "${cdn_urls[@]}"))
    for cdn_url in "${shuffled_cdn_urls[@]}"; do
        if curl -4 -sL -k "$cdn_url$o_url" --max-time 6 | grep -q "success" >/dev/null 2>&1; then
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
    if echo "" | grep -P "test" >/dev/null 2>&1; then
        TODAY=$(echo "$COUNT" | grep -oP '"daily":\s*[0-9]+' | sed 's/"daily":[[:space:]]*\([0-9]*\)/\1/')
        TOTAL=$(echo "$COUNT" | grep -oP '"total":\s*[0-9]+' | sed 's/"total":[[:space:]]*\([0-9]*\)/\1/')
    else
        TODAY=$(echo "$COUNT" | grep -oE '"daily":[[:space:]]*[0-9]+' | sed 's/"daily":[[:space:]]*\([0-9]*\)/\1/')
        TOTAL=$(echo "$COUNT" | grep -oE '"total":[[:space:]]*[0-9]+' | sed 's/"total":[[:space:]]*\([0-9]*\)/\1/')
    fi
}

rebuild_cloud_init() {
    if [ -f "/etc/cloud/cloud.cfg" ]; then
        chattr -i /etc/cloud/cloud.cfg
        if grep -q "preserve_hostname: true" "/etc/cloud/cloud.cfg"; then
            :
        else
            sed_compatible -i 's/preserve_hostname:[[:space:]]*false/preserve_hostname: true/g' "/etc/cloud/cloud.cfg"
            echo "change preserve_hostname to true"
        fi
        if grep -q "disable_root: false" "/etc/cloud/cloud.cfg"; then
            :
        else
            sed_compatible -i 's/disable_root:[[:space:]]*true/disable_root: false/g' "/etc/cloud/cloud.cfg"
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
        sed -i '/^[[:space:]]*- set-passwords/s/^/#/' /etc/cloud/cloud.cfg
        chattr +i /etc/cloud/cloud.cfg
    fi
}

get_available_space() {
    local available_space
    available_space=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
    echo "$available_space"
}

install_base_packages() {
    if [ "$SYSTEM" = "Alpine" ] && command -v apk >/dev/null 2>&1; then
        apk update
    elif [ "$SYSTEM" = "Arch" ] && command -v pacman >/dev/null 2>&1; then
        pacman -Sy
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get autoremove -y
    elif command -v yum >/dev/null 2>&1; then
        yum update -y
    elif command -v dnf >/dev/null 2>&1; then
        dnf update -y
    fi
    install_package wget
    install_package curl
    install_package sudo
    if [ "$SYSTEM" = "Alpine" ]; then
        install_package dos2unix || apk add --no-cache busybox-extras
    else
        install_package dos2unix
    fi
    install_package ufw || _yellow "ufw not available on this system"
    install_package jq
    install_package uidmap || _yellow "uidmap not available on this system"
    if [ "$SYSTEM" = "Alpine" ]; then
        install_package ipcalc || apk add --no-cache ipcalc-ng
    else
        install_package ipcalc
    fi
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
            service_manager restart apparmor
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
    service_manager restart snap.lxd.daemon
}

configure_resources() {
   if [ "${noninteractive:-false}" = true ]; then
       available_space=$(get_available_space)
       disk_nums=$((available_space - 1))
       storage_path=""
   else
       while true; do
           _green "Do you want to specify a custom path for the storage pool? (y/n) [n]:"
           reading "是否需要指定存储池的自定义路径？(y/n) [n]：" use_custom_path
           use_custom_path=${use_custom_path:-n}
           if [[ "$use_custom_path" =~ ^[yYnN]$ ]]; then
               break
           else
               _yellow "Please enter y or n."
               _yellow "请输入 y 或 n。"
           fi
       done
       if [[ "$use_custom_path" =~ ^[yY]$ ]]; then
           while true; do
               _green "Please enter the custom storage path (e.g., /data/lxd-storage):"
               reading "请输入自定义存储路径 (例如：/data/lxd-storage)：" storage_path
               if [[ -n "$storage_path" && "$storage_path" =~ ^/.+ ]]; then
                   if [ ! -d "$storage_path" ]; then
                       mkdir -p "$storage_path" 2>/dev/null
                       if [ $? -eq 0 ]; then
                           _green "Created directory: $storage_path"
                           _green "已创建目录：$storage_path"
                           break
                       else
                           _yellow "Failed to create directory. Please check permissions or try another path."
                           _yellow "创建目录失败，请检查权限或尝试其他路径。"
                       fi
                   else
                       break
                   fi
               else
                   _yellow "Please enter a valid absolute path starting with /."
                   _yellow "请输入以 / 开头的有效绝对路径。"
               fi
           done
       else
           storage_path=""
       fi
       while true; do
           _green "How large a storage pool does the host need to open? (Note that it is in GB, enter 10 if you need 10G storage pool):"
           reading "宿主机需要开设多大的存储池？(注意是GB为单位，需要10G存储池则输入10)：" disk_nums
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

execute_storage_init() {
    local backend="$1"
    local temp
    if [ "$backend" = "lvm" ]; then
        if [ -n "$storage_path" ]; then
            mkdir -p "$storage_path"
            /snap/bin/lxd init --auto 2>/dev/null || true
            /snap/bin/lxc storage delete default 2>/dev/null || true
            temp=$(/snap/bin/lxc storage create lvm_pool lvm size="${disk_nums}GB" source="${storage_path}/lvm.img" 2>&1)
        else
            temp=$(/snap/bin/lxd init --storage-backend lvm --storage-create-loop "$disk_nums" --storage-pool lvm_pool --auto 2>&1)
        fi
    else
        if [ -n "$storage_path" ]; then
            mkdir -p "$storage_path"
            /snap/bin/lxd init --auto 2>/dev/null || true
            /snap/bin/lxc storage delete default 2>/dev/null || true
            temp=$(/snap/bin/lxc storage create default "$backend" size="${disk_nums}GB" source="${storage_path}/${backend}.img" 2>&1)
        else
            temp=$(/snap/bin/lxd init --storage-backend "$backend" --storage-create-loop "$disk_nums" --storage-pool default --auto 2>&1)
        fi
    fi
    echo "$temp"
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
        if [ -n "$storage_path" ]; then
            mkdir -p "$storage_path"
            /snap/bin/lxd init --auto
            /snap/bin/lxc storage delete default 2>/dev/null || true
            /snap/bin/lxc storage create default dir source="$storage_path"
        else
            /snap/bin/lxd init --storage-backend "$backend" --auto
        fi
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
    temp=$(execute_storage_init "$backend")
    local status=$?
    _green "Init storage:"
    echo "$temp"
    if echo "$temp" | grep -q "lxd.migrate" && [ $status -ne 0 ]; then
        /snap/bin/lxd.migrate
        temp=$(execute_storage_init "$backend")
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
    if [ -n "$storage_path" ]; then
        mkdir -p "$storage_path"
        /snap/bin/lxd init --auto
        /snap/bin/lxc storage delete default 2>/dev/null || true
        /snap/bin/lxc storage create default dir source="$storage_path"
    else
        /snap/bin/lxd init --storage-backend dir --auto
    fi
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
        "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/buildct.sh"
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
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    SYSCTL_CONF="/etc/sysctl.conf"
    SYSCTL_D_CONF="/etc/sysctl.d/99-custom.conf"
    if [ -f "$SYSCTL_CONF" ]; then
        if grep -q "^net.ipv4.ip_forward=1" "$SYSCTL_CONF"; then
            sed -i 's/^#\?net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' "$SYSCTL_CONF"
        else
            echo "net.ipv4.ip_forward=1" >>"$SYSCTL_CONF"
        fi
    fi
    mkdir -p /etc/sysctl.d
    if ! grep -q "^net.ipv4.ip_forward=1" "$SYSCTL_D_CONF" 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >>"$SYSCTL_D_CONF"
    fi
    if sysctl --system >/dev/null 2>&1; then
        sysctl --system >/dev/null
    else
        sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
        sysctl -p "$SYSCTL_D_CONF" >/dev/null 2>&1
    fi
    lxc network set lxdbr0 raw.dnsmasq dhcp-option=6,8.8.8.8,8.8.4.4
    lxc network set lxdbr0 dns.mode managed
    lxc network set lxdbr0 ipv4.dhcp true
    lxc network set lxdbr0 ipv6.dhcp true
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
        service_manager daemon-reload
        service_manager enable check-dns.service
        service_manager start check-dns.service
    else
        echo "Service already exists. Skipping installation."
    fi
}

setup_network_preferences() {
    if [ -f /etc/gai.conf ]; then
        sed -i 's/.*precedence ::ffff:0:0\/96.*/precedence ::ffff:0:0\/96  100/g' /etc/gai.conf
        if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "networking.service"; then
            service_manager restart networking
        elif command -v rc-service >/dev/null 2>&1 && rc-service --list | grep -q "networking"; then
            service_manager restart networking
        fi
    fi
    install_package iptables
    if [ "$SYSTEM" = "Debian" ] || [ "$SYSTEM" = "Ubuntu" ]; then
        install_package iptables-persistent
    elif [ "$SYSTEM" = "Alpine" ]; then
        if command -v rc-update >/dev/null 2>&1; then
            rc-update add iptables default 2>/dev/null || true
        fi
    elif [ "$SYSTEM" = "CentOS" ] || [ "$SYSTEM" = "Fedora" ]; then
        if command -v firewall-cmd >/dev/null 2>&1; then
            _green "firewall-cmd is available, using firewalld for persistence"
        else
            install_package iptables-services 2>/dev/null || true
        fi
    else
        _yellow "Note: iptables persistence may need manual configuration on this system"
    fi
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
    configure_lxd_network
    download_preset_files
    configure_system
    remove_system_limits
    install_dns_check
    setup_network_preferences
    show_completion_info
}

main
