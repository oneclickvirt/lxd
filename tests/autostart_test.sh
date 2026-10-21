#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2329
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for kind in ct vm; do
 function_name=configure_security
 [[ "$kind" != vm ]] || function_name=configure_limits
 source <(awk -v f="$function_name" '$0 == f "() {" {p=1} p {print} p && /^}$/ {exit}' "$root/scripts/build$kind.sh")
 name=owned-instance; autostart_seen=false; fail_autostart=false
 lxc() {
  if [[ "$*" == "config set owned-instance boot.autostart true" ]]; then
   autostart_seen=true
   ! $fail_autostart
  else
   return 0
  fi
 }
 "$function_name"
 $autostart_seen
 fail_autostart=true
 if "$function_name"; then
  echo 'Failed autostart configuration was accepted' >&2
  exit 1
 fi
done
echo 'CT and VM autostart, including write-failure propagation, passed'
