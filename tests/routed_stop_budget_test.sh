#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python3 - "$ROOT_DIR/scripts/build_ipv6_network.sh" "$work/function.sh" <<'PY'
from pathlib import Path
import sys
source=Path(sys.argv[1]).read_text()
start=source.index('stop_lxd_instance() {')
Path(sys.argv[2]).write_text(source[start:source.index('\n}\n',start)+2]+'\n')
PY
for scenario in clean completed timeout unknown force-failure; do
    CASE_NAME=$scenario TRACE_FILE="$work/$scenario" bash -eu - "$work/function.sh" <<'BASH'
source "$1"
CASE_STATE=103
timeout() {
    printf '%s\n' "$*" >> "$TRACE_FILE"
    [ "$1" = -k ] && [ "$2" = 5 ]
    shift 3
    "$@"
}
lxd_container_status_code() { echo "$CASE_STATE"; }
lxc() {
    [ "$1" = stop ] && [ "$2" = guest ]
    if [ "${3:-}" = --force ]; then
        [ "$CASE_NAME" != force-failure ] || return 1
        CASE_STATE=102
        return 0
    fi
    [ "${3:-}" = --timeout ] && [ "${4:-}" = 40 ]
    case "$CASE_NAME" in
        clean) CASE_STATE=102; return 0 ;;
        completed) CASE_STATE=102 ;;
        unknown) CASE_STATE=109 ;;
    esac
    return 1
}
result=0
stop_lxd_instance guest || result=$?
case "$CASE_NAME" in
    unknown|force-failure) [ "$result" -ne 0 ] ;;
    *) [ "$result" -eq 0 ] ;;
esac
case "$CASE_NAME" in
    timeout|force-failure) grep -Fqx -- '-k 5 25 lxc stop guest --force' "$TRACE_FILE" ;;
    *) ! grep -q -- --force "$TRACE_FILE" ;;
esac
BASH
done
echo 'LXD routed stop has bounded graceful/force RPCs and refuses unknown states'
