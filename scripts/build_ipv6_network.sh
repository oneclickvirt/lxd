#!/bin/bash
# by https://github.com/oneclickvirt/lxd
# 2026.08.26
# oneclickvirt-ipv6-helper-version: 2026.09.20

# ./build_ipv6_network.sh LXC容器名称 <是否使用nft/ipt进行映射>

LXD_STATE_DIR="${LXD_STATE_DIR:-/usr/local/bin}"

state_file() {
    printf '%s/%s\n' "${LXD_STATE_DIR%/}" "$1"
}

# Keep the IPv6 probe in a dedicated cron.d file.  Updating the root user's
# crontab with `crontab -l | crontab -` is racy with administrators and with
# other provisioning jobs, and can erase unrelated scheduled work.  Paths are
# overridable for isolated tests.
cron_path_has_symlink() {
    local path="$1" prefix component rest
    [ -n "$path" ] || return 1
    case "$path" in
        /*) prefix=/; rest=${path#/} ;;
        *) prefix=.; rest=$path ;;
    esac
    while [ -n "$rest" ]; do
        component=${rest%%/*}
        if [ "$rest" = "$component" ]; then
            rest=
        else
            rest=${rest#*/}
        fi
        [ -n "$component" ] || continue
        if [ "$prefix" = / ]; then
            prefix="/$component"
        elif [ "$prefix" = . ]; then
            prefix="./$component"
        else
            prefix="$prefix/$component"
        fi
        [ -L "$prefix" ] && return 0
    done
    return 1
}

append_cron_once() {
    local cron_line="$1"
    local cron_dir="${OCV_IPV6_CRON_DIR:-/etc/cron.d}"
    local cron_file="${OCV_IPV6_CRON_FILE:-$cron_dir/oneclickvirt-ipv6}"
    local lock_file="${OCV_IPV6_CRON_LOCK:-/run/lock/oneclickvirt-ipv6.lock}"
    local lock_dir=${lock_file%/*} lock_fd tmp last_byte
    [ "$lock_dir" != "$lock_file" ] || lock_dir=.
    command -v flock >/dev/null 2>&1 || return 1
    cron_path_has_symlink "$cron_dir" && return 1
    [ -e "$cron_dir" ] || mkdir -p "$cron_dir" || return 1
    [ -d "$cron_dir" ] || return 1
    cron_path_has_symlink "$cron_file" && return 1
    [ -e "$cron_file" ] && [ -f "$cron_file" ] || [ ! -e "$cron_file" ] || return 1
    cron_path_has_symlink "$lock_dir" && return 1
    [ -e "$lock_dir" ] || mkdir -p "$lock_dir" || return 1
    [ -d "$lock_dir" ] || return 1
    [ -L "$lock_file" ] && return 1
    exec {lock_fd}>>"$lock_file" || return 1
    if ! flock -x "$lock_fd"; then
        exec {lock_fd}>&-
        return 1
    fi
    if cron_path_has_symlink "$cron_dir" || cron_path_has_symlink "$cron_file" ||
        cron_path_has_symlink "$lock_dir" || [ -L "$cron_file" ] || [ -L "$lock_file" ]; then
        flock -u "$lock_fd"; exec {lock_fd}>&-
        return 1
    fi
    if [ -f "$cron_file" ] && grep -Fqx "$cron_line" "$cron_file" 2>/dev/null; then
        flock -u "$lock_fd"; exec {lock_fd}>&-
        return 0
    fi
    tmp=$(mktemp "${cron_file}.tmp.XXXXXX") || {
        flock -u "$lock_fd"; exec {lock_fd}>&-
        return 1
    }
    if [ -f "$cron_file" ]; then
        cat "$cron_file" >"$tmp" || { rm -f "$tmp"; flock -u "$lock_fd"; exec {lock_fd}>&-; return 1; }
        last_byte=$(tail -c 1 "$cron_file" 2>/dev/null | od -An -t x1 | tr -d '[:space:]')
        [ -z "$last_byte" ] || [ "$last_byte" = 0a ] || printf '\n' >>"$tmp" || {
            rm -f "$tmp"; flock -u "$lock_fd"; exec {lock_fd}>&-; return 1
        }
    fi
    if ! printf '%s\n' "$cron_line" >>"$tmp" || ! chmod 0644 "$tmp" || ! mv -f "$tmp" "$cron_file"; then
        rm -f "$tmp"
        flock -u "$lock_fd"; exec {lock_fd}>&-
        return 1
    fi
    flock -u "$lock_fd"
    exec {lock_fd}>&-
}

has_unsafe_scalar_chars() {
    local value="$1"
    [[ "$value" == *$'\n'* || "$value" == *$'\r'* || "$value" == *$'\033'* ]]
}

normalize_ipv6_address() {
    local value="$1"
    ! has_unsafe_scalar_chars "$value" || return 1
    python3 - "$value" <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.ip_address(sys.argv[1].strip().strip("[]"))
except ValueError:
    raise SystemExit(1)
if address.version != 6:
    raise SystemExit(1)
print(address.compressed)
PY
}

normalize_ipv6_interface() {
    local value="$1"
    ! has_unsafe_scalar_chars "$value" || return 1
    python3 - "$value" <<'PY'
import ipaddress
import sys

try:
    interface = ipaddress.ip_interface(sys.argv[1].strip())
except ValueError:
    raise SystemExit(1)
if interface.version != 6:
    raise SystemExit(1)
print(interface.with_prefixlen)
PY
}

normalize_ipv6_network() {
    local value="$1"
    ! has_unsafe_scalar_chars "$value" || return 1
    python3 - "$value" <<'PY'
import ipaddress
import sys

try:
    network = ipaddress.ip_interface(sys.argv[1].strip()).network
except ValueError:
    raise SystemExit(1)
if network.version != 6:
    raise SystemExit(1)
print(network.with_prefixlen)
PY
}

write_atomic_scalar() {
    local file="$1" value="$2" dir tmp
    [ -n "$value" ] && ! has_unsafe_scalar_chars "$value" || return 1
    dir=${file%/*}
    [ "$dir" != "$file" ] || dir=.
    mkdir -p "$dir" || return 1
    tmp=$(mktemp "${file}.tmp.XXXXXX") || return 1
    if ! printf '%s\n' "$value" >"$tmp" || ! chmod 0644 "$tmp" || ! mv -f "$tmp" "$file"; then
        rm -f "$tmp"
        return 1
    fi
}

read_strict_ipv6_file() {
    local file="$1" value line_count
    [ -f "$file" ] || return 1
    line_count=$(awk 'END { print NR + 0 }' "$file" 2>/dev/null) || return 1
    [ "$line_count" -eq 1 ] || return 1
    IFS= read -r value <"$file" || [ -n "$value" ] || return 1
    normalize_ipv6_address "$value"
}

select_ipv6_interface() {
    local preferred_address="${1:-}" candidates="${2:-}"
    ! has_unsafe_scalar_chars "$preferred_address" || return 1
    python3 - "$preferred_address" "$candidates" <<'PY'
import ipaddress
import sys

preferred = sys.argv[1].strip()
values = []
for raw in sys.argv[2].splitlines():
    try:
        interface = ipaddress.ip_interface(raw.strip())
    except ValueError:
        continue
    if interface.version != 6:
        continue
    if preferred and interface.ip.compressed == preferred:
        print(interface.with_prefixlen)
        raise SystemExit(0)
    values.append(interface)
if values:
    print(values[0].with_prefixlen)
    raise SystemExit(0)
raise SystemExit(1)
PY
}

ipv6_reserved_addresses() {
    python3 - <<'PY'
import ipaddress
import json
import os
import re
import subprocess

env = dict(os.environ, LC_ALL="C", NO_COLOR="1")
try:
    addresses = json.loads(re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", subprocess.check_output(
        ["ip", "-j", "-6", "addr", "show"],
        stderr=subprocess.DEVNULL, env=env)))
    routes = json.loads(re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", subprocess.check_output(
        ["ip", "-j", "-6", "route", "show", "table", "all"],
        stderr=subprocess.DEVNULL, env=env)))
    if not isinstance(addresses, list) or not isinstance(routes, list):
        raise ValueError("invalid ip JSON")
except (OSError, subprocess.CalledProcessError, ValueError, KeyError, TypeError):
    raise SystemExit(1)
reserved = set()
for interface in addresses:
    for item in interface.get("addr_info", []):
        if item.get("family") == "inet6":
            reserved.add(ipaddress.IPv6Address(item["local"]))

def route_values(route, key):
    value = route.get(key)
    if value:
        yield value
    for group in ("nexthops", "multipath"):
        entries = route.get(group, [])
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if isinstance(entry, dict) and entry.get(key):
                yield entry[key]

for route in routes:
    for gateway in route_values(route, "gateway"):
        try:
            reserved.add(ipaddress.IPv6Address(gateway))
        except (ValueError, TypeError):
            continue
    destination = route.get("dst") or "default"
    if destination != "default":
        try:
            subnet = ipaddress.IPv6Network(destination, strict=False)
        except (ValueError, TypeError):
            # Some route kinds expose labels such as "local" or
            # "multicast" in dst. They are not addresses to reserve.
            continue
        if subnet.prefixlen == 128:
            reserved.add(subnet.network_address)
for address in sorted(reserved):
    print(address.compressed)
PY
}

random_ipv6_candidate() {
    local network="$1" excluded="${2:-}" reserved
    reserved=$(ipv6_reserved_addresses) || return 1
    python3 - "$network" "$excluded" "$reserved" <<'PY'
import ipaddress
import secrets
import sys

try:
    network = ipaddress.ip_network(sys.argv[1].strip(), strict=False)
    excluded = ipaddress.ip_address(sys.argv[2]) if sys.argv[2] else None
except ValueError:
    raise SystemExit(1)
if network.version != 6:
    raise SystemExit(1)
reserved = {ipaddress.IPv6Address(raw) for raw in sys.argv[3].splitlines() if raw}
if excluded is not None:
    reserved.add(excluded)
available = network.num_addresses - sum(address in network for address in reserved)
if available < 1:
    raise SystemExit(1)
for _ in range(256):
    candidate = ipaddress.ip_address(int(network.network_address) + secrets.randbelow(network.num_addresses))
    if candidate not in reserved:
        print(candidate.compressed)
        raise SystemExit(0)
for offset in range(min(network.num_addresses, 65536)):
    candidate = ipaddress.IPv6Address(int(network.network_address) + offset)
    if candidate not in reserved:
        print(candidate.compressed)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

generate_ipv6_candidates() {
    local network="$1" limit="${2:-65533}" reserved
    reserved=$(ipv6_reserved_addresses) || return 1
    python3 - "$network" "$limit" "$reserved" <<'PY'
import ipaddress
import sys

try:
    network = ipaddress.ip_network(sys.argv[1].strip(), strict=False)
    limit = int(sys.argv[2])
except (ValueError, IndexError):
    raise SystemExit(1)
if network.version != 6 or limit < 1:
    raise SystemExit(1)
reserved = {ipaddress.IPv6Address(raw) for raw in sys.argv[3].splitlines() if raw}
for offset in range(min(limit, network.num_addresses)):
    candidate = ipaddress.IPv6Address(int(network.network_address) + offset)
    if candidate not in reserved:
        print(candidate.compressed)
PY
}

get_container_ipv6() {
    local container_name="$1" value
    value=$(lxc list "$container_name" --format=json | jq -er '
        [.[0].state.network | to_entries[]? | .value.addresses[]?
            | select(.family == "inet6" and .scope == "global") | .address]
        | unique
        | if length == 1 then .[0] else error("expected exactly one global IPv6 address") end
    ') || return 1
    normalize_ipv6_address "$value"
}

is_virtual_machine() {
    local name="$1" type
    type=$(lxc info "$name" 2>/dev/null | awk -F': *' '$1 == "Type" {print $2; exit}')
    [ "$type" = "virtual-machine" ]
}

wait_for_vm_guest_agent() {
    local attempt
    # A running VM is not necessarily ready for exec yet. Bound each probe as
    # well as the number of probes so an unavailable agent cannot hang setup.
    for ((attempt = 0; attempt < 24; attempt++)); do
        if timeout 5 lxc exec "$CONTAINER_NAME" -- true >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

configure_vm_guest_ipv6() {
    local address="$1" guest_mac script unit
    is_virtual_machine "$CONTAINER_NAME" || return 0
    guest_mac=$(lxc config get "$CONTAINER_NAME" volatile.eth1.hwaddr 2>/dev/null || true)
    guest_mac=$(printf '%s' "$guest_mac" | tr '[:upper:]' '[:lower:]')
    [[ "$guest_mac" =~ ^[0-9a-f]{2}(:[0-9a-f]{2}){5}$ ]] || return 1
    address=$(normalize_ipv6_address "$address") || return 1
    wait_for_vm_guest_agent || return 1
    script=$(cat <<EOF
#!/bin/sh
set -eu
TARGET_MAC='$guest_mac'
TARGET_ADDRESS='$address'
TARGET_GATEWAY='fe80::1'
iface=''
for path in /sys/class/net/*; do
    [ -e "\$path/address" ] || continue
    mac=\$(cat "\$path/address" 2>/dev/null || true)
    if [ "\$(printf '%s' "\$mac" | tr '[:upper:]' '[:lower:]')" = "\$TARGET_MAC" ]; then
        iface=\$(basename "\$path")
        break
    fi
done
[ -n "\$iface" ] || exit 1
ip link set dev "\$iface" up
ip -6 addr replace "\$TARGET_ADDRESS/128" dev "\$iface"
ip -6 route replace default via "\$TARGET_GATEWAY" dev "\$iface" metric 50
EOF
)
    unit=$(cat <<'EOF'
[Unit]
Description=OneClickVirt routed IPv6 guest address
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/oneclickvirt-routed-ipv6
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
)
    printf '%s\n' "$script" | lxc exec "$CONTAINER_NAME" -- sh -c 'cat > /usr/local/sbin/oneclickvirt-routed-ipv6' || return 1
    printf '%s\n' "$unit" | lxc exec "$CONTAINER_NAME" -- sh -c 'cat > /etc/systemd/system/oneclickvirt-routed-ipv6.service' || return 1
    lxc exec "$CONTAINER_NAME" -- chmod 0755 /usr/local/sbin/oneclickvirt-routed-ipv6 || return 1
    lxc exec "$CONTAINER_NAME" -- systemctl daemon-reload || return 1
    lxc exec "$CONTAINER_NAME" -- systemctl enable --now oneclickvirt-routed-ipv6.service || return 1
}

get_host_ipv6_interface() {
    local raw
    raw=$(host_ipv6_json_rows addresses 2>/dev/null | awk -F '\t' '$3 == "global" {print $2}')
    select_ipv6_interface "" "$raw"
}

# 检测防火墙后端：优先nftables，回退iptables
detect_firewall_backend() {
    FW_BACKEND=""
    if command -v nft >/dev/null 2>&1; then
        FW_BACKEND="nft"
        return 0
    fi
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y nftables >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y nftables >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y nftables >/dev/null 2>&1
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --noconfirm nftables >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache nftables >/dev/null 2>&1
    fi
    if command -v nft >/dev/null 2>&1; then
        FW_BACKEND="nft"
        return 0
    fi
    FW_BACKEND="ipt"
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >/dev/null 2>&1
    fi
    return 0
}

save_firewall_rules() {
    if [ "$FW_BACKEND" = "nft" ]; then
        nft list ruleset > /etc/nftables.conf 2>/dev/null || return 1
        if command -v systemctl >/dev/null 2>&1; then
            systemctl enable nftables >/dev/null 2>&1 || return 1
        fi
    else
        mkdir -p /etc/iptables || return 1
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || return 1
        ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || return 1
        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save >/dev/null 2>&1 || return 1
        fi
    fi
    return 0
}

# 服务管理兼容性函数
service_manager() {
    local action=$1
    local service_name=$2
    local success=false
    
    case "$action" in
        daemon-reload)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl daemon-reload 2>/dev/null && success=true
            else
                success=true
            fi
            ;;
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
    esac
    
    $success && return 0 || return 1
}

# 输出颜色函数
_red() { printf '\033[31m\033[01m%s\033[0m\n' "$*"; }
_green() { printf '\033[32m\033[01m%s\033[0m\n' "$*"; }
_yellow() { printf '\033[33m\033[01m%s\033[0m\n' "$*"; }
_blue() { printf '\033[36m\033[01m%s\033[0m\n' "$*"; }

# 设置UTF-8环境
setup_locale() {
    utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "utf8|UTF-8")
    if [[ -z "$utf8_locale" ]]; then
        _yellow "No UTF-8 locale found"
    else
        export LC_ALL="$utf8_locale"
        export LANG="$utf8_locale"
        export LANGUAGE="$utf8_locale"
        _green "Locale set to $utf8_locale"
    fi
}

# 安装依赖包
install_package() {
    package_name=$1
    if command -v "$package_name" >/dev/null 2>&1; then
        _green "$package_name has been installed"
        _green "$package_name 已经安装"
    else
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "$package_name"; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$package_name" --fix-missing
        fi
        _green "$package_name has attempted to install"
        _green "$package_name 已尝试安装"
    fi
}

get_physical_interface() {
    local iface=""
    iface=$(LC_ALL=C NO_COLOR=1 ip -j route show default 2>/dev/null |
        python3 -c 'import json,re,sys; data=json.loads(re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]",b"",sys.stdin.buffer.read())); print(next((r.get("dev", "") for r in data if r.get("dst", "default") == "default"), ""))' 2>/dev/null)
    if [ -z "$iface" ]; then
        local iface_path candidate
        for iface_path in /sys/class/net/*; do
            [ -e "$iface_path" ] || continue
            candidate=$(basename "$iface_path")
            [ -e "/sys/devices/virtual/net/$candidate" ] && continue
            iface="$candidate"
            break
        done
    fi
    printf '%s\n' "$iface"
}

# Resolve the interface that owns the selected global IPv6 address. This keeps
# HE/6in4, sit/vti/GRE and routed-bridge deployments on their actual tunnel or
# bridge instead of guessing the first physical NIC.
host_ipv6_json_rows() {
    local mode="$1" target="${2:-}"
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "$mode" "$target" <<'PY'
import ipaddress
import json
import os
import re
import subprocess
import sys

mode, target = sys.argv[1:]
args = {
    "addresses": ["-6", "addr", "show"],
    "default": ["-6", "route", "show", "default"],
    "neighbors": ["-6", "neigh", "show", "dev", target],
}.get(mode)
if args is None:
    raise SystemExit(1)
try:
    env = dict(os.environ, LC_ALL="C", NO_COLOR="1")
    raw = subprocess.check_output(["ip", "-j", *args], env=env,
                                  stderr=subprocess.DEVNULL)
    data = json.loads(re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", raw))
    if not isinstance(data, list):
        raise ValueError("invalid ip JSON")
    if mode == "addresses":
        for interface in data:
            name = interface.get("ifname", "")
            for item in interface.get("addr_info", []):
                if item.get("family") != "inet6" or item.get("tentative") or "tentative" in item.get("flags", []):
                    continue
                cidr = f'{ipaddress.IPv6Address(item["local"]).compressed}/{item["prefixlen"]}'
                ipaddress.IPv6Interface(cidr)
                print(name, cidr, item.get("scope", ""), sep="\t")
    elif mode == "default":
        for route in data:
            if (route.get("dst") or "default") != "default":
                continue
            if route.get("dev"):
                print(route["dev"], route.get("gateway", ""), sep="\t")
            for group in ("nexthops", "multipath"):
                entries = route.get(group, [])
                if not isinstance(entries, list):
                    continue
                for entry in entries:
                    if isinstance(entry, dict) and entry.get("dev"):
                        print(entry["dev"], entry.get("gateway", ""), sep="\t")
    else:
        for neighbor in data:
            if neighbor.get("router") or "router" in neighbor.get("flags", []):
                print(ipaddress.IPv6Address(neighbor["dst"]))
except (OSError, subprocess.CalledProcessError, ValueError, KeyError, TypeError):
    raise SystemExit(1)
PY
}

# Pick the widest public IPv6 prefix while keeping the owning interface and
# address together. A host can expose a /128 and a delegated /38 or /64 on
# the same NIC; matching the preferred address alone would select the /128.
select_ipv6_uplink_row() {
    local preferred="${1:-}" requested="${2:-}" rows="${3:-}"
    printf '%s\n' "$rows" | python3 -c '
import ipaddress
import sys

preferred = sys.argv[1].strip()
requested = sys.argv[2].strip()
public = ipaddress.IPv6Network("2000::/3")
candidates = []
for raw in sys.stdin:
    fields = raw.rstrip("\n").split("\t")
    if len(fields) != 3 or fields[2] != "global":
        continue
    interface, cidr = fields[0], fields[1]
    if requested and interface != requested:
        continue
    try:
        address = ipaddress.IPv6Interface(cidr)
    except ValueError:
        continue
    if address.version != 6 or address.ip not in public or not address.ip.is_global:
        continue
    preferred_rank = 0 if preferred and address.ip.compressed == preferred else 1
    candidates.append((address.network.prefixlen, preferred_rank, interface, address.with_prefixlen))
if not candidates:
    raise SystemExit(1)
candidates.sort()
print(candidates[0][2], candidates[0][3], sep="\t")
' "$preferred" "$requested"
}

ipv6_uplink_interface() {
    local preferred="${1:-}" requested="${LXD_IPV6_UPLINK:-}" rows selected
    rows=$(host_ipv6_json_rows addresses) || return 1
    if [ -n "$requested" ] && [[ "$requested" =~ ^[A-Za-z0-9_.:-]{1,15}$ ]]; then
        selected=$(select_ipv6_uplink_row "$preferred" "$requested" "$rows" 2>/dev/null || true)
        if [ -n "$selected" ]; then
            printf '%s\n' "$selected" | awk -F '\t' 'NF {print $1; exit}'
            return 0
        fi
    fi
    selected=$(select_ipv6_uplink_row "$preferred" "" "$rows" 2>/dev/null || true)
    [ -n "$selected" ] || return 1
    printf '%s\n' "$selected" | awk -F '\t' 'NF {print $1; exit}'
}

ipv6_uplink_cidr() {
    local iface="$1" preferred="${2:-}" rows selected
    [ -n "$iface" ] || return 1
    rows=$(host_ipv6_json_rows addresses) || return 1
    selected=$(select_ipv6_uplink_row "$preferred" "$iface" "$rows" 2>/dev/null || true)
    [ -n "$selected" ] || return 1
    printf '%s\n' "$selected" | awk -F '\t' 'NF {print $2; exit}'
}

# A /128 host route cannot be treated as a public address pool. A routed /64,
# /38 or /127 remains usable when the upstream provides routing/NDP support.
ipv6_allocation_network() {
    local detected="${1:-}" requested="${LXD_IPV6_ROUTED_PREFIX:-}" value
    value="${requested:-$detected}"
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "$value" <<'PY'
import ipaddress
import sys

try:
    network = ipaddress.ip_network(sys.argv[1].strip(), strict=False)
except ValueError:
    raise SystemExit(1)
if network.version != 6 or network.prefixlen > 127:
    raise SystemExit(1)
if not network.subnet_of(ipaddress.IPv6Network("2000::/3")):
    raise SystemExit(1)
print(network.with_prefixlen)
PY
}

ipv6_pool_has_extra_address() {
    local network="$1" excluded="${2:-}"
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "$network" "$excluded" <<'PY'
import ipaddress
import sys

try:
    network = ipaddress.ip_network(sys.argv[1].strip(), strict=False)
    excluded = ipaddress.IPv6Address(sys.argv[2]) if sys.argv[2] else None
except ValueError:
    raise SystemExit(1)
if network.prefixlen > 127:
    raise SystemExit(1)
available = network.num_addresses - (1 if excluded is not None and excluded in network else 0)
raise SystemExit(0 if available > 0 else 1)
PY
}

disable_legacy_link_local_cleanup() {
    local legacy="${LXD_LEGACY_FE80_CLEANUP:-/usr/local/bin/remove_route.sh}" current
    [ -f "$legacy" ] || return 0
    # Remove only the minimal legacy helper generated by this project. A
    # user-maintained script that happens to mention fe80 must be preserved.
    awk '
        BEGIN { commands = 0; valid = 1 }
        /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
        /^[[:space:]]*ip([[:space:]]+-6)?[[:space:]]+addr[[:space:]]+del[[:space:]]+fe80:[0-9A-Fa-f:]+(\/[0-9]+)?[[:space:]]+dev[[:space:]]+[A-Za-z0-9_.:-]+[[:space:]]*$/ { commands++; next }
        { valid = 0 }
        END { exit !(valid && commands == 1) }
    ' "$legacy" || return 0
    # Do not rewrite the administrator's root crontab while removing a
    # legacy helper.  The helper is no longer installed by this project and
    # the dedicated cron.d entry is independently managed.
    rm -f -- "$legacy"
}

configure_ipv6_nat66_fallback() {
    local network="${LXD_IPV6_NETWORK:-lxdbr0}" parent current existing_mode
    if command -v lxc >/dev/null 2>&1 && [ -n "${CONTAINER_NAME:-}" ]; then
        parent=$(lxc config device get "$CONTAINER_NAME" eth0 parent 2>/dev/null || true)
        [[ "$parent" =~ ^[A-Za-z0-9_.:-]+$ ]] && network="$parent"
        current=$(lxc network get "$network" ipv6.address 2>/dev/null || true)
        if [ -z "$current" ] || [ "$current" = "none" ]; then
            if ! lxc network set "$network" ipv6.address auto 2>/dev/null; then
                _red "Unable to enable IPv6 addressing on ${network}; refusing NAT66 fallback." >&2
                return 1
            fi
        fi
        if ! lxc network set "$network" ipv6.nat true 2>/dev/null; then
            _red "Unable to enable IPv6 NAT on ${network}; refusing NAT66 fallback." >&2
            return 1
        fi
    fi
    existing_mode=$(cat "$(state_file lxd_ipv6_mode)" 2>/dev/null || true)
    if [ "$existing_mode" != routed ] && [ "$existing_mode" != public-nat ] &&
        [ ! -s "$(state_file lxd_ipv6_mapping_interface)" ]; then
        write_atomic_scalar "$(state_file lxd_ipv6_mode)" nat66 2>/dev/null || return 1
    fi
    _yellow "No additional routed IPv6 address is available; retaining the container IPv6 network and enabling NAT66 where supported."
    _yellow "宿主机没有可分配的额外公网 IPv6；保留容器 IPv6 网络，并在支持时启用 NAT66。"
}

# Check whether an IPv6 address is a usable GUA allocation source. Textual
# prefix tests are unsafe because the same address may contain leading zeros.
is_public_ipv6() {
    local address="${1:-}"
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "$address" <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.IPv6Address(sys.argv[1])
except ValueError:
    raise SystemExit(1)

global_unicast = ipaddress.IPv6Network("2000::/3")
non_public = (
    ipaddress.IPv6Network("2001::/32"),       # Teredo
    ipaddress.IPv6Network("2001:2::/48"),     # benchmarking
    ipaddress.IPv6Network("2001:10::/28"),    # ORCHID
    ipaddress.IPv6Network("2001:20::/28"),    # ORCHIDv2
    ipaddress.IPv6Network("2001:db8::/32"),   # documentation
    ipaddress.IPv6Network("2002::/16"),       # 6to4
    ipaddress.IPv6Network("3fff::/20"),       # documentation
)
usable = (
    address in global_unicast
    and address.is_global
    and not address.is_private
    and not address.is_multicast
    and not any(address in prefix for prefix in non_public)
)
raise SystemExit(0 if usable else 1)
PY
}

# 检查IPv6地址是否为私有地址
is_private_ipv6() {
    ! is_public_ipv6 "${1:-}"
}

# 获取公网IPv6地址
check_ipv6() {
    local candidate state_path normalized prefix fallback network
    state_path=$(state_file lxd_check_ipv6)
    IPV6=""
    fallback=""
    while IFS= read -r candidate; do
        prefix="${candidate##*/}"
        candidate=${candidate%/*}
        if normalized=$(normalize_ipv6_address "$candidate" 2>/dev/null) && ! is_private_ipv6 "$normalized"; then
            fallback="${fallback:-$normalized}"
            if network=$(ipv6_allocation_network "${normalized}/${prefix}" 2>/dev/null) &&
                ipv6_pool_has_extra_address "$network" "$normalized"; then
                IPV6="$normalized"
                break
            fi
        fi
    done < <(host_ipv6_json_rows addresses 2>/dev/null | awk -F '\t' '$3 == "global" {print $2}')
    [ -n "$IPV6" ] || IPV6="$fallback"
    [ -n "$IPV6" ] || return 1
    write_atomic_scalar "$state_path" "$IPV6"
    printf '%s\n' "$IPV6"
}

# 更新系统配置参数
update_sysctl() {
    local sysctl_config="$1" key value custom_conf
    local use_etc_sysctl_conf=false
    # 格式: key=value
    key="${sysctl_config%%=*}"
    value="${sysctl_config#*=}"
    # 目标配置文件（systemd 方式）
    custom_conf="/etc/sysctl.d/99-custom.conf"
    mkdir -p /etc/sysctl.d || return 1
    # 检查 /etc/sysctl.conf 是否存在并且在系统加载路径中
    if [ -f /etc/sysctl.conf ]; then
        if grep -q "/etc/sysctl.conf" /etc/sysctl.d/README* 2>/dev/null || \
           grep -q "/etc/sysctl.conf" /lib/systemd/system/sysctl.service 2>/dev/null; then
            use_etc_sysctl_conf=true
        fi
    fi
    # 更新 /etc/sysctl.d/99-custom.conf
    if grep -q "^$sysctl_config" "$custom_conf" 2>/dev/null; then
        : # 已经有正确配置，跳过
    elif grep -q "^#$sysctl_config" "$custom_conf" 2>/dev/null; then
        sed -i "s/^#$sysctl_config/$sysctl_config/" "$custom_conf" || return 1
    elif grep -q "^$key" "$custom_conf" 2>/dev/null; then
        sed -i "s|^$key.*|$sysctl_config|" "$custom_conf" || return 1
    else
        echo "$sysctl_config" >> "$custom_conf" || return 1
    fi
    # 如果系统还在用 /etc/sysctl.conf，也同步更新
    if [ "$use_etc_sysctl_conf" = true ]; then
        if grep -q "^$sysctl_config" /etc/sysctl.conf; then
            : # 已经有正确配置
        elif grep -q "^#$sysctl_config" /etc/sysctl.conf; then
            sed -i "s/^#$sysctl_config/$sysctl_config/" /etc/sysctl.conf || return 1
        elif grep -q "^$key" /etc/sysctl.conf; then
            sed -i "s|^$key.*|$sysctl_config|" /etc/sysctl.conf || return 1
        else
            echo "$sysctl_config" >> /etc/sysctl.conf || return 1
        fi
    fi
    sysctl -w "$key=$value" >/dev/null 2>&1 || return 1
}

lxd_container_status_code() {
    lxc list "$1" --format=json 2>/dev/null |
        jq -er --arg name "$1" '[.[] | select(.name == $name) | .status_code] |
            if length == 1 then .[0] else error("container status is unavailable") end'
}

# 等待容器状态变更
wait_for_container_status() {
    local container_name=$1 target_status=$2 timeout=$3
    local interval=3 elapsed_time=0 status expected_code
    case "$target_status" in
        RUNNING) expected_code=103 ;;
        STOPPED) expected_code=102 ;;
        *) return 1 ;;
    esac
    while [ "$elapsed_time" -lt "$timeout" ]; do
        status=$(lxd_container_status_code "$container_name") || return 1
        if [ "$status" = "$expected_code" ]; then
            return 0
        fi
        echo "Waiting for the container \"$container_name\" to $target_status..."
        echo "${status}"
        sleep $interval
        elapsed_time=$((elapsed_time + interval))
    done
    return 1
}

# 使用网络设备方式映射IPv6
setup_network_device_mapping() {
    local ipv6_state host_address allocation_cidr
    ipv6_state=$(state_file lxd_check_ipv6)
    IPV6=$(read_strict_ipv6_file "$ipv6_state" 2>/dev/null || true)
    if [ -z "$IPV6" ]; then
        IPV6=$(check_ipv6) || return 1
    fi
    ipv6_network_name=$(ipv6_uplink_interface "$IPV6" 2>/dev/null || true)
    ip_network_gam=$(ipv6_uplink_cidr "$ipv6_network_name" "$IPV6" 2>/dev/null || true)
    _yellow "Local IPV6 address: $ip_network_gam"
    if [ -n "$ip_network_gam" ]; then
        # Linux suppresses ordinary router advertisements after forwarding is
        # enabled unless the uplink explicitly opts in. Keep SLAAC routes.
        update_sysctl "net.ipv6.conf.${ipv6_network_name}.accept_ra=2" || return 1
        # Incus/LXD refuses to start a routed NIC unless its global proxy NDP
        # switch is enabled. Keep the uplink explicit too: this is required
        # for upstream neighbor discovery, while the global key is the
        # runtime's mandatory capability check.
        update_sysctl "net.ipv6.conf.all.proxy_ndp=1" || return 1
        update_sysctl "net.ipv6.conf.${ipv6_network_name}.proxy_ndp=1" || return 1
        update_sysctl "net.ipv6.conf.all.forwarding=1" || return 1
        # update_sysctl already applies each setting. A blanket reload can
        # restore stale RA/forwarding values and interrupt host IPv6.
        allocation_cidr=$(ipv6_allocation_network "$ip_network_gam" 2>/dev/null || true)
        host_address=${ip_network_gam%/*}
        if [ -z "$allocation_cidr" ] || ! ipv6_pool_has_extra_address "$allocation_cidr" "$host_address"; then
            _red "No additional IPv6 address is available in $ip_network_gam"
            _red "宿主机前缀没有可分配的额外 IPv6 地址（/128 不是地址池）"
            configure_ipv6_nat66_fallback || return 1
            return 0
        fi
        lxc_ipv6=$(random_ipv6_candidate "$allocation_cidr" "$host_address") || {
            _red "No additional IPv6 address is available in $allocation_cidr"
            configure_ipv6_nat66_fallback || return 1
            return 0
        }
        _green "Container $CONTAINER_NAME IPV6:"
        _green "$lxc_ipv6"
        if ! lxc stop "$CONTAINER_NAME" 2>/dev/null; then
            [ "$(lxd_container_status_code "$CONTAINER_NAME")" = 102 ] || return 1
        fi
        sleep 3
        wait_for_container_status "$CONTAINER_NAME" "STOPPED" 24 || return 1
        lxc config device remove "$CONTAINER_NAME" eth1 2>/dev/null || true
        if ! lxc config device add "$CONTAINER_NAME" eth1 nic nictype=routed parent="$ipv6_network_name" ipv6.address="$lxc_ipv6"; then
            _red "Failed to add routed IPv6 device for $CONTAINER_NAME"
            _red "为 $CONTAINER_NAME 添加 routed IPv6 设备失败"
            return 1
        fi
        sleep 3
        start_lxd_instance "$CONTAINER_NAME" || return 1
        # Routed NICs on LXD VMs are visible to the guest but do not receive
        # an address from LXD. Install a small guest-side systemd unit so the
        # address and route survive VM reboot and stop/start cycles. LXC
        # containers keep their existing runtime-managed configuration.
        if is_virtual_machine "$CONTAINER_NAME"; then
            if ! configure_vm_guest_ipv6 "$lxc_ipv6"; then
                # Generic cloud VM images may not include the LXD guest agent;
                # without it there is no safe post-boot channel to configure
                # the routed NIC. Remove the unusable device and keep IPv6
                # egress through the managed NAT66 network as a bounded fallback.
                _yellow "Routed IPv6 guest configuration failed; falling back to managed IPv6 NAT"
                _yellow "独立 IPv6 客体配置失败，回退到受管 IPv6 NAT"
                lxc stop "$CONTAINER_NAME" 2>/dev/null || true
                wait_for_container_status "$CONTAINER_NAME" "STOPPED" 24 || return 1
                lxc config device remove "$CONTAINER_NAME" eth1 2>/dev/null || true
                start_lxd_instance "$CONTAINER_NAME" || return 1
                configure_ipv6_nat66_fallback || return 1
                _red "Managed NAT restored, but the requested independent IPv6 was not configured" >&2
                _red "已恢复受管 NAT，但请求的独立 IPv6 未配置成功" >&2
                return 1
            fi
        fi
        handle_fe80_gateway "$ipv6_gateway_fe80" "$ipv6_network_name"
        setup_ipv6_cron || return 1
        write_atomic_scalar "${CONTAINER_NAME}_v6" "$lxc_ipv6" || return 1
        write_atomic_scalar "$(state_file lxd_ipv6_mode)" routed || return 1
    else
        _red "No host IPv6 network address found for routed mapping"
        _red "未找到宿主机 IPv6 网络地址，无法使用 routed 方式映射"
        return 1
    fi
}

# 处理fe80网关
handle_fe80_gateway() {
    local gateway_kind="${1:-N}" interface="${2:-}"
    disable_legacy_link_local_cleanup
    if [[ "$gateway_kind" == "Y" ]]; then
        _blue "Retaining the link-local IPv6 gateway on ${interface:-the uplink}; it is required for RA/NDP."
    else
        _blue "Retaining link-local IPv6 addresses on ${interface:-the uplink}; no destructive cleanup is performed."
    fi
}

# 设置IPv6相关的定时任务
setup_ipv6_cron() {
    append_cron_once '*/1 * * * * root curl --noproxy '\''*'\'' -6 -fsS --connect-timeout 6 --max-time 6 https://ipv6.ip.sb && curl --noproxy '\''*'\'' -6 -fsS --connect-timeout 6 --max-time 6 https://ipv6.ip.sb'
}

# 使用nft/ipt映射IPv6
setup_firewall_mapping() {
    if ! IPV6_NETWORK=$(ipv6_allocation_network "${IPV6_NETWORK:-}" 2>/dev/null) ||
        ! ipv6_pool_has_extra_address "$IPV6_NETWORK" "${IPV6:-}"; then
        configure_ipv6_nat66_fallback || return 1
        return 0
    fi
    detect_firewall_backend
    if [ "$FW_BACKEND" = "nft" ]; then
        setup_nft_mapping
    else
        install_package netfilter-persistent
        setup_ipt_mapping
    fi
}

# 使用nftables映射IPv6
setup_nft_mapping() {
    local found_ipv6=""
    while IFS= read -r IPV6; do
        if [[ $IPV6 == "$CONTAINER_IPV6" ]]; then
            continue
        fi
        if ! ping6 -c1 -w1 -q "$IPV6" &>/dev/null; then
            if ! nft list ruleset 2>/dev/null | grep -F "ip6 daddr $IPV6" | grep -Fq "dnat to $CONTAINER_IPV6"; then
                _green "$IPV6"
                found_ipv6="$IPV6"
                break
            fi
        fi
        _yellow "$IPV6"
    done < <(generate_ipv6_candidates "$IPV6_NETWORK" 65533)
    if [ -z "$found_ipv6" ]; then
        _red "No IPV6 address available, no auto mapping"
        _red "无可用 IPV6 地址，不进行自动映射"
        exit 1
    fi
    IPV6="$found_ipv6"
    write_atomic_scalar "$(state_file lxd_ipv6_mapping_interface)" "$interface" || return 1
    write_atomic_scalar "$(state_file lxd_ipv6_mapping_prefix_len)" 128 || return 1
    write_atomic_scalar "$(state_file lxd_ipv6_mode)" public-nat || return 1
    ip -6 addr replace "$IPV6/128" dev "$interface" || return 1
    # 创建nftables IPv6 NAT表
    if ! nft list table ip6 lxd_ipv6_nat >/dev/null 2>&1; then
        nft add table ip6 lxd_ipv6_nat || return 1
    fi
    if ! nft list chain ip6 lxd_ipv6_nat prerouting >/dev/null 2>&1; then
        nft 'add chain ip6 lxd_ipv6_nat prerouting { type nat hook prerouting priority -100; policy accept; }' || return 1
    fi
    if ! nft list chain ip6 lxd_ipv6_nat postrouting >/dev/null 2>&1; then
        nft 'add chain ip6 lxd_ipv6_nat postrouting { type nat hook postrouting priority 100; policy accept; }' || return 1
    fi
    nft add rule ip6 lxd_ipv6_nat prerouting ip6 daddr "$IPV6" dnat to "$CONTAINER_IPV6" || return 1
    nft add rule ip6 lxd_ipv6_nat postrouting ip6 saddr "$CONTAINER_IPV6" snat to "$IPV6" || return 1
    # 持久化
    setup_persistence_service || return 1
    save_firewall_rules || return 1
    test_ipv6_connectivity "$IPV6"
    write_atomic_scalar "${CONTAINER_NAME}_v6" "$IPV6"
}

# 使用iptables映射IPv6
setup_ipt_mapping() {
    # 寻找未使用的子网内的一个IPV6地址
    local found_ipv6=""
    while IFS= read -r IPV6; do
        if [[ $IPV6 == "$CONTAINER_IPV6" ]]; then
            continue
        fi
        if ! ping6 -c1 -w1 -q "$IPV6" &>/dev/null; then
            if ! ip6tables -t nat -C PREROUTING -d "$IPV6" -j DNAT --to-destination "$CONTAINER_IPV6" &>/dev/null; then
                _green "$IPV6"
                found_ipv6="$IPV6"
                break
            fi
        fi
        _yellow "$IPV6"
    done < <(generate_ipv6_candidates "$IPV6_NETWORK" 65533)
    # 检查是否找到未使用的 IPV6 地址
    if [ -z "$found_ipv6" ]; then
        _red "No IPV6 address available, no auto mapping"
        _red "无可用 IPV6 地址，不进行自动映射"
        exit 1
    fi
    IPV6="$found_ipv6"
    write_atomic_scalar "$(state_file lxd_ipv6_mapping_interface)" "$interface" || return 1
    write_atomic_scalar "$(state_file lxd_ipv6_mapping_prefix_len)" 128 || return 1
    write_atomic_scalar "$(state_file lxd_ipv6_mode)" public-nat || return 1
    # 映射 IPV6 地址到容器的私有 IPV6 地址
    ip -6 addr replace "$IPV6/128" dev "$interface" || return 1
    ip6tables -t nat -A PREROUTING -d "$IPV6" -j DNAT --to-destination "$CONTAINER_IPV6" || return 1
    ip6tables -t nat -A POSTROUTING -s "$CONTAINER_IPV6" -j SNAT --to-source "$IPV6" || return 1
    # 设置持久化服务
    setup_persistence_service || return 1
    # 保存iptables规则
    save_firewall_rules || return 1
    # 测试连通性
    test_ipv6_connectivity "$IPV6"
    # 写入信息
    write_atomic_scalar "${CONTAINER_NAME}_v6" "$IPV6"
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

# 设置持久化服务
setup_persistence_service() {
    if [ ! -f /usr/local/bin/add-ipv6.sh ]; then
        if ! wget "${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/add-ipv6.sh" -O /usr/local/bin/add-ipv6.sh; then
            _red "Failed to download add-ipv6.sh"
            _red "下载 add-ipv6.sh 失败"
            return 1
        fi
        chmod +x /usr/local/bin/add-ipv6.sh || return 1
    else
        echo "Script already exists. Skipping installation."
    fi
    if [ ! -f /etc/systemd/system/add-ipv6.service ]; then
        if ! wget "${cdn_success_url}https://raw.githubusercontent.com/oneclickvirt/lxd/main/scripts/add-ipv6.service" -O /etc/systemd/system/add-ipv6.service; then
            _red "Failed to download add-ipv6.service"
            _red "下载 add-ipv6.service 失败"
            return 1
        fi
        chmod +x /etc/systemd/system/add-ipv6.service || return 1
        service_manager daemon-reload || return 1
        service_manager enable add-ipv6.service || return 1
        service_manager start add-ipv6.service || return 1
    else
        echo "Service already exists. Skipping installation."
    fi
}

# 保存iptables规则 (已废弃，使用save_firewall_rules替代)
save_iptables_rules() {
    save_firewall_rules
}

# 测试IPv6连通性
rdisc6_router_addresses() {
    python3 -c '
import ipaddress, re, sys
raw = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", sys.stdin.read())
seen = set()
for line in raw.splitlines():
    if not any(label in line.casefold() for label in ("router", "routeur", "路由器")):
        continue
    for token in re.findall(r"[0-9A-Fa-f:]+", line):
        try:
            address = ipaddress.IPv6Address(token)
        except ValueError:
            continue
        if address not in seen:
            seen.add(address)
            print(address.compressed)
'
}

ensure_ipv6_default_route() {
    local route iface gateway raw candidates="" output
    route=$(host_ipv6_json_rows default 2>/dev/null || true)
    [ -n "$route" ] && return 0
    iface=$(ipv6_uplink_interface 2>/dev/null || get_physical_interface) || return 1
    [[ "$iface" =~ ^[A-Za-z0-9_.:-]{1,15}$ ]] || return 1
    while IFS= read -r raw; do
        raw=$(normalize_ipv6_address "$raw" 2>/dev/null || true)
        [ -n "$raw" ] && candidates="${candidates}${raw}\n"
    done < <(host_ipv6_json_rows neighbors "$iface" 2>/dev/null)
    if [ -z "$candidates" ] && command -v rdisc6 >/dev/null 2>&1; then
        output=$(LC_ALL=C NO_COLOR=1 timeout 10 rdisc6 "$iface" 2>/dev/null || true)
        while IFS= read -r raw; do
            raw=$(normalize_ipv6_address "$raw" 2>/dev/null || true)
            [ -n "$raw" ] && candidates="${candidates}${raw}\n"
        done < <(printf '%s\n' "$output" | rdisc6_router_addresses)
    fi
    [ -n "$candidates" ] || return 1
    while IFS= read -r gateway; do
        [ -n "$gateway" ] || continue
        ip -6 route replace default via "$gateway" dev "$iface" metric 4096 2>/dev/null || continue
        if host_ipv6_json_rows default 2>/dev/null | awk -F '\t' -v dev="$iface" '$1 == dev {found=1} END {exit !found}' &&
           curl --noproxy '*' -6 -fsS --connect-timeout 6 --max-time 6 https://ipv6.ip.sb >/dev/null 2>&1; then
            _green "Recovered IPv6 default route via ${gateway} on ${iface}."
            return 0
        fi
        ip -6 route del default via "$gateway" dev "$iface" metric 4096 2>/dev/null ||
            ip -6 route del default dev "$iface" metric 4096 2>/dev/null || true
    done < <(printf '%b' "$candidates" | awk 'NF && !seen[$0]++')
    return 1
}

test_ipv6_connectivity() {
    local ipv6_addr=$1
    if ping6 -c 3 "$ipv6_addr" &>/dev/null; then
        _green "$CONTAINER_NAME The external IPV6 address of the container is $ipv6_addr"
        _green "$CONTAINER_NAME 容器的外网IPV6地址为 $ipv6_addr"
    else
        _red "Mapping failure"
        _red "映射失败"
        exit 1
    fi
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
    if [ ! -d "$LXD_STATE_DIR" ]; then
        mkdir -p "$LXD_STATE_DIR"
    fi
    disable_legacy_link_local_cleanup
    setup_locale
    CONTAINER_NAME="$1"
    if [[ -z "$CONTAINER_NAME" || "$CONTAINER_NAME" == *[!A-Za-z0-9_.-]* ]]; then
        _red "Invalid LXC container name"
        exit 1
    fi
    use_iptables="${2:-N}"
    use_iptables=$(echo "$use_iptables" | tr '[:upper:]' '[:lower:]')
    # 安装必要的包
    install_package sudo
    install_package lshw
    install_package jq
    install_package net-tools
    install_package cron
    install_package python3
    # 先选择真正拥有公网 IPv6 的接口；没有公网地址时保留双栈容器并
    # 回退到其受管网络的 NAT66，而不是把外部查询结果当作本地地址。
    if ! IPV6=$(check_ipv6 2>/dev/null); then
        configure_ipv6_nat66_fallback || return 1
        return 0
    fi
    if ! ensure_ipv6_default_route; then
        _red "A public IPv6 address exists but no verified IPv6 default route is available." >&2
        _yellow "Falling back to the managed network's NAT66 mode." >&2
        configure_ipv6_nat66_fallback || return 1
        return 0
    fi
    interface=$(ipv6_uplink_interface "$IPV6" 2>/dev/null || true)
    if [ -z "$interface" ]; then
        _red "No physical network interface found"
        _red "未找到物理网卡"
        configure_ipv6_nat66_fallback || return 1
        return 0
    fi
    _yellow "NIC $interface"
    _yellow "网卡 $interface"
    # 等待容器运行
    wait_for_container_status "$CONTAINER_NAME" "RUNNING" 24
    # 获取指定LXC容器的内网IPV6
    CONTAINER_IPV6=$(get_container_ipv6 "$CONTAINER_NAME" 2>/dev/null || true)
    if [ -z "$CONTAINER_IPV6" ]; then
        _red "Container has no intranet IPV6 address, no auto-mapping"
        _red "容器无内网IPV6地址，不进行自动映射"
        configure_ipv6_nat66_fallback || return 1
        return 0
    fi
    _blue "The container with the name $CONTAINER_NAME has an intranet IPV6 address of $CONTAINER_IPV6"
    _blue "$CONTAINER_NAME 容器的内网IPV6地址为 $CONTAINER_IPV6"
    # 获取宿主机的IPV6地址（含CIDR）
    ipv6_address=$(ipv6_uplink_cidr "$interface" "$IPV6" 2>/dev/null || true)
    if [[ $ipv6_address == */* ]]; then
        ipv6_length=$(echo "$ipv6_address" | awk -F '/' '{ print $2 }')
        _green "subnet size: $ipv6_length"
        _green "子网大小: $ipv6_length"
    else
        _green "Subnet size for IPV6 not queried"
        _green "查询不到IPV6的子网大小"
        exit 1
    fi
    if ! [[ "$ipv6_length" =~ ^[0-9]+$ ]] || [ "$ipv6_length" -lt 1 ] || [ "$ipv6_length" -gt 128 ]; then
        _red "Invalid IPv6 subnet prefix length: $ipv6_length"
        _red "无效的IPv6子网前缀长度: $ipv6_length"
        exit 1
    fi
    write_atomic_scalar "$(state_file lxd_ipv6_prefix_len)" "$ipv6_length" || exit 1
    IPV6_NETWORK=$(ipv6_allocation_network "$ipv6_address" 2>/dev/null) || {
        _red "Cannot parse host IPv6 network: $ipv6_address"
        configure_ipv6_nat66_fallback || return 1
        return 0
    }
    if ! ipv6_pool_has_extra_address "$IPV6_NETWORK" "${ipv6_address%/*}"; then
        configure_ipv6_nat66_fallback || return 1
        return 0
    fi
    # fe80检测
    output=$(host_ipv6_json_rows default 2>/dev/null | awk -F '\t' '$2 != "" {print $2}')
    num_lines=$(echo "$output" | wc -l)
    ipv6_gateway=""
    if [ "$num_lines" -eq 1 ]; then
        ipv6_gateway="$output"
    elif [ "$num_lines" -ge 2 ]; then
        non_fe80_lines=$(echo "$output" | grep -v '^fe80')
        if [ -n "$non_fe80_lines" ]; then
            ipv6_gateway=$(echo "$non_fe80_lines" | head -n 1)
        else
            ipv6_gateway=$(echo "$output" | head -n 1)
        fi
    fi
    # 判断fe80是否已加白
    if [[ $ipv6_gateway == fe80* ]]; then
        ipv6_gateway_fe80="Y"
    else
        ipv6_gateway_fe80="N"
    fi
    # 检查是否存在 IPV6
    if [ -z "$IPV6_NETWORK" ]; then
        _red "No IPV6 subnet, no automatic mapping"
        _red "无 IPV6 子网，不进行自动映射"
        exit 1
    fi
    _blue "The IPV6 subnet is $IPV6_NETWORK"
    _blue "宿主机的IPV6子网为 $IPV6_NETWORK"
    # 根据选项决定映射方式
    if [[ $use_iptables == n ]]; then
        setup_network_device_mapping || return 1
    else
        cdn_urls=("https://cdn0.spiritlhl.top/" "http://cdn1.spiritlhl.net/" "http://cdn2.spiritlhl.net/" "http://cdn3.spiritlhl.net/" "http://cdn4.spiritlhl.net/")
        check_cdn_file
        setup_firewall_mapping
    fi
}

if [ "${ONECLICKVIRT_TESTING:-0}" != "1" ]; then
    main "$@"
fi
