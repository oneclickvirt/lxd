#!/usr/bin/env bash
# Resolve this before any helper changes directory to /root.  BASH_SOURCE can
# be relative when the script is invoked as `bash scripts/buildct.sh`.
OCV_BUILDCT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || OCV_BUILDCT_DIR=""
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


# 输入
# ./buildct.sh 服务器名称 CPU核数 内存大小 硬盘大小 SSH端口 外网起端口 外网止端口 下载速度 上传速度 是否启用IPV6(Y or N) 系统(留空则为debian12)
# 如果 外网起端口 外网止端口 都设置为0则不做区间外网端口映射了，只映射基础的SSH端口，注意不能为空，不进行映射需要设置为0

# Keep cleanup limited to instances that this invocation actually created.  A
# failed configuration must not leave an instance that later callers mistake
# for a successful result, nor may it remove a caller's pre-existing instance.
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

# 初始化变量和依赖检查
init_env() {
    cd /root >/dev/null 2>&1 || exit 1
    if ! command -v jq >/dev/null 2>&1; then
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

# 检测CDN可用性
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

# 获取系统架构
get_system_arch() {
    sys_bit=""
    sys_bit_alt=""
    self_image_arch=""
    sysarch="$(uname -m)"
    case "${sysarch}" in
    "x86_64" | "x86" | "amd64" | "x64")
        sys_bit="x86_64"
        sys_bit_alt="amd64"
        self_image_arch="x86_64"
        ;;
    "i386" | "i686")
        sys_bit="i686"
        sys_bit_alt="i386"
        self_image_arch=""
        ;;
    "aarch64" | "armv8" | "armv8l")
        sys_bit="aarch64"
        sys_bit_alt="arm64"
        self_image_arch="arm64"
        ;;
    "armv7l")
        sys_bit="armv7l"
        sys_bit_alt="armhf"
        self_image_arch=""
        ;;
    "s390x") sys_bit="s390x" ;;
    "ppc64le") sys_bit="ppc64le" ;;
    *)
        sys_bit="x86_64"
        sys_bit_alt="amd64"
        self_image_arch="x86_64"
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
        echo "Error: container name must not be empty, start with '-', or contain '/'."
        echo "错误：容器名称不能为空，不能以 '-' 开头，也不能包含 '/'。"
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

configure_ipv6_only_dns() {
    # IPv6-only instances have no managed IPv4 bridge to provide the usual
    # 127.0.0.53 stub. Install a small atomic resolver file using IPv6 DNS.
    lxc exec "$name" -- sh -c 'set -eu; if [ -L /etc/resolv.conf ]; then rm -f /etc/resolv.conf; fi; if [ -e /etc/resolv.conf ] && [ ! -f /etc/resolv.conf ]; then exit 1; fi; tmp=$(mktemp /etc/.resolv.conf.ocv.XXXXXX); printf "%s\n" "nameserver 2606:4700:4700::1111" "nameserver 2001:4860:4860::8888" >"$tmp"; chmod 0644 "$tmp"; mv -f "$tmp" /etc/resolv.conf'
}

normalize_network_type() {
    network_type=$(printf '%s' "${OCV_NETWORK_TYPE:-}" | tr '[:upper:]' '[:lower:]')
    enable_ipv6=$(printf '%s' "${enable_ipv6:-n}" | tr '[:upper:]' '[:lower:]')
    if [ -z "$network_type" ]; then
        if [ "${enable_ipv6:-n}" = "y" ]; then
            network_type="nat_ipv4_ipv6"
        else
            network_type="nat_ipv4"
        fi
    fi
    case "$network_type" in
    nat_ipv4)
        enable_ipv6="n"
        ;;
    nat_ipv4_ipv6)
        enable_ipv6="y"
        ;;
    ipv6_only)
        enable_ipv6="y"
        ;;
    *)
        echo "Error: OCV_NETWORK_TYPE must be nat_ipv4, nat_ipv4_ipv6, or ipv6_only." >&2
        echo "错误：OCV_NETWORK_TYPE 必须为 nat_ipv4、nat_ipv4_ipv6 或 ipv6_only。" >&2
        return 1
        ;;
    esac
}

require_public_ipv6_result() {
    case "${OCV_REQUIRE_PUBLIC_IPV6:-no}" in
    1 | true | TRUE | yes | YES) ;;
    *) return 0 ;;
    esac
    local record="${name}_v6" address
    if [ ! -s "$record" ]; then
        echo "Error: independent public IPv6 was required, but IPv6 setup only produced a fallback or no address." >&2
        echo "错误：当前模式要求独立公网 IPv6，但 IPv6 配置仅生成了回退网络或未分配地址。" >&2
        return 1
    fi
    address=$(tail -n 1 "$record")
    python3 - "$address" <<'PY'
import ipaddress
import sys
try:
    address = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if address.version == 6 and address.is_global else 1)
PY
}

# A previous installer run may have left an older helper in /root.  Never
# silently reuse it: prefer the versioned helper next to this script, or
# download and validate the current marker before replacing the cached copy.
refresh_ipv6_helper() {
    local target="${1:-./build_ipv6_network.sh}" source_path script_path temporary
    local marker='# oneclickvirt-ipv6-helper-version: 2026.09.20'
    script_path="${OCV_BUILDCT_DIR:-}"
    source_path="$script_path/build_ipv6_network.sh"
    if [ -f "$source_path" ] && grep -Fqx "$marker" "$source_path"; then
        if ! cmp -s "$source_path" "$target"; then
            cp -f -- "$source_path" "$target" || return 1
        fi
        chmod +x "$target" || return 1
        return 0
    fi
    if [ -f "$target" ] && grep -Fqx "$marker" "$target"; then
        chmod +x "$target" || return 1
        return 0
    fi
    temporary=$(mktemp "${target}.tmp.XXXXXX") || return 1
    if ! download_host_file "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/build_ipv6_network.sh" "$temporary" ||
       ! grep -Fqx "$marker" "$temporary"; then
        rm -f -- "$temporary"
        echo "Error: downloaded IPv6 helper is missing the expected version marker." >&2
        return 1
    fi
    chmod +x "$temporary" && mv -f -- "$temporary" "$target"
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

image_name_matches_system() {
    local image_name="$1"
    [ -n "${a:-}" ] || return 1
    if [ -z "${b:-}" ]; then
        [[ "$image_name" == "${a}_"* ]]
        return
    fi
    [[ "$image_name" == "${a}_${b}"* ]]
}

find_matching_image_from_stream() {
    local image_name
    while IFS= read -r image_name; do
        [ -n "$image_name" ] || continue
        if image_name_matches_system "$image_name"; then
            printf '%s\n' "$image_name"
            return 0
        fi
    done
    return 1
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

# 处理镜像
process_image() {
    image_download_url=""
    image_name=""
    fixed_system=false
    status_tuna=false
    if [ -n "${self_image_arch:-}" ]; then
        process_self_fixed_images || return 1
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
    local matched_image
    matched_image=$(curl -fsSLk -m 10 "${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd_images/main/${self_image_arch}_all_images.txt" 2>/dev/null | find_matching_image_from_stream)
    if [ -n "$matched_image" ]; then
        use_fixed_image "$matched_image" || return 1
    fi
}

# 使用固定镜像
use_fixed_image() {
    # This is the selected image consumed by create_container after returning,
    # not a temporary download-only name (Bash locals do not survive the call).
    image_name="$1"
    fixed_system=true
    image_download_url="https://github.com/oneclickvirt/lxd_images/releases/download/${a}/${image_name}"
    image_alias_output=$(ocv_image_alias_target "$image_name") || return 1
    if [ -z "$image_alias_output" ]; then
        if ! wget "${cdn_success_url}${image_download_url}"; then
            echo "Failed to download image: ${image_download_url}"
            echo "镜像下载失败：${image_download_url}"
            return 1
        fi
        chmod 777 "$image_name"
        if ! unzip "$image_name"; then
            rm -f -- "$image_name"
            echo "Failed to unzip image: ${image_name}"
            echo "镜像解压失败：${image_name}"
            return 1
        fi
        rm -f -- "$image_name"
        if ! ocv_import_split_image lxd.tar.xz rootfs.squashfs "$image_name"; then
            rm -f -- lxd.tar.xz rootfs.squashfs
            echo "Failed to import image: ${image_name}"
            echo "镜像导入失败：${image_name}"
            return 1
        fi
        rm -f -- lxd.tar.xz rootfs.squashfs
        echo "A matching image exists and will be created using ${image_download_url}"
        echo "匹配的镜像存在，将使用 ${image_download_url} 进行创建"
    fi
}

# 处理images仓库
process_images_repository() {
    system="$(find_remote_image_alias images container)"
    if [ -n "$system" ]; then
        echo "A matching image exists and will be created using images:${system}"
        echo "匹配的镜像存在，将使用 images:${system} 进行创建"
        fixed_system=false
    fi
}

# 处理opsmaru仓库
process_opsmaru_repository() {
    system="$(find_remote_image_alias opsmaru container)"
    if [ -n "$system" ]; then
        echo "A matching image exists and will be created using opsmaru:${system}"
        echo "匹配的镜像存在，将使用 opsmaru:${system} 进行创建"
        status_tuna=true
        fixed_system=false
    else
        status_tuna=false
    fi
    if [ "$status_tuna" = false ]; then
        echo "No matching image found, please execute"
        echo "lxc image list images:system/version_number OR lxc image list opsmaru:system/version_number"
        echo "Check if a corresponding image exists"
        echo "未找到匹配的镜像，请执行"
        echo "lxc image list images:系统/版本号 或 lxc image list opsmaru:系统/版本号"
        echo "查询是否存在对应镜像"
        return 1
    fi
}

# 创建容器
create_container() {
    if lxc info "$name" >/dev/null 2>&1; then
        echo "Error: an instance named '$name' already exists." >&2
        echo "错误：名为 '$name' 的实例已存在。" >&2
        return 1
    fi
    rm -f -- "$name" || return 1
    # 计算硬盘大小参数
    if [[ $disk == *.* ]]; then
        # 小数硬盘大小，转换为 MiB
        disk_mb=$(awk -v disk="$disk" 'BEGIN { mb = int(disk * 1024); if (mb < 1) mb = 1; printf "%d", mb }')
        disk_param=(-d "root,size=${disk_mb}MiB")
    else
        # 整数硬盘大小，使用 GiB
        disk_param=(-d "root,size=${disk}GiB")
    fi
    
    if [ -z "$image_download_url" ] && [ "$status_tuna" = true ]; then
        if ! create_instance_with_tracking lxc init "opsmaru:${system}" "$name" -c limits.cpu="$cpu" -c limits.memory="$memory"MiB "${disk_param[@]}" -s "${storage_pool:-default}"; then
            echo "Container creation failed, please check the previous output message" >&2
            echo "容器创建失败，请检查前面的输出信息" >&2
            return 1
        fi
    elif [ -z "$image_download_url" ]; then
        if ! create_instance_with_tracking lxc init "images:${system}" "$name" -c limits.cpu="$cpu" -c limits.memory="$memory"MiB "${disk_param[@]}" -s "${storage_pool:-default}"; then
            echo "Container creation failed, please check the previous output message" >&2
            echo "容器创建失败，请检查前面的输出信息" >&2
            return 1
        fi
    else
        if ! create_instance_with_tracking lxc init "$image_name" "$name" -c limits.cpu="$cpu" -c limits.memory="$memory"MiB "${disk_param[@]}" -s "${storage_pool:-default}"; then
            echo "Container creation failed, please check the previous output message" >&2
            echo "容器创建失败，请检查前面的输出信息" >&2
            return 1
        fi
    fi
    if ! lxc info "$name" >/dev/null 2>&1; then
        echo "Container creation did not produce instance '$name'." >&2
        echo "容器创建后未找到实例 '$name'。" >&2
        return 1
    fi
}

# 配置存储限制
configure_storage() {
    # 硬盘大小已在创建容器时通过 -d root,size=... 参数设置
    # 这里只设置额外的硬盘配额限制
    if [[ $disk == *.* ]]; then
        disk_mb=$(awk -v disk="$disk" 'BEGIN { mb = int(disk * 1024); if (mb < 1) mb = 1; printf "%d", mb }')
        lxc config device set "$name" root limits.max "$disk_mb"MiB || return 1
    else
        lxc config device set "$name" root limits.max "$disk"GiB || return 1
    fi
}

# 配置IO限制
configure_io() {
    lxc config device set "$name" root limits.read 500MB || return 1
    lxc config device set "$name" root limits.write 500MB || return 1
    lxc config device set "$name" root limits.read 5000iops || return 1
    lxc config device set "$name" root limits.write 5000iops || return 1
}

# 配置CPU限制
configure_cpu() {
    lxc config set "$name" limits.cpu.priority 0 || return 1
    lxc config set "$name" limits.cpu.allowance 50% || return 1
    lxc config set "$name" limits.cpu.allowance 25ms/100ms || return 1
}

# 配置内存限制
configure_memory() {
    lxc config set "$name" limits.memory.swap true || return 1
    lxc config set "$name" limits.memory.swap.priority 1 || return 1
}

# 配置安全设置
configure_security() {
    lxc config set "$name" security.nesting true || return 1
}

# 安装和配置系统
setup_system() {
    ori=$(date | md5sum)
    passwd=${ori:2:9}
    if ! lxc start "$name"; then
        echo "Container start failed: $name" >&2
        echo "容器启动失败：$name" >&2
        return 1
    fi
    sleep 3
    /usr/local/bin/check-dns.sh || return 1
    sleep 3
    if [ "$fixed_system" = false ]; then
        setup_mirrors || return 1
        install_packages || return 1
    fi
    setup_ssh || return 1
    configure_ipv6 || return 1
}

# 设置镜像源
setup_mirrors() {
    if [[ "${CN}" == true ]]; then
        lxc exec "$name" -- sh -c 'if command -v yum >/dev/null 2>&1; then yum install -y curl; fi' || return 1
        lxc exec "$name" -- sh -c 'if command -v apt-get >/dev/null 2>&1; then apt-get install curl -y --fix-missing; fi' || return 1
        lxc exec "$name" -- curl -fLk https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh -o ChangeMirrors.sh || return 1
        lxc exec "$name" -- chmod 777 ChangeMirrors.sh || return 1
        lxc exec "$name" -- ./ChangeMirrors.sh --source mirrors.tuna.tsinghua.edu.cn --web-protocol http --intranet false --backup true --updata-software false --clean-cache false --ignore-backup-tips || return 1
        lxc exec "$name" -- rm -f -- ChangeMirrors.sh || return 1
    fi
}

# 安装必要软件包
install_packages() {
    if echo "$system" | grep -qiE "centos|almalinux|fedora|rocky|oracle"; then
        lxc exec "$name" -- sudo yum update -y || return 1
        lxc exec "$name" -- sudo yum install -y curl dos2unix || return 1
    elif echo "$system" | grep -qiE "alpine"; then
        lxc exec "$name" -- apk update || return 1
        lxc exec "$name" -- apk add --no-cache curl || return 1
    elif echo "$system" | grep -qiE "openwrt"; then
        lxc exec "$name" -- opkg update || return 1
    elif echo "$system" | grep -qiE "archlinux"; then
        lxc exec "$name" -- pacman -Sy --noconfirm --needed curl dos2unix bash || return 1
    else
        lxc exec "$name" -- sudo apt-get update -y || return 1
        lxc exec "$name" -- sudo apt-get install curl dos2unix -y --fix-missing || return 1
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
        download_host_file "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_sh.sh" /usr/local/bin/ssh_sh.sh || return 1
        chmod 777 /usr/local/bin/ssh_sh.sh || return 1
        dos2unix /usr/local/bin/ssh_sh.sh || return 1
    fi
    cp /usr/local/bin/ssh_sh.sh /root || return 1
    lxc file push /root/ssh_sh.sh "$name"/root/ || return 1
    lxc exec "$name" -- chmod 777 ssh_sh.sh || return 1
    lxc exec "$name" -- ./ssh_sh.sh "$passwd" || return 1
}

# 配置其他系统的SSH
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

configure_port() {
    lxc restart "$name" || return 1
    echo "Waiting for the container to start. Attempting to retrieve the container's IP address..."
    max_retries=3
    delay=5
    container_ip=""
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
        return 1
    fi
    ipv4_address=$(ip addr show | awk '/inet .*global/ && !/inet6/ {print $2}' | sed -n '1p' | cut -d/ -f1)
    echo "Host IPv4 address: $ipv4_address"
    if ! lxc config device override "$name" eth0 ipv4.address="$container_ip" 2>/dev/null; then
        if ! lxc config device set "$name" eth0 ipv4.address "$container_ip" 2>/dev/null; then
            echo "Error: Failed to set ipv4.address for device 'eth0' in container '$name'." >&2
            return 1
        fi
    fi
    if [ "$network_type" != "ipv6_only" ]; then
        replace_proxy_device ssh-port "listen=tcp:$ipv4_address:$sshn" "connect=tcp:$container_ip:22" nat=true || return 1
    else
        remove_device_if_exists ssh-port
    fi
    if [ "$network_type" != "ipv6_only" ] && [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
        replace_proxy_device nattcp-ports "listen=tcp:$ipv4_address:$nat1-$nat2" "connect=tcp:0.0.0.0:$nat1-$nat2" nat=true || return 1
        replace_proxy_device natudp-ports "listen=udp:$ipv4_address:$nat1-$nat2" "connect=udp:0.0.0.0:$nat1-$nat2" nat=true || return 1
    else
        remove_device_if_exists nattcp-ports
        remove_device_if_exists natudp-ports
    fi
}

# 配置IPv6
configure_ipv6() {
    if [ -n "$enable_ipv6" ]; then
        if [ "$enable_ipv6" == "y" ]; then
            ensure_container_ipv6_cron || return 1
            sleep 1
            refresh_ipv6_helper ./build_ipv6_network.sh || return 1
            ./build_ipv6_network.sh "$name" || return 1
            require_public_ipv6_result || return 1
        fi
    fi
}

wait_for_container_ready_to_shutdown() {
    echo "Waiting for container to complete initialization..."
    echo "等待容器完成初始化配置..."
    local max_wait=18
    local check_interval=6
    local waited=0
    while [ "$waited" -lt "$max_wait" ]; do
        if lxc exec "$name" -- pgrep -f "apt|yum|pacman|apk|opkg" > /dev/null 2>&1; then
            echo "Container is executing package management operations, continuing to wait..."
            echo "容器正在执行包管理操作，继续等待..."
        elif lxc exec "$name" -- pgrep -f "ssh|sshd|config" > /dev/null 2>&1; then
            echo "Container is executing SSH configuration, continuing to wait..."
            echo "容器正在执行SSH配置，继续等待..."
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

safe_shutdown_container() {
    echo "Safely shutting down container..."
    echo "正在安全关闭容器..."
    if ! lxc stop "$name" --timeout=30; then
        echo "Error: failed to stop container '$name'." >&2
        return 1
    fi
    local max_shutdown_wait=30
    local waited=0
    while [ "$waited" -lt "$max_shutdown_wait" ]; do
        local container_status
        container_status=$(lxc list "$name" --format=json 2>/dev/null |
            jq -er --arg name "$name" '[.[] | select(.name == $name) | .status_code] |
                if length == 1 then .[0] else error("container status is unavailable") end') || return 1
        if [ "$container_status" = 102 ]; then
            echo "Container has been safely stopped"
            echo "容器已安全停止"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
        echo "Waiting for container to stop... (${waited}/${max_shutdown_wait}s)"
        echo "等待容器停止... (${waited}/${max_shutdown_wait}秒)"
    done
    echo "Error: container stop timed out; aborting configuration." >&2
    echo "错误：容器停止超时，已中止配置。" >&2
    return 1
}

configure_network_speed() {
    wait_for_container_ready_to_shutdown
    safe_shutdown_container || return 1
    if ((in == out)); then
        speed_limit="$in"
    else
        speed_limit=$(($in > $out ? $in : $out))
    fi
    if [ "$network_type" = "ipv6_only" ]; then
        # The default profile's eth0 otherwise keeps private IPv4/DHCP/NAT
        # alive even though no IPv4 proxy devices were created.  Mask that
        # inherited NIC locally and apply limits to the routed IPv6 device.
        lxc config device remove "$name" eth0 >/dev/null 2>&1 || true
        lxc config device add "$name" eth0 none || return 1
        lxc config device set "$name" eth1 limits.egress "$out"Mbit || return 1
        lxc config device set "$name" eth1 limits.ingress "$in"Mbit || return 1
        lxc config device set "$name" eth1 limits.max "$speed_limit"Mbit || return 1
    else
        lxc config device set "$name" eth0 limits.egress "$out"Mbit || return 1
        lxc config device set "$name" eth0 limits.ingress "$in"Mbit || return 1
        lxc config device set "$name" eth0 limits.max "$speed_limit"Mbit || return 1
    fi
    lxc start "$name" || return 1
    if [ "$network_type" = "ipv6_only" ]; then
        configure_ipv6_only_dns || return 1
    fi
}

cleanup_and_output() {
    rm -f -- ssh_bash.sh config.sh ssh_sh.sh
    if echo "$system" | grep -qiE "alpine"; then
        sleep 3
        lxc stop "$name" --timeout=30 || return 1
        lxc start "$name" || return 1
    fi
    local record record_tmp
    if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
        record="$name $sshn $passwd $nat1 $nat2"
    elif [ "$nat1" == "0" ] && [ "$nat2" == "0" ]; then
        record="$name $sshn $passwd"
    else
        return 1
    fi
    lxc config set "$name" user.description "$record" || return 1
    record_tmp="${name}.tmp.$$"
    if ! printf '%s\n' "$record" >"$record_tmp" || ! mv -f -- "$record_tmp" "$name"; then
        rm -f -- "$record_tmp"
        return 1
    fi
    printf '%s\n' "$record"
    return 0
}

main() {
    init_env || return 1
    check_china
    cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")
    check_cdn_file || return 1
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
    normalize_network_type || return 1
    system="${11:-debian12}"
    ensure_lxd_ready || return 1
    if ! normalize_image_system "$system"; then
        echo "Error: system must be a valid image name, such as debian12 or debian/12."
        echo "错误：系统名称必须有效，例如 debian12 或 debian/12。"
        return 1
    fi
    system="$normalized_system"
    validate_inputs || return 1
    get_system_arch
    process_image || return 1
    create_container || return 1
    configure_storage || return 1
    configure_io || return 1
    configure_cpu || return 1
    configure_memory || return 1
    configure_security || return 1
    setup_system || return 1
    configure_port || return 1
    configure_ipv6 || return 1
    configure_network_speed || return 1
    cleanup_and_output || return 1
    build_succeeded=true
}

if [[ "${ONECLICKVIRT_TESTING:-}" != "1" ]]; then
    main "$@"
fi
