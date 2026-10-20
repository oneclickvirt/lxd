#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2329
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source <(awk '/^wait_for_instance_ssh_ready\(\) \{/ {p=1} p {print} p && /^}$/ {exit}' "$root/scripts/buildvm.sh")
source <(awk '/^vm_ipv4_from_state\(\) \{/ {p=1} p {print} p && /^}$/ {exit}' "$root/scripts/buildvm.sh")
name=vm-fixture
probes=0 sleeps=0 ready_after=3
timeout() {
    [[ "$1" == -k && "$2" == 2 && "$3" =~ ^[0-9]+$ ]]
    [[ "$4 $5 $6 $7" == 'lxc exec vm-fixture --' ]]
    probes=$((probes + 1))
    ((probes >= ready_after))
}
sleep() { sleeps=$((sleeps + 1)); }
wait_for_instance_ssh_ready 30
[[ "$probes" == 3 && "$sleeps" == 2 ]]
probes=0 sleeps=0 ready_after=100
if wait_for_instance_ssh_ready 8; then
    echo 'Unavailable guest agent incorrectly accepted' >&2; exit 1
fi
[[ "$probes" == 2 && "$sleeps" == 2 ]]
state='[{"name":"other","state":{"network":{"eth0":{"addresses":[{"family":"inet","address":"10.0.0.99","scope":"global"}]}}}},{"name":"vm-fixture","state":{"network":{"lo":{"addresses":[{"family":"inet","address":"127.0.0.1","scope":"local"}]},"ens19":{"addresses":[{"family":"inet6","address":"fe80::1","scope":"link"},{"family":"inet","address":"10.0.0.5"}]}}}}]'
[[ "$(vm_ipv4_from_state <<<"$state")" == 10.0.0.5 ]]
for bad in '[]' '[{"name":"vm-fixture","state":{}}]' \
    '[{"name":"vm-fixture","state":{"network":{"eth0":{"addresses":[{"family":"inet","address":"10.0.0.5"},{"family":"inet","address":"10.0.0.6"}]}}}}]'; do
    if vm_ipv4_from_state <<<"$bad" >/dev/null 2>&1; then
        echo 'Missing or ambiguous IPv4 incorrectly accepted' >&2; exit 1
    fi
done
# The restart path must gate all IP discovery and IPv6 guest commands on the
# real guest-agent/SSH probe. A cached daemon address alone is insufficient.
flow=$(awk '/^configure_network\(\) \{/ {p=1} p {print} p && /^}$/ {exit}' "$root/scripts/buildvm.sh")
prefix=${flow%%echo *}
[[ "$prefix" == *'lxc restart "$name" || return 1'* ]]
[[ "$prefix" == *'wait_for_instance_ssh_ready || return 1'* ]]
echo 'VM post-restart readiness, renamed interfaces and bounded failure passed'

# The IPv6 helper also stops and starts the VM. Its fresh boot must become
# ready before the following shutdown, not only after the first restart.
workdir=$(mktemp -d)
trap 'rm -rf -- "$workdir"' EXIT
(
    cd "$workdir"
    export ONECLICKVIRT_TESTING=1
    source "$root/scripts/buildvm.sh"
    name=vm-fixture enable_ipv6=y sshn=20001 nat1=0 nat2=0
    trace="$workdir/trace"
    export trace
    cat >build_ipv6_network.sh <<'HELPER'
#!/bin/sh
printf 'helper-started-new-boot\n' >>"$trace"
HELPER
    chmod +x build_ipv6_network.sh
    lxc() {
        case "$1" in
            list) printf '%s\n' '[{"name":"vm-fixture","state":{"network":{"ens19":{"addresses":[{"family":"inet","address":"192.0.2.2","scope":"global"}]}}}}]' ;;
            restart) printf 'first-restart\n' >>"$trace" ;;
            *) return 1 ;;
        esac
    }
    ip() { printf '    inet 192.0.2.1/24 scope global eth0\n'; }
    firewall-cmd() { :; }
    configure_firewall_ports() { :; }
    wait_for_instance_ssh_ready() { printf 'guest-ready\n' >>"$trace"; }
    ensure_container_ipv6_cron() { :; }
    refresh_ipv6_helper() { :; }
    wait_for_vm_ready_to_shutdown() { :; }
    safe_shutdown_vm() {
        [[ "$(tail -n 1 "$trace")" == guest-ready ]] || {
            echo 'Shutdown raced the boot performed by the IPv6 helper' >&2
            exit 7
        }
        printf 'shutdown-after-ready\n' >>"$trace"
        return 1 # stop here without configuring devices or launching a guest
    }
    if configure_network; then
        echo 'The fixture unexpectedly configured a real guest' >&2; exit 1
    fi
    [[ "$(cat "$trace")" == $'first-restart\nguest-ready\nhelper-started-new-boot\nguest-ready\nshutdown-after-ready' ]]
)
echo 'IPv6 helper reboot must become ready before shutdown: passed'
