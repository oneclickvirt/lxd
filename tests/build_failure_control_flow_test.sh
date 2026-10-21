#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031,SC2034,SC2329
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/lxd-build-flow-test.XXXXXX")
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

mock_identity_json() {
    jq -n --arg owner "${mock_creation_token:-fixture-token}" --arg uuid "fixture-uuid" \
        '{config: {"user.oneclickvirt.creation-token": $owner, "volatile.uuid": $uuid}}'
}

run_create_failure_test() {
    local kind="$1"
    local script="$repo_root/scripts/build${kind}.sh"
    local workdir="$tmpdir/${kind}-create"
    mkdir -p "$workdir"

    (
        cd "$workdir"
        export ONECLICKVIRT_TESTING=1
        # shellcheck disable=SC1090
        source "$script"

        local lxc_log="$workdir/lxc.log"
        local continued="$workdir/continued"
        lxc() {
            printf '%s\n' "$*" >>"$lxc_log"
            case "${1:-}" in
            init | info)
                return 1
                ;;
            *)
                return 0
                ;;
            esac
        }
        init_env() { :; }
        ensure_lxd_ready() { :; }
        check_vm_support() { :; }
        check_china() { :; }
        check_cdn_file() { :; }
        get_system_arch() { :; }
        detect_arch() { :; }
        detect_os() { :; }
        install_dependencies() { :; }
        validate_inputs() { :; }
        normalize_image_system() {
            normalized_system="$1"
            return 0
        }
        process_image() {
            image_download_url=""
            status_tuna=false
            fixed_system=false
        }
        handle_image() {
            image_download_url=""
            status_tuna=false
            fixed_system=false
        }
        mark_continuation() {
            : >"$continued"
        }
        configure_storage() { mark_continuation; }
        configure_io() { mark_continuation; }
        configure_cpu() { mark_continuation; }
        configure_memory() { mark_continuation; }
        configure_security() { mark_continuation; }
        configure_limits() { mark_continuation; }
        setup_system() { mark_continuation; }
        setup_vm() { mark_continuation; }
        configure_port() { mark_continuation; }
        configure_network_speed() { mark_continuation; }
        configure_network() { mark_continuation; }
        cleanup_and_output() { mark_continuation; }
        cleanup_and_finish() { mark_continuation; }

        if main create-case 1 256 2 20001 0 0 100 100 N debian12 >output 2>&1; then
            fail "build${kind}: main succeeded after lxc init failed"
        fi
        [ ! -e "$continued" ] || fail "build${kind}: configuration continued after lxc init failed"
        [ ! -e create-case ] || fail "build${kind}: wrote a success record after lxc init failed"
        grep -Eq '^init ' "$lxc_log" || fail "build${kind}: lxc init was not attempted"
        if grep -Fq 'completed successfully' output; then
            fail "build${kind}: printed a success message after lxc init failed"
        fi
    )
}

run_stop_timeout_test() {
    local kind="$1"
    local script="$repo_root/scripts/build${kind}.sh"
    local workdir="$tmpdir/${kind}-stop"
    mkdir -p "$workdir"

    (
        cd "$workdir"
        export ONECLICKVIRT_TESTING=1
        # shellcheck disable=SC1090
        source "$script"

        local lxc_log="$workdir/lxc.log"
        local record="stop-case-${kind}"
        # Keep bounded CLI calls inside this shell so the fixture's lxc
        # implementation also covers the VM restart before the stop check.
        timeout() {
            if [ "${1:-}" = -k ]; then shift 2; fi
            shift
            "$@"
        }
        lxc() {
            printf '%s\n' "$*" >>"$lxc_log"
            case "${1:-}" in
            info)
                printf 'Status: RUNNING\n'
                ;;
            list)
                printf '[]\n'
                ;;
            esac
            return 0
        }
        sleep() { :; }
        if [[ "$kind" == vm ]]; then
            vm_ipv4_from_state() { printf '192.0.2.2\n'; }
        else
        jq() { printf '192.0.2.2\n'; }
        fi
        ip() { printf '2: eth0 inet 192.0.2.1/24 scope global eth0\n'; }
        init_env() { :; }
        ensure_lxd_ready() { :; }
        check_vm_support() { :; }
        check_china() { :; }
        check_cdn_file() { :; }
        get_system_arch() { :; }
        detect_arch() { :; }
        detect_os() { :; }
        install_dependencies() { :; }
        validate_inputs() { :; }
        normalize_image_system() {
            normalized_system="$1"
            return 0
        }
        process_image() { :; }
        handle_image() { :; }
        create_container() { :; }
        create_vm() { :; }
        configure_storage() { :; }
        configure_io() { :; }
        configure_cpu() { :; }
        configure_memory() { :; }
        configure_security() { :; }
        configure_limits() { :; }
        setup_system() {
            passwd=test-password
            return 0
        }
        setup_vm() {
            passwd=test-password
            return 0
        }
        configure_port() { :; }
        configure_firewall_ports() { :; }
        wait_for_container_ready_to_shutdown() { :; }
        wait_for_instance_ssh_ready() { :; }
        wait_for_vm_ready_to_shutdown() { :; }

        if main "$record" 1 256 2 20001 0 0 100 100 N debian12 >output 2>&1; then
            fail "build${kind}: main succeeded after stop timed out"
        fi
        [ ! -e "$record" ] || fail "build${kind}: wrote a success record after stop timed out"
        grep -Eq '^stop ' "$lxc_log" || fail "build${kind}: stop was not attempted"
        if grep -Eq '^(config|start) ' "$lxc_log"; then
            fail "build${kind}: configured or restarted the instance after stop timed out"
        fi
        if grep -Fq 'completed successfully' output; then
            fail "build${kind}: printed a success message after stop timed out"
        fi
    )
}

run_rollback_cleanup_test() {
    local kind="$1"
    local script="$repo_root/scripts/build${kind}.sh"
    local workdir="$tmpdir/${kind}-rollback"
    mkdir -p "$workdir"

    (
        cd "$workdir"
        export ONECLICKVIRT_TESTING=1
        # shellcheck disable=SC1090
        source "$script"

        local lxc_log="$workdir/lxc.log"
        lxc() {
            printf '%s\n' "$*" >>"$lxc_log"
            if [ "${1:-}" = query ]; then mock_identity_json; fi
            return 0
        }
        name="rollback-${kind}"
        created_instance=true
        created_identity=$'fixture-token\tfixture-uuid'
        build_succeeded=false
        trap cleanup_failed_instance EXIT
        exit 1
    ) && fail "build${kind}: failed invocation returned success"

    grep -Fxq "delete --force rollback-${kind}" "$workdir/lxc.log" ||
        fail "build${kind}: failed invocation did not remove its new instance"

    (
        cd "$workdir"
        export ONECLICKVIRT_TESTING=1
        # shellcheck disable=SC1090
        source "$script"

        local lxc_log="$workdir/preexisting.log"
        lxc() {
            printf '%s\n' "$*" >>"$lxc_log"
            return 0
        }
        name="preexisting-${kind}"
        created_instance=false
        build_succeeded=false
        trap cleanup_failed_instance EXIT
        exit 1
    ) && fail "build${kind}: pre-existing instance path returned success"

    [ ! -e "$workdir/preexisting.log" ] ||
        fail "build${kind}: cleanup touched a pre-existing instance"
}

run_init_status_tracking_test() {
    local kind="$1"
    local script="$repo_root/scripts/build${kind}.sh"
    local workdir="$tmpdir/${kind}-init-status"
    mkdir -p "$workdir"

    (
        cd "$workdir"
        export ONECLICKVIRT_TESTING=1
        # shellcheck disable=SC1090
        source "$script"

        local lxc_log="$workdir/lxc.log"
        name="late-${kind}"
        created_instance=false
        build_succeeded=false
        lxc() {
            printf '%s\n' "$*" >>"$lxc_log"
            case "${1:-}" in
            init) mock_creation_token="${!#}"; mock_creation_token="${mock_creation_token#*=}"; return 42 ;;
            query) mock_identity_json ;;
            info) return 0 ;;
            delete) return 0 ;;
            esac
            return 0
        }

        local init_status=0
        if create_instance_with_tracking lxc init image "$name"; then
            fail "build${kind}: late init failure was reported as success"
        else
            init_status=$?
        fi
        [ "$init_status" -eq 42 ] || fail "build${kind}: init status changed from 42 to ${init_status}"
        [ "$created_instance" = true ] || fail "build${kind}: late-created instance was not tracked"
        cleanup_failed_instance || true
        grep -Fxq "delete --force $name" "$lxc_log" ||
            fail "build${kind}: late-created instance was not removed"
    )
}

run_configuration_failure_cleanup_test() {
    local kind="$1"
    local script="$repo_root/scripts/build${kind}.sh"
    local workdir="$tmpdir/${kind}-configure"
    mkdir -p "$workdir"

    (
        cd "$workdir"
        export ONECLICKVIRT_TESTING=1
        # shellcheck disable=SC1090
        source "$script"

        local lxc_log="$workdir/lxc.log"
        local exists=false
        lxc() {
            printf '%s\n' "$*" >>"$lxc_log"
            case "${1:-}" in
            init)
                mock_creation_token="${!#}"; mock_creation_token="${mock_creation_token#*=}"
                exists=true
                return 0
                ;;
            query)
                [ "$exists" = true ] || return 1
                mock_identity_json
                ;;
            info)
                if [ "$exists" = true ]; then
                    return 0
                fi
                return 1
                ;;
            delete)
                exists=false
                return 0
                ;;
            esac
            return 0
        }
        init_env() { :; }
        ensure_lxd_ready() { :; }
        check_vm_support() { :; }
        check_china() { :; }
        check_cdn_file() { :; }
        get_system_arch() { :; }
        detect_arch() { :; }
        detect_os() { :; }
        install_dependencies() { :; }
        validate_inputs() { :; }
        normalize_image_system() { normalized_system="$1"; }
        process_image() {
            image_download_url=""
            status_tuna=false
            fixed_system=false
        }
        handle_image() {
            image_download_url=""
            status_tuna=false
            fixed_system=false
        }
        configure_storage() { return 37; }
        configure_limits() { return 37; }
        trap cleanup_failed_instance EXIT
        if main configure-case 1 256 2 20001 0 0 100 100 N debian12 >output 2>&1; then
            fail "build${kind}: configuration failure was reported as success"
        fi
        exit 37
    ) && fail "build${kind}: configuration failure returned success"

    grep -Fxq 'delete --force configure-case' "$workdir/lxc.log" ||
        fail "build${kind}: configuration failure did not roll back the instance"
    [ ! -e "$workdir/configure-case" ] ||
        fail "build${kind}: configuration failure wrote a success record"
}

run_mirror_package_failure_test() {
    local kind="$1"
    local script="$repo_root/scripts/build${kind}.sh"
    local workdir="$tmpdir/${kind}-mirror-package"
    mkdir -p "$workdir"

    (
        cd "$workdir"
        export ONECLICKVIRT_TESTING=1
        # shellcheck disable=SC1090
        source "$script"

        name="mirror-${kind}"
        CN=true
        system=debian12
        lxc() {
            if [[ "$*" == *'yum install -y curl'* ]]; then
                return 88
            fi
            return 0
        }
        if [ "$kind" = ct ]; then
            if setup_mirrors; then
                fail "build${kind}: mirror package installation failure was ignored"
            fi
        elif setup_mirror_and_packages; then
            fail "build${kind}: mirror package installation failure was ignored"
        fi
    )
}

run_ssh_setup_exec_boundary_test() {
    local kind="$1"
    (
        export ONECLICKVIRT_TESTING=1
        # shellcheck disable=SC1090
        source "$repo_root/scripts/build${kind}.sh"
        name="ssh-${kind}"
        passwd="test-only-password"
        cdn_success_url=""
        local history_executed=false
        # Isolate downloads and copies, but execute the final history command
        # through a real process boundary, just like the container exec API.
        curl() { :; }
        download_host_file() { :; }
        cp() { :; }
        chmod() { :; }
        dos2unix() { :; }
        lxc() {
            [ "${1:-}" = exec ] || return 0
            shift 3
            case "${1:-}" in
                chmod | dos2unix | ./ssh_bash.sh | sudo) return 0 ;;
                bash)
                    if [ "${2:-}" = config.sh ]; then return 0; fi
                    ;;
            esac
            command env "$@" || return $?
            history_executed=true
        }
        setup_ssh_bash || fail "build${kind}: SSH setup failed at the exec boundary"
        [ "$history_executed" = true ] || fail "build${kind}: history cleanup was not executed"
    )
}

run_ssh_setup_exec_boundary_test ct
run_ssh_setup_exec_boundary_test vm
run_create_failure_test ct
run_create_failure_test vm
run_stop_timeout_test ct
run_stop_timeout_test vm
run_rollback_cleanup_test ct
run_rollback_cleanup_test vm
run_init_status_tracking_test ct
run_init_status_tracking_test vm
run_configuration_failure_cleanup_test ct
run_configuration_failure_cleanup_test vm
run_mirror_package_failure_test ct
run_mirror_package_failure_test vm

printf 'LXD build failure control-flow tests passed\n'
