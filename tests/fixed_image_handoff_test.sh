#!/usr/bin/env bash
# Verify the real image-selection-to-create handoff without downloading images.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for scenario in imported cached download_failed import_failed; do
    (
        cd "$test_dir"
        ONECLICKVIRT_TESTING=1 source "$repo_root/scripts/buildct.sh"
        selected=debian_12_bookworm_amd64_default.zip
        a=debian b=12 cdn_success_url=""
        rm -f -- cached alias-target
        printf metadata >lxd.tar.xz; printf rootfs >rootfs.squashfs
        fingerprint=$(cat lxd.tar.xz rootfs.squashfs | sha256sum); fingerprint=${fingerprint%% *}
        if [[ "$scenario" == cached ]]; then touch cached; printf '%s\n' "$fingerprint" >alias-target; fi
        image_name=stale_alias
        lxc() {
            case "$*" in
                'image alias list --format=json')
                    if [[ -f alias-target ]]; then
                        jq -n --arg name "$selected" --arg target "$(cat alias-target)" '[{name:$name,target:$target}]'
                    else printf '[]\n'; fi ;;
                'image show '*) [[ -f cached ]] ;;
                'image import lxd.tar.xz rootfs.squashfs --alias '*)
                    [[ "${*: -1}" == "$selected" ]] || fail 'wrong import alias'
                    [[ "$scenario" != import_failed ]] || return 1
                    touch cached; printf '%s\n' "$fingerprint" >alias-target ;;
                'info fixture') [[ -f "$test_dir/created" ]] ;;
                *) fail "unexpected runtime command: $*" ;;
            esac
        }
        wget() { [[ "$scenario" != download_failed ]]; }
        unzip() { printf metadata >lxd.tar.xz; printf rootfs >rootfs.squashfs; }
        chmod() { return 0; }
        create_instance_with_tracking() {
            [[ "$1:$2:$3:$4" == "lxc:init:$selected:fixture" ]] || fail "selection lost before init: $3"
            : >"$test_dir/created"
        }
        process_self_fixed_images() { use_fixed_image "$selected"; }
        self_image_arch=x86_64
        process_images_repository() { fail 'fixed image fell through to remote'; }
        process_opsmaru_repository() { fail 'fixed image fell through to fallback'; }
        status=0
        process_image >"$test_dir/output" 2>&1 || status=$?
        if [[ "$scenario" == *_failed ]]; then
            [[ "$status" != 0 ]] || fail "$scenario hidden"
            exit 0
        fi
        [[ "$status" == 0 && "$image_name" == "$selected" ]] || fail "$scenario did not retain the selected image"
        name=fixture cpu=1 memory=256 disk=3 storage_pool=default
        rm -f -- "$test_dir/created"
        create_container || fail "$scenario failed creating selected image"
    )
done
printf 'PASS: LXD fixed image handoff (4 scenarios, no skipped tests)\n'

