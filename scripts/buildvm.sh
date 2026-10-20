#!/usr/bin/env bash
# from
# https://github.com/oneclickvirt/lxd
# 2026.08.30

# Load before changing directory or touching shared downloads and logs.
load_instance_ownership() {
    local script_dir helper temporary
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
    for helper in "$script_dir/instance_ownership.sh" /usr/local/bin/instance_ownership.sh /root/instance_ownership.sh; do
        if [ -f "$helper" ]; then
            # shellcheck source=/dev/null
            . "$helper" || return 1
            if declare -F ocv_import_split_image >/dev/null && declare -F ocv_image_alias_target >/dev/null; then
                return 0
            fi
        fi
    done
    temporary=$(mktemp "${TMPDIR:-/tmp}/lxd-ownership.XXXXXX") || return 1
    if ! curl -fsSL "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/instance_ownership.sh" -o "$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi
    # shellcheck source=/dev/null
    . "$temporary"
    local status=$?
    rm -f -- "$temporary"
    [ "$status" -eq 0 ] || return "$status"
    declare -F ocv_import_split_image >/dev/null && declare -F ocv_image_alias_target >/dev/null
}
load_instance_ownership || { echo "Missing instance_ownership.sh; download it with this script." >&2; exit 1; }
OCV_SCRIPT_RUNTIME=lxd
OCV_INSTANCE_CLI=lxc
if [ "${ONECLICKVIRT_TESTING:-}" != "1" ]; then
    ocv_lock_scripts || exit 1
fi


# Remove only a VM that this invocation created when a later step fails.  This
# prevents a failed creation from being reported as a running VM while keeping
# an existing VM with the requested name untouched.
created_instance=false
created_identity=""
build_succeeded=false
cleanup_failed_instance() {
    local status=$?
    if [ "$created_instance" = true ] && [ "$build_succeeded" != true ] && [ -n "${name:-}" ] && command -v lxc >/dev/null 2>&1; then
        ocv_remove_owned_instance "$name" "$created_identity" || echo "Failed to roll back LXD instance: $name" >&2
    fi
    return "$status"
}

create_instance_with_tracking() {
    local init_status=0
    ocv_create_owned "$name" "$@" || init_status=$?
    created_identity="$ocv_created_identity"
    created_instance=false
    [ -z "$created_identity" ] || created_instance=true
    return "$init_status"
}
if [[ "${ONECLICKVIRT_TESTING:-}" != "1" ]]; then
    trap cleanup_failed_instance EXIT
fi

lxd_storage_pool() {
    local pool_name="${LXD_STORAGE_POOL:-}"
    if [ -z "$pool_name" ] && [ -r /usr/local/bin/lxd_storage_pool ]; then
        IFS= read -r pool_name </usr/local/bin/lxd_storage_pool || true
    fi
    [[ "$pool_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || pool_name="default"
    printf '%s\n' "$pool_name"
}

run_lxc_probe() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 15 lxc "$@"
    else
        lxc "$@"
    fi
}

ensure_lxd_ready() {
    storage_pool="$(lxd_storage_pool)"
    if ! command -v lxc >/dev/null 2>&1; then
        echo "Error: LXD is not installed or not in PATH." >&2
        echo "错误：LXD 未安装或不在 PATH 中。" >&2
        return 1
    fi
    if ! run_lxc_probe info >/dev/null 2>&1; then
        echo "Error: LXD is not initialized; run lxdinstall.sh successfully first." >&2
        echo "错误：LXD 尚未初始化，请先成功运行 lxdinstall.sh。" >&2
        return 1
    fi
    if ! run_lxc_probe storage show "$storage_pool" >/dev/null 2>&1; then
        echo "Error: LXD storage pool '$storage_pool' is unavailable." >&2
        echo "错误：LXD 存储池 '$storage_pool' 不可用。" >&2
        return 1
    fi
}


check_vm_support() {
    echo "Checking VM virtualization support..."
    echo "检查虚拟机虚拟化支持..."
    if ! command -v lxc >/dev/null 2>&1; then
        echo "Error: LXD is not installed or not in PATH"
        echo "错误：LXD未安装或不在PATH中"
        return 1
    fi
    local drivers
    drivers=$(lxc info | grep -i "driver:")
    echo "Available drivers: $drivers"
    echo "可用驱动: $drivers"
    if ! echo "$drivers" | grep -qi "qemu"; then
        echo "Error: LXD does not support virtual machines (qemu driver not found)"
        echo "错误：LXD不支持虚拟机（未找到qemu驱动）"
        echo "Only LXC containers are supported on this system"
        echo "此系统仅支持LXC容器"
        return 1
    fi
    # Detect KVM hardware acceleration vs QEMU TCG software emulation
    if [ -e /dev/kvm ]; then
        if [ -w /dev/kvm ]; then
            echo "KVM hardware acceleration available - VMs will use KVM nested virtualization"
            echo "KVM硬件加速可用 - 虚拟机将使用KVM嵌套虚拟化"
        else
            echo "Warning: /dev/kvm exists but is not writable, falling back to TCG emulation"
            echo "警告: /dev/kvm存在但无写入权限，降级为TCG模拟"
        fi
    else
        echo "KVM not available - VMs will use QEMU TCG software emulation (slower)"
        echo "KVM不可用 - 虚拟机将使用QEMU TCG软件模拟（较慢）"
    fi
}

# shellcheck disable=SC2034
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "$ID" in
        ubuntu | pop | neon | zorin)
            OS="ubuntu"
            if [ "${UBUNTU_CODENAME:-}" != "" ]; then
                VERSION="$UBUNTU_CODENAME"
            else
                VERSION="$VERSION_CODENAME"
            fi
            PACKAGETYPE="apt"
            PACKAGETYPE_INSTALL="apt install -y"
            PACKAGETYPE_UPDATE="apt update -y"
            PACKAGETYPE_REMOVE="apt remove -y"
            ;;
        debian)
            OS="$ID"
            VERSION="$VERSION_CODENAME"
            PACKAGETYPE="apt"
            PACKAGETYPE_INSTALL="apt install -y"
            PACKAGETYPE_UPDATE="apt update -y"
            PACKAGETYPE_REMOVE="apt remove -y"
            ;;
        kali)
            OS="debian"
            PACKAGETYPE="apt"
            PACKAGETYPE_INSTALL="apt install -y"
            PACKAGETYPE_UPDATE="apt update -y"
            PACKAGETYPE_REMOVE="apt remove -y"
            YEAR="$(echo "$VERSION_ID" | cut -f1 -d.)"
            ;;
        centos | almalinux | rocky)
            OS="$ID"
            VERSION="$VERSION_ID"
            PACKAGETYPE="dnf"
            PACKAGETYPE_INSTALL="dnf install -y"
            PACKAGETYPE_REMOVE="dnf remove -y"
            if [[ "$VERSION" =~ ^7 ]]; then
                PACKAGETYPE="yum"
            fi
            ;;
        arch | archarm | endeavouros | blendos | garuda)
            OS="arch"
            VERSION=""
            PACKAGETYPE="pacman"
            PACKAGETYPE_INSTALL="pacman -S --noconfirm --needed"
            PACKAGETYPE_UPDATE="pacman -Sy"
            PACKAGETYPE_REMOVE="pacman -Rsc --noconfirm"
            PACKAGETYPE_ONLY_REMOVE="pacman -Rdd --noconfirm"
            ;;
        manjaro | manjaro-arm)
            OS="manjaro"
            VERSION=""
            PACKAGETYPE="pacman"
            PACKAGETYPE_INSTALL="pacman -S --noconfirm --needed"
            PACKAGETYPE_UPDATE="pacman -Sy"
            PACKAGETYPE_REMOVE="pacman -Rsc --noconfirm"
            PACKAGETYPE_ONLY_REMOVE="pacman -Rdd --noconfirm"
            ;;
        alpine)
            OS="alpine"
            VERSION="$VERSION_ID"
            PACKAGETYPE="apk"
            PACKAGETYPE_INSTALL="apk add --no-cache"
            PACKAGETYPE_UPDATE="apk update"
            PACKAGETYPE_REMOVE="apk del"
            ;;
        esac
    fi
    if [ -z "${PACKAGETYPE:-}" ]; then
        if command -v apt >/dev/null 2>&1; then
            PACKAGETYPE="apt"
            PACKAGETYPE_INSTALL="apt install -y"
            PACKAGETYPE_UPDATE="apt update -y"
            PACKAGETYPE_REMOVE="apt remove -y"
        elif command -v dnf >/dev/null 2>&1; then
            PACKAGETYPE="dnf"
            PACKAGETYPE_INSTALL="dnf install -y"
            PACKAGETYPE_UPDATE="dnf check-update"
            PACKAGETYPE_REMOVE="dnf remove -y"
        elif command -v yum >/dev/null 2>&1; then
            PACKAGETYPE="yum"
            PACKAGETYPE_INSTALL="yum install -y"
            PACKAGETYPE_UPDATE="yum check-update"
            PACKAGETYPE_REMOVE="yum remove -y"
        elif command -v pacman >/dev/null 2>&1; then
            PACKAGETYPE="pacman"
            PACKAGETYPE_INSTALL="pacman -S --noconfirm --needed"
            PACKAGETYPE_UPDATE="pacman -Sy"
            PACKAGETYPE_REMOVE="pacman -Rsc --noconfirm"
        elif command -v apk >/dev/null 2>&1; then
            PACKAGETYPE="apk"
            PACKAGETYPE_INSTALL="apk add --no-cache"
            PACKAGETYPE_UPDATE="apk update"
            PACKAGETYPE_REMOVE="apk del"
        fi
    fi
}

install_dependencies() {
    cd /root >/dev/null 2>&1 || exit 1
    if ! command -v jq >/dev/null 2>&1; then
        $PACKAGETYPE_INSTALL jq
    fi
}

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
    local shuffled_cdn_urls=()
    mapfile -t shuffled_cdn_urls < <(printf '%s\n' "${cdn_urls[@]}" | shuf)
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
    local withoutcdn_upper
    withoutcdn_upper=$(printf '%s' "${WITHOUTCDN:-}" | tr '[:lower:]' '[:upper:]')
    if [ "$withoutcdn_upper" = "TRUE" ]; then
        export cdn_success_url=""
        echo "WITHOUTCDN=TRUE, skip CDN acceleration"
        return
    fi
    check_cdn "https://raw.githubusercontent.com/spiritLHLS/ecs/main/back/test"
    if [ -n "$cdn_success_url" ]; then
        echo "CDN available, using CDN"
    else
        echo "No CDN available, no use CDN"
    fi
}

retry_curl() {
    local url="$1"
    local max_attempts=5
    local delay=1
    _retry_result=""
    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        if _retry_result=$(curl -slk -m 6 "$url"); then
            if [ -n "$_retry_result" ]; then
                return 0
            fi
        fi
        sleep "$delay"
        delay=$((delay * 2))
    done
    return 1
}

retry_wget() {
    local url="$1"
    local filename="$2"
    local max_attempts=5
    local delay=1
    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        echo "Downloading $filename (attempt $attempt/$max_attempts)..."
        echo "正在下载 $filename (尝试 $attempt/$max_attempts)..."
        wget --progress=bar:force "$url" -O "$filename" && return 0
        sleep "$delay"
        delay=$((delay * 2))
    done
    return 1
}

detect_arch() {
    sys_bit=""
    sys_bit_alt=""
    sysarch="$(uname -m)"
    case "${sysarch}" in
    "x86_64" | "x86" | "amd64" | "x64")
        sys_bit="amd64"
        sys_bit_alt="x86_64"
        ;;
    "i386" | "i686")
        sys_bit="i686"
        sys_bit_alt="i386"
        ;;
    "aarch64" | "armv8" | "armv8l")
        sys_bit="arm64"
        sys_bit_alt="aarch64"
        ;;
    "armv7l")
        sys_bit="armv7l"
        sys_bit_alt="armhf"
        ;;
    "s390x") sys_bit="s390x" ;;
    "ppc64le") sys_bit="ppc64le" ;;
    *)
        sys_bit="amd64"
        sys_bit_alt="x86_64"
        ;;
    esac
}

validate_positive_int() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

validate_non_negative_int() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

validate_positive_number() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk -v n="$1" 'BEGIN { exit !(n > 0) }'
}

validate_port() {
    validate_non_negative_int "$1" && [ "$1" -le 65535 ]
}

validate_positive_port() {
    validate_positive_int "$1" && [ "$1" -le 65535 ]
}

validate_instance_name() {
    [ -n "$1" ] && [ "$1" != "." ] && [ "$1" != ".." ] && [[ "$1" != -* ]] && [[ "$1" != */* ]]
}

validate_inputs() {
    if ! validate_instance_name "$name"; then
        echo "Error: VM name must not be empty, start with '-', or contain '/'."
        echo "错误：虚拟机名称不能为空，不能以 '-' 开头，也不能包含 '/'。"
        return 1
    fi
    if ! validate_positive_int "$cpu" || ! validate_positive_int "$memory" || ! validate_positive_int "$in" || ! validate_positive_int "$out"; then
        echo "Error: CPU, memory and speed values must be positive integers."
        echo "错误：CPU、内存和网速参数必须是正整数。"
        return 1
    fi
    if ! validate_positive_number "$disk"; then
        echo "Error: disk size must be a positive number."
        echo "错误：硬盘大小必须是正数。"
        return 1
    fi
    if ! validate_positive_port "$sshn" || ! validate_port "$nat1" || ! validate_port "$nat2"; then
        echo "Error: ports must be integers in range 0-65535, and SSH port must be greater than 0."
        echo "错误：端口必须是 0-65535 的整数，SSH 端口必须大于 0。"
        return 1
    fi
    if { [ "$nat1" = "0" ] && [ "$nat2" != "0" ]; } || { [ "$nat1" != "0" ] && [ "$nat2" = "0" ]; }; then
        echo "Error: NAT port range must either be both 0 or both non-zero."
        echo "错误：NAT 端口起止必须同时为 0，或同时为非 0。"
        return 1
    fi
    if [ "$nat1" != "0" ] && [ "$nat2" != "0" ] && [ "$nat1" -gt "$nat2" ]; then
        echo "Error: NAT start port cannot be greater than NAT end port."
        echo "错误：NAT 起始端口不能大于结束端口。"
        return 1
    fi
}

replace_proxy_device() {
    local device_name="$1"
    shift
    lxc config device remove "$name" "$device_name" 2>/dev/null || true
    lxc config device add "$name" "$device_name" proxy "$@"
}

remove_device_if_exists() {
    local device_name="$1"
    lxc config device remove "$name" "$device_name" 2>/dev/null || true
}

ensure_container_ipv6_cron() {
    lxc exec "$name" -- sh -c 'set -eu; if [ -L /etc/cron.d ]; then exit 1; fi; [ -d /etc/cron.d ] || exit 0; mkdir -p /run/lock; test ! -L /run/lock; lock=/run/lock/oneclickvirt-ipv6.lock.d; acquired=0; i=0; while [ "$i" -lt 100 ]; do if mkdir "$lock" 2>/dev/null; then acquired=1; break; fi; i=$((i + 1)); sleep 0.1; done; [ "$acquired" -eq 1 ]; trap '\''rmdir "$lock" 2>/dev/null || true'\'' EXIT; target=/etc/cron.d/oneclickvirt-ipv6; line="*/1 * * * * root curl --noproxy '\''*'\'' -6 -fsS --connect-timeout 6 --max-time 6 https://ipv6.ip.sb >/dev/null 2>&1 && curl --noproxy '\''*'\'' -6 -fsS --connect-timeout 6 --max-time 6 https://ipv6.ip.sb >/dev/null 2>&1"; if [ -L "$target" ] || { [ -e "$target" ] && [ ! -f "$target" ]; }; then exit 1; fi; if [ -f "$target" ] && grep -Fqx "$line" "$target"; then exit 0; fi; tmp=$(mktemp /etc/cron.d/.oneclickvirt-ipv6.XXXXXX); trap '\''rm -f -- "$tmp"; rmdir "$lock" 2>/dev/null || true'\'' EXIT; if [ -f "$target" ]; then cat "$target" >"$tmp"; last=$(tail -c 1 "$target" 2>/dev/null | od -An -t x1 | tr -d "[:space:]"); [ -z "$last" ] || [ "$last" = 0a ] || printf "\n" >>"$tmp"; fi; printf "%s\n" "$line" >>"$tmp"; chmod 0644 "$tmp"; mv -f "$tmp" "$target"'
}

download_host_file() {
    local url="$1"
    local output="$2"
    if ! curl -fsSLk "${cdn_success_url}${url}" -o "$output"; then
        echo "Failed to download: $url"
        echo "下载失败：$url"
        return 1
    fi
}

strip_image_separators() {
    local value="$1"
    while [[ "$value" == [/:_.-]* ]]; do
        value="${value#?}"
    done
    while [[ "$value" == *[/:_.-] ]]; do
        value="${value%?}"
    done
    printf '%s\n' "$value"
}

canonical_image_family() {
    local family="$1"
    case "$family" in
    alma) family="almalinux" ;;
    rocky) family="rockylinux" ;;
    oraclelinux | oracle-linux | oracle_linux) family="oracle" ;;
    arch) family="archlinux" ;;
    esac
    printf '%s\n' "$family"
}

normalize_image_system() {
    local raw="${1:-}"
    local input prefix
    input="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    input="${input#images:}"
    input="${input#opsmaru:}"
    input="$(strip_image_separators "$input")"
    if [ -z "$input" ]; then
        return 1
    fi
    if [[ "$input" == */* ]]; then
        a="${input%%/*}"
        b="${input#*/}"
        b="${b%%/*}"
    else
        prefix="${input%%[0-9]*}"
        if [ "$prefix" != "$input" ]; then
            a="$prefix"
            b="${input#"$prefix"}"
        else
            a="$input"
            b=""
        fi
    fi
    a="$(strip_image_separators "$a")"
    b="$(strip_image_separators "$b")"
    a="$(canonical_image_family "$a")"
    normalized_system="${a}${b}"
    [ -n "$a" ]
}

remote_image_query() {
    if [ -n "${b:-}" ]; then
        printf '%s/%s\n' "$a" "$b"
    else
        printf '%s\n' "$a"
    fi
}

find_remote_image_alias() {
    local remote="$1"
    local image_type="$2"
    local query
    command -v lxc >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1
    query="$(remote_image_query)"
    lxc image list "${remote}:${query}" --format=json 2>/dev/null | jq -r --arg ARCHITECTURE "${sys_bit:-}" --arg ARCHITECTURE_ALT "${sys_bit_alt:-}" --arg IMAGE_TYPE "$image_type" '
        .[]?
        | select((.type // "") == $IMAGE_TYPE)
        | select($ARCHITECTURE == "" or (.architecture // "") == $ARCHITECTURE or ($ARCHITECTURE_ALT != "" and (.architecture // "") == $ARCHITECTURE_ALT))
        | .aliases[]?
        | .name // empty
        | select(length > 0)
    ' | head -n 1
}

format_disk_size() {
    if [[ $disk == *.* ]]; then
        disk_mb=$(awk -v disk="$disk" 'BEGIN { mb = int(disk * 1024); if (mb < 1) mb = 1; printf "%d", mb }')
        printf '%sMiB' "$disk_mb"
    else
        printf '%sGiB' "$disk"
    fi
}

get_kvm_images() {
    local api_urls=(
        "https://githubapi.spiritlhl.top"
        "https://api.github.com"
        "https://githubapi.spiritlhl.workers.dev"
    )
    for api_url in "${api_urls[@]}"; do
        local response
        response=$(curl -4 -s -m 6 "${api_url}/repos/oneclickvirt/lxd_images/releases/tags/kvm_images")
        if [ $? -eq 0 ] && echo "$response" | jq -e '.assets' >/dev/null 2>&1; then
            echo "$response" | jq -r '.assets[].name'
            return 0
        fi
        sleep 1
    done
    return 1
}

handle_image() {
    image_download_url=""
    fixed_system=false
    if [[ "$sys_bit" == "amd64" || "$sys_bit" == "arm64" ]]; then
        local kvm_images=()
        mapfile -t kvm_images < <(get_kvm_images)
        if [ ${#kvm_images[@]} -eq 0 ]; then
            echo "Failed to get KVM images list"
            echo "获取KVM镜像列表失败"
            check_standard_images || return 1
            return 0
        fi
        local target_images=()
        local cloud_images=()
        for image_name in "${kvm_images[@]}"; do
            if [ -z "${b}" ]; then
                if [[ "$image_name" == "${a}"*"${sys_bit}"*"kvm.zip" ]]; then
                    target_images+=("$image_name")
                    if [[ "$image_name" == *"cloud"* ]]; then
                        cloud_images+=("$image_name")
                    fi
                fi
            else
                if [[ "$image_name" == "${a}_${b}"*"${sys_bit}"*"kvm.zip" ]]; then
                    target_images+=("$image_name")
                    if [[ "$image_name" == *"cloud"* ]]; then
                        cloud_images+=("$image_name")
                    fi
                fi
            fi
        done
        local selected_image=""
        if [ ${#cloud_images[@]} -gt 0 ]; then
            selected_image="${cloud_images[0]}"
        elif [ ${#target_images[@]} -gt 0 ]; then
            selected_image="${target_images[0]}"
        fi
        if [ -n "$selected_image" ]; then
            fixed_system=true
            image_download_url="https://github.com/oneclickvirt/lxd_images/releases/download/kvm_images/${selected_image}"
            image_alias_output=$(ocv_image_alias_target "${a}${b}") || return 1
            local short_alias="${a}${b}"
            if [ -z "$image_alias_output" ]; then
                import_image "$selected_image" "$image_download_url" || return 1
                echo "A matching image exists and will be created using ${image_download_url}"
                echo "匹配的镜像存在，将使用 ${image_download_url} 进行创建"
            else
                system="$short_alias"
            fi
        fi
    fi
    if [ -z "$image_download_url" ]; then
        check_standard_images || return 1
    fi
}

import_image() {
    local image_name="$1"
    local image_url="$2"
    local short_alias="${a}${b}"
    local cached_target
    cached_target=$(ocv_image_alias_target "$short_alias") || return 1
    if [ -n "$cached_target" ]; then
        echo "Image $short_alias already exists, skipping import"
        echo "镜像 $short_alias 已存在，跳过导入"
        system="$short_alias"
        return 0
    fi
    if ! retry_wget "${cdn_success_url}${image_url}" "$image_name"; then
        echo "Failed to download image: $image_url"
        echo "镜像下载失败：$image_url"
        return 1
    fi
    chmod 777 "$image_name"
    if ! unzip "$image_name"; then
        rm -f -- "$image_name"
        echo "Failed to unzip image: $image_name"
        echo "镜像解压失败：$image_name"
        return 1
    fi
    rm -f -- "$image_name"
    if ! ocv_import_split_image lxd.tar.xz disk.qcow2 "$short_alias"; then
        rm -f -- lxd.tar.xz disk.qcow2
        echo "Failed to import image: $short_alias"
        echo "镜像导入失败：$short_alias"
        return 1
    fi
    rm -f -- lxd.tar.xz disk.qcow2
    system="$short_alias"
}

check_standard_images() {
    system="$(find_remote_image_alias images virtual-machine)"
    if [ -n "$system" ]; then
        echo "A matching image exists and will be created using images:${system}"
        echo "匹配的镜像存在，将使用 images:${system} 进行创建"
        fixed_system=false
        return
    fi
    system="$(find_remote_image_alias opsmaru virtual-machine)"
    if [ -n "$system" ]; then
        echo "A matching image exists and will be created using opsmaru:${system}"
        echo "匹配的镜像存在，将使用 opsmaru:${system} 进行创建"
        status_tuna=true
        fixed_system=false
    else
        status_tuna=false
    fi
    if [ -z "$image_download_url" ] && [ "$status_tuna" = false ]; then
        echo "No matching image found, please execute"
        echo "lxc image list images:system/version_number OR lxc image list opsmaru:system/version_number"
        echo "Check if a corresponding image exists"
        echo "未找到匹配的镜像，请执行"
        echo "lxc image list images:系统/版本号 或 lxc image list opsmaru:系统/版本号"
        echo "查询是否存在对应镜像"
        return 1
    fi
}

create_vm() {
    if lxc info "$name" >/dev/null 2>&1; then
        echo "Error: an instance named '$name' already exists." >&2
        echo "错误：名为 '$name' 的实例已存在。" >&2
        return 1
    fi
    rm -f -- "$name" || return 1
    disk_size=$(format_disk_size)
    if [ -z "$image_download_url" ] && [ "$status_tuna" = true ]; then
        if ! create_instance_with_tracking lxc init "opsmaru:${system}" "$name" --vm -c limits.cpu="$cpu" -c limits.memory="$memory"MiB -d root,size="$disk_size" -s "${storage_pool:-default}"; then
            echo "VM creation failed, please check the previous output message" >&2
            echo "虚拟机创建失败，请检查前面的输出信息" >&2
            return 1
        fi
    elif [ -z "$image_download_url" ]; then
        if ! create_instance_with_tracking lxc init "images:${system}" "$name" --vm -c limits.cpu="$cpu" -c limits.memory="$memory"MiB -d root,size="$disk_size" -s "${storage_pool:-default}"; then
            echo "VM creation failed, please check the previous output message" >&2
            echo "虚拟机创建失败，请检查前面的输出信息" >&2
            return 1
        fi
    else
        if ! create_instance_with_tracking lxc init "$system" "$name" --vm -c limits.cpu="$cpu" -c limits.memory="$memory"MiB -d root,size="$disk_size" -s "${storage_pool:-default}"; then
            echo "VM creation failed, please check the previous output message" >&2
            echo "虚拟机创建失败，请检查前面的输出信息" >&2
            return 1
        fi
    fi
    if ! lxc info "$name" >/dev/null 2>&1; then
        echo "VM creation did not produce instance '$name'." >&2
        echo "虚拟机创建后未找到实例 '$name'。" >&2
        return 1
    fi
}

configure_limits() {
    lxc config set "$name" security.secureboot false || return 1
}

setup_vm() {
    ori=$(date | md5sum)
    passwd=${ori:2:9}
    if ! start_lxd_instance "$name"; then
        echo "VM start failed: $name" >&2
        echo "虚拟机启动失败：$name" >&2
        return 1
    fi
    echo "Waiting for VM to start..."
    sleep 30
    max_retries=10
    local vm_ready=false
    for ((i=1; i<=max_retries; i++)); do
        echo "Attempt $i: Waiting for VM to be ready..."
        if lxc exec "$name" -- echo "VM is ready" 2>/dev/null; then
            vm_ready=true
            break
        fi
        sleep 10
    done
    if [ "$vm_ready" != true ]; then
        echo "Error: VM did not become ready for configuration." >&2
        echo "错误：虚拟机未就绪，已中止配置。" >&2
        return 1
    fi
    chmod 777 /usr/local/bin/check-dns.sh || return 1
    /usr/local/bin/check-dns.sh || return 1
    sleep 3
    if [ "$fixed_system" = false ]; then
        setup_mirror_and_packages || return 1
    fi
    setup_ssh || return 1
}

setup_mirror_and_packages() {
    if [[ "${CN}" == true ]]; then
        lxc exec "$name" -- sh -c 'if command -v yum >/dev/null 2>&1; then yum install -y curl; fi' || return 1
        lxc exec "$name" -- sh -c 'if command -v apt-get >/dev/null 2>&1; then apt-get install curl -y --fix-missing; fi' || return 1
        lxc exec "$name" -- curl -fLk https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh -o ChangeMirrors.sh || return 1
        lxc exec "$name" -- chmod 777 ChangeMirrors.sh || return 1
        lxc exec "$name" -- ./ChangeMirrors.sh --source mirrors.tuna.tsinghua.edu.cn --web-protocol http --intranet false --backup true --updata-software false --clean-cache false --ignore-backup-tips >/dev/null || return 1
        lxc exec "$name" -- rm -f -- ChangeMirrors.sh || return 1
    fi
    if echo "$system" | grep -qiE "centos|almalinux|fedora|rocky|oracle"; then
        lxc exec "$name" -- sudo yum update -y || return 1
        lxc exec "$name" -- sudo yum install -y curl dos2unix || return 1
    elif echo "$system" | grep -qiE "alpine"; then
        lxc exec "$name" -- apk update || return 1
        lxc exec "$name" -- apk add --no-cache curl || return 1
    elif echo "$system" | grep -qiE "archlinux"; then
        lxc exec "$name" -- pacman -Sy --noconfirm --needed curl dos2unix bash || return 1
    else
        lxc exec "$name" -- sudo apt-get update -y || return 1
        lxc exec "$name" -- sudo apt-get install curl dos2unix -y --fix-missing || return 1
    fi
}

setup_ssh() {
    setup_ssh_bash
}

setup_ssh_bash() {
    if [ ! -f /usr/local/bin/ssh_bash.sh ]; then
        download_host_file "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_bash.sh" /usr/local/bin/ssh_bash.sh || return 1
        chmod 777 /usr/local/bin/ssh_bash.sh || return 1
        dos2unix /usr/local/bin/ssh_bash.sh || return 1
    fi
    cp /usr/local/bin/ssh_bash.sh /root || return 1
    lxc file push /root/ssh_bash.sh "$name"/root/ || return 1
    lxc exec "$name" -- chmod 777 ssh_bash.sh || return 1
    lxc exec "$name" -- dos2unix ssh_bash.sh || return 1
    lxc exec "$name" -- sudo ./ssh_bash.sh "$passwd" || return 1
    if [ ! -f /usr/local/bin/config.sh ]; then
        download_host_file "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/config.sh" /usr/local/bin/config.sh || return 1
        chmod 777 /usr/local/bin/config.sh || return 1
        dos2unix /usr/local/bin/config.sh || return 1
    fi
    cp /usr/local/bin/config.sh /root || return 1
    lxc file push /root/config.sh "$name"/root/ || return 1
    lxc exec "$name" -- chmod +x config.sh || return 1
    lxc exec "$name" -- dos2unix config.sh || return 1
    lxc exec "$name" -- bash config.sh || return 1
    # history is a Bash builtin, not an executable in the container.
    lxc exec "$name" -- bash -c 'history -c' || return 1
}

wait_for_vm_ready_to_shutdown() {
    echo "Waiting for VM to complete initialization..."
    echo "等待虚拟机完成初始化配置..."
    local max_wait=18
    local check_interval=6
    local waited=0
    while [ "$waited" -lt "$max_wait" ]; do
        if lxc exec "$name" -- pgrep -f "apt|yum|pacman|apk" > /dev/null 2>&1; then
            echo "VM is executing package management operations, continue waiting..."
            echo "虚拟机正在执行包管理操作，继续等待..."
        elif lxc exec "$name" -- pgrep -f "ssh|sshd|config" > /dev/null 2>&1; then
            echo "VM is executing SSH configuration, continue waiting..."
            echo "虚拟机正在执行SSH配置，继续等待..."
        fi
        sleep "$check_interval"
        waited=$((waited + check_interval))
        echo "Waited ${waited} seconds..."
        echo "已等待 ${waited} 秒..."
    done
    if [ "$waited" -ge "$max_wait" ]; then
        echo "Wait timeout, forcing shutdown process..."
        echo "等待超时，强制继续关机流程..."
    fi
}

safe_shutdown_vm() {
    echo "Safely shutting down VM..."
    echo "正在安全关闭虚拟机..."
    if ! lxc stop "$name" --timeout=30; then
        echo "Error: failed to stop VM '$name'." >&2
        return 1
    fi
    local max_shutdown_wait=30
    local waited=0
    while [ "$waited" -lt "$max_shutdown_wait" ]; do
        local vm_status
        vm_status=$(lxc info "$name" | grep "Status:" | awk '{print $2}')
        if [ "$vm_status" = "STOPPED" ]; then
            echo "VM has been safely stopped"
            echo "虚拟机已安全停止"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
        echo "Waiting for VM to stop... (${waited}/${max_shutdown_wait}s)"
        echo "等待虚拟机停止... (${waited}/${max_shutdown_wait}秒)"
    done
    echo "Error: VM stop timed out; aborting configuration." >&2
    echo "错误：虚拟机停止超时，已中止配置。" >&2
    return 1
}

wait_for_instance_ssh_ready() {
    local max_wait="${1:-180}" interval=3 waited=0 started elapsed budget delay
    [[ "$max_wait" =~ ^[0-9]+$ ]] || max_wait=180
    while ((waited < max_wait)); do
        budget=$((max_wait - waited))
        ((budget <= 15)) || budget=15
        started=$SECONDS
        if timeout -k 2 "$budget" lxc exec "$name" -- sh -c 'awk '\''NR > 1 && $2 ~ /:0016$/ && $4 == "0A" { found=1 } END { exit !found }'\'' /proc/net/tcp /proc/net/tcp6' >/dev/null 2>&1; then
            return 0
        fi
        elapsed=$((SECONDS - started))
        ((elapsed > 0)) || elapsed=1
        waited=$((waited + elapsed))
        ((waited < max_wait)) || break
        delay=$interval
        ((waited + delay <= max_wait)) || delay=$((max_wait - waited))
        sleep "$delay" || return 1
        waited=$((waited + delay))
    done
    echo "Error: SSH server inside '$name' did not become ready within ${max_wait}s." >&2
    return 1
}

# Interface names differ between images and daemon versions. Accept one
# unambiguous global IPv4 from this exact instance, excluding loopback.
vm_ipv4_from_state() {
    jq -er --arg name "$name" '
        [.[] | select(.name == $name) | (.state.network // {}) | to_entries[] |
         select(.key != "lo") | .value.addresses[]? |
         select(.family == "inet" and (.scope // "global") == "global") | .address] |
        unique | if length == 1 then .[0] else error("guest IPv4 is absent or ambiguous") end
    '
}

configure_network() {
    lxc restart "$name" || return 1
    wait_for_instance_ssh_ready || return 1
    echo "Waiting for the VM to start. Attempting to retrieve the VM's IP address..."
    echo "等待虚拟机启动，尝试获取虚拟机IP地址..."
    max_retries=5
    delay=10
    vm_ip=""
    for ((i=1; i<=max_retries; i++)); do
        echo "Attempt $i: Waiting $delay seconds before retrieving VM info..."
        echo "尝试 $i: 等待 $delay 秒后获取虚拟机信息..."
        sleep $delay
        vm_ip=""
        if vm_info=$(lxc list "$name" --format json 2>/dev/null); then
            vm_ip=$(vm_ipv4_from_state <<<"$vm_info" 2>/dev/null) || vm_ip=""
        fi
        if [[ -n "$vm_ip" ]]; then
            echo "VM IPv4 address: $vm_ip"
            echo "虚拟机IPv4地址: $vm_ip"
            break
        fi
        delay=$((delay + 5))
    done
    if [[ -z "$vm_ip" ]]; then
        echo "Error: VM failed to start or no IP address was assigned."
        echo "错误：虚拟机启动失败或未分配IP地址"
        return 1
    fi
    ipv4_address=$(ip addr show | awk '/inet .*global/ && !/inet6/ {print $2}' | sed -n '1p' | cut -d/ -f1)
    echo "Host IPv4 address: $ipv4_address"
    echo "主机IPv4地址: $ipv4_address"
    if [ -n "$enable_ipv6" ]; then
        if [ "$enable_ipv6" == "y" ]; then
            echo "Configuring IPv6..."
            echo "配置IPv6..."
            ensure_container_ipv6_cron || return 1
            sleep 1
            if [ ! -f "./build_ipv6_network.sh" ]; then
                download_host_file "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/build_ipv6_network.sh" build_ipv6_network.sh || return 1
                chmod +x build_ipv6_network.sh || return 1
            fi
            ./build_ipv6_network.sh "$name" || return 1
        fi
    fi
    configure_firewall_ports
    wait_for_vm_ready_to_shutdown
    safe_shutdown_vm || return 1
    configure_network_limits || return 1
    set_ip_address_binding "$vm_ip" || return 1
    configure_port_mapping "$vm_ip" "$ipv4_address" || return 1
    start_lxd_instance "$name" || return 1
    wait_for_instance_ssh_ready || return 1
    echo "Network configuration completed successfully!"
    echo "网络配置成功完成！"
}

configure_firewall_ports() {
    if command -v firewall-cmd >/dev/null 2>&1; then
        echo "Configuring firewall-cmd ports..."
        firewall-cmd --permanent "--add-port=${sshn}/tcp"
        if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
            firewall-cmd --permanent "--add-port=${nat1}-${nat2}/tcp"
            firewall-cmd --permanent "--add-port=${nat1}-${nat2}/udp"
        fi
        firewall-cmd --reload
    elif command -v ufw >/dev/null 2>&1; then
        echo "Configuring ufw ports..."
        ufw allow "${sshn}/tcp"
        if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
            ufw allow "${nat1}:${nat2}/tcp"
            ufw allow "${nat1}:${nat2}/udp"
        fi
        ufw reload
    fi
}

configure_network_limits() {
    echo "Configuring network speed limits..."
    echo "配置网络限速..."
    if ((in == out)); then
        speed_limit="$in"
    else
        speed_limit=$(($in > $out ? $in : $out))
    fi
    if ! lxc config device override "$name" enp5s0 limits.egress="$out"Mbit limits.ingress="$in"Mbit limits.max="$speed_limit"Mbit 2>/dev/null; then
        echo "Failed to configure enp5s0, trying eth0..."
        if ! lxc config device override "$name" eth0 limits.egress="$out"Mbit limits.ingress="$in"Mbit limits.max="$speed_limit"Mbit 2>/dev/null; then
            lxc config device set "$name" eth0 limits.egress "$out"Mbit || return 1
            lxc config device set "$name" eth0 limits.ingress "$in"Mbit || return 1
            lxc config device set "$name" eth0 limits.max "$speed_limit"Mbit || return 1
        fi
    fi
}

set_ip_address_binding() {
    local vm_ip="$1"
    echo "Setting IP address binding to $vm_ip..."
    echo "设置IP地址绑定到 $vm_ip..."
    if ! lxc config device set "$name" enp5s0 ipv4.address "$vm_ip" 2>/dev/null; then
        if ! lxc config device override "$name" enp5s0 ipv4.address="$vm_ip" 2>/dev/null; then
            if ! lxc config device set "$name" eth0 ipv4.address "$vm_ip" 2>/dev/null; then
                if ! lxc config device override "$name" eth0 ipv4.address="$vm_ip" 2>/dev/null; then
                    echo "Error: Failed to bind IP address in VM '$name'." >&2
                    echo "错误：虚拟机 '$name' 的IP地址绑定失败。" >&2
                    return 1
                fi
            fi
        fi
    fi
}

configure_port_mapping() {
    local vm_ip="$1"
    local host_ip="$2"
    echo "Configuring port mapping..."
    echo "配置端口映射..."
    echo "Adding SSH port mapping: $host_ip:$sshn -> $vm_ip:22"
    replace_proxy_device ssh-port "listen=tcp:$host_ip:$sshn" "connect=tcp:$vm_ip:22" nat=true || return 1
    if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
        echo "Adding NAT TCP port mapping: $host_ip:$nat1-$nat2 -> $vm_ip:$nat1-$nat2"
        replace_proxy_device nattcp-ports "listen=tcp:$host_ip:$nat1-$nat2" "connect=tcp:$vm_ip:$nat1-$nat2" nat=true || return 1
        echo "Adding NAT UDP port mapping: $host_ip:$nat1-$nat2 -> $vm_ip:$nat1-$nat2"
        replace_proxy_device natudp-ports "listen=udp:$host_ip:$nat1-$nat2" "connect=udp:$vm_ip:$nat1-$nat2" nat=true || return 1
    else
        remove_device_if_exists nattcp-ports
        remove_device_if_exists natudp-ports
    fi
}

cleanup_and_finish() {
    rm -f -- ssh_bash.sh config.sh ssh_sh.sh
    local record record_tmp
    if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
        record="$name $sshn $passwd $nat1 $nat2"
    elif [ "$nat1" == "0" ] && [ "$nat2" == "0" ]; then
        record="$name $sshn $passwd"
    else
        return 1
    fi
    record_tmp="${name}.tmp.$$"
    if ! printf '%s\n' "$record" >"$record_tmp" || ! mv -f -- "$record_tmp" "$name"; then
        rm -f -- "$record_tmp"
        return 1
    fi
    printf '%s\n' "$record"
    return 0
}


# LXD 5.21 can briefly retain a routed VM tap route after stop completes.
# Retry only that reported conflict; never delete a route owned by the daemon.
start_lxd_instance() {
    local attempt output status
    for attempt in 1 2 3; do
        if output=$(timeout 60 lxc start "$1" 2>&1); then
            [ -z "$output" ] || printf '%s\n' "$output"
            return 0
        else
            status=$?
        fi
        printf '%s\n' "$output" >&2
        if [[ "$output" != *"Failed adding host route"* || "$output" != *"File exists"* || "$attempt" = 3 ]]; then
            return "$status"
        fi
        sleep "$((attempt * 3))"
    done
}

main() {
    check_vm_support || return 1
    name="${1:-test}"
    cpu="${2:-1}"
    memory="${3:-512}"
    disk="${4:-10}"
    sshn="${5:-20001}"
    nat1="${6:-20002}"
    nat2="${7:-20025}"
    in="${8:-10240}"
    out="${9:-10240}"
    enable_ipv6="${10:-N}"
    enable_ipv6=$(echo "$enable_ipv6" | tr '[:upper:]' '[:lower:]')
    system="${11:-debian11}"
    ensure_lxd_ready || return 1
    if ! normalize_image_system "$system"; then
        echo "Error: system must be a valid image name, such as debian11 or debian/11."
        echo "错误：系统名称必须有效，例如 debian11 或 debian/11。"
        return 1
    fi
    system="$normalized_system"
    detect_os
    validate_inputs || return 1
    install_dependencies || return 1
    detect_arch
    check_china
    cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")
    check_cdn_file
    handle_image || return 1
    create_vm || return 1
    configure_limits || return 1
    setup_vm || return 1
    configure_network || return 1
    cleanup_and_finish || return 1
    build_succeeded=true
}
if [[ "${ONECLICKVIRT_TESTING:-}" != "1" ]]; then
    main "$@"
fi
