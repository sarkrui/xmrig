#!/usr/bin/env bash

set -euo pipefail


ROOT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ORB_SSH_PORT="${ORB_SSH_PORT:-32222}"
ORB_SSH_KEY="${ORB_SSH_KEY:-${HOME}/.orbstack/ssh/id_ed25519}"
ARM_VM="${ARM_VM:-build-arm64}"
AMD_VM="${AMD_VM:-build-amd64}"
VM_REPO_DIR="${VM_REPO_DIR:-/mnt/mac${ROOT_DIR}}"

SSH_BASE=(
    ssh
    -p "${ORB_SSH_PORT}"
    -i "${ORB_SSH_KEY}"
    -o BatchMode=yes
)


die() {
    echo "error: $*" >&2
    exit 1
}


run_remote_bash() {
    local vm=$1
    local script=$2

    "${SSH_BASE[@]}" "${vm}@127.0.0.1" "bash -lc $(printf '%q' "${script}")"
}


vm_for_target() {
    case "$1" in
        linux-amd64)
            echo "${AMD_VM}"
            ;;
        linux-aarch64)
            echo "${ARM_VM}"
            ;;
        *)
            die "unsupported Linux target: $1"
            ;;
    esac
}


expected_arch_for_target() {
    case "$1" in
        linux-amd64)
            echo "x86_64"
            ;;
        linux-aarch64)
            echo "aarch64"
            ;;
        *)
            die "unsupported Linux target: $1"
            ;;
    esac
}


preflight_vm_target() {
    local target=$1
    local vm
    local expected_arch
    local actual_arch
    local missing_tools

    vm=$(vm_for_target "${target}")
    expected_arch=$(expected_arch_for_target "${target}")
    actual_arch=$(run_remote_bash "${vm}" "uname -m")

    case "${target}:${actual_arch}" in
        linux-amd64:x86_64|linux-aarch64:aarch64|linux-aarch64:arm64)
            ;;
        *)
            die "${vm} returned architecture ${actual_arch}, expected ${expected_arch} for ${target}"
            ;;
    esac

    missing_tools=$(run_remote_bash "${vm}" '
        missing=0
        for cmd in cmake ninja gcc g++ curl perl pkg-config autoconf automake libtoolize; do
            if ! command -v "$cmd" >/dev/null 2>&1; then
                printf "%s\n" "$cmd"
                missing=1
            fi
        done
        exit "$missing"
    ' || true)

    if [ -n "${missing_tools}" ]; then
        die "${vm} is missing required build tools for ${target}: ${missing_tools//$'\n'/, }"
    fi

    run_remote_bash "${vm}" "[ -d $(printf '%q' "${VM_REPO_DIR}") ]" >/dev/null
}


run_macos_target() {
    "${ROOT_DIR}/scripts/build-target.sh" "$1"
}


run_linux_target() {
    local target=$1
    local vm

    vm=$(vm_for_target "${target}")
    run_remote_bash "${vm}" "cd $(printf '%q' "${VM_REPO_DIR}") && ./scripts/build-target.sh $(printf '%q' "${target}")"
}


if [ "$(uname -s)" != "Darwin" ]; then
    die "scripts/cross-build.sh is intended to be launched from macOS"
fi

if [ "$#" -gt 0 ]; then
    TARGETS=("$@")
else
    TARGETS=(
        linux-amd64
        linux-aarch64
        macos-amd64
        macos-arm64
    )
fi

command -v ssh >/dev/null 2>&1 || die "ssh is required to reach the OrbStack build VMs"
[ -f "${ORB_SSH_KEY}" ] || die "missing OrbStack SSH key at ${ORB_SSH_KEY}"

for target in "${TARGETS[@]}"; do
    case "${target}" in
        linux-amd64|linux-aarch64)
            preflight_vm_target "${target}"
            ;;
    esac
done

linux_pids=()
linux_targets=()

for target in "${TARGETS[@]}"; do
    case "${target}" in
        macos-amd64|macos-arm64)
            run_macos_target "${target}"
            ;;
        linux-amd64|linux-aarch64)
            run_linux_target "${target}" &
            linux_pids+=("$!")
            linux_targets+=("${target}")
            ;;
        *)
            die "unsupported target: ${target}"
            ;;
    esac
done

for i in "${!linux_pids[@]}"; do
    if ! wait "${linux_pids[$i]}"; then
        die "build failed for ${linux_targets[$i]}"
    fi
done
