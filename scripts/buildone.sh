#!/usr/bin/env bash
# from
# https://github.com/oneclickvirt/lxd
# 2025.08.03

# 输入
# ./buildone.sh 服务器名称 CPU核数 内存大小 硬盘大小 SSH端口 外网起端口 外网止端口 下载速度 上传速度 是否启用IPV6(Y or N) 系统(留空则为debian12)
# 如果 外网起端口 外网止端口 都设置为0则不做区间外网端口映射了，只映射基础的SSH端口，注意不能为空，不进行映射需要设置为0

# 初始化变量和依赖检查
init_env() {
    cd /root >/dev/null 2>&1
    if ! command -v jq; then
        apt-get install jq -y
    fi
}

# 检测IP区域
check_china() {
    echo "IP area being detected ......"
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 6 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            echo "根据ipapi.co提供的信息，当前IP可能在中国，使用中国镜像完成相关组件安装"
            CN=true
        fi
    fi
}

# 检测CDN
check_cdn() {
    local o_url=$1
    local shuffled_cdn_urls=($(shuf -e "${cdn_urls[@]}")) # 打乱数组顺序
    for cdn_url in "${shuffled_cdn_urls[@]}"; do
        if curl -sL -k "$cdn_url$o_url" --max-time 6 | grep -q "success" >/dev/null 2>&1; then
            export cdn_success_url="$cdn_url"
            return
        fi
        sleep 0.5
    done
    export cdn_success_url=""
}

# 检测CDN可用性
check_cdn_file() {
    check_cdn "https://raw.githubusercontent.com/spiritLHLS/ecs/main/back/test"
    if [ -n "$cdn_success_url" ]; then
        echo "CDN available, using CDN"
    else
        echo "No CDN available, no use CDN"
    fi
}

# 获取系统架构
get_system_arch() {
    sysarch="$(uname -m)"
    case "${sysarch}" in
    "x86_64" | "x86" | "amd64" | "x64") sys_bit="x86_64" ;;
    "i386" | "i686") sys_bit="i686" ;;
    "aarch64" | "armv8" | "armv8l") sys_bit="aarch64" ;;
    "armv7l") sys_bit="armv7l" ;;
    "s390x") sys_bit="s390x" ;;
    "ppc64le") sys_bit="ppc64le" ;;
    *) sys_bit="x86_64" ;;
    esac
}

# 处理镜像
process_image() {
    image_download_url=""
    fixed_system=false
    if [[ "$sys_bit" == "x86_64" || "$sys_bit" == "arm64" ]]; then
        process_self_fixed_images
    else
        output=$(lxc image list images:${a}/${b})
    fi

    if [ -z "$image_download_url" ]; then
        process_images_repository
    fi

    if [ -z "$image_download_url" ] && [ -z "$system" ]; then
        process_opsmaru_repository
    fi
}

# 处理自定义镜像
process_self_fixed_images() {
    self_fixed_images=($(curl -slk -m 6 ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd_images/main/${sys_bit}_all_images.txt))
    for image_name in "${self_fixed_images[@]}"; do
        if [ -z "${b}" ]; then
            if [[ "$image_name" == "${a}"* ]]; then
                use_fixed_image "$image_name"
                break
            fi
        else
            if [[ "$image_name" == "${a}_${b}"* ]]; then
                use_fixed_image "$image_name"
                break
            fi
        fi
    done
}

# 使用固定镜像
use_fixed_image() {
    local image_name=$1
    fixed_system=true
    image_download_url="https://github.com/oneclickvirt/lxd_images/releases/download/${a}/${image_name}"
    image_alias_output=$(lxc image alias list)
    if [[ "$image_alias_output" != *"$image_name"* ]]; then
        wget "${cdn_success_url}${image_download_url}"
        chmod 777 "$image_name"
        unzip "$image_name"
        rm -rf "$image_name"
        lxc image import lxd.tar.xz rootfs.squashfs --alias "$image_name"
        rm -rf lxd.tar.xz rootfs.squashfs
        echo "A matching image exists and will be created using ${image_download_url}"
        echo "匹配的镜像存在，将使用 ${image_download_url} 进行创建"
    fi
}

# 处理images仓库
process_images_repository() {
    system=$(lxc image list images:${a}/${b} --format=json | jq -r --arg ARCHITECTURE "$sys_bit" '.[] | select(.type == "container" and .architecture == $ARCHITECTURE) | .aliases[0].name' | head -n 1)
    if [ -n "$system" ]; then
        echo "A matching image exists and will be created using images:${system}"
        echo "匹配的镜像存在，将使用 images:${system} 进行创建"
        fixed_system=false
    fi
}

# 处理opsmaru仓库
process_opsmaru_repository() {
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
}

# 创建容器
create_container() {
    rm -rf "$name"
    if [ -z "$image_download_url" ] && [ "$status_tuna" = true ]; then
        lxc init opsmaru:${system} "$name" -c limits.cpu="$cpu" -c limits.memory="$memory"MiB
    elif [ -z "$image_download_url" ]; then
        lxc init images:${system} "$name" -c limits.cpu="$cpu" -c limits.memory="$memory"MiB
    else
        lxc init "$image_name" "$name" -c limits.cpu="$cpu" -c limits.memory="$memory"MiB
    fi
    if [ $? -ne 0 ]; then
        echo "Container creation failed, please check the previous output message"
        echo "容器创建失败，请检查前面的输出信息"
        exit 1
    fi
}

# 配置存储
configure_storage() {
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
}

# 配置IO限制
configure_io() {
    lxc config device set "$name" root limits.read 500MB
    lxc config device set "$name" root limits.write 500MB
    lxc config device set "$name" root limits.read 5000iops
    lxc config device set "$name" root limits.write 5000iops
}

# 配置CPU限制
configure_cpu() {
    lxc config set "$name" limits.cpu.priority 0
    lxc config set "$name" limits.cpu.allowance 50%
    lxc config set "$name" limits.cpu.allowance 25ms/100ms
}

# 配置内存限制
configure_memory() {
    lxc config set "$name" limits.memory.swap true
    lxc config set "$name" limits.memory.swap.priority 1
}

# 配置安全设置
configure_security() {
    lxc config set "$name" security.nesting true
}

# 安装和配置系统
setup_system() {
    ori=$(date | md5sum)
    passwd=${ori:2:9}
    lxc start "$name"
    sleep 3
    /usr/local/bin/check-dns.sh
    sleep 3
    if [ "$fixed_system" = false ]; then
        setup_mirrors
        install_packages
    fi
    setup_ssh
    configure_ipv6
}

# 设置镜像源
setup_mirrors() {
    if [[ "${CN}" == true ]]; then
        lxc exec "$name" -- yum install -y curl
        lxc exec "$name" -- apt-get install curl -y --fix-missing
        lxc exec "$name" -- curl -lk https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh -o ChangeMirrors.sh
        lxc exec "$name" -- chmod 777 ChangeMirrors.sh
        lxc exec "$name" -- ./ChangeMirrors.sh --source mirrors.tuna.tsinghua.edu.cn --web-protocol http --intranet false --backup true --updata-software false --clean-cache false --ignore-backup-tips
        lxc exec "$name" -- rm -rf ChangeMirrors.sh
    fi
}

# 安装必要软件包
install_packages() {
    if echo "$system" | grep -qiE "centos|almalinux|fedora|rocky|oracle"; then
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
}

# 配置SSH
setup_ssh() {
    if echo "$system" | grep -qiE "alpine|openwrt"; then
        setup_ssh_sh
    else
        setup_ssh_bash
    fi
}

# 配置Alpine和OpenWrt的SSH
setup_ssh_sh() {
    if [ ! -f /usr/local/bin/ssh_sh.sh ]; then
        curl -L ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_sh.sh -o /usr/local/bin/ssh_sh.sh
        chmod 777 /usr/local/bin/ssh_sh.sh
        dos2unix /usr/local/bin/ssh_sh.sh
    fi
    cp /usr/local/bin/ssh_sh.sh /root
    lxc file push /root/ssh_sh.sh "$name"/root/
    lxc exec "$name" -- chmod 777 ssh_sh.sh
    lxc exec "$name" -- ./ssh_sh.sh ${passwd}
}

# 配置其他系统的SSH
setup_ssh_bash() {
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
}

configure_port() {
    lxc restart "$name"
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
        exit 1
    fi
    ipv4_address=$(ip addr show | awk '/inet .*global/ && !/inet6/ {print $2}' | sed -n '1p' | cut -d/ -f1)
    echo "Host IPv4 address: $ipv4_address"
    if ! lxc config device override "$name" eth0 ipv4.address="$container_ip" 2>/dev/null; then
        if ! lxc config device set "$name" eth0 ipv4.address "$container_ip" 2>/dev/null; then
            echo "Error: Failed to set ipv4.address for device 'eth0' in container '$name'." >&2
            exit 1
        fi
    fi
    lxc config device add "$name" ssh-port proxy listen=tcp:$ipv4_address:$sshn connect=tcp:$container_ip:22 nat=true
    if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
        lxc config device add "$name" nattcp-ports proxy listen=tcp:$ipv4_address:$nat1-$nat2 connect=tcp:0.0.0.0:$nat1-$nat2 nat=true
        lxc config device add "$name" natudp-ports proxy listen=udp:$ipv4_address:$nat1-$nat2 connect=udp:0.0.0.0:$nat1-$nat2 nat=true
    fi
}

# 配置IPv6
configure_ipv6() {
    if [ -n "$enable_ipv6" ]; then
        if [ "$enable_ipv6" == "y" ]; then
            lxc exec "$name" -- echo '*/1 * * * * curl -m 6 -s ipv6.ip.sb && curl -m 6 -s ipv6.ip.sb' | crontab -
            sleep 1
            if [ ! -f "./build_ipv6_network.sh" ]; then
                curl -L ${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/build_ipv6_network.sh -o build_ipv6_network.sh
                chmod +x build_ipv6_network.sh
            fi
            ./build_ipv6_network.sh "$name"
        fi
    fi
}

# 配置网络限速
configure_network_speed() {
    lxc stop "$name"
    if ((in == out)); then
        speed_limit="$in"
    else
        speed_limit=$(($in > $out ? $in : $out))
    fi
    lxc config device override "$name" eth0 limits.egress="$out"Mbit limits.ingress="$in"Mbit limits.max="$speed_limit"Mbit
    lxc start "$name"
}

# 清理和输出结果
cleanup_and_output() {
    rm -rf ssh_bash.sh config.sh ssh_sh.sh
    if echo "$system" | grep -qiE "alpine"; then
        sleep 3
        lxc stop "$name"
        lxc start "$name"
    fi
    if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
        lxc config set "$name" user.description "$name $sshn $passwd $nat1 $nat2"
        echo "$name $sshn $passwd $nat1 $nat2" >>"$name"
        echo "$name $sshn $passwd $nat1 $nat2"
        exit 1
    fi
    if [ "$nat1" == "0" ] && [ "$nat2" == "0" ]; then
        lxc config set "$name" user.description "$name $sshn $passwd"
        echo "$name $sshn $passwd" >>"$name"
        echo "$name $sshn $passwd"
    fi
}

main() {
    init_env
    check_china
    cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")
    check_cdn_file
    # 解析参数
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
    get_system_arch
    process_image
    create_container
    configure_storage
    configure_io
    configure_cpu
    configure_memory
    configure_security
    setup_system
    configure_port
    configure_network_speed
    cleanup_and_output
}

main "$@"
