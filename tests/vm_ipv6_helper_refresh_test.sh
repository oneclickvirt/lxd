#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
source <(awk '$0 == "refresh_ipv6_helper() {" {p=1} p {print} p && /^}$/ {exit}' "$root/scripts/buildvm.sh")
OCV_BUILDVM_DIR="$root/scripts"
printf 'old helper\n' > "$work/helper.sh"
download_host_file() { echo 'unexpected download' >&2; return 1; }
refresh_ipv6_helper "$work/helper.sh"
cmp -s "$root/scripts/build_ipv6_network.sh" "$work/helper.sh"
test -x "$work/helper.sh"

# An installed standalone VM script has no adjacent helper; validate a fetched
# version before replacing the last usable copy.
OCV_BUILDVM_DIR="$work/missing"
printf 'old helper\n' > "$work/helper.sh"
download_host_file() { printf 'invalid downloaded helper\n' > "$2"; }
if refresh_ipv6_helper "$work/helper.sh" >/dev/null 2>&1; then
    echo 'unversioned download was accepted' >&2
    exit 1
fi
test "$(cat "$work/helper.sh")" = 'old helper'
download_host_file() { cp "$root/scripts/build_ipv6_network.sh" "$2"; }
refresh_ipv6_helper "$work/helper.sh"
cmp -s "$root/scripts/build_ipv6_network.sh" "$work/helper.sh"
echo 'LXD VM refresh replaces stale IPv6 helpers and preserves them on invalid downloads'
