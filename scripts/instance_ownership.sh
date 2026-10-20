#!/usr/bin/env bash
# Shared creation ownership and local script serialization.
# A daemon name is not an object identity. Tag init/copy atomically and keep
# the daemon-generated UUID so failed callers cannot adopt a same-name object.

ocv_lock_scripts() {
    local lock_dir="${1:-/run/oneclickvirt-script-locks}" lock_file inherited
    [ -n "${OCV_SCRIPT_RUNTIME:-}" ] || return 1
    command -v flock >/dev/null 2>&1 || {
        printf 'flock (util-linux) is required for concurrent script safety.\n' >&2
        return 1
    }
    [ ! -L "$lock_dir" ] || return 1
    mkdir -p -m 700 -- "$lock_dir" || return 1
    [ "$(stat -c %u "$lock_dir")" = "$EUID" ] || return 1
    [ "$(stat -c %a "$lock_dir")" = 700 ] || return 1
    # Incus and LXD both use /root/log and identically named helper files.
    lock_file="$lock_dir/scripts.lock"
    [ ! -L "$lock_file" ] || return 1
    inherited="${_OCV_SCRIPT_LOCK_FD:-}"
    if [[ "$inherited" =~ ^[1-9][0-9]{1,8}$ ]] &&
        [ "${_OCV_SCRIPT_LOCK_SCOPE:-}" = shared-files-v1 ] &&
        [ "/proc/$$/fd/$inherited" -ef "$lock_file" ]; then
        ocv_script_lock_fd="$inherited"
    else
        exec {ocv_script_lock_fd}>>"$lock_file" || return 1
    fi
    if ! flock -xn "$ocv_script_lock_fd"; then
        printf 'Another creation script is active; waiting for its files and rollback to finish.\n' >&2
        flock -xw 1800 "$ocv_script_lock_fd" || return 1
    fi
    _OCV_SCRIPT_LOCK_FD="$ocv_script_lock_fd"
    _OCV_SCRIPT_LOCK_SCOPE=shared-files-v1
    export _OCV_SCRIPT_LOCK_FD _OCV_SCRIPT_LOCK_SCOPE
    # Never unlink the lock file: replacing its inode would split the lock.
}

ocv_valid_instance_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
}

ocv_new_creation_token() {
    local token
    token=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n') || return 1
    [[ "$token" =~ ^[a-f0-9]{32}$ ]] || return 1
    printf '%s\n' "$token"
}

ocv_creation_token() {
    if [ -n "${_OCV_CREATE_TOKEN:-}" ]; then
        [[ "$_OCV_CREATE_TOKEN" =~ ^[a-f0-9]{32}$ ]] || return 1
        printf '%s\n' "$_OCV_CREATE_TOKEN"
    else
        ocv_new_creation_token
    fi
}

ocv_instance_identity() {
    local instance_name="$1" data
    ocv_valid_instance_name "$instance_name" || return 1
    data=$("$OCV_INSTANCE_CLI" query "/1.0/instances/$instance_name") || return 1
    jq -er '
        (if type=="object" and (.metadata? | type)=="object" then .metadata else . end) |
        .config["user.oneclickvirt.creation-token"] as $owner |
        .config["volatile.uuid"] as $uuid |
        select(($owner | type)=="string" and ($uuid | type)=="string" and
               ($owner | length)>0 and ($uuid | length)>0) |
        [$owner, $uuid] | @tsv
    ' <<<"$data"
}

ocv_owned_identity() {
    local identity
    identity=$(ocv_instance_identity "$1") || return 1
    [ "${identity%%$'\t'*}" = "$2" ] || return 1
    printf '%s\n' "$identity"
}

# The marker is part of init/copy, not a subsequent config write: a failed
# command must not adopt an object another caller created under the same name.
ocv_create_owned() {
    local instance_name="$1" token status=0
    shift
    ocv_created_identity=""
    ocv_valid_instance_name "$instance_name" || return 1
    token=$(ocv_creation_token) || return 1
    "$@" -c "user.oneclickvirt.creation-token=$token" || status=$?
    if ! ocv_created_identity=$(ocv_owned_identity "$instance_name" "$token"); then
        ocv_created_identity=""
        if [ "$status" -eq 0 ]; then
            printf 'Created instance identity could not be verified: %s\n' "$instance_name" >&2
            return 1
        fi
    fi
    return "$status"
}

ocv_remove_owned_instance() {
    local instance_name="$1" expected="$2" actual
    [ -n "$expected" ] || return 1
    actual=$(ocv_instance_identity "$instance_name") || {
        printf 'Cannot verify rollback ownership; retained instance: %s\n' "$instance_name" >&2
        return 1
    }
    if [ "$actual" != "$expected" ]; then
        printf 'Rollback identity changed; retained instance: %s\n' "$instance_name" >&2
        return 1
    fi
    # The daemon has no conditional DELETE API. The shared script lock closes
    # the check/delete race among these scripts; out-of-band daemon clients
    # must not concurrently delete/recreate names belonging to an active run.
    "$OCV_INSTANCE_CLI" delete --force "$instance_name"
}


# Image identity is independent of aliases: the panel and CLI installers may
# cache exactly the same image under different names. Reuse that fingerprint
# while retaining unrelated aliases, including a concurrent caller's alias.
ocv_image_alias_target() {
    local alias="$1" data target
    data=$("$OCV_INSTANCE_CLI" image alias list --format=json) || return 1
    target=$(jq -er --arg alias "$alias" '
        [.[]? | select(.name == $alias) | .target] |
        if length > 1 then error("duplicate image alias") else .[0] // "" end
    ' <<<"$data") || return 1
    [ -z "$target" ] || [[ "$target" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$target"
}

ocv_import_split_image() {
    local metadata="$1" rootfs="$2" alias="$3" fingerprint target
    fingerprint=$(set -o pipefail; cat -- "$metadata" "$rootfs" | sha256sum) || return 1
    fingerprint=${fingerprint%% *}
    [[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] || return 1
    target=$(ocv_image_alias_target "$alias") || return 1
    if [ -n "$target" ] && [ "$target" != "$fingerprint" ]; then
        printf 'Refusing to replace an image alias owned by another fingerprint: %s\n' "$alias" >&2
        return 1
    fi
    if ! "$OCV_INSTANCE_CLI" image show "$fingerprint" >/dev/null 2>&1; then
        if ! "$OCV_INSTANCE_CLI" image import "$metadata" "$rootfs" --alias "$alias"; then
            # Another process may have imported the same fingerprint after
            # the probe. Only a verified cached image permits this recovery.
            "$OCV_INSTANCE_CLI" image show "$fingerprint" >/dev/null 2>&1 || return 1
        fi
    fi
    target=$(ocv_image_alias_target "$alias") || return 1
    if [ -z "$target" ]; then
        "$OCV_INSTANCE_CLI" image alias create "$alias" "$fingerprint" || {
            target=$(ocv_image_alias_target "$alias") || return 1
            [ "$target" = "$fingerprint" ] || return 1
        }
    fi
    target=$(ocv_image_alias_target "$alias") || return 1
    [ "$target" = "$fingerprint" ] || return 1
    "$OCV_INSTANCE_CLI" image show "$fingerprint" >/dev/null 2>&1
}
