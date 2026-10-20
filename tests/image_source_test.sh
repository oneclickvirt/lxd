#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
eval "$(awk '/^handle_image\(\)/ {p=1} p {print} p && /^}/ {exit}' "$repo_root/scripts/buildvm.sh")"
# shellcheck source=/dev/null
. "$repo_root/scripts/instance_ownership.sh"
OCV_INSTANCE_CLI=lxc
lxc() { [[ "$*" == 'image alias list --format=json' ]] && printf '[]\n'; }
import_image() { imported="$1"; imported_url="$2"; [[ "$import_ok" == true ]]; }
check_standard_images() { fallback=true; [[ "$fallback_ok" == true ]]; }
get_kvm_images() { printf '%s\n' "$metadata"; }
image_name_matches_system() { [[ "$1" == "${a}_${b}_"* ]]; }
a=debian; b=12; sys_bit=amd64; fallback_ok=true; import_ok=true
metadata="debian_12_bookworm_amd64_default_kvm.zip
debian_12_bookworm_amd64_cloud_kvm.zip"
fallback=false; imported=""; image_download_url=""
handle_image >/dev/null
[[ "$imported" == debian_12_bookworm_amd64_cloud_kvm.zip && "$fallback" == false ]]
[[ "$imported_url" == https://github.com/oneclickvirt/lxd_images/releases/download/kvm_images/debian_12_bookworm_amd64_cloud_kvm.zip ]]
metadata=""; fallback=false
handle_image >/dev/null
[[ "$fallback" == true ]]
fallback_ok=false
if handle_image >/dev/null; then echo 'missing image sources accepted' >&2; exit 1; fi
metadata=debian_12_bookworm_amd64_cloud_kvm.zip; import_ok=false; fallback=false
if handle_image >/dev/null; then echo 'failed import hidden' >&2; exit 1; fi
echo 'lxd VM source selection and metadata fallback tests passed'
