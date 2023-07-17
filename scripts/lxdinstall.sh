#!/bin/bash
# by https://github.com/spiritLHLS/lxc
# 2023.07.17


# curl -L https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/lxdinstall.sh -o lxdinstall.sh && chmod +x lxdinstall.sh && bash lxdinstall.sh

cd /root >/dev/null 2>&1
if [ ! -d "/usr/local/bin" ]; then
    mkdir -p "$directory"
fi
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading(){ read -rp "$(_green "$1")" "$2"; }
cdn_urls=("https://cdn.spiritlhl.workers.dev/" "https://cdn3.spiritlhl.net/" "https://cdn1.spiritlhl.net/" "https://ghproxy.com/" "https://cdn2.spiritlhl.net/")
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
    if command -v $package_name > /dev/null 2>&1 ; then
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
        if curl -sL -k "$cdn_url$o_url" --max-time 6 | grep -q "success" > /dev/null 2>&1; then
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
  curl -6 -ksm1 "https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2FspiritLHLS%2Flxc&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=&edge_flat=true" 2>&1) &&
  TODAY=$(expr "$COUNT" : '.*\s\([0-9]\{1,\}\)\s/.*') && TOTAL=$(expr "$COUNT" : '.*/\s\([0-9]\{1,\}\)\s.*')
}

rebuild_cloud_init(){
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
            lines_after_system_info=$(echo "$content" | sed -n "$((line_number+1)),\$p")
            if [ -n "$lines_after_system_info" ]; then
                updated_content=$(echo "$content" | sed "$((line_number+1)),\$d")
                echo "$updated_content" > "/etc/cloud/cloud.cfg"
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
lxd_snap=`dpkg -l |awk '/^[hi]i/{print $2}' | grep -ow snap`
lxd_snapd=`dpkg -l |awk '/^[hi]i/{print $2}' | grep -ow snapd`
if [[ "$lxd_snap" =~ ^snap.* ]]&&[[ "$lxd_snapd" =~ ^snapd.* ]]
then
    _green "snap is installed"
    _green "snap已安装"
else
    _green "start installation of snap"
    _green "开始安装snap"
    apt-get update
#     install_package snap
    install_package snapd
fi
snap_core=`snap list core`
snap_lxd=`snap list lxd`
if [[ "$snap_core" =~ core.* ]]&&[[ "$snap_lxd" =~ lxd.* ]]
then
    _green "lxd is installed"
    _green "lxd已安装"
    lxd_lxc_detect=`lxc list`
    if [[ "$lxd_lxc_detect" =~ "snap-update-ns failed with code1".* ]]
    then
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
    ! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
    export PATH=$PATH:/snap/bin
    ! lxc -h >/dev/null 2>&1 && _yellow 'lxc路径有问题，请检查修复' && exit
    _green "LXD installation complete"
    _green "LXD安装完成"        
fi

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
# /snap/bin/lxd init --storage-backend zfs --storage-create-loop "$disk_nums" --storage-pool default --auto
# zfs检测与安装
temp=$(/snap/bin/lxd init --storage-backend zfs --storage-create-loop "$disk_nums" --storage-pool default --auto 2>&1)
if [[ $? -ne 0 ]]; then
    status=false
else
    status=true
fi
echo "$temp"
if echo "$temp" | grep -q "lxd.migrate" && [[ $status == false ]]; then
    /snap/bin/lxd.migrate
    temp=$(/snap/bin/lxd init --storage-backend zfs --storage-create-loop "$disk_nums" --storage-pool default --auto 2>&1)
    if [[ $? -ne 0 ]]; then
        status=false
    else
        status=true
    fi
    echo "$temp"
fi

removezfs(){
    rm /etc/apt/sources.list.d/bullseye-backports.list
    rm /etc/apt/preferences.d/90_zfs
    sed -i "/$lineToRemove/d" /etc/apt/sources.list
    apt-get remove ${codename}-backports -y
    apt-get remove zfs-dkms zfs-zed -y
    apt-get update
}

checkzfs(){
  if echo "$temp" | grep -q "'zfs' isn't available" && [[ $status == false ]]; then
      _green "zfs module call failed, trying to compile zfs module plus load kernel..."
      _green "zfs模块调用失败，尝试编译zfs模块加载入内核..."
    #   apt-get install -y linux-headers-amd64
      codename=$(lsb_release -cs)
      lineToRemove="deb http://deb.debian.org/debian ${codename}-backports main contrib non-free"
      echo "deb http://deb.debian.org/debian ${codename}-backports main contrib non-free"|sudo tee -a /etc/apt/sources.list && apt-get update
    #   apt-get install -y linux-headers-amd64
      install_package ${codename}-backports
      if grep -q "deb http://deb.debian.org/debian bullseye-backports main contrib" /etc/apt/sources.list.d/bullseye-backports.list && grep -q "deb-src http://deb.debian.org/debian bullseye-backports main contrib" /etc/apt/sources.list.d/bullseye-backports.list; then
          echo "已修改源"
      else
          echo "deb http://deb.debian.org/debian bullseye-backports main contrib" > /etc/apt/sources.list.d/bullseye-backports.list
          echo "deb-src http://deb.debian.org/debian bullseye-backports main contrib" >> /etc/apt/sources.list.d/bullseye-backports.list
echo "Package: src:zfs-linux
Pin: release n=bullseye-backports
Pin-Priority: 990" > /etc/apt/preferences.d/90_zfs
      fi
      apt-get update
      apt-get install -y dpkg-dev linux-headers-generic linux-image-generic
      if [ $? -ne 0 ]; then
          apt-get install -y dpkg-dev linux-headers-generic linux-image-generic --fix-missing
      fi
      if [[ $? -ne 0 ]]; then
          status=false
          removezfs
          return
      else
          status=true
      fi
      apt-get install -y zfsutils-linux
      if [ $? -ne 0 ]; then
          apt-get install -y zfsutils-linux --fix-missing
      fi
      if [[ $? -ne 0 ]]; then
          status=false
          removezfs
          return
      else
          status=true
      fi
      apt-get install -y zfs-dkms
      if [ $? -ne 0 ]; then
          apt-get install -y zfs-dkms --fix-missing
      fi
      if [[ $? -ne 0 ]]; then
          status=false
          removezfs
          return
      else
          status=true
      fi
      _green "Please reboot the machine (perform a reboot reboot) and execute this script again to load the new kernel, after the reboot you will need to enter the configuration you need again"
      _green "请重启本机(执行 reboot 重启)再次执行本脚本以加载新内核，重启后需要再次输入你需要的配置"
      exit 1
  fi
}

checkzfs
if [[ $status == false ]]; then
    _yellow "zfs compilation failed, trying to use another storage type ......"
    _yellow "zfs编译失败，尝试使用其他存储类型......"
    # 类型设置-硬盘
    # "zfs" 
    SUPPORTED_BACKENDS=("lvm" "btrfs" "ceph" "dir")
    STORAGE_BACKEND=""
    for backend in "${SUPPORTED_BACKENDS[@]}"; do
        if command -v $backend >/dev/null; then
            STORAGE_BACKEND=$backend
            _green "Use $STORAGE_BACKEND storage type"
            _green "使用 $STORAGE_BACKEND 存储类型"
            break
        fi
    done
    if [ -z "$STORAGE_BACKEND" ]; then
        _yellow "No supported storage types, please contact the script maintainer"
        _yellow "无可支持的存储类型，请联系脚本维护者"
        exit 1
    fi
  #   if [ "$STORAGE_BACKEND" = "zfs" ]; then
  #       /snap/bin/lxd init --storage-backend "$STORAGE_BACKEND" --storage-create-loop "$disk_nums" --storage-pool default --auto
    if [ "$STORAGE_BACKEND" = "dir" ]; then
        _green "Infinite storage pool size using default dir type due to no zfs"
        _green "由于无zfs，使用默认dir类型无限定存储池大小"
        /snap/bin/lxd init --storage-backend "$STORAGE_BACKEND" --auto
    elif [ "$STORAGE_BACKEND" = "lvm" ]; then
        _green "Infinite storage pool size using default lvm type due to no zfs"
        _green "由于无zfs，使用默认lvm类型无限定存储池大小"
        DISK=$(lsblk -p -o NAME,TYPE | awk '$2=="disk"{print $1}')
        /snap/bin/lxd init --storage-backend lvm --storage-create-device $DISK --storage-pool lvm_pool --auto
    else
        /snap/bin/lxd init --storage-backend "$STORAGE_BACKEND" --storage-create-device "$disk_nums" --storage-pool default --auto
    fi
fi
install_package uidmap

# 虚拟内存设置
curl -sLk "${cdn_success_url}https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/swap2.sh" -o swap2.sh && chmod +x swap2.sh
./swap2.sh "$memory_nums"
sleep 2
! lxc -h >/dev/null 2>&1 && echo 'alias lxc="/snap/bin/lxc"' >> /root/.bashrc && source /root/.bashrc
export PATH=$PATH:/snap/bin
! lxc -h >/dev/null 2>&1 && _yellow '使用 lxc -h 检测到路径有问题，请手动查看LXD是否安装成功' && exit 1
# 设置镜像不更新
lxc config unset images.auto_update_interval
lxc config set images.auto_update_interval 0
# 设置自动配置内网IPV6地址
lxc network set lxdbr0 ipv6.address auto
# 下载预制文件
files=(
    "https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/ssh.sh"
    "https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/alpinessh.sh"
    "https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/config.sh"
    "https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/buildone.sh"
)
for file in "${files[@]}"; do
    filename=$(basename "$file")
    rm -rf "$filename"
    curl -sLk "${cdn_success_url}${file}" -o "$filename"
    chmod 777 "$filename"
    dos2unix "$filename"
done
cp /root/alpinessh.sh /usr/local/bin
cp /root/config.sh /usr/local/bin
cp /root/config.sh /usr/local/bin
# 设置IPV4优先
sed -i 's/.*precedence ::ffff:0:0\/96.*/precedence ::ffff:0:0\/96  100/g' /etc/gai.conf && systemctl restart networking
# 预设谷歌的DNS
if [ -f "/etc/resolv.conf" ]
then
    cp /etc/resolv.conf /etc/resolv.conf.bak
    sudo chattr -i /etc/resolv.conf
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
    sudo chattr +i /etc/resolv.conf
fi
if [ ! -f /usr/local/bin/check-dns.sh ]; then
    wget ${cdn_success_url}https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/check-dns.sh -O /usr/local/bin/check-dns.sh
    chmod +x /usr/local/bin/check-dns.sh
else
    echo "Script already exists. Skipping installation."
fi
if [ ! -f /etc/systemd/system/check-dns.service ]; then
    wget ${cdn_success_url}https://raw.githubusercontent.com/spiritLHLS/lxc/main/scripts/check-dns.service -O /etc/systemd/system/check-dns.service
    chmod +x /etc/systemd/system/check-dns.service
    systemctl daemon-reload
    systemctl enable check-dns.service
    systemctl start check-dns.service
else
    echo "Service already exists. Skipping installation."
fi
# 加载iptables并设置回源且允许NAT端口转发
install_package iptables 
install_package iptables-persistent
iptables -t nat -A POSTROUTING -j MASQUERADE
sysctl net.ipv4.ip_forward=1
sysctl_path=$(which sysctl)
if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    if grep -q "^#net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    fi
else
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
${sysctl_path} -p
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
_green "脚本当天运行次数:${TODAY}，累计运行次数:${TOTAL}"
_green "If you need to turn on more than 100 cts, it is recommended to wait for a few minutes before performing a reboot to reboot the machine to make the settings take effect"
_green "The reboot will ensure that the DNS detection mechanism takes effect, otherwise the batch opening process may cause the host's DNS to be overwritten by the merchant's preset"
_green "如果你需要开启超过100个小鸡，建议等待几分钟后执行 reboot 重启本机以使得设置生效"
_green "重启后可以保证DNS的检测机制生效，否则批量开启过程中可能导致宿主机的DNS被商家预设覆盖，所以最好重启系统一次"
