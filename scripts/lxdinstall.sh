#!/bin/bash
# by https://github.com/oneclickvirt/lxd
# 2026.08.30

# 一键安装（交互式）：
# curl -L https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/lxdinstall.sh -o lxdinstall.sh && chmod +x lxdinstall.sh && bash lxdinstall.sh
#
# 一键安装（无交互，环境变量预定义）：
# export noninteractive=true
# export DISK_NUMS=40
# bash lxdinstall.sh
#
# export noninteractive=true
# export DISK_NUMS=40
# export STORAGE_PATH=/data/lxd-storage
# bash lxdinstall.sh
#
# 可用环境变量：
#   noninteractive=true        跳过所有交互提示，使用默认值或其他环境变量
#   DISK_NUMS=<正整数>          存储池大小（单位 GB），如 DISK_NUMS=40
#   STORAGE_PATH=<绝对路径>     自定义存储路径，如 STORAGE_PATH=/data/lxd-storage
#   WITHOUTCDN=true            跳过 CDN 加速
#   CN=true                    强制使用中国镜像

cd /root >/dev/null 2>&1 || exit 1
REGEX=("debian|astra" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "amazon[[:space:]]+linux" "fedora" "arch|manjaro" "alpine" "freebsd")
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
TRIED_STORAGE_FILE="/usr/local/bin/lxd_tried_storage"
INSTALLED_STORAGE_FILE="/usr/local/bin/lxd_installed_storage"
STORAGE_POOL_FILE="/usr/local/bin/lxd_storage_pool"
MANAGED_STORAGE_POOL="oneclickvirt"
LEGACY_TRIED_STORAGE_FILE="/usr/local/bin/incus_tried_storage"
LEGACY_INSTALLED_STORAGE_FILE="/usr/local/bin/incus_installed_storage"
if [ ! -d "/usr/local/bin" ]; then
    mkdir -p /usr/local/bin
fi
[ ! -f "$TRIED_STORAGE_FILE" ] && [ -f "$LEGACY_TRIED_STORAGE_FILE" ] && cp "$LEGACY_TRIED_STORAGE_FILE" "$TRIED_STORAGE_FILE"
[ ! -f "$INSTALLED_STORAGE_FILE" ] && [ -f "$LEGACY_INSTALLED_STORAGE_FILE" ] && cp "$LEGACY_INSTALLED_STORAGE_FILE" "$INSTALLED_STORAGE_FILE"

# An existing pool may contain instances and volumes from an earlier
# installation. It is never safe for this installer to replace it.
storage_pool_exists() {
    local pool_name="${1:-default}"
    /snap/bin/lxc storage show "$pool_name" >/dev/null 2>&1
}

# `lxc query` returns an API envelope on real daemons while test doubles and
# older wrappers may return the metadata object directly.  Normalize both
# forms before inspecting profile/network fields.
# JSON inventories work on LTS clients whose storage/network list has no -c.
# Capture the command first so a daemon failure cannot become an empty list.
runtime_resource_names() {
    local data
    data=$(lxc "$1" list --format json) || return 1
    jq -sr '
        if length != 1 or (.[0] | type) != "array" then error("invalid runtime inventory")
        else .[0] end |
        if all(.[]; type == "object" and (.name | type) == "string" and (.name | length) > 0)
        then .[].name else error("invalid resource name") end
    ' <<<"$data"
}

api_metadata() {
    # Slurp first: jq 1.6 can exit successfully on empty input even with -e.
    # Exactly one object is required before any default-setting mutation.
    jq -cs --arg resource "${1:-object}" '
        if length != 1 or (.[0] | type) != "object"
        then error("expected one API object") else .[0] end |
        if has("metadata") then
            if .type == "sync" and (.metadata | type) == "object"
               and ((has("status_code") | not) or .status_code == 200)
            then .metadata else error("invalid API envelope") end
        elif .type == "error" or .type == "async" or .type == "sync"
        then error("invalid API response") else . end |
        if $resource == "profile" then
            if (.devices | type) == "object"
               and all(.devices[]; type == "object" and all(.[]; type == "string"))
            then . else error("invalid profile devices") end
        elif $resource == "network" then
            if .type == "bridge" and .managed == true
               and (.config | type) == "object" and all(.config[]; type == "string")
            then . else error("invalid managed bridge configuration") end
        else . end
    '
}

valid_storage_pool_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
}

active_storage_pool() {
    local pool_name=""
    if [ -r "$STORAGE_POOL_FILE" ]; then
        IFS= read -r pool_name <"$STORAGE_POOL_FILE" || true
        if valid_storage_pool_name "$pool_name" && storage_pool_exists "$pool_name"; then
            printf '%s\n' "$pool_name"
            return 0
        fi
    fi
    # Prefer the pool referenced by an existing default profile, including
    # common names such as "local". Do not reinitialize a partially set up host.
    pool_name=$(/snap/bin/lxc query /1.0/profiles/default 2>/dev/null | api_metadata |
        jq -r '[.devices[]? | select(.type == "disk" and .path == "/") | .pool // empty] | if length == 1 then .[0] else empty end' 2>/dev/null)
    if valid_storage_pool_name "$pool_name" && storage_pool_exists "$pool_name"; then
        printf '%s\n' "$pool_name"
        return 0
    fi
    if storage_pool_exists default; then
        printf '%s\n' default
        return 0
    fi
    local pools
    pools=$(runtime_resource_names storage) || return 2
    if [ -n "$pools" ]; then
        if [[ "$pools" != *$'\n'* ]] && valid_storage_pool_name "$pools" && storage_pool_exists "$pools"; then
            printf '%s\n' "$pools"
            return 0
        fi
        _red "Multiple storage pools exist; set STORAGE_POOL_FILE to the pool to reuse" >&2
        return 2
    fi
    return 1
}

record_storage_pool() {
    local pool_name="$1"
    valid_storage_pool_name "$pool_name" || return 1
    printf '%s\n' "$pool_name" >"$STORAGE_POOL_FILE"
}

_red() { printf '\033[31m\033[01m%s\033[0m\n' "$*"; }
_green() { printf '\033[32m\033[01m%s\033[0m\n' "$*"; }
_yellow() { printf '\033[33m\033[01m%s\033[0m\n' "$*"; }
_blue() { printf '\033[36m\033[01m%s\033[0m\n' "$*"; }
reading() { read -rp "$(_green "$1")" "$2"; }

is_true() {
    local value
    value=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
    [ "$value" = "true" ] || [ "$value" = "1" ] || [ "$value" = "yes" ] || [ "$value" = "y" ]
}

is_noninteractive() {
    noninteractive="${noninteractive:-${NONINTERACTIVE:-}}"
    export noninteractive
    is_true "$noninteractive"
}

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

wait_for_lxd_daemon_ready() {
    local max_wait="${1:-120}"
    local elapsed=0
    while [ "$elapsed" -lt "$max_wait" ]; do
        if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet snap.lxd.daemon 2>/dev/null; then
            if command -v timeout >/dev/null 2>&1; then
                timeout 15 lxc info >/dev/null 2>&1 && return 0
            else
                lxc info >/dev/null 2>&1 && return 0
            fi
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

restart_lxd_daemon_safely() {
    if ! command -v systemctl >/dev/null 2>&1; then
        service_manager restart snap.lxd.daemon
        return $?
    fi

    # Ubuntu 24.04 with the LXD 5.21 snap can leave daemon.stop waiting
    # forever after a reboot (the daemon repeatedly reports fanotify event 0).
    # Queue the restart without blocking the installer, then bound the wait.
    systemctl restart --no-block snap.lxd.daemon 2>/dev/null || return 1
    if wait_for_lxd_daemon_ready 120; then
        return 0
    fi

    _yellow "LXD daemon restart timed out; forcing the stuck stop job to recover"
    _yellow "LXD 守护进程重启超时，正在强制恢复卡住的停止任务"
    systemctl kill --kill-who=all --signal=SIGKILL snap.lxd.daemon 2>/dev/null || true
    systemctl reset-failed snap.lxd.daemon 2>/dev/null || true
    systemctl start --no-block snap.lxd.daemon 2>/dev/null || return 1
    if wait_for_lxd_daemon_ready 120; then
        return 0
    fi

    _red "LXD daemon did not become ready after forced recovery"
    _red "强制恢复后 LXD 守护进程仍未就绪"
    return 1
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
    local package_name="$1"
    local status=0
    if command -v "$package_name" >/dev/null 2>&1; then
        _green "$package_name has been installed"
        _green "$package_name 已经安装"
        return 0
    else
        if [ "$SYSTEM" = "Alpine" ] && command -v apk >/dev/null 2>&1; then
            apk add --no-cache "$package_name" || status=$?
        elif [ "$SYSTEM" = "Arch" ] && command -v pacman >/dev/null 2>&1; then
            pacman -S --noconfirm --needed "$package_name" || status=$?
        elif command -v apt-get >/dev/null 2>&1; then
            if ! apt-get install -y "$package_name"; then
                apt-get install -y "$package_name" --fix-missing || status=$?
            fi
        elif command -v yum >/dev/null 2>&1; then
            yum install -y "$package_name" || status=$?
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y "$package_name" || status=$?
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache "$package_name" || status=$?
        elif command -v pacman >/dev/null 2>&1; then
            pacman -S --noconfirm --needed "$package_name" || status=$?
        else
            _yellow "No supported package manager found"
            _yellow "未找到支持的包管理器"
            return 1
        fi
        if [ "$status" -ne 0 ]; then
            _red "Failed to install $package_name"
            _red "$package_name 安装失败"
            return "$status"
        fi
        _green "$package_name has attempted to install"
        _green "$package_name 已尝试安装"
    fi
}

# A minimal Debian/Ubuntu host may have the LXD snap and no host dnsmasq
# executable.  LXD still delegates managed bridge DNS checks to dnsmasq, so
# make this dependency explicit instead of allowing initialization to fail
# after the runtime package has already been installed.
install_dnsmasq() {
    command -v dnsmasq >/dev/null 2>&1 && return 0
    local package_name=dnsmasq
    if command -v apt-get >/dev/null 2>&1; then
        package_name=dnsmasq-base
    fi
    install_package "$package_name" || return 1
    command -v dnsmasq >/dev/null 2>&1 || {
        _red "dnsmasq was installed but the executable is unavailable"
        return 1
    }
}

# Other vendor sysctl files can contain unsupported optional keys. Validate
# the forwarding file we own and the effective value before declaring ready.
apply_forwarding_config() {
    local config_file="$1"
    if sysctl --help 2>&1 | grep -q -- '--system'; then
        if ! sysctl --system >/dev/null 2>&1; then
            sysctl -p "$config_file" >/dev/null 2>&1 || return 1
        fi
    else
        sysctl -p "$config_file" >/dev/null 2>&1 || return 1
    fi
    [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" = "1" ] || {
        _red "Required IPv4 forwarding is not enabled"
        return 1
    }
}

# uidmap is a Debian package name; other distributions use shadow packages.
install_uidmap() {
    if command -v newuidmap >/dev/null 2>&1 && command -v newgidmap >/dev/null 2>&1; then
        return 0
    fi
    if command -v apt-get >/dev/null 2>&1; then
        install_package uidmap || return 1
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        install_package shadow-utils || return 1
    elif command -v apk >/dev/null 2>&1; then
        install_package shadow-uidmap || install_package shadow || return 1
    elif command -v pacman >/dev/null 2>&1; then
        install_package shadow || return 1
    else
        _red "No supported package manager found for uidmap"
        return 1
    fi
    if ! command -v newuidmap >/dev/null 2>&1 || ! command -v newgidmap >/dev/null 2>&1; then
        _red "newuidmap/newgidmap are still unavailable after package installation"
        return 1
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

download_file() {
    local url="$1"
    local output="$2"
    if ! curl -fsSLk "${cdn_success_url}${url}" -o "$output"; then
        _red "Failed to download: ${url}"
        _red "下载失败：${url}"
        exit 1
    fi
}

ensure_lxc_path() {
    # SSH commands and services do not load interactive aliases or snap's
    # login profile. Install a stable CLI entry point without replacing any
    # existing administrator/package-owned command.
    if [ -x /snap/bin/lxc ] && [ ! -e /usr/local/bin/lxc ] && [ ! -L /usr/local/bin/lxc ]; then
        mkdir -p /usr/local/bin || return 1
        ln -s /snap/bin/lxc /usr/local/bin/lxc || return 1
    fi
    export PATH="$PATH:/snap/bin"
    lxc -h >/dev/null 2>&1
}

statistics_of_run_times() {
    COUNT=$(curl -4 -ksm1 "https://hits.spiritlhl.net/lxd?action=hit&title=Hits&title_bg=%23555555&count_bg=%2324dde1&edge_flat=false" 2>/dev/null ||
        curl -6 -ksm1 "https://hits.spiritlhl.net/lxd?action=hit&title=Hits&title_bg=%23555555&count_bg=%2324dde1&edge_flat=false" 2>/dev/null)
    TODAY=$(echo "$COUNT" | grep -oE '"daily":[[:space:]]*[0-9]+' | sed 's/"daily":[[:space:]]*\([0-9]*\)/\1/')
    TOTAL=$(echo "$COUNT" | grep -oE '"total":[[:space:]]*[0-9]+' | sed 's/"total":[[:space:]]*\([0-9]*\)/\1/')
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
        apk update || return 1
    elif [ "$SYSTEM" = "Arch" ] && command -v pacman >/dev/null 2>&1; then
        pacman -Sy || return 1
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update || return 1
    elif command -v yum >/dev/null 2>&1; then
        yum update -y || return 1
    elif command -v dnf >/dev/null 2>&1; then
        dnf update -y || return 1
    fi
    install_package wget || return 1
    install_package curl || return 1
    install_package sudo || return 1
    if [ "$SYSTEM" = "Alpine" ]; then
        install_package dos2unix || apk add --no-cache busybox-extras || return 1
    else
        install_package dos2unix || return 1
    fi
    install_package ufw || _yellow "ufw not available on this system"
    install_package jq || return 1
    install_uidmap || return 1
    if [ "$SYSTEM" = "Alpine" ]; then
        install_package ipcalc || apk add --no-cache ipcalc-ng || return 1
    else
        install_package ipcalc || return 1
    fi
    install_package unzip || return 1
    install_dnsmasq || return 1
}

install_lxd() {
    # A clean Debian/Ubuntu host has no snap command yet.  Bootstrap snapd
    # before inspecting or installing the LXD snap; otherwise the installer
    # rejects the exact fresh hosts it is meant to support.
    if ! command -v snap >/dev/null 2>&1; then
        command -v apt-get >/dev/null 2>&1 || {
            _red "snap is unavailable and apt-get cannot bootstrap snapd"
            return 1
        }
        apt-get update || return 1
        install_package snapd || return 1
        if command -v systemctl >/dev/null 2>&1 &&
           systemctl list-unit-files snapd.socket >/dev/null 2>&1; then
            systemctl enable --now snapd.socket >/dev/null 2>&1 || {
                _red "无法启动 snapd.socket，LXD snap 无法继续安装"
                return 1
            }
        fi
    fi
    command -v snap >/dev/null 2>&1 || {
        _red "snapd installation did not provide the snap command"
        return 1
    }
    if command -v systemctl >/dev/null 2>&1; then
        local snap_ready=false
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            if snap list >/dev/null 2>&1; then
                snap_ready=true
                break
            fi
            sleep 1
        done
        if [ "$snap_ready" != true ]; then
            _red "snapd daemon is not ready"
            return 1
        fi
    fi
    snap_core=$(snap list core 2>/dev/null || true)
    snap_lxd=$(snap list lxd 2>/dev/null || true)
    if [[ "$snap_lxd" =~ (^|[[:space:]])lxd([[:space:]]|$) ]]; then
        _green "lxd is installed"
        _green "lxd已安装"
        ensure_lxc_path || return 1
        local lxd_lxc_detect
        if ! lxd_lxc_detect=$(lxc list 2>&1); then
            if [[ "$lxd_lxc_detect" =~ snap-update-ns[[:space:]]+failed[[:space:]]+with[[:space:]]+code[[:space:]]*1 ]]; then
                service_manager restart apparmor || return 1
                snap restart lxd || return 1
                lxc list >/dev/null 2>&1 || return 1
            else
                _red "LXD environment check failed: $lxd_lxc_detect"
                return 1
            fi
        elif [[ "$lxd_lxc_detect" =~ snap-update-ns[[:space:]]+failed[[:space:]]+with[[:space:]]+code[[:space:]]*1 ]]; then
            service_manager restart apparmor || return 1
            snap restart lxd || return 1
        else
            _green "No problems with environmental testing"
            _green "环境检测无问题"
        fi
    else
        _green "Start installation of LXD"
        _green "开始安装LXD"
        if ! snap install lxd; then
            # Installing core is a compatibility fallback for old snap
            # stores.  Never remove an existing snap here: that can delete a
            # live LXD data directory while recovering a transient store
            # error.
            snap install core || return 1
            snap install lxd || return 1
        fi
        ensure_lxc_path || return 1
        ! lxc -h >/dev/null 2>&1 && _yellow 'lxc路径有问题，请检查修复' && return 1
        _green "LXD installation complete"
        _green "LXD安装完成"
    fi
    snap set lxd lxcfs.loadavg=true || return 1
    snap set lxd lxcfs.pidfd=true || return 1
    snap set lxd lxcfs.cfs=true || return 1
    restart_lxd_daemon_safely || return 1
    command -v lxc >/dev/null 2>&1 || return 1
    lxc --version >/dev/null 2>&1 || return 1
}

configure_resources() {
    # 支持环境变量预定义以实现无交互安装。
    if [ -z "${noninteractive:-${NONINTERACTIVE:-}}" ] && { [ -n "${DISK_NUMS:-}" ] || [ -n "${STORAGE_PATH:-}" ]; }; then
        export noninteractive=true
    fi
    if is_noninteractive; then
        # 存储路径：优先使用 STORAGE_PATH 环境变量，未设置则留空使用默认
        storage_path="${STORAGE_PATH:-}"
        if [ -n "$storage_path" ]; then
            if [[ ! "$storage_path" =~ ^/.+ ]]; then
                _red "STORAGE_PATH must be an absolute path: $storage_path"
                _red "STORAGE_PATH 必须是绝对路径：$storage_path"
                exit 1
            fi
            if [ ! -d "$storage_path" ]; then
                if ! mkdir -p "$storage_path" 2>/dev/null; then
                    _red "Failed to create STORAGE_PATH: $storage_path"
                    _red "创建 STORAGE_PATH 失败：$storage_path"
                    exit 1
                fi
            fi
            echo "$storage_path" >/usr/local/bin/lxd_storage_path
            _green "Using storage path: $storage_path"
            _green "使用自定义存储路径：$storage_path"
        else
            rm -f /usr/local/bin/lxd_storage_path
        fi
        # 存储池大小：优先使用 DISK_NUMS 环境变量，否则自动计算（可用空间 - 1GB）
        if [ -n "${DISK_NUMS:-}" ]; then
            if ! [[ "${DISK_NUMS}" =~ ^[1-9][0-9]*$ ]]; then
                _red "DISK_NUMS must be a positive integer: $DISK_NUMS"
                _red "DISK_NUMS 必须是正整数：$DISK_NUMS"
                exit 1
            fi
            disk_nums="$DISK_NUMS"
            _green "Using pre-defined storage pool size: ${disk_nums}GB"
            _green "使用预定义存储池大小：${disk_nums}GB"
        else
            available_space=$(get_available_space)
            if ! [[ "$available_space" =~ ^[0-9]+$ ]] || [ "$available_space" -le 1 ]; then
                _red "Available disk space is insufficient for automatic storage sizing: ${available_space:-unknown}GB"
                _red "可用磁盘空间不足，无法自动设置存储池大小：${available_space:-unknown}GB"
                exit 1
            fi
            disk_nums=$((available_space - 1))
            _green "Auto-detected storage pool size: ${disk_nums}GB"
            _green "自动检测存储池大小：${disk_nums}GB"
        fi
    else
        while true; do
            _green "Do you want to specify a custom path for the storage pool? (y/n) [n]:"
            reading "是否需要指定存储池的自定义路径？(y/n) [n]：" use_custom_path || return 1
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
                reading "请输入自定义存储路径 (例如：/data/lxd-storage)：" storage_path || return 1
                if [[ -n "$storage_path" && "$storage_path" =~ ^/.+ ]]; then
                    if [ ! -d "$storage_path" ]; then
                        mkdir -p "$storage_path" 2>/dev/null
                        if [ $? -eq 0 ]; then
                            echo "$storage_path" >/usr/local/bin/lxd_storage_path
                            _green "Created directory: $storage_path"
                            _green "已创建目录：$storage_path"
                            break
                        else
                            _yellow "Failed to create directory. Please check permissions or try another path."
                            _yellow "创建目录失败，请检查权限或尝试其他路径。"
                        fi
                    else
                        echo "$storage_path" >/usr/local/bin/lxd_storage_path
                        break
                    fi
                else
                    _yellow "Please enter a valid absolute path starting with /."
                    _yellow "请输入以 / 开头的有效绝对路径。"
                fi
            done
        else
            storage_path=""
            rm -f /usr/local/bin/lxd_storage_path
        fi
        while true; do
            _green "How large a storage pool does the host need to open? (Note that it is in GB, enter 10 if you need 10G storage pool):"
            reading "宿主机需要开设多大的存储池？(注意是GB为单位，需要10G存储池则输入10)：" disk_nums || return 1
            if [[ "$disk_nums" =~ ^[1-9][0-9]*$ ]]; then
                break
            else
                _yellow "Invalid input, please enter a positive integer."
                _yellow "输入无效，请输入一个正整数。"
            fi
        done
    fi
}

record_tried_storage() {
    local storage_type="$1"
    grep -qxF "$storage_type" "$TRIED_STORAGE_FILE" 2>/dev/null || echo "$storage_type" >>"$TRIED_STORAGE_FILE"
    is_storage_tried "$storage_type" || TRIED_STORAGE+=("$storage_type")
}

record_installed_storage() {
    local storage_type="$1"
    grep -qxF "$storage_type" "$INSTALLED_STORAGE_FILE" 2>/dev/null || echo "$storage_type" >>"$INSTALLED_STORAGE_FILE"
    is_storage_installed "$storage_type" || INSTALLED_STORAGE+=("$storage_type")
}

load_storage_state() {
    TRIED_STORAGE=()
    INSTALLED_STORAGE=()
    if [ -f "$TRIED_STORAGE_FILE" ]; then
        while IFS= read -r storage_type; do
            [ -n "$storage_type" ] && TRIED_STORAGE+=("$storage_type")
        done <"$TRIED_STORAGE_FILE"
    fi
    if [ -f "$INSTALLED_STORAGE_FILE" ]; then
        while IFS= read -r storage_type; do
            [ -n "$storage_type" ] && INSTALLED_STORAGE+=("$storage_type")
        done <"$INSTALLED_STORAGE_FILE"
    fi
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

# 创建稀疏文件
create_sparse_file() {
    local file_path="$1"
    local size_gb="$2"
    if dd if=/dev/zero of="$file_path" bs=1G count=0 seek="${size_gb}" 2>/dev/null; then
        _green "使用 dd 创建稀疏文件成功: $file_path (${size_gb}GB)"
        _green "Successfully created sparse file using dd: $file_path (${size_gb}GB)"
        return 0
    else
        _yellow "dd 创建失败，尝试使用 truncate..."
        _yellow "dd failed, trying truncate..."
        if command -v truncate >/dev/null 2>&1; then
            if truncate -s "${size_gb}G" "$file_path" 2>/dev/null; then
                _green "使用 truncate 创建稀疏文件成功: $file_path (${size_gb}GB)"
                _green "Successfully created sparse file using truncate: $file_path (${size_gb}GB)"
                return 0
            else
                _red "truncate 创建失败"
                _red "truncate failed"
                return 1
            fi
        else
            _red "truncate 命令不可用，无法创建稀疏文件"
            _red "truncate command not available, cannot create sparse file"
            return 1
        fi
    fi
}

# 创建和配置存储池（使用自定义路径）
create_storage_pool_with_custom_path() {
    local backend="$1"
    local storage_path="$2"
    local disk_nums="$3"
    local pool_name="${4:-$MANAGED_STORAGE_POOL}"
    local loop_file mount_point temp status
    if ! valid_storage_pool_name "$pool_name"; then
        _red "Invalid managed storage pool name: $pool_name"
        return 1
    fi
    if storage_pool_exists "$pool_name"; then
        _yellow "检测到已有 $pool_name 存储池，将保留并复用它"
        _yellow "An existing $pool_name storage pool was found; preserving and reusing it"
        return 0
    fi
    mkdir -p "$storage_path" || return 1
    if [ "$backend" = "lvm" ]; then
        loop_file="$storage_path/lvm_pool.img"
        _green "创建 LVM 存储池..."
        _green "Creating LVM storage pool..."
        if [ -f "$loop_file" ]; then
            _red "检测到已有 LVM 循环文件，拒绝覆盖：$loop_file"
            _red "Existing LVM loop file found; refusing to overwrite: $loop_file"
            return 1
        fi
        _green "创建稀疏文件：$loop_file (${disk_nums}GB)..."
        if ! create_sparse_file "$loop_file" "$disk_nums"; then
            return 1
        fi
        _green "设置循环设备..."
        loop_dev=$(losetup -f) || return 1
        losetup "$loop_dev" "$loop_file" || return 1
        _green "创建 LVM 物理卷和卷组..."
        pvcreate "$loop_dev" >/dev/null 2>&1 || return 1
        vgcreate lxd_vg "$loop_dev" >/dev/null 2>&1 || return 1
        printf '%s\n' "$loop_file" > "$storage_path/lvm_loop_file.txt" || return 1
        temp=$(/snap/bin/lxc storage create "$pool_name" lvm source=lxd_vg 2>&1)
        status=$?
    elif [ "$backend" = "btrfs" ]; then
        loop_file="$storage_path/btrfs_pool.img"
        mount_point="$storage_path/btrfs_mount"
        _green "创建 btrfs 存储池..."
        _green "Creating btrfs storage pool..."
        if mountpoint -q "$mount_point" 2>/dev/null; then
            _red "检测到已挂载的 btrfs 路径，拒绝卸载：$mount_point"
            _red "Existing btrfs mount found; refusing to unmount: $mount_point"
            return 1
        fi
        if [ -f "$loop_file" ]; then
            _red "检测到已有 btrfs 循环文件，拒绝覆盖：$loop_file"
            _red "Existing btrfs loop file found; refusing to overwrite: $loop_file"
            return 1
        fi
        mkdir -p "$mount_point" || return 1
        _green "创建稀疏文件：$loop_file (${disk_nums}GB)..."
        if ! create_sparse_file "$loop_file" "$disk_nums"; then
            return 1
        fi
        _green "格式化为 btrfs..."
        mkfs.btrfs -f "$loop_file" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            _red "btrfs 格式化失败"
            _red "btrfs formatting failed"
            return 1
        fi
        _green "挂载 btrfs 文件系统..."
        if ! mount -o loop "$loop_file" "$mount_point"; then
            _red "挂载失败"
            _red "Mount failed"
            return 1
        fi
        if ! grep -Fq "$loop_file" /etc/fstab 2>/dev/null; then
            if ! printf '%s\n' "$loop_file $mount_point btrfs loop 0 0" >>/etc/fstab; then
                _red "无法写入 /etc/fstab，取消 btrfs 存储池创建"
                umount "$mount_point" 2>/dev/null || true
                rm -f -- "$loop_file"
                return 1
            fi
            _green "已添加到 /etc/fstab 实现开机自动挂载"
            _green "Added to /etc/fstab for automatic mounting on boot"
        fi
        chmod 711 "$mount_point" || return 1
        temp=$(/snap/bin/lxc storage create "$pool_name" btrfs source="$mount_point" 2>&1)
        status=$?
    elif [ "$backend" = "zfs" ]; then
        loop_file="$storage_path/zfs_pool.img"
        local zpool_name="lxd_zfs_pool"
        _green "创建 ZFS 存储池..."
        _green "Creating ZFS storage pool..."
        if zpool list "$zpool_name" >/dev/null 2>&1; then
            _red "检测到已有 ZFS 存储池，拒绝销毁：$zpool_name"
            _red "Existing ZFS pool found; refusing to destroy: $zpool_name"
            return 1
        fi
        if [ -f "$loop_file" ]; then
            _red "检测到已有 ZFS 循环文件，拒绝覆盖：$loop_file"
            _red "Existing ZFS loop file found; refusing to overwrite: $loop_file"
            return 1
        fi
        _green "创建稀疏文件：$loop_file (${disk_nums}GB)..."
        if ! create_sparse_file "$loop_file" "$disk_nums"; then
            return 1
        fi
        _green "创建 ZFS pool..."
        zpool create -f "$zpool_name" "$loop_file" >/dev/null 2>&1 || return 1
        if ! zpool list "$zpool_name" >/dev/null 2>&1; then
            _red "ZFS pool 创建失败！"
            _red "ZFS pool creation failed!"
            return 1
        fi
        temp=$(/snap/bin/lxc storage create "$pool_name" zfs source="$zpool_name" 2>&1)
        status=$?
    elif [ "$backend" = "dir" ]; then
        temp=$(/snap/bin/lxc storage create "$pool_name" dir source="$storage_path" 2>&1)
        status=$?
    else
        _red "不支持的存储后端：$backend"
        _red "Unsupported storage backend: $backend"
        return 1
    fi
    echo "$temp"
    return $status
}

execute_storage_init() {
    local backend="$1"
    local temp
    local status
    local existing_pool

    if existing_pool=$(active_storage_pool); then
        _yellow "检测到现有 $existing_pool 存储池，将保留并复用它"
        _yellow "An existing $existing_pool storage pool was found; preserving and reusing it"
        record_storage_pool "$existing_pool" || return 1
        echo "Existing $existing_pool storage pool preserved"
        return 0
    fi
    if [ -n "$storage_path" ]; then
        # Initialize the daemon without deleting the default pool that the
        # automatic initializer may create. The requested custom path is used
        # by a separate managed pool and build scripts select that pool later.
        local init_output init_status
        init_output=$(/snap/bin/lxd init --auto 2>&1)
        init_status=$?
        if [ "$init_status" -ne 0 ] && ! grep -Eiq 'already[[:space:]]+(been[[:space:]]+)?initialized|already[[:space:]]+exists|already[[:space:]]+configured' <<<"$init_output"; then
            printf '%s\n' "$init_output" >&2
            _red "LXD 初始化失败，无法创建自定义存储池"
            _red "LXD initialization failed; cannot create the custom storage pool"
            return 1
        fi
        _yellow "当前存储池列表："
        _yellow "Current storage pools:"
        /snap/bin/lxc storage list 2>/dev/null || true
        if storage_pool_exists "$MANAGED_STORAGE_POOL"; then
            _yellow "检测到已有 $MANAGED_STORAGE_POOL 存储池，将保留并复用它"
            _yellow "An existing $MANAGED_STORAGE_POOL storage pool was found; preserving and reusing it"
            record_storage_pool "$MANAGED_STORAGE_POOL" || return 1
            echo "Existing $MANAGED_STORAGE_POOL storage pool preserved"
            return 0
        fi
        if create_storage_pool_with_custom_path "$backend" "$storage_path" "$disk_nums" "$MANAGED_STORAGE_POOL"; then
            temp="Storage pool created successfully"
            status=0
            record_storage_pool "$MANAGED_STORAGE_POOL" || return 1
            # Network and profile repair is performed by
            # ensure_runtime_network after storage setup. Do not invoke a
            # second `lxd init --auto` here, because it can fail or rewrite
            # administrator settings on a partially initialized daemon.
        else
            temp="Failed to create storage pool with custom path"
            status=1
        fi
    else
        if [ "$backend" = "dir" ]; then
            temp=$(/snap/bin/lxd init --storage-backend dir --storage-pool default --auto 2>&1)
        else
            temp=$(/snap/bin/lxd init --storage-backend "$backend" --storage-create-loop "$disk_nums" --storage-pool default --auto 2>&1)
        fi
        status=$?
        if [ "$status" -eq 0 ] && storage_pool_exists default; then
            record_storage_pool default || return 1
        fi
    fi
    echo "$temp"
    return $status
}

# Newly installed userspace tools do not imply a kernel reboot is required.
# Preserve fallback/retry only when support is neither active nor loadable.
ensure_storage_kernel_support() {
    local backend="$1" module
    case "$backend" in
        btrfs|zfs)
            grep -qw "$backend" /proc/filesystems && return 0
            module="$backend"
            ;;
        lvm)
            grep -qw device-mapper /proc/devices && return 0
            module=dm_mod
            ;;
        *) return 0 ;;
    esac
    modprobe "$module" && return 0
    _yellow "$backend kernel support is unavailable; retaining the retry marker and trying another backend"
    _yellow "$backend 内核支持不可用，保留重试标记并尝试其他存储后端"
    echo "$backend" >/usr/local/bin/lxd_reboot || return 1
    return 1
}

init_storage_backend() {
    local backend="$1"
    if is_storage_tried "$backend"; then
        _yellow "已经尝试过 ${backend}，跳过"
        _yellow "Already tried $backend, skipping"
        return 1
    fi
    if [ "$backend" = "dir" ]; then
        _green "使用默认dir类型无限定存储池大小"
        _green "Using default dir type with unlimited storage pool size"
        echo "dir" >/usr/local/bin/lxd_storage_type
        local temp status
        temp=$(execute_storage_init "$backend")
        status=$?
        echo "$temp"
        record_tried_storage "$backend"
        return "$status"
    fi
    _green "尝试使用 $backend 类型，存储池大小为 $disk_nums"
    _green "Trying to use $backend type with storage pool size $disk_nums"
    if [ "$backend" = "btrfs" ] && ! is_storage_installed "btrfs" && ! command -v btrfs >/dev/null; then
        _yellow "正在安装 btrfs-progs..."
        _yellow "Installing btrfs-progs..."
        install_package btrfs-progs || return 1
        record_installed_storage "btrfs"
    elif [ "$backend" = "lvm" ] && ! is_storage_installed "lvm" && ! command -v lvm >/dev/null; then
        _yellow "正在安装 lvm2..."
        _yellow "Installing lvm2..."
        install_package lvm2 || return 1
        record_installed_storage "lvm"
    elif [ "$backend" = "zfs" ] && ! is_storage_installed "zfs" && ! command -v zfs >/dev/null; then
        _yellow "正在安装 zfsutils-linux..."
        _yellow "Installing zfsutils-linux..."
        install_package zfsutils-linux || return 1
        record_installed_storage "zfs"
    elif [ "$backend" = "ceph" ] && ! is_storage_installed "ceph" && ! command -v ceph >/dev/null; then
        _yellow "正在安装 ceph-common..."
        _yellow "Installing ceph-common..."
        install_package ceph-common || return 1
        record_installed_storage "ceph"
    fi
    ensure_storage_kernel_support "$backend" || return 1
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
    local existing_pool pool_status
    if existing_pool=$(active_storage_pool); then
        _green "检测到现有 $existing_pool 存储池，跳过后端重新初始化"
        _green "An existing $existing_pool storage pool was found; skipping backend reinitialization"
        record_storage_pool "$existing_pool" || return 1
        return 0
    else
        pool_status=$?
        [ "$pool_status" -eq 1 ] || return "$pool_status"
    fi
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
    execute_storage_init dir
}

# Storage initialization can be skipped on a reused host; profile and network
# initialization must still run. Only add missing devices/settings and preserve
# existing pools, custom NICs, addresses and explicit IPv6 disablement.
ensure_runtime_network() {
    local pool profiles profile roots root_pool nics nic network bridge="lxdbr0" networks config value
    command -v jq >/dev/null 2>&1 || { _red "jq is required to verify initialization"; return 1; }
    lxc info >/dev/null 2>&1 || { _red "LXD daemon is unavailable"; return 1; }
    pool=$(active_storage_pool) || { _red "No unambiguous usable storage pool"; return 1; }
    profiles=$(lxc profile list --format csv -c n) || return 1
    if ! grep -Fxq default <<< "$profiles"; then
        lxc profile create default || return 1
    fi
    profile=$(lxc query /1.0/profiles/default) || return 1
    profile=$(api_metadata profile <<<"$profile") || return 1
    roots=$(jq -er '[.devices // {} | to_entries[] | select(.value.type == "disk" and .value.path == "/")] | length' <<< "$profile") || return 1
    if [ "$roots" -eq 0 ]; then
        if jq -e '.devices.root != null' <<< "$profile" >/dev/null; then
            _red "default profile device root is already used; leaving it unchanged"
            return 1
        fi
        lxc profile device add default root disk path=/ pool="$pool" || return 1
    elif [ "$roots" -eq 1 ]; then
        root_pool=$(jq -r '.devices[] | select(.type == "disk" and .path == "/") | .pool // empty' <<< "$profile")
        if [ -z "$root_pool" ] || ! storage_pool_exists "$root_pool"; then
            _red "default profile root refers to an unavailable pool; leaving it unchanged"
            return 1
        fi
    else
        _red "default profile has multiple root disks; leaving it unchanged"
        return 1
    fi

    nics=$(jq -er '[.devices // {} | to_entries[] | select(.value.type == "nic")] | length' <<< "$profile") || return 1
    if [ "$nics" -gt 0 ]; then
        # Custom NIC layouts are user configuration. Validate their referenced
        # resources without replacing them with the installer's default bridge.
        while IFS= read -r nic; do
            network=$(jq -r '.network // empty' <<< "$nic")
            if [ "$network" = "$bridge" ]; then
                continue # A missing installer bridge is repaired below.
            elif [ "$network" = "none" ]; then
                # `none` is a valid explicit LXD profile choice; preserve it
                # without looking for a network object of that name.
                continue
            elif [ -n "$network" ]; then
                lxc network show "$network" >/dev/null || return 1
            else
                network=$(jq -r '.parent // empty' <<< "$nic")
                [ -z "$network" ] || [ "$network" = "$bridge" ] || ip link show dev "$network" >/dev/null || return 1
            fi
        done < <(jq -c '.devices[] | select(.type == "nic")' <<< "$profile")
        if ! jq -e --arg bridge "$bridge" '.devices[] | select(.type == "nic" and (.network == $bridge or .parent == $bridge))' <<< "$profile" >/dev/null; then
            _yellow "Preserving the custom default-profile network; ensuring the installer bridge separately"
        fi
    elif jq -e '.devices.eth0 != null' <<< "$profile" >/dev/null; then
        _red "default profile device eth0 is already used; leaving it unchanged"
        return 1
    fi

    networks=$(runtime_resource_names network) || return 1
    if ! grep -Fxq "$bridge" <<< "$networks"; then
        if ip link show dev "$bridge" >/dev/null 2>&1; then
            _red "$bridge already exists outside LXD; refusing to replace it"
            return 1
        fi
        # IPv4 is required for the default NAT setup. IPv6 is optional.
        lxc network create "$bridge" ipv4.address=auto ipv4.nat=true ipv4.dhcp=true ipv6.address=none || return 1
        lxc network set "$bridge" ipv6.address auto || _yellow "IPv6 unavailable; retaining IPv4 networking"
    fi
    config=$(lxc query "/1.0/networks/$bridge") || return 1
    config=$(api_metadata network <<<"$config") || return 1
    jq -e '.type == "bridge" and .managed == true' <<< "$config" >/dev/null || {
        _red "$bridge is not a managed bridge"; return 1;
    }
    for value in ipv4.address ipv4.dhcp ipv4.nat; do
        network=$(jq -r --arg key "$value" '.config[$key] // empty' <<< "$config") || return 1
        if [ -z "$network" ]; then
            if [ "$value" = ipv4.address ]; then
                lxc network set "$bridge" "$value" auto || return 1
            else
                lxc network set "$bridge" "$value" true || return 1
            fi
        elif { [ "$value" = ipv4.address ] && [ "$network" = none ]; } ||
             { [ "$value" = ipv4.dhcp ] && [ "$network" = false ]; }; then
            _red "$bridge explicitly disables $value; default IPv4 NAT is unavailable (setting preserved)"
            return 1
        fi
    done
    if [ "$nics" -eq 0 ]; then
        lxc profile device add default eth0 nic network="$bridge" name=eth0 || return 1
    fi
    # LXD can acknowledge a managed network just before the bridge appears in
    # the host link table. Wait briefly for the kernel interface to settle.
    local link_attempt=0
    while ! ip link show dev "$bridge" >/dev/null 2>&1; do
        link_attempt=$((link_attempt + 1))
        if [ "$link_attempt" -ge 10 ]; then
            _red "$bridge has no host interface"
            return 1
        fi
        sleep 1
    done
    _green "LXD storage, default profile and $bridge are ready"
}

configure_lxd_network() {
    ensure_lxc_path
    ensure_runtime_network || return 1
    local config dns_mode raw_dnsmasq
    config=$(lxc query /1.0/networks/lxdbr0) || return 1
    config=$(api_metadata network <<<"$config") || return 1
    dns_mode=$(jq -r '.config["dns.mode"] // empty' <<< "$config") || return 1
    if [ -z "$dns_mode" ]; then
        lxc network set lxdbr0 dns.mode managed || return 1
    fi
    # A managed bridge with no explicit raw.dnsmasq can inherit the host's
    # loopback resolver, which is unreachable from containers. Add upstreams
    # only when no administrator DNS configuration exists.
    raw_dnsmasq=$(jq -r '.config["raw.dnsmasq"] // empty' <<< "$config") || return 1
    if [ -z "$raw_dnsmasq" ]; then
        lxc network set lxdbr0 raw.dnsmasq $'server=1.1.1.1\nserver=8.8.8.8' || return 1
    fi
    lxc config set images.auto_update_interval 0 || return 1
    if ! lxc remote list 2>/dev/null | grep -q '^| opsmaru[[:space:]]*|'; then
        lxc remote add opsmaru https://images.opsmaru.dev/spaces/9bfad87bd318b8f06012059a --public --protocol simplestreams ||
            _yellow "Optional image remote opsmaru is unavailable"
    fi
    return 0
}

download_preset_files() {
    files=(
        "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_bash.sh"
        "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/ssh_sh.sh"
        "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/config.sh"
        "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/instance_ownership.sh"
        "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/buildct.sh"
    )
    for file in "${files[@]}"; do
        filename=$(basename "$file")
        rm -f -- "$filename"
        download_file "$file" "$filename" || return 1
        chmod 755 "$filename" || return 1
        dos2unix "$filename" || return 1
    done
    cp /root/ssh_sh.sh /usr/local/bin || return 1
    cp /root/ssh_bash.sh /usr/local/bin || return 1
    cp /root/config.sh /usr/local/bin || return 1
    cp /root/instance_ownership.sh /usr/local/bin || return 1
}

configure_system() {
    command -v sysctl >/dev/null 2>&1 || return 1
    sysctl -w net.ipv4.ip_forward=1 >/dev/null || return 1
    SYSCTL_CONF="/etc/sysctl.conf"
    SYSCTL_D_CONF="/etc/sysctl.d/99-custom.conf"
    if [ -f "$SYSCTL_CONF" ]; then
        if grep -q "^net.ipv4.ip_forward=1" "$SYSCTL_CONF"; then
            sed -i 's/^#\?net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' "$SYSCTL_CONF"
        else
            echo "net.ipv4.ip_forward=1" >>"$SYSCTL_CONF"
        fi
    fi
    mkdir -p /etc/sysctl.d || return 1
    if ! grep -q "^net.ipv4.ip_forward=1" "$SYSCTL_D_CONF" 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >>"$SYSCTL_D_CONF" || return 1
    fi
    apply_forwarding_config "$SYSCTL_D_CONF" || return 1
    # Required network settings are validated by ensure_runtime_network.
    # Preserve custom DNS, addressing and explicit IPv6 disablement here.
    # Ensure root has subuid/subgid entries for unprivileged containers
    grep -q "^root:" /etc/subuid 2>/dev/null || echo 'root:100000:65536' >>/etc/subuid || return 1
    grep -q "^root:" /etc/subgid 2>/dev/null || echo 'root:100000:65536' >>/etc/subgid || return 1
}

remove_system_limits() {
    if [ -f "/etc/security/limits.conf" ]; then
        if ! grep -Fq "*          hard    nproc       unlimited" /etc/security/limits.conf; then
            echo '*          hard    nproc       unlimited' | sudo tee -a /etc/security/limits.conf
        fi
        if ! grep -Fq "*          soft    nproc       unlimited" /etc/security/limits.conf; then
            echo '*          soft    nproc       unlimited' | sudo tee -a /etc/security/limits.conf
        fi
    fi
    if [ -f "/etc/systemd/logind.conf" ]; then
        if ! grep -q "UserTasksMax=infinity" /etc/systemd/logind.conf; then
            echo 'UserTasksMax=infinity' | sudo tee -a /etc/systemd/logind.conf
        fi
    fi
    if command -v ufw >/dev/null 2>&1; then
        ufw disable || _yellow "Unable to disable ufw; verify firewall rules manually"
    fi
}

install_dns_check() {
    if ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
        _yellow "No systemd installation detected; skipping optional DNS checker"
        return 0
    fi
    if [ ! -f /usr/local/bin/check-dns.sh ]; then
        download_file "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/check-dns.sh" /usr/local/bin/check-dns.sh || return 1
        chmod +x /usr/local/bin/check-dns.sh || return 1
    else
        echo "Script already exists. Skipping installation."
    fi
    if [ ! -f /etc/systemd/system/check-dns.service ]; then
        download_file "https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/check-dns.service" /etc/systemd/system/check-dns.service || return 1
        chmod +x /etc/systemd/system/check-dns.service || return 1
        service_manager daemon-reload || return 1
        service_manager enable check-dns.service || return 1
        service_manager start check-dns.service || return 1
    else
        echo "Service already exists. Skipping installation."
    fi
}

# LXD proxy devices that listen on the host address traverse the Linux bridge
# netfilter path. Load and persist br_netfilter so published ports can reach
# containers after both the current run and a host reboot.
ensure_bridge_netfilter() {
    local module_file=/etc/modules-load.d/oneclickvirt-bridge-netfilter.conf
    if [ ! -d /proc/sys/net/bridge ]; then
        command -v modprobe >/dev/null 2>&1 || return 1
        modprobe br_netfilter || return 1
    fi
    [ -d /proc/sys/net/bridge ] || return 1
    command -v sysctl >/dev/null 2>&1 || return 1
    sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null || return 1
    sysctl -w net.bridge.bridge-nf-call-ip6tables=1 >/dev/null || return 1
    mkdir -p /etc/modules-load.d /etc/sysctl.d || return 1
    if [ ! -f "$module_file" ] || ! grep -Fxq br_netfilter "$module_file"; then
        printf '%s\n' br_netfilter >"$module_file" || return 1
    fi
    local sysctl_file=/etc/sysctl.d/99-oneclickvirt-bridge.conf
    if [ ! -f "$sysctl_file" ] || ! grep -Eq '^net\.bridge\.bridge-nf-call-iptables=1$' "$sysctl_file"; then
        printf '%s\n' 'net.bridge.bridge-nf-call-iptables=1' >>"$sysctl_file" || return 1
    fi
    if ! grep -Eq '^net\.bridge\.bridge-nf-call-ip6tables=1$' "$sysctl_file"; then
        printf '%s\n' 'net.bridge.bridge-nf-call-ip6tables=1' >>"$sysctl_file" || return 1
    fi
}

save_lxd_nat_rules() {
    local destination="${1:-/etc/nftables.d/oneclickvirt-lxd.nft}" rules temporary
    rules=$(nft list table inet lxd_nat) || return 1
    temporary=$(mktemp "${destination}.XXXXXX") || return 1
    # Only replace a complete snapshot; a failed read must preserve the last
    # working file. Flush only our table when loading it again after a reboot.
    if ! printf '%s\n' '#!/usr/sbin/nft -f' 'add table inet lxd_nat' 'flush table inet lxd_nat' "$rules" >"$temporary" ||
        ! chmod 644 "$temporary" || ! mv -f -- "$temporary" "$destination"; then
        rm -f -- "$temporary"
        return 1
    fi
}

nftables_persistence_file() {
    case "${SYSTEM:-}" in
        CentOS|Fedora) printf '%s\n' /etc/sysconfig/nftables.conf ;;
        Alpine) printf '%s\n' /etc/nftables.nft ;;
        Debian|Ubuntu|Arch) printf '%s\n' /etc/nftables.conf ;;
        *) printf '%s\n' 'No supported nftables boot persistence for this system' >&2; return 1 ;;
    esac
}

enable_nftables_persistence() {
    # Enabling is intentionally separate from package discovery and is called
    # only after the complete snapshot/include exists. Do not start or reload.
    if [ "${SYSTEM:-}" = Alpine ]; then
        install_package nftables-openrc || return 1
    fi
    service_manager enable nftables || return 1
}

iptables_persistence_file() {
    case "${SYSTEM:-}" in
        Debian|Ubuntu) printf '%s\n' /etc/iptables/rules.v4 ;;
        CentOS|Fedora) printf '%s\n' /etc/sysconfig/iptables ;;
        Arch) printf '%s\n' /etc/iptables/iptables.rules ;;
        Alpine) printf '%s\n' /etc/iptables/rules-save ;;
        *) printf '%s\n' 'No supported iptables boot persistence for this system' >&2; return 1 ;;
    esac
}

ensure_iptables_persistent() {
    local persistence_service=iptables
    case "${SYSTEM:-}" in
        Debian|Ubuntu)
            DEBIAN_FRONTEND=noninteractive install_package iptables-persistent || return 1
            persistence_service=netfilter-persistent
            ;;
        CentOS|Fedora) install_package iptables-services || return 1 ;;
        Alpine) install_package iptables-openrc || return 1 ;;
        Arch) : ;;
        *) return 1 ;;
    esac
    # Enable boot restoration without starting/reloading another live policy.
    service_manager enable "$persistence_service" || return 1
}

save_iptables_persistence() {
    local target="${1:?iptables persistence target is required}" save_command="${2:?iptables save command is required}"
    local resolved directory temporary
    if [ -L "$target" ]; then
        resolved=$(readlink -f -- "$target") || return 1
        [ -e "$resolved" ] || return 1
    else
        resolved="$target"
    fi
    directory=$(dirname -- "$resolved") || return 1
    mkdir -p -- "$directory" || return 1
    [ ! -e "$resolved" ] || [ -f "$resolved" ] || return 1
    temporary=$(mktemp "$directory/.oneclickvirt-iptables.XXXXXX") || return 1
    # Preserve mode/owner of existing policies; a new snapshot starts at 600.
    if { [ -f "$resolved" ] && ! cp -p -- "$resolved" "$temporary"; } ||
        ! "$save_command" >"$temporary" || ! mv -f -- "$temporary" "$resolved"; then
        rm -f -- "$temporary"
        return 1
    fi
}

configure_nft_masquerade() {
    local nat_enabled rule=""
    nat_enabled=$(/snap/bin/lxc network get lxdbr0 ipv4.nat) || return 1
    if [ "$nat_enabled" = true ]; then
        rule='add rule inet lxd_nat postrouting_masq meta nfproto ipv4 iifname "lxdbr0" oifname != "lxdbr0" masquerade'
    fi
    # Migrate the installer-owned chain atomically. IPv6 routing/NAT remains
    # controlled by LXD's network settings, including explicit NAT disablement.
    nft -f - <<NFT || return 1
add table inet lxd_nat
add chain inet lxd_nat postrouting_masq { type nat hook postrouting priority srcnat; policy accept; }
flush chain inet lxd_nat postrouting_masq
$rule
NFT
    sync_lxd_firewalld_masquerade || return 1
    retire_lxd_iptables_masquerade "$@"
}

ocv_lock_firewall() {
    local lock_dir=/run/oneclickvirt-firewall-locks lock_file
    command -v flock >/dev/null 2>&1 || return 1
    [ ! -L "$lock_dir" ] || return 1
    mkdir -p -m 700 -- "$lock_dir" || return 1
    [ "$(stat -c %u "$lock_dir")" = "$EUID" ] || return 1
    [ "$(stat -c %a "$lock_dir")" = 700 ] || return 1
    lock_file="$lock_dir/firewall.lock"
    [ ! -L "$lock_file" ] || return 1
    exec {ocv_firewall_lock_fd}>>"$lock_file" || return 1
    # Keep the inode: unlinking it would let another process bypass this lock.
    flock -xw 120 "$ocv_firewall_lock_fd" || return 1
}

ocv_with_firewall_lock() {
    # The subshell releases the lock on both success and failure.
    ( ocv_lock_firewall && "$@" )
}

sync_lxd_firewalld_masquerade() {
    local subnet="${1:-}" prefix octet active=false state_status=127
    local permanent_rules="" runtime_rules="" scope rules rule source present
    local cli=firewall-cmd
    local octets=() options=() scopes=(permanent)
    local pattern="^0 -s ([0-9./]+) ['\"]?!['\"]? -o lxdbr0 -m comment --comment ['\"]?oneclickvirt-lxd-ipv4['\"]? -j MASQUERADE$"
    # Validate before changing either scope, preserving working rules on bad
    # runtime metadata. An empty subnet means remove only this installer's NAT.
    if [ -n "$subnet" ]; then
        [[ "$subnet" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1
        prefix="${subnet##*/}"
        ((10#$prefix >= 1 && 10#$prefix <= 32)) || return 1
        IFS=. read -r -a octets <<<"${subnet%/*}"
        for octet in "${octets[@]}"; do ((10#$octet <= 255)) || return 1; done
    fi
    if command -v firewall-cmd >/dev/null 2>&1; then
        state_status=0
        firewall-cmd --state >/dev/null 2>&1 || state_status=$?
        # Only NOT_RUNNING permits offline mutation. A D-Bus failure is not
        # evidence that the daemon stopped; do not overwrite its configuration.
        if [ "$state_status" -ne 0 ] && [ "$state_status" -ne 252 ]; then
            # No saved direct configuration means there is nothing for a
            # stopped/unavailable daemon to restore; kernel cleanup follows.
            [ -z "$subnet" ] && [ ! -e /etc/firewalld/direct.xml ] && return 0
            return 1
        fi
    fi
    if [ "$state_status" -eq 0 ]; then
        active=true
        permanent_rules=$(firewall-cmd --permanent --direct --get-rules ipv4 nat POSTROUTING) || return 1
        runtime_rules=$(firewall-cmd --direct --get-rules ipv4 nat POSTROUTING) || return 1
        scopes+=(runtime)
    else
        [ -z "$subnet" ] || return 1
        # Retire saved rules through the offline API when the daemon is down,
        # so its next start cannot restore stale NAT. Never edit firewalld XML.
        [ -f /etc/firewalld/direct.xml ] || return 0
        local saved_status=0
        grep -Fq 'oneclickvirt-lxd-ipv4' /etc/firewalld/direct.xml || saved_status=$?
        [ "$saved_status" -ne 1 ] || return 0
        [ "$saved_status" -eq 0 ] || return 1
        [ "$state_status" -eq 252 ] || return 1
        command -v firewall-offline-cmd >/dev/null 2>&1 || return 1
        cli=firewall-offline-cmd
        permanent_rules=$("$cli" --direct --get-rules ipv4 nat POSTROUTING) || return 1
    fi
    for scope in "${scopes[@]}"; do
        options=()
        rules="$permanent_rules"
        if [ "$scope" = runtime ]; then
            rules="$runtime_rules"
        elif [ "$active" = true ]; then
            options=(--permanent)
        fi
        present=false
        while IFS= read -r rule; do
            if [[ "$rule" =~ $pattern ]] && [ "${BASH_REMATCH[1]}" = "$subnet" ]; then present=true; fi
        done <<<"$rules"
        if [ -n "$subnet" ] && [ "$present" = false ]; then
            "$cli" "${options[@]}" --direct --add-rule ipv4 nat POSTROUTING 0 \
                -s "$subnet" ! -o lxdbr0 -m comment --comment oneclickvirt-lxd-ipv4 -j MASQUERADE || return 1
        fi
        # Add the replacement before retiring the old subnet. Rebuild
        # arguments from a strict match; never evaluate firewall output.
        while IFS= read -r rule; do
            if [[ "$rule" =~ $pattern ]]; then
                source="${BASH_REMATCH[1]}"
                if [ -z "$subnet" ] || [ "$source" != "$subnet" ]; then
                    "$cli" "${options[@]}" --direct --remove-rule ipv4 nat POSTROUTING 0 \
                        -s "$source" ! -o lxdbr0 -m comment --comment oneclickvirt-lxd-ipv4 -j MASQUERADE || return 1
                fi
            fi
        done <<<"$rules"
    done
}

configure_firewalld_masquerade() {
    local nat_enabled subnet="" zone status scope
    local options=()
    nat_enabled=$(/snap/bin/lxc network get lxdbr0 ipv4.nat) || return 1
    if [ "$nat_enabled" = true ]; then
        subnet=$(/snap/bin/lxc network get lxdbr0 ipv4.address) || return 1
    fi
    firewall-cmd --state >/dev/null 2>&1 || return 1
    sync_lxd_firewalld_masquerade "$subnet" || return 1
    for scope in permanent runtime; do
        options=()
        [ "$scope" != permanent ] || options=(--permanent)
        status=0
        zone=$(LC_ALL=C firewall-cmd "${options[@]}" --get-zone-of-interface=lxdbr0 2>&1) || status=$?
        if [ "$status" -eq 2 ] && [ "$zone" = 'no zone' ]; then
            firewall-cmd "${options[@]}" --zone=trusted --add-interface=lxdbr0 || return 1
        elif [ "$status" -ne 0 ]; then
            return 1
        fi
        # Keep an existing runtime or administrator zone assignment.
    done
}

remove_lxd_iptables_masquerade() {
    local rules rule source backend="${1:-iptables}"
    local pattern='^-A POSTROUTING -s ([0-9./]+) ! -o lxdbr0 -m comment --comment "?oneclickvirt-lxd-ipv4"? -j MASQUERADE$'
    rules=$("$backend" -w -t nat -S POSTROUTING) || return 1
    while IFS= read -r rule; do
        if [[ "$rule" =~ $pattern ]]; then
            source="${BASH_REMATCH[1]}"
            "$backend" -w -t nat -D POSTROUTING -s "$source" ! -o lxdbr0 -m comment --comment oneclickvirt-lxd-ipv4 -j MASQUERADE || return 1
        fi
    done <<<"$rules"
}

remove_lxd_iptables_persistence() {
    local config_file="${1:-/etc/iptables/rules.v4}" temporary
    [ -f "$config_file" ] || return 0
    if [ -L "$config_file" ]; then
        config_file=$(readlink -f -- "$config_file") || return 1
    fi
    temporary=$(mktemp "${config_file}.XXXXXX") || return 1
    # Preserve the saved policy; runtime snapshots may differ from it.
    if ! cp -p -- "$config_file" "$temporary" || ! awk '
        /^-A POSTROUTING -s [0-9.]+\/[0-9]+ ! -o lxdbr0 -m comment --comment "?oneclickvirt-lxd-ipv4"? -j MASQUERADE$/ { next }
        { print }
    ' "$config_file" >"$temporary" || ! mv -f -- "$temporary" "$config_file"; then
        rm -f -- "$temporary"
        return 1
    fi
}

retire_lxd_iptables_masquerade() {
    local backend config_file version
    for backend in iptables-nft iptables-legacy iptables; do
        command -v "$backend" >/dev/null 2>&1 || continue
        version=$("$backend" --version) || return 1
        # An unloaded legacy NAT table contains no rules to retire. Avoid
        # requiring the legacy kernel modules on a host that only uses nft.
        if [[ "$version" == *legacy* ]]; then
            [ -e /proc/net/ip_tables_names ] || continue
            [ -r /proc/net/ip_tables_names ] || return 1
            grep -Fxq nat /proc/net/ip_tables_names || continue
        fi
        remove_lxd_iptables_masquerade "$backend" || return 1
    done
    if [ "$#" -eq 0 ]; then
        set -- /etc/iptables/rules.v4 /etc/sysconfig/iptables /etc/iptables/iptables.rules /etc/iptables/rules-save
    fi
    for config_file in "$@"; do
        remove_lxd_iptables_persistence "$config_file" || return 1
    done
}

add_iptables_masq_once() {
    local nat_enabled subnet prefix octet
    local subnet_octets=()
    nat_enabled=$(/snap/bin/lxc network get lxdbr0 ipv4.nat) || return 1
    if [ "$nat_enabled" != true ]; then
        remove_lxd_iptables_masquerade
        return $?
    fi
    subnet=$(/snap/bin/lxc network get lxdbr0 ipv4.address) || return 1
    [[ "$subnet" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1
    prefix="${subnet##*/}"
    ((10#$prefix >= 1 && 10#$prefix <= 32)) || return 1
    IFS=. read -r -a subnet_octets <<<"${subnet%/*}"
    for octet in "${subnet_octets[@]}"; do
        ((10#$octet <= 255)) || return 1
    done
    remove_lxd_iptables_masquerade || return 1
    iptables -w -t nat -C POSTROUTING -s "$subnet" ! -o lxdbr0 -m comment --comment oneclickvirt-lxd-ipv4 -j MASQUERADE 2>/dev/null ||
        iptables -w -t nat -A POSTROUTING -s "$subnet" ! -o lxdbr0 -m comment --comment oneclickvirt-lxd-ipv4 -j MASQUERADE || return 1
}

setup_network_preferences() {
    ensure_bridge_netfilter || {
        _red "br_netfilter is required for LXD host-address proxy port mappings"
        return 1
    }
    if [ -f /etc/gai.conf ]; then
        sed -i 's/.*precedence ::ffff:0:0\/96.*/precedence ::ffff:0:0\/96  100/g' /etc/gai.conf
        if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "networking.service"; then
            service_manager restart networking || return 1
        elif command -v rc-service >/dev/null 2>&1 && rc-service --list | grep -q "networking"; then
            service_manager restart networking || return 1
        fi
    fi
    # 优先使用nftables，不可用时降级为iptables
    local fw_backend=""
    if command -v nft >/dev/null 2>&1; then
        fw_backend="nft"
    else
        install_package nftables
        if command -v nft >/dev/null 2>&1; then
            fw_backend="nft"
        else
            fw_backend="ipt"
        fi
    fi
    if [ "$fw_backend" = "nft" ]; then
        configure_nft_masquerade || return 1
        # Persist only the installer-owned table. Writing `nft list ruleset`
        # here replaces administrator rules and can capture LXD's transient
        # interface-dependent tables before lxdbr0 exists at boot.
        mkdir -p /etc/nftables.d || return 1
        local nft_file=/etc/nftables.d/oneclickvirt-lxd.nft config_file
        config_file=$(nftables_persistence_file) || return 1
        save_lxd_nat_rules "$nft_file" || return 1
        mkdir -p -- "$(dirname -- "$config_file")" || return 1
        if [ -f "$config_file" ]; then
            if ! grep -qF 'include "/etc/nftables.d/oneclickvirt-lxd.nft"' "$config_file" 2>/dev/null &&
               ! grep -qF 'include "/etc/nftables.d/*.nft"' "$config_file" 2>/dev/null; then
                echo 'include "/etc/nftables.d/oneclickvirt-lxd.nft"' >> "$config_file" || return 1
            fi
        else
            cat > "$config_file" <<'NFTEOF' || return 1
#!/usr/sbin/nft -f
include "/etc/nftables.d/oneclickvirt-lxd.nft"
NFTEOF
        fi
        enable_nftables_persistence || return 1
    elif command -v firewall-cmd >/dev/null 2>&1; then
        install_package iptables || return 1
        configure_firewalld_masquerade || return 1
    else
        install_package iptables || return 1
        ensure_iptables_persistent || return 1
        add_iptables_masq_once || return 1
        # This branch changes only IPv4 NAT; do not overwrite IPv6 policy via
        # a global netfilter-persistent save after our atomic snapshot.
        local policy_file
        policy_file=$(iptables_persistence_file) || return 1
        save_iptables_persistence "$policy_file" iptables-save || return 1
    fi
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
    install_base_packages || return 1
    if ! command -v flock >/dev/null 2>&1; then install_package util-linux || return 1; fi
    check_cdn_file
    rebuild_cloud_init
    if command -v apt-get >/dev/null 2>&1; then
        apt-get remove cloud-init -y || _yellow "cloud-init removal failed; continuing with existing cloud-init"
    fi
    statistics_of_run_times
    install_lxd || return 1
    /snap/bin/lxd waitready --timeout=120 || return 1
    configure_resources || return 1
    load_storage_state
    setup_storage || return 1
    configure_lxd_network || return 1
    download_preset_files || return 1
    configure_system || return 1
    remove_system_limits || return 1
    install_dns_check || return 1
    ocv_with_firewall_lock setup_network_preferences || return 1
    ensure_runtime_network || return 1
    show_completion_info
}

if [[ "${ONECLICKVIRT_TESTING:-}" != "1" ]]; then
    main
fi
