#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source <(awk '/^wait_for_vm_guest_agent\(\) \{/ {p=1} p {print} p && /^}$/ {exit}' "$root/scripts/build_ipv6_network.sh")
CONTAINER_NAME=vm-fixture
probes=0
sleeps=0
timeout() {
    [[ "$*" == '5 lxc exec vm-fixture -- true' ]]
    probes=$((probes + 1))
    ((probes >= ready_after))
}
sleep() { sleeps=$((sleeps + 1)); }
ready_after=4
wait_for_vm_guest_agent
[[ "$probes" == 4 && "$sleeps" == 3 ]]
probes=0
sleeps=0
ready_after=25
if wait_for_vm_guest_agent; then
    echo 'Unavailable guest agent unexpectedly accepted' >&2
    exit 1
fi
[[ "$probes" == 24 && "$sleeps" == 24 ]]
echo 'VM guest agent readiness: delayed success and bounded failure passed'
