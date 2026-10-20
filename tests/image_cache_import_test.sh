#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
. "$repo/scripts/instance_ownership.sh"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
printf metadata >"$test_dir/metadata"
printf rootfs >"$test_dir/rootfs"
expected=$(cat "$test_dir/metadata" "$test_dir/rootfs" | sha256sum)
expected=${expected%% *}
OCV_INSTANCE_CLI=cache_cli
scenario=''

fail() { printf '%s\n' "$*" >&2; exit 1; }
cache_cli() {
    printf '%s\n' "$*" >>"$test_dir/calls"
    case "$1 $2 $3" in
        'image alias list')
            local target=''
            [ ! -f "$test_dir/target" ] || target=$(cat "$test_dir/target")
            jq -n --arg target "$target" --arg other "$expected" \
                '[{name:"panel-cache",target:$other}] + (if $target == "" then [] else [{name:"script-alias",target:$target}] end)'
            ;;
        'image alias create')
            [ "$scenario" != alias-failure ] || return 1
            [ "$4" = script-alias ] && [ "$5" = "$expected" ] || return 1
            printf '%s\n' "$5" >"$test_dir/target"
            ;;
        'image show '*) [ -f "$test_dir/cached" ] && [ "$3" = "$expected" ] ;;
        'image import '*)
            if [ "$scenario" = import-failure ]; then return 1; fi
            touch "$test_dir/cached"
            if [ "$scenario" = concurrent-import ]; then return 1; fi
            printf '%s\n' "$expected" >"$test_dir/target"
            ;;
        *) return 1 ;;
    esac
}

for scenario in cached new concurrent-import import-failure alias-failure conflict; do
    rm -f "$test_dir/cached" "$test_dir/target" "$test_dir/calls"
    case "$scenario" in cached|alias-failure|conflict) touch "$test_dir/cached" ;; esac
    if [ "$scenario" = conflict ]; then printf '%064d\n' 1 >"$test_dir/target"; fi
    status=0
    ocv_import_split_image "$test_dir/metadata" "$test_dir/rootfs" script-alias || status=$?
    case "$scenario" in
        cached|new|concurrent-import)
            [ "$status" -eq 0 ] || fail "$scenario failed to recover an available image"
            [ "$(cat "$test_dir/target")" = "$expected" ] || fail 'alias does not refer to the verified fingerprint'
            ;;
        *) [ "$status" -ne 0 ] || fail "$scenario incorrectly reported success" ;;
    esac
    if [ "$scenario" = cached ]; then
        ! grep -q '^image import ' "$test_dir/calls" || fail 'cached fingerprint was reimported'
    fi
    if [ "$scenario" = conflict ]; then
        [ "$(cat "$test_dir/target")" = "$(printf '%064d' 1)" ] || fail 'custom alias was replaced'
        ! grep -q '^image alias create ' "$test_dir/calls" || fail 'custom alias was mutated'
    fi
    ! grep -Eq '^image (delete|alias delete)' "$test_dir/calls" || fail 'existing image or alias was deleted'
done
if ocv_import_split_image "$test_dir/missing" "$test_dir/rootfs" script-alias >/dev/null 2>&1; then
    fail 'unreadable image input was accepted'
fi
printf 'Split image cache reuse, concurrent import, ownership and failure propagation passed\n'
