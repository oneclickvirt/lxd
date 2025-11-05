#!/bin/bash
# by https://github.com/oneclickvirt/lxd
# 2025.08.14

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
        daemon-reload)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl daemon-reload 2>/dev/null && success=true
            else
                success=true
            fi
            ;;
    esac
    
    $success && return 0 || return 1
}

cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")
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
    local shuffled_cdn_urls=($(shuf -e "${cdn_urls[@]}")) # 打乱数组顺序
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
    # 使用grep -E代替grep -P以提高兼容性（BusyBox等）
    if echo "" | grep -P "test" >/dev/null 2>&1; then
        # 如果grep支持-P，使用原有的Perl正则
        TODAY=$(echo "$COUNT" | grep -oP '"daily":\s*[0-9]+' | sed 's/"daily":[[:space:]]*\([0-9]*\)/\1/')
        TOTAL=$(echo "$COUNT" | grep -oP '"total":\s*[0-9]+' | sed 's/"total":[[:space:]]*\([0-9]*\)/\1/')
    else
        # 如果grep不支持-P，使用-E兼容写法
        TODAY=$(echo "$COUNT" | grep -oE '"daily":[[:space:]]*[0-9]+' | sed 's/"daily":[[:space:]]*\([0-9]*\)/\1/')
        TOTAL=$(echo "$COUNT" | grep -oE '"total":[[:space:]]*[0-9]+' | sed 's/"total":[[:space:]]*\([0-9]*\)/\1/')
    fi
}


lxc config set core.https_address 0.0.0.0:8443
service_manager restart snap.lxd.daemon

# 设置镜像不更新
lxc config unset images.auto_update_interval
lxc config set images.auto_update_interval 0
# 设置自动配置内网IPV6地址
lxc network set lxdbr0 ipv6.address auto
# 下载预制文件
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
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl_path=$(which sysctl)
if [ -f "/etc/sysctl.conf" ]; then
    if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        sed -i 's/^#\?net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    else
        echo "net.ipv4.ip_forward=1" >>/etc/sysctl.conf
    fi
fi
SYSCTL_D_CONF="/etc/sysctl.d/99-custom.conf"
mkdir -p /etc/sysctl.d
if ! grep -q "^net.ipv4.ip_forward=1" "$SYSCTL_D_CONF" 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" >>"$SYSCTL_D_CONF"
fi
# BusyBox sysctl 不支持 --system，使用 -p 代替
if ${sysctl_path} --system >/dev/null 2>&1; then
    ${sysctl_path} --system >/dev/null
else
    ${sysctl_path} -p /etc/sysctl.conf >/dev/null 2>&1
    ${sysctl_path} -p "$SYSCTL_D_CONF" >/dev/null 2>&1
fi
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
service_manager enable vnstat
service_manager start vnstat
pgrep -c vnstatd
vnstat -v
vnstatd -v
vnstati -v

# 加装证书
wget ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/panel_scripts/client.crt -O /root/snap/lxd/common/config/client.crt
chmod 777 /root/snap/lxd/common/config/client.crt
# 双确认，部分版本切换了命令
lxc config trust add /root/snap/lxd/common/config/client.crt
lxc config trust add-certificate /root/snap/lxd/common/config/client.crt
lxc config set core.https_address :8443
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
    service_manager daemon-reload
    service_manager enable check-dns.service
    service_manager start check-dns.service
else
    echo "Service already exists. Skipping installation."
fi
# 设置IPV4优先
if [ -f /etc/gai.conf ]; then
    sed -i 's/.*precedence ::ffff:0:0\/96.*/precedence ::ffff:0:0\/96  100/g' /etc/gai.conf
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "networking.service"; then
        service_manager restart networking
    elif command -v rc-service >/dev/null 2>&1 && rc-service --list | grep -q "networking"; then
        service_manager restart networking
    fi
fi
lxc remote list
lxc remote remove spiritlhl
lxc remote add spiritlhl https://lxdimages.spiritlhl.net --protocol simplestreams --public
lxc image list spiritlhl:debian
lxc remote list
