#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2329
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/instance_ownership.sh"
OCV_INSTANCE_CLI=lxc
source <(awk '/^safe_shutdown_vm\(\) \{/ {p=1} p {print} p && /^}$/ {exit}' "$root/scripts/buildvm.sh")
name=vm-fixture
stop_called=false
lxc() {
    case "$1" in
        stop) [[ "$*" == 'stop vm-fixture --timeout=120' ]]; stop_called=true; return "$stop_rc" ;;
        query) [[ "$2" == /1.0/instances/vm-fixture ]]; printf '%s\n' "$response" ;;
        *) return 1 ;;
    esac
}
sleep() { :; }
for response in '{"status":"Stopped","status_code":102}' '{"status":"STOPPED"}' \
    '{"metadata":{"status":"stopped","status_code":"102"}}'; do
    stop_rc=0; stop_called=false
    safe_shutdown_vm
    [[ "$stop_called" == true ]]
    stop_rc=1
    safe_shutdown_vm # completed shutdown reported after the client timed out
done
for response in '' '{}' '[]' '{"status":"Running","status_code":103}' \
    '{"status":"Running","status_code":102}' 'not-json'; do
    stop_rc=1
    if safe_shutdown_vm >/dev/null 2>&1; then
        echo 'Unconfirmed shutdown incorrectly accepted' >&2; exit 1
    fi
done
stop_rc=0 response='{"status":"Running","status_code":103}'
if safe_shutdown_vm >/dev/null 2>&1; then
    echo 'A still-running VM incorrectly accepted after stop returned success' >&2; exit 1
fi
echo 'VM graceful shutdown budget, legacy/current JSON and timeout-state race passed'
