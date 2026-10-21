#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for function in start_lxd_instance restart_lxd_instance; do
    source <(awk -v name="$function" '$0 == name "() {" {p=1} p {print} p && /^}$/ {exit}' "$root/scripts/buildvm.sh")
done
for scenario in success transient unrelated unknown failed-start; do
    printf '0\n' >"$work/starts"
    timeout() { if [ "$1" = -k ]; then shift 2; fi; shift; "$@"; }
    sleep() { :; }
    lxc() {
        case "$1" in
            restart)
                [ "$scenario" != success ] || return 0
                if [ "$scenario" = unrelated ]; then echo 'storage unavailable' >&2
                else echo 'The instance cannot be started as in Error status' >&2; fi
                return 1 ;;
            list)
                status=102
                [ "$scenario" != unknown ] || status=101
                printf '[{"name":"guest","status_code":%s},{"name":"unrelated","status_code":103}]\n' "$status" ;;
            start)
                count=$(cat "$work/starts"); echo "$((count+1))" >"$work/starts"
                [ "$scenario" != failed-start ] || { echo 'disk unavailable' >&2; return 1; } ;;
            *) return 1 ;;
        esac
    }
    result=0
    restart_lxd_instance guest >"$work/output" 2>&1 || result=$?
    count=$(cat "$work/starts")
    case "$scenario" in
        success) [ "$result" -eq 0 ] && [ "$count" -eq 0 ] ;;
        transient) [ "$result" -eq 0 ] && [ "$count" -eq 1 ] ;;
        failed-start) [ "$result" -ne 0 ] && [ "$count" -eq 3 ] ;;
        *) [ "$result" -ne 0 ] && [ "$count" -eq 0 ] ;;
    esac
done
echo 'LXD VM restart recovers the known Error-to-Stopped transition and preserves other failures'
