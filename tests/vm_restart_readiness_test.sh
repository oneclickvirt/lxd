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
