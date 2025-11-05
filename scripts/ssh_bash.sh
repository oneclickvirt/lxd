#!/bin/bash
# by https://github.com/oneclickvirt/lxd
# 2025.07.11

# 服务管理兼容性函数：支持systemd、OpenRC和传统service命令
# 策略：尝试所有可用的服务管理工具，确保至少一个成功
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
            if command -v chkconfig >/dev/null 2>&1; then
                chkconfig "$service_name" on 2>/dev/null && success=true
            fi
            if command -v update-rc.d >/dev/null 2>&1; then
                update-rc.d "$service_name" defaults 2>/dev/null || update-rc.d "$service_name" enable 2>/dev/null && success=true
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
    esac
    
    $success && return 0 || return 1
}

if [ -f "/etc/resolv.conf" ]; then
    cp /etc/resolv.conf /etc/resolv.conf.bak
    echo "nameserver 8.8.8.8" | tee -a /etc/resolv.conf >/dev/null
    echo "nameserver 8.8.4.4" | tee -a /etc/resolv.conf >/dev/null
fi

temp_file_apt_fix="/tmp/apt_fix.txt"
REGEX=("debian|astra|kali" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "arch|manjaro" "alpine" "freebsd")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Arch" "Alpine" "FreeBSD")
PACKAGE_UPDATE=("! apt-get update && apt-get --fix-broken install -y && apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "pacman -Sy" "apk update" "pkg update")
PACKAGE_INSTALL=("apt-get -y install" "apt-get -y install" "yum -y install" "yum -y install" "yum -y install" "pacman -Sy --noconfirm --needed" "apk add --no-cache" "pkg install -y")
PACKAGE_REMOVE=("apt-get -y remove" "apt-get -y remove" "yum -y remove" "yum -y remove" "yum -y remove" "pacman -Rsc --noconfirm" "apk del" "pkg delete")
PACKAGE_UNINSTALL=("apt-get -y autoremove" "apt-get -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "" "" "pkg autoremove")
CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')" "$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(uname -s)")
SYS="${CMD[0]}"
[[ -n $SYS ]] || exit 1
for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}"
        [[ -n $SYSTEM ]] && break
    fi
done
[[ -z $SYSTEM ]] && exit 1
[[ $EUID -ne 0 ]] && exit 1

checkupdate() {
    if command -v apt-get >/dev/null 2>&1; then
        apt_update_output=$(apt-get update 2>&1)
        echo "$apt_update_output" >"$temp_file_apt_fix"
        if grep -q 'NO_PUBKEY' "$temp_file_apt_fix"; then
            public_keys=$(grep -oE 'NO_PUBKEY [0-9A-F]+' "$temp_file_apt_fix" | awk '{ print $2 }')
            joined_keys=$(echo "$public_keys" | paste -sd " ")
            echo "No Public Keys: ${joined_keys}"
            apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ${joined_keys}
            apt-get update
            if [ $? -eq 0 ]; then
                _green "Fixed"
            fi
        fi
        rm "$temp_file_apt_fix"
    else
        ${PACKAGE_UPDATE[int]}
    fi
}

install_required_modules() {
    modules=("dos2unix" "wget" "curl" "sudo" "bash" "lsof" "ssh" "sshpass" "openssh-server")
    for module in "${modules[@]}"; do
        # 特殊处理Alpine系统的包名差异
        if [ "$SYSTEM" = "Alpine" ]; then
            case "$module" in
                "openssh-server") module="openssh" ;;
                "dos2unix") module="dos2unix" ;; # 如果不存在，会回退到busybox-extras
            esac
        fi
        
        if command -v apt-get >/dev/null 2>&1; then
            if command -v $module >/dev/null 2>&1; then
                echo "$module is installed!"
                echo "$module 已经安装！"
            else
                apt-get install -y $module
                if [ $? -ne 0 ]; then
                    apt-get install -y $module --fix-missing
                fi
                echo "$module has tried to install!"
                echo "$module 已尝试过安装！"
            fi
        else
            ${PACKAGE_INSTALL[int]} $module 2>/dev/null || {
                # 如果安装失败且是Alpine系统，尝试备选包
                if [ "$SYSTEM" = "Alpine" ] && [ "$module" = "dos2unix" ]; then
                    apk add --no-cache busybox-extras
                fi
            }
        fi
    done
    if command -v apt-get >/dev/null 2>&1; then
        ${PACKAGE_INSTALL[int]} cron 
    elif [ "$SYSTEM" = "Alpine" ]; then
        apk add --no-cache cronie || apk add --no-cache dcron
    else
        ${PACKAGE_INSTALL[int]} cronie
    fi
}

remove_duplicate_lines() {
    chattr -i "$1"
    # 预处理：去除行尾空格和制表符
    sed -i 's/[ \t]*$//' "$1"
    # 去除重复行并跳过空行和注释行
    if [ -f "$1" ]; then
        awk '{ line = $0; gsub(/^[ \t]+/, "", line); gsub(/[ \t]+/, " ", line); if (!NF || !seen[line]++) print $0 }' "$1" >"$1.tmp" && mv -f "$1.tmp" "$1"
    fi
    chattr +i "$1"
}

checkupdate
install_required_modules
service_manager enable sshd
service_manager enable ssh
sleep 3
ssh-keygen -A
service_manager start ssh
service_manager start sshd
if [ -f "/etc/motd" ]; then
    echo '' >/etc/motd
    echo 'Related repo https://github.com/oneclickvirt/lxd' >>/etc/motd
    echo '--by https://t.me/spiritlhl' >>/etc/motd
fi
sudo service iptables stop 2>/dev/null
chkconfig iptables off 2>/dev/null
if [ -f "/etc/sysconfig/selinux" ]; then
    sudo sed -i.bak '/^SELINUX=/cSELINUX=disabled' /etc/sysconfig/selinux
fi
if [ -f "/etc/selinux/config" ]; then
    sudo sed -i.bak '/^SELINUX=/cSELINUX=disabled' /etc/selinux/config
fi
sudo setenforce 0
echo root:"$1" | sudo chpasswd root
update_sshd_config() {
    local config_file="$1"
    if [ -f "$config_file" ]; then
        echo "updating $config_file"
        sudo sed -i "s/^#\?Port.*/Port 22/g" "$config_file"
        sudo sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/g" "$config_file"
        sudo sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g" "$config_file"
        sudo sed -i 's/#ListenAddress 0.0.0.0/ListenAddress 0.0.0.0/' "$config_file"
        sudo sed -i 's/#ListenAddress ::/ListenAddress ::/' "$config_file"
        sudo sed -i 's/#AddressFamily any/AddressFamily any/' "$config_file"
        sudo sed -i "s/^#\?PubkeyAuthentication.*/PubkeyAuthentication no/g" "$config_file"
        sudo sed -i '/^#UsePAM\|UsePAM/c #UsePAM no' "$config_file"
        sudo sed -i '/^AuthorizedKeysFile/s/^/#/' "$config_file"
        sudo sed -i 's/^#[[:space:]]*KbdInteractiveAuthentication.*\|^KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' "$config_file"
    fi
}
update_sshd_config "/etc/ssh/sshd_config"
remove_duplicate_lines /etc/ssh/sshd_config
if [ -d /etc/ssh/sshd_config.d ]; then
    for config_file in /etc/ssh/sshd_config.d/*; do
        if [ -f "$config_file" ]; then
            update_sshd_config "$config_file"
            remove_duplicate_lines "$config_file"
        fi
    done
fi
config_dir="/etc/ssh/sshd_config.d/"
for file in "$config_dir"*
do
    if [ -f "$file" ] && [ -r "$file" ]; then
        if grep -q "PasswordAuthentication no" "$file"; then
            sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' "$file"
            echo "File $file updated"
        fi
    fi
done
service_manager restart ssh
service_manager restart sshd
rm -rf "$0"
