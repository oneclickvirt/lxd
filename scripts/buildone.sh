#!/usr/bin/env bash
# from
# https://github.com/oneclickvirt/lxd
# 2025.02.02

# 输入
# ./buildone.sh 服务器名称 CPU核数 内存大小 硬盘大小 SSH端口 外网起端口 外网止端口 下载速度 上传速度 是否启用IPV6(Y or N) 系统(留空则为debian12)
# 如果 外网起端口 外网止端口 都设置为0则不做区间外网端口映射了，只映射基础的SSH端口，注意不能为空，不进行映射需要设置为0

# 创建容器
cd /root >/dev/null 2>&1
if ! command -v jq; then
    apt-get install jq -y
fi

check_china() {
    echo "IP area being detected ......"
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 6 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            echo "根据ipapi.co提供的信息，当前IP可能在中国，使用中国镜像完成相关组件安装"
            CN=true
        fi
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

check_china
cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn3.spiritlhl.net/" "http://cdn1.spiritlhl.net/" "https://ghproxy.com/" "http://cdn2.spiritlhl.net/")
check_cdn_file
name="${1:-test}"
cpu="${2:-1}"
memory="${3:-256}"
disk="${4:-2}"
sshn="${5:-20001}"
nat1="${6:-20002}"
nat2="${7:-20025}"
in="${8:-10240}"
out="${9:-10240}"
enable_ipv6="${10:-N}"
enable_ipv6=$(echo "$enable_ipv6" | tr '[:upper:]' '[:lower:]')
system="${11:-debian12}"
a="${system%%[0-9]*}"
b="${system##*[!0-9.]}"
sys_bit=""
sysarch="$(uname -m)"
case "${sysarch}" in
"x86_64" | "x86" | "amd64" | "x64") sys_bit="x86_64" ;;
"i386" | "i686") sys_bit="i686" ;;
"aarch64" | "armv8" | "armv8l") sys_bit="aarch64" ;;
"armv7l") sys_bit="armv7l" ;;
"s390x") sys_bit="s390x" ;;
    #     "riscv64") sys_bit="riscv64";;
"ppc64le") sys_bit="ppc64le" ;;
    #     "ppc64") sys_bit="ppc64";;
*) sys_bit="x86_64" ;;
esac

# 处理镜像是否存在，是否使用自编译、官方、第三方镜像的问题
image_download_url=""
fixed_system=false
if [[ "$sys_bit" == "x86_64" || "$sys_bit" == "arm64" ]]; then
    self_fixed_images=($(curl -slk -m 6 ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd_images/main/${sys_bit}_fixed_images.txt))
    for image_name in "${self_fixed_images[@]}"; do
        if [ -z "${b}" ]; then
            # 若无版本号，则仅识别系统名字匹配第一个链接，放宽系统识别
            if [[ "$image_name" == "${a}"* ]]; then
                fixed_system=true
                # image_download_url=$(echo "$response" | jq -r ".assets[$i].browser_download_url")
                image_download_url="https://github.com/oneclickvirt/lxd_images/releases/download/${a}/${image_name}"
                image_alias_output=$(lxc image alias list)
                if [[ "$image_alias_output" != *"$image_name"* ]]; then
                    wget "${cdn_success_url}${image_download_url}"
                    chmod 777 "$image_name"
                    unzip "$image_name"
                    rm -rf "$image_name"
                    # 导入为对应镜像
                    lxc image import lxd.tar.xz rootfs.squashfs --alias "$image_name"
                    rm -rf lxd.tar.xz rootfs.squashfs
                    echo "A matching image exists and will be created using ${image_download_url}"
                    echo "匹配的镜像存在，将使用 ${image_download_url} 进行创建"
                fi
                break
            fi
        else
            # 有版本号，精确识别系统
            if [[ "$image_name" == "${a}_${b}"* ]]; then
                fixed_system=true
                # image_download_url=$(echo "$response" | jq -r ".assets[$i].browser_download_url")
                image_download_url="https://github.com/oneclickvirt/lxd_images/releases/download/${a}/${image_name}"
                image_alias_output=$(lxc image alias list)
                if [[ "$image_alias_output" != *"$image_name"* ]]; then
                    wget "${cdn_success_url}${image_download_url}"
                    chmod 777 "$image_name"
                    unzip "$image_name"
                    rm -rf "$image_name"
                    # 导入为对应镜像
                    lxc image import lxd.tar.xz rootfs.squashfs --alias "$image_name"
                    rm -rf lxd.tar.xz rootfs.squashfs
                    echo "A matching image exists and will be created using ${image_download_url}"
                    echo "匹配的镜像存在，将使用 ${image_download_url} 进行创建"
                fi
                break
            fi
        fi
    done
else
    output=$(lxc image list images:${a}/${b})
fi
# 宿主机未识别到要下载的容器链接时
if [ -z "$image_download_url" ]; then
    system=$(lxc image list images:${a}/${b} --format=json | jq -r --arg ARCHITECTURE "$sys_bit" '.[] | select(.type == "container" and .architecture == $ARCHITECTURE) | .aliases[0].name' | head -n 1)
    echo "A matching image exists and will be created using images:${system}"
    echo "匹配的镜像存在，将使用 images:${system} 进行创建"
    fixed_system=false
fi
if [ -z "$image_download_url" ] && [ -z "$system" ]; then
    system=$(lxc image list opsmaru:${a}/${b} --format=json | jq -r --arg ARCHITECTURE "$sys_bit" '.[] | select(.type == "container" and .architecture == $ARCHITECTURE) | .aliases[0].name' | head -n 1)
    if [ $? -ne 0 ]; then
        status_tuna=false
    else
        if echo "$system" | grep -q "${a}"; then
            echo "A matching image exists and will be created using opsmaru:${system}"
            echo "匹配的镜像存在，将使用 opsmaru:${system} 进行创建"
            status_tuna=true
            fixed_system=false
        else
            status_tuna=false
        fi
    fi
    if [ "$status_tuna" = false ]; then
        echo "No matching image found, please execute"
        echo "lxc image list images:system/version_number OR lxc image list opsmaru:system/version_number"
        echo "Check if a corresponding image exists"
        echo "未找到匹配的镜像，请执行"
        echo "lxc image list images:系统/版本号 或 lxc image list opsmaru:系统/版本号"
        echo "查询是否存在对应镜像"
        exit 1
    fi
fi

# 开始创建容器
rm -rf "$name"
if [ -z "$image_download_url" ] && [ "$status_tuna" = true ]; then
    lxc init opsmaru:${system} "$name" -c limits.cpu="$cpu" -c limits.memory="$memory"MiB
elif [ -z "$image_download_url" ]; then
    lxc init images:${system} "$name" -c limits.cpu="$cpu" -c limits.memory="$memory"MiB
else
    lxc init "$image_name" "$name" -c limits.cpu="$cpu" -c limits.memory="$memory"MiB
fi
# --config=user.network-config="network:\n  version: 2\n  ethernets:\n    eth0:\n      nameservers:\n        addresses: [8.8.8.8, 8.8.4.4]"
if [ $? -ne 0 ]; then
    echo "Container creation failed, please check the previous output message"
    echo "容器创建失败，请检查前面的输出信息"
    exit 1
fi
# 硬盘大小
if [ -f /usr/local/bin/lxd_storage_type ]; then
    storage_type=$(cat /usr/local/bin/lxd_storage_type)
else
    storage_type="btrfs"
fi
if [[ $disk == *.* ]]; then
    disk_mb=$(echo "$disk * 1024" | bc | cut -d '.' -f 1)
    lxc storage create "$name" "$storage_type" size="$disk_mb"MB >/dev/null 2>&1
    lxc config device override "$name" root size="$disk_mb"MB
    lxc config device set "$name" root limits.max "$disk_mb"MB
else
    lxc storage create "$name" "$storage_type" size="$disk"GB >/dev/null 2>&1
    lxc config device override "$name" root size="$disk"GB
    lxc config device set "$name" root limits.max "$disk"GB
fi
# IO
lxc config device set "$name" root limits.read 500MB
lxc config device set "$name" root limits.write 500MB
lxc config device set "$name" root limits.read 5000iops
lxc config device set "$name" root limits.write 5000iops
# cpu
lxc config set "$name" limits.cpu.priority 0
lxc config set "$name" limits.cpu.allowance 50%
lxc config set "$name" limits.cpu.allowance 25ms/100ms
# 内存
lxc config set "$name" limits.memory.swap true
lxc config set "$name" limits.memory.swap.priority 1
# 支持docker虚拟化
lxc config set "$name" security.nesting true
# 安全性防范设置 - 只有Ubuntu支持
# if [ "$(uname -a | grep -i ubuntu)" ]; then
#   # Set the security settings
#   lxc config set "$1" security.syscalls.intercept.mknod true
#   lxc config set "$1" security.syscalls.intercept.setxattr true
# fi
ori=$(date | md5sum)
passwd=${ori:2:9}
lxc start "$name"
sleep 3
/usr/local/bin/check-dns.sh
sleep 3
if [ "$fixed_system" = false ]; then
    if [[ "${CN}" == true ]]; then
        lxc exec "$name" -- yum install -y curl
        lxc exec "$name" -- apt-get install curl -y --fix-missing
        lxc exec "$name" -- curl -lk https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh -o ChangeMirrors.sh
        lxc exec "$name" -- chmod 777 ChangeMirrors.sh
        lxc exec "$name" -- ./ChangeMirrors.sh --source mirrors.tuna.tsinghua.edu.cn --web-protocol http --intranet false --close-firewall true --backup true --updata-software false --clean-cache false --ignore-backup-tips
        lxc exec "$name" -- rm -rf ChangeMirrors.sh
    fi
    if echo "$system" | grep -qiE "centos" || echo "$system" | grep -qiE "almalinux" || echo "$system" | grep -qiE "fedora" || echo "$system" | grep -qiE "rocky" || echo "$system" | grep -qiE "oracle"; then
        lxc exec "$name" -- sudo yum update -y
        lxc exec "$name" -- sudo yum install -y curl
        lxc exec "$name" -- sudo yum install -y dos2unix
    elif echo "$system" | grep -qiE "alpine"; then
        lxc exec "$name" -- apk update
        lxc exec "$name" -- apk add --no-cache curl
    elif echo "$system" | grep -qiE "openwrt"; then
        lxc exec "$name" -- opkg update
    elif echo "$system" | grep -qiE "archlinux"; then
        lxc exec "$name" -- pacman -Sy
        lxc exec "$name" -- pacman -Sy --noconfirm --needed curl
        lxc exec "$name" -- pacman -Sy --noconfirm --needed dos2unix
        lxc exec "$name" -- pacman -Sy --noconfirm --needed bash
    else
        lxc exec "$name" -- sudo apt-get update -y
        lxc exec "$name" -- sudo apt-get install curl -y --fix-missing
        lxc exec "$name" -- sudo apt-get install dos2unix -y --fix-missing
    fi
fi
if echo "$system" | grep -qiE "alpine" || echo "$system" | grep -qiE "openwrt"; then
    if [ ! -f /usr/local/bin/ssh_sh.sh ]; then
        curl -L ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_sh.sh -o /usr/local/bin/ssh_sh.sh
        chmod 777 /usr/local/bin/ssh_sh.sh
        dos2unix /usr/local/bin/ssh_sh.sh
    fi
    cp /usr/local/bin/ssh_sh.sh /root
    lxc file push /root/ssh_sh.sh "$name"/root/
    lxc exec "$name" -- chmod 777 ssh_sh.sh
    lxc exec "$name" -- ./ssh_sh.sh ${passwd}
else
    if [ ! -f /usr/local/bin/ssh_bash.sh ]; then
        curl -L ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_bash.sh -o /usr/local/bin/ssh_bash.sh
        chmod 777 /usr/local/bin/ssh_bash.sh
        dos2unix /usr/local/bin/ssh_bash.sh
    fi
    cp /usr/local/bin/ssh_bash.sh /root
    lxc file push /root/ssh_bash.sh "$name"/root/
    lxc exec "$name" -- chmod 777 ssh_bash.sh
    lxc exec "$name" -- dos2unix ssh_bash.sh
    lxc exec "$name" -- sudo ./ssh_bash.sh $passwd
    if [ ! -f /usr/local/bin/config.sh ]; then
        curl -L ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/config.sh -o /usr/local/bin/config.sh
        chmod 777 /usr/local/bin/config.sh
        dos2unix /usr/local/bin/config.sh
    fi
    cp /usr/local/bin/config.sh /root
    lxc file push /root/config.sh "$name"/root/
    lxc exec "$name" -- chmod +x config.sh
    lxc exec "$name" -- dos2unix config.sh
    lxc exec "$name" -- bash config.sh
    lxc exec "$name" -- history -c
fi
lxc config device add "$name" ssh-port proxy listen=tcp:0.0.0.0:$sshn connect=tcp:127.0.0.1:22
# 是否要创建V6地址
if [ -n "$enable_ipv6" ]; then
    if [ "$enable_ipv6" == "y" ]; then
        lxc exec "$name" -- echo '*/1 * * * * curl -m 6 -s ipv6.ip.sb && curl -m 6 -s ipv6.ip.sb' | crontab -
        sleep 1
        if [ ! -f "./build_ipv6_network.sh" ]; then
            # 如果不存在，则从指定 URL 下载并添加可执行权限
            curl -L ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/build_ipv6_network.sh -o build_ipv6_network.sh
            chmod +x build_ipv6_network.sh
        fi
        ./build_ipv6_network.sh "$name"
    fi
fi
if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
    lxc config device add "$name" nattcp-ports proxy listen=tcp:0.0.0.0:$nat1-$nat2 connect=tcp:127.0.0.1:$nat1-$nat2
    lxc config device add "$name" natudp-ports proxy listen=udp:0.0.0.0:$nat1-$nat2 connect=udp:127.0.0.1:$nat1-$nat2
fi
# 网速
lxc stop "$name"
if ((in == out)); then
    speed_limit="$in"
else
    speed_limit=$(($in > $out ? $in : $out))
fi
# 上传 下载 最大
lxc config device override "$name" eth0 limits.egress="$out"Mbit limits.ingress="$in"Mbit limits.max="$speed_limit"Mbit
lxc start "$name"
rm -rf ssh_bash.sh config.sh ssh_sh.sh
if echo "$system" | grep -qiE "alpine"; then
    sleep 3
    lxc stop "$name"
    lxc start "$name"
fi
if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
    echo "$name $sshn $passwd $nat1 $nat2" >>"$name"
    echo "$name $sshn $passwd $nat1 $nat2"
    exit 1
fi
if [ "$nat1" == "0" ] && [ "$nat2" == "0" ]; then
    echo "$name $sshn $passwd" >>"$name"
    echo "$name $sshn $passwd"
fi
