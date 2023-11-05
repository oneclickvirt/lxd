#!/bin/bash
# by https://github.com/spiritLHLS/lxd
# 2023.11.05

if [ -f "/etc/resolv.conf" ]; then
    cp /etc/resolv.conf /etc/resolv.conf.bak
    echo "nameserver 8.8.8.8" | tee -a /etc/resolv.conf >/dev/null
    echo "nameserver 8.8.4.4" | tee -a /etc/resolv.conf >/dev/null
fi

temp_file_apt_fix="/tmp/apt_fix.txt"
REGEX=("debian|astra|kali" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "arch" "freebsd")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Arch" "FreeBSD")
PACKAGE_UPDATE=("! apt-get update && apt-get --fix-broken install -y && apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "pacman -Sy" "pkg update")
PACKAGE_INSTALL=("apt-get -y install" "apt-get -y install" "yum -y install" "yum -y install" "yum -y install" "pacman -Sy --noconfirm --needed" "pkg install -y")
PACKAGE_REMOVE=("apt-get -y remove" "apt-get -y remove" "yum -y remove" "yum -y remove" "yum -y remove" "pacman -Rsc --noconfirm" "pkg delete")
PACKAGE_UNINSTALL=("apt-get -y autoremove" "apt-get -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "" "pkg autoremove")
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
    modules=("dos2unix" "wget" "curl" "sudo" "bash" "sshpass" "openssh-server")
    for module in "${modules[@]}"; do
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
            ${PACKAGE_INSTALL[int]} $module
        fi
    done
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
sudo systemctl enable sshd
sudo systemctl enable ssh
sleep 3
sudo service ssh start
sudo service sshd start
sudo systemctl start sshd
sudo systemctl start ssh
if [ -f "/etc/motd" ]; then
    echo 'Related repo https://github.com/spiritLHLS/lxd' >>/etc/motd
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
if [ -f /etc/ssh/sshd_config ]; then
    sudo sed -i "s/^#\?Port.*/Port 22/g" /etc/ssh/sshd_config
    sudo sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config
    sudo sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g" /etc/ssh/sshd_config
    sudo sed -i 's/#ListenAddress 0.0.0.0/ListenAddress 0.0.0.0/' /etc/ssh/sshd_config
    sudo sed -i 's/#ListenAddress ::/ListenAddress ::/' /etc/ssh/sshd_config
    sudo sed -i 's/#AddressFamily any/AddressFamily any/' /etc/ssh/sshd_config
    sudo sed -i "s/^#\?PubkeyAuthentication.*/PubkeyAuthentication no/g" /etc/ssh/sshd_config
    sudo sed -i '/^#UsePAM\|UsePAM/c #UsePAM no' /etc/ssh/sshd_config
    sudo sed -i '/^AuthorizedKeysFile/s/^/#/' /etc/ssh/sshd_config
fi
if [ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]; then
    sudo sed -i "s/^#\?Port.*/Port 22/g" /etc/ssh/sshd_config.d/50-cloud-init.conf
    sudo sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config.d/50-cloud-init.conf
    sudo sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g" /etc/ssh/sshd_config.d/50-cloud-init.conf
    sudo sed -i 's/#ListenAddress 0.0.0.0/ListenAddress 0.0.0.0/' /etc/ssh/sshd_config.d/50-cloud-init.conf
    sudo sed -i 's/#ListenAddress ::/ListenAddress ::/' /etc/ssh/sshd_config.d/50-cloud-init.conf
    sudo sed -i 's/#AddressFamily any/AddressFamily any/' /etc/ssh/sshd_config.d/50-cloud-init.conf
    sudo sed -i "s/^#\?PubkeyAuthentication.*/PubkeyAuthentication no/g" /etc/ssh/sshd_config.d/50-cloud-init.conf
    sudo sed -i '/^#UsePAM\|UsePAM/c #UsePAM no' /etc/ssh/sshd_config.d/50-cloud-init.conf
    sudo sed -i '/^AuthorizedKeysFile/s/^/#/' /etc/ssh/sshd_config.d/50-cloud-init.conf
fi
remove_duplicate_lines /etc/ssh/sshd_config
remove_duplicate_lines /etc/ssh/sshd_config.d/50-cloud-init.conf
sudo service ssh restart
sudo service sshd restart
sudo systemctl restart sshd
sudo systemctl restart ssh
rm -rf "$0"
