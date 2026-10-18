#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for script in buildvm.sh build_ipv6_network.sh; do
    source <(awk '/^start_lxd_instance\(\) \{/{p=1} p{print} p && /^}/{exit}' "$root/scripts/$script")
    for mode in transient permanent unrelated; do
        echo 0 > "$tmp/count"
        timeout() { shift; "$@"; }
        sleep() { :; }
        lxc() {
            test "$1" = start && test "$2" = guest
            local count
            count=$(cat "$tmp/count"); count=$((count + 1)); echo "$count" > "$tmp/count"
            if [[ "$mode" = transient && "$count" = 2 ]]; then return 0; fi
            if [[ "$mode" = unrelated ]]; then echo 'storage pool unavailable' >&2; return 1; fi
            echo 'Failed adding host route: RTNETLINK answers: File exists' >&2
            return 1
        }
        status=0
        start_lxd_instance guest > "$tmp/output" 2>&1 || status=$?
        count=$(cat "$tmp/count")
        case "$mode" in
            transient) [[ "$status" = 0 && "$count" = 2 ]] ;;
            permanent) [[ "$status" != 0 && "$count" = 3 ]] ;;
            unrelated) [[ "$status" != 0 && "$count" = 1 ]] ;;
        esac
    done
done
echo 'Routed start retry: transient recovery and bounded error propagation passed'
