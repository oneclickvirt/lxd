#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export ONECLICKVIRT_TESTING=1
export LXD_STATE_DIR
LXD_STATE_DIR=$(mktemp -d)
trap 'rm -rf "$LXD_STATE_DIR"' EXIT

# The allocator consumes iproute2 JSON. Use a deterministic fixture so this
# contract test also runs on macOS and minimal CI runners without `ip`.
TEST_BIN_DIR=$(mktemp -d)
trap 'rm -rf "$LXD_STATE_DIR" "$TEST_BIN_DIR"' EXIT
cat >"$TEST_BIN_DIR/ip" <<'STUB'
#!/usr/bin/env bash
case "$*" in
    '-j -6 addr show')
        if [[ "${LXD_TEST_TUNNEL:-}" == 1 ]]; then
            printf '\033[36m%s\033[0m\n' '[{"ifname":"he-ipv6","addr_info":[{"family":"inet6","local":"2606:4700::1","prefixlen":64,"scope":"global"}]}]'
        elif [[ "${LXD_TEST_SAME_INTERFACE:-}" == 1 ]]; then
            printf '\033[36m%s\033[0m\n' '[{"ifname":"eth0","addr_info":[{"family":"inet6","local":"2a14:7c0:1002:10f8::1","prefixlen":128,"scope":"global"},{"family":"inet6","local":"2a14:7c0:1002:10f8::2","prefixlen":38,"scope":"global"}]}]'
        else
            printf '%s\n' '[{"ifname":"eth0","addr_info":[]}]'
        fi
        ;;
    '-j -6 route show default')
        if [[ -n "${LXD_TEST_ROUTE_STATE:-}" && -f "$LXD_TEST_ROUTE_STATE" ]]; then
            printf '%s\n' '[{"dst":"default","dev":"eth0","gateway":"2606:4700::1"}]'
        else
            printf '%s\n' '[]'
        fi
        ;;
    '-j -6 neigh show dev eth0')
        printf '%s\n' '[{"dst":"2606:4700::1","router":true}]'
        ;;
    '-j -6 route show table all')
        printf '%s\n' '[]'
        ;;
    *)
        printf '%s\n' 'default via 2606:4700::1 dev eth0'
        ;;
esac
STUB
chmod +x "$TEST_BIN_DIR/ip"
export PATH="$TEST_BIN_DIR:$PATH"

# shellcheck disable=SC1091 # The test sources the repository script through a computed path.
source "$ROOT_DIR/scripts/build_ipv6_network.sh"

gateway_rows=$(printf '\033[35mRouteur : fe80::1\033[0m\n路由器：fe80::2\nRouter: fe80::3\n' | rdisc6_router_addresses)
[[ "$gateway_rows" == $'fe80::1\nfe80::2\nfe80::3' ]] || fail "localized router-advertisement gateways: $gateway_rows"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    [ "$expected" = "$actual" ] || fail "$label: expected [$expected], got [$actual]"
}

assert_eq "2001:db8::1" "$(normalize_ipv6_address '2001:0db8:0:0::1')" "normalize IPv6"
assert_eq "2001:db8:abcd::10/120" "$(normalize_ipv6_interface '2001:0db8:abcd::10/120')" "normalize /120 interface"
assert_eq "2001:db8:abcd::/120" "$(normalize_ipv6_network '2001:db8:abcd::10/120')" "normalize /120 network"

if normalize_ipv6_address $'2001:db8::1\nwarning'; then
    fail "polluted IPv6 value must be rejected"
fi
if normalize_ipv6_interface 'inet6 2001:db8::1/64 scope global'; then
    fail "diagnostic IPv6 interface output must be rejected"
fi

state_path=$(state_file lxd_check_ipv6)
write_atomic_scalar "$state_path" "2001:db8::2"
assert_eq "2001:db8::2" "$(read_strict_ipv6_file "$state_path")" "read strict state"
grep -Fq 'oneclickvirt-lxd-ipv6-proxy-ndp.service' "$ROOT_DIR/scripts/build_ipv6_network.sh" ||
    fail "host proxy-NDP sysctl persistence service is missing"
printf '2001:db8::2\n2001:db8::3\n' >"$state_path"
if read_strict_ipv6_file "$state_path"; then
    fail "multi-line cached IPv6 state must be rejected"
fi

interfaces=$'2001:db8::1/64\n2001:db8:1::2/120'
assert_eq "2001:db8:1::2/120" "$(select_ipv6_interface '2001:db8:1::2' "$interfaces")" "select preferred interface"

candidate=$(random_ipv6_candidate '2001:db8::/127' '2001:db8::')
assert_eq "2001:db8::1" "$candidate" "generate /127 candidate"
if random_ipv6_candidate '2001:db8::1/128' '2001:db8::1'; then
    fail "/128 with its only address excluded must fail"
fi

mapfile -t candidates < <(generate_ipv6_candidates '2001:db8::/126' 20)
assert_eq "4" "${#candidates[@]}" "bounded /126 expansion"
assert_eq "2001:db8::" "${candidates[0]}" "first /126 address"
assert_eq "2001:db8::3" "${candidates[3]}" "last /126 address"

assert_eq "2a14:7c0:1000::/38" "$(ipv6_allocation_network '2a14:7c0:1002:10f8::1/38')" "normalize non-nibble routed prefix"
assert_eq "2606:4700::/127" "$(ipv6_allocation_network '2606:4700::1/127')" "retain /127 routed prefix"
assert_eq "2606:4700::/64" "$(ipv6_allocation_network '2606:4700::1/64')" "retain SLAAC /64 shape"
if ipv6_allocation_network '2606:4700::1/128' >/dev/null; then
    fail "/128 was accepted as an IPv6 allocation pool"
fi
if ipv6_pool_has_extra_address '2606:4700::1/128' '2606:4700::1'; then
    fail "/128 was reported to have an extra address"
fi
if ! ipv6_pool_has_extra_address '2606:4700::/127' '2606:4700::'; then
    fail "/127 was rejected despite having one remaining address"
fi
export LXD_IPV6_ROUTED_PREFIX='2a14:7c0:1002:2000::/64'
assert_eq "2a14:7c0:1002:2000::/64" "$(ipv6_allocation_network '2606:4700::1/128')" "explicit routed prefix overrides host /128"
unset LXD_IPV6_ROUTED_PREFIX

printf '%s\n' routed >"$LXD_STATE_DIR/lxd_ipv6_mode"
configure_ipv6_nat66_fallback >/dev/null
assert_eq routed "$(cat "$LXD_STATE_DIR/lxd_ipv6_mode")" "fallback preserves existing routed mode"
rm -f "$LXD_STATE_DIR/lxd_ipv6_mode"
configure_ipv6_nat66_fallback >/dev/null
assert_eq nat66 "$(cat "$LXD_STATE_DIR/lxd_ipv6_mode")" "fallback records NAT66 mode"

# A real LXD command failure must not be recorded as a successful NAT66
# fallback.  The earlier no-command fixture only exercises state bookkeeping.
lxc() {
    case "$1 $2 $3 $4 $5" in
        "config device get"*) return 1 ;;
        "network get"*) return 1 ;;
        "network set"*) return 1 ;;
        *) return 1 ;;
    esac
}
CONTAINER_NAME=lxd-fallback-failure
if configure_ipv6_nat66_fallback >/dev/null 2>&1; then
    fail "LXD NAT66 command failure was hidden"
fi
unset CONTAINER_NAME
unset -f lxc

# shellcheck disable=SC2329 # Called indirectly by the sourced network helpers.
ip() {
    case "$*" in
    "-o -6 addr show dev he-ipv6 scope global")
        printf '%s\n' '7: he-ipv6    inet6 2606:4700::1/64 scope global'
        ;;
    *)
        command ip "$@"
        ;;
    esac
}
export LXD_IPV6_UPLINK=he-ipv6
export LXD_TEST_TUNNEL=1
assert_eq "he-ipv6" "$(ipv6_uplink_interface)" "explicit tunnel uplink"
assert_eq "2606:4700::1/64" "$(ipv6_uplink_cidr he-ipv6 2606:4700::1)" "tunnel address selection"
unset LXD_TEST_TUNNEL
unset LXD_IPV6_UPLINK
unset -f ip

export LXD_TEST_SAME_INTERFACE=1
assert_eq eth0 "$(ipv6_uplink_interface '2a14:7c0:1002:10f8::1')" 'same-interface wider prefix uplink'
assert_eq '2a14:7c0:1002:10f8::2/38' "$(ipv6_uplink_cidr eth0 '2a14:7c0:1002:10f8::1')" 'same-interface wider prefix CIDR'
unset LXD_TEST_SAME_INTERFACE

route_state="$LXD_STATE_DIR/route-state"
export LXD_TEST_ROUTE_STATE="$route_state"
ip() {
    case "$*" in
    "-6 route show default") ;;
    "-o -6 addr show dev eth0 scope global") printf '%s\n' '2: eth0 inet6 2606:4700::2/64 scope global' ;;
    "route show default") printf '%s\n' 'default via 2606:4700::1 dev eth0' ;;
    "-6 neigh show dev eth0") printf '%s\n' '2606:4700::1 dev eth0 lladdr 00:11:22:33:44:55 router REACHABLE' ;;
    "-6 route replace default via 2606:4700::1 dev eth0 metric 4096") printf '%s\n' ok >"$route_state" ;;
    "-6 route show default dev eth0") [ -f "$route_state" ] && printf '%s\n' 'default via 2606:4700::1 dev eth0 metric 4096' ;;
    "-6 route del default via 2606:4700::1 dev eth0 metric 4096"|"-6 route del default dev eth0 metric 4096") rm -f "$route_state" ;;
    *) command ip "$@" ;;
    esac
}
curl() { return 0; }
export LXD_IPV6_UPLINK=eth0
export LXD_TEST_SAME_INTERFACE=1
ensure_ipv6_default_route || fail "IPv6 default route was not recovered from a verified router neighbor"
[ -f "$route_state" ] || fail "verified IPv6 route was not retained"
rm -f "$route_state"
curl() { return 1; }
if ensure_ipv6_default_route; then
    fail "IPv6 route probe failure was accepted"
fi
[ ! -e "$route_state" ] || fail "unverified IPv6 route was not rolled back"
unset LXD_IPV6_UPLINK
unset LXD_TEST_SAME_INTERFACE
unset -f ip curl
unset LXD_TEST_ROUTE_STATE

legacy_cleanup="$LXD_STATE_DIR/remove_route.sh"
printf '%s\n' '#!/bin/bash' 'ip addr del fe80::1/64 dev eth0' >"$legacy_cleanup"
export LXD_LEGACY_FE80_CLEANUP="$legacy_cleanup"
disable_legacy_link_local_cleanup
[ ! -e "$legacy_cleanup" ] || fail "legacy fe80 cleanup helper was left active"
unset LXD_LEGACY_FE80_CLEANUP

admin_cleanup="$LXD_STATE_DIR/admin-route.sh"
printf '%s\n' '#!/bin/bash' 'ip addr del fe80::2/64 dev eth0' 'echo keep-this-script' >"$admin_cleanup"
export LXD_LEGACY_FE80_CLEANUP="$admin_cleanup"
disable_legacy_link_local_cleanup
[ -e "$admin_cleanup" ] || fail "administrator fe80 script was removed"
unset LXD_LEGACY_FE80_CLEANUP

if grep -Eq 'ip[[:space:]]+addr[[:space:]]+del[[:space:]]+fe80:' "$ROOT_DIR/scripts/build_ipv6_network.sh"; then
    fail "build script still deletes link-local IPv6 addresses"
fi

# Reboot restoration must consume strict prefix metadata and preserve only
# existing global mappings; it must not invent /64 state or bind ULA addresses.
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/add-ipv6.sh"

# A persisted mapping must remain bound to its original routed bridge after a
# reboot, even if the physical NIC is the current default-route interface.
printf '%s\n' vmbr2 >"$LXD_STATE_DIR/lxd_ipv6_mapping_interface"
# shellcheck disable=SC2329 # Called indirectly by get_interface.
ip() {
    case "$*" in
    "link show dev vmbr2"|"link show dev eth0") return 0 ;;
    "-6 route show default") printf '%s\n' 'default via fe80::1 dev eth0 proto ra metric 1024' ;;
    *) command ip "$@" ;;
    esac
}
assert_eq vmbr2 "$(get_interface)" "saved routed bridge wins over default route"
rm -f "$LXD_STATE_DIR/lxd_ipv6_mapping_interface"
export LXD_TEST_ROUTE_STATE="$LXD_STATE_DIR/restoration-route"
touch "$LXD_TEST_ROUTE_STATE"
assert_eq eth0 "$(get_interface)" "IPv6 default-route fallback"
rm -f "$LXD_TEST_ROUTE_STATE"
unset LXD_TEST_ROUTE_STATE
unset -f ip

printf '%s\n' 128 >"$LXD_STATE_DIR/lxd_ipv6_mapping_prefix_len"
assert_eq 128 "$(get_host_ipv6_prefixlen eth0)" "strict persisted /128 prefix"
printf '%s\n' 64 128 >"$LXD_STATE_DIR/lxd_ipv6_mapping_prefix_len"
if read_strict_prefix_len "$LXD_STATE_DIR/lxd_ipv6_mapping_prefix_len" >/dev/null; then
    fail "multiline mapping prefix was accepted"
fi
restore_calls="$LXD_STATE_DIR/restore-calls"
# The JSON parser itself is covered by add_ipv6_restore_test.sh.
restore_ipv6_json_rows() { [ "$1" = addresses ]; }
# shellcheck disable=SC2329 # Called indirectly by restore_address.
ip() {
    case "$*" in
    "-6 addr show dev eth0") return 1 ;;
    "-6 addr replace "*) printf '%s\n' "$*" >>"$restore_calls" ;;
    *) command ip "$@" ;;
    esac
}
restore_address 'fd42::1' eth0 64
[ ! -s "$restore_calls" ] || fail "ULA was restored as a public address"
restore_address '2606:4700::1' eth0 128
grep -Fq -- '-6 addr replace 2606:4700::1/128 dev eth0' "$restore_calls" || fail "global /128 mapping was not restored"
unset -f restore_ipv6_json_rows
unset -f ip

grep -Fq 'wait_for_container_status "$CONTAINER_NAME" "STOPPED" 24 || return 1' "$ROOT_DIR/scripts/build_ipv6_network.sh" ||
    fail "routed IPv6 setup must stop only after a confirmed STOPPED state"
grep -Fq 'setup_ipv6_cron || return 1' "$ROOT_DIR/scripts/build_ipv6_network.sh" ||
    fail "IPv6 keepalive installation failure must not be hidden"
grep -Fq 'ip6tables-restore < "$rules_file" 2>/dev/null || return 1' "$ROOT_DIR/scripts/add-ipv6.sh" ||
    fail "IPv6 iptables restore failure must be reported"
grep -Fq 'nft -f /etc/nftables.conf 2>/dev/null || return 1' "$ROOT_DIR/scripts/add-ipv6.sh" ||
    fail "IPv6 nft restore failure must be reported"

printf 'build_ipv6_network tests passed\n'
