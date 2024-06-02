#!/bin/bash
# by https://github.com/oneclickvirt/lxd
# 2024.03.23

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
if [ ! -d "/usr/local/bin" ]; then
    mkdir -p /usr/local/bin
fi
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }
cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn3.spiritlhl.net/" "http://cdn1.spiritlhl.net/" "https://ghproxy.com/" "http://cdn2.spiritlhl.net/")
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
    for cdn_url in "${cdn_urls[@]}"; do
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

statistics_of_run-times() {
    COUNT=$(
        curl -4 -ksm1 "https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2FspiritLHLS%2Flxc&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=&edge_flat=true" 2>&1 ||
            curl -6 -ksm1 "https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2FspiritLHLS%2Flxc&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=&edge_flat=true" 2>&1
    ) &&
        TODAY=$(expr "$COUNT" : '.*\s\([0-9]\{1,\}\)\s/.*') && TOTAL=$(expr "$COUNT" : '.*/\s\([0-9]\{1,\}\)\s.*')
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

apt-get update
apt-get autoremove -y
install_package wget
install_package curl
install_package sudo
install_package dos2unix
install_package ufw
install_package jq
install_package uidmap
check_cdn_file
rebuild_cloud_init
apt-get remove cloud-init -y
statistics_of_run-times

# lxd安装
lxd_snap=$(dpkg -l | awk '/^[hi]i/{print $2}' | grep -ow snap)
lxd_snapd=$(dpkg -l | awk '/^[hi]i/{print $2}' | grep -ow snapd)
if [[ "$lxd_snap" =~ ^snap.* ]] && [[ "$lxd_snapd" =~ ^snapd.* ]]; then
    _green "snap is installed"
    _green "snap已安装"
else
    _green "start installation of snap"
    _green "开始安装snap"
    apt-get update
    #     install_package snap
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
lxc config set core.https_address 0.0.0.0:8443
systemctl restart snap.lxd.daemon

# 读取母鸡配置
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
    reading "宿主机需要开设多大的存储池？(存储池就是小鸡硬盘之和的大小，推荐SWAP和存储池加起来达到母鸡硬盘的95%空间，注意是GB为单位，需要10G存储池则输入10)：" disk_nums
    if [[ "$disk_nums" =~ ^[1-9][0-9]*$ ]]; then
        break
    else
        _yellow "Invalid input, please enter a positive integer."
        _yellow "输入无效，请输入一个正整数。"
    fi
done

# 资源池设置-硬盘
# lxd init --storage-backend btrfs --storage-create-loop "$disk_nums" --storage-pool default --auto
# btrfs 检测与安装
temp=$(/snap/bin/lxd init --storage-backend btrfs --storage-create-loop "$disk_nums" --storage-pool default --auto 2>&1)
if [[ $? -ne 0 ]]; then
    status=false
else
    status=true
fi
echo "$temp"
if echo "$temp" | grep -q "lxd.migrate" && [[ $status == false ]]; then
    /snap/bin/lxd.migrate
    temp=$(/snap/bin/lxd init --storage-backend btrfs --storage-create-loop "$disk_nums" --storage-pool default --auto 2>&1)
    if [[ $? -ne 0 ]]; then
        status=false
    else
        status=true
    fi
    echo "$temp"
fi
if [[ $status == false ]]; then
    _yellow "trying to use another storage type ......"
    _yellow "尝试使用其他存储类型......"
    # 类型设置-硬盘
    SUPPORTED_BACKENDS=("zfs" "lvm" "ceph" "dir")
    STORAGE_BACKEND=""
    for backend in "${SUPPORTED_BACKENDS[@]}"; do
        if command -v $backend >/dev/null; then
            STORAGE_BACKEND=$backend
            if [ "$STORAGE_BACKEND" = "dir" ]; then
                if [ ! -f /usr/local/bin/lxd_reboot ]; then
                    install_package btrfs-progs
                    _green "Please reboot the machine (perform a reboot reboot) and execute this script again to load the btrfs kernel, after the reboot you will need to enter the configuration you need init again"
                    _green "请重启本机(执行 reboot 重启)再次执行本脚本以加载btrfs内核，重启后需要再次输入你需要的初始化的配置"
                    echo "" > /usr/local/bin/lxd_reboot
                    exit 1
                fi
                _green "Infinite storage pool size using default dir type due to no btrfs"
                _green "由于无btrfs，使用默认dir类型无限定存储池大小"
                echo "dir" >/usr/local/bin/lxd_storage_type
                /snap/bin/lxd init --storage-backend "$STORAGE_BACKEND" --auto
            else
                _green "Infinite storage pool size using default $backend type due to no btrfs"
                _green "由于无btrfs，使用默认 $backend 类型无限定存储池大小"
                DISK=$(lsblk -p -o NAME,TYPE | awk '$2=="disk"{print $1}')
                /snap/bin/lxd init --storage-backend lvm --storage-create-device $DISK --storage-create-loop "$disk_nums" --storage-pool lvm_pool --auto
            fi
            if [[ $? -ne 0 ]]; then
                _yellow "Use $STORAGE_BACKEND storage type failed."
                _yellow "使用 $STORAGE_BACKEND 存储类型失败。"
            else
                echo $backend >/usr/local/bin/lxd_storage_type
                break
            fi
        fi
    done
    if [ -z "$STORAGE_BACKEND" ]; then
        _yellow "No supported storage types, please contact the script maintainer"
        _yellow "无可支持的存储类型，请联系脚本维护者"
        exit 1
    fi
else
    echo "btrfs" >/usr/local/bin/lxd_storage_type
fi
install_package uidmap

# 虚拟内存设置
curl -sLk "${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/swap2.sh" -o swap2.sh && chmod +x swap2.sh
./swap2.sh "$memory_nums"
sleep 2
! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >>/root/.bashrc && source /root/.bashrc
export PATH=$PATH:/snap/bin
! lxc -h >/dev/null 2>&1 && _yellow '使用 lxc -h 检测到路径有问题，请手动查看LXD是否安装成功' && exit 1
# 设置镜像不更新
lxc config unset images.auto_update_interval
lxc config set images.auto_update_interval 0
# 使用第三方镜像链接
lxc remote add opsmaru https://images.opsmaru.dev/spaces/9bfad87bd318b8f06012059a --public --protocol simplestreams
# 设置自动配置内网IPV6地址
lxc network set lxdbr0 ipv6.address auto
# 下载预制文件
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
sysctl net.ipv4.ip_forward=1
sysctl_path=$(which sysctl)
if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    if grep -q "^#net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    fi
else
    echo "net.ipv4.ip_forward=1" >>/etc/sysctl.conf
fi
${sysctl_path} -p
lxc network set lxdbr0 raw.dnsmasq dhcp-option=6,8.8.8.8,8.8.4.4
lxc network set lxdbr0 dns.mode managed
# managed none dynamic
lxc network set lxdbr0 ipv4.dhcp true
lxc network set lxdbr0 ipv6.dhcp true
# 解除进程数限制
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
# 环境安装
# 安装vnstat
install_package make
install_package gcc
install_package libc6-dev
install_package libsqlite3-0
install_package libsqlite3-dev
install_package libgd3 
install_package libgd-dev
cd /usr/src
wget https://humdi.net/vnstat/vnstat-2.11.tar.gz
chmod 777 vnstat-2.11.tar.gz
tar zxvf vnstat-2.11.tar.gz
cd vnstat-2.11
./configure --prefix=/usr --sysconfdir=/etc && make && make install
cp -v examples/systemd/vnstat.service /etc/systemd/system/
systemctl enable vnstat
systemctl start vnstat
pgrep -c vnstatd
vnstat -v
vnstatd -v
vnstati -v

# 加装证书
wget ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/panel_scripts/client.crt -O /root/snap/lxd/common/config/client.crt
chmod 777 /root/snap/lxd/common/config/client.crt
lxc config trust add /root/snap/lxd/common/config/client.crt
lxc config set core.https_address :9969
# 加载修改脚本
wget ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/panel_scripts/modify.sh -O /root/modify.sh
chmod 777 /root/modify.sh
ufw disable
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
# 设置IPV4优先
sed -i 's/.*precedence ::ffff:0:0\/96.*/precedence ::ffff:0:0\/96  100/g' /etc/gai.conf && systemctl restart networking
# 加载iptables并设置回源且允许NAT端口转发
install_package iptables
install_package iptables-persistent
iptables -t nat -A POSTROUTING -j MASQUERADE
_green "脚本当天运行次数:${TODAY}，累计运行次数:${TOTAL}"
_green "If you need to turn on more than 100 cts, it is recommended to wait for a few minutes before performing a reboot to reboot the machine to make the settings take effect"
_green "The reboot will ensure that the DNS detection mechanism takes effect, otherwise the batch opening process may cause the host's DNS to be overwritten by the merchant's preset"
_green "如果你需要开启超过100个小鸡，建议等待几分钟后执行 reboot 重启本机以使得设置生效"
_green "重启后可以保证DNS的检测机制生效，否则批量开启过程中可能导致宿主机的DNS被商家预设覆盖，所以最好重启系统一次"
