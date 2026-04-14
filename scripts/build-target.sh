#!/usr/bin/env bash

set -euo pipefail


ROOT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE_CACHE_DIR="${ROOT_DIR}/scripts/build"

UV_VERSION="1.51.0"
HWLOC_VERSION="2.12.1"
OPENSSL_VERSION="3.0.16"


usage() {
    cat <<'EOF'
Usage: scripts/build-target.sh <target>

Targets:
  linux-amd64
  linux-aarch64
  macos-amd64
  macos-arm64
EOF
}


die() {
    echo "error: $*" >&2
    exit 1
}


detect_jobs() {
    local jobs

    jobs=$(nproc 2>/dev/null || true)
    if [ -n "${jobs}" ]; then
        echo "${jobs}"
        return
    fi

    jobs=$(sysctl -n hw.ncpu 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || true)
    if [ -n "${jobs}" ]; then
        echo "${jobs}"
        return
    fi

    echo 4
}


host_build_triple() {
    case "$(uname -s):$(uname -m)" in
        Darwin:arm64)
            echo "arm64-apple-darwin"
            ;;
        Darwin:x86_64)
            echo "x86_64-apple-darwin"
            ;;
        Linux:aarch64|Linux:arm64)
            echo "aarch64-linux-gnu"
            ;;
        Linux:x86_64|Linux:amd64)
            echo "x86_64-linux-gnu"
            ;;
        *)
            die "unsupported build host $(uname -s):$(uname -m)"
            ;;
    esac
}


download_file() {
    local url=$1
    local dest=$2

    if [ -f "${dest}" ]; then
        return
    fi

    mkdir -p -- "$(dirname "${dest}")"

    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --retry 3 --output "${dest}" "${url}"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "${dest}" "${url}"
    else
        die "curl or wget is required to download ${url}"
    fi
}


extract_archive() {
    local archive=$1
    local work_dir=$2
    local extracted_dir_name=$3

    rm -rf -- "${work_dir:?}/${extracted_dir_name}"
    mkdir -p -- "${work_dir}"
    tar -xzf "${archive}" -C "${work_dir}"
}


copy_tree_contents() {
    local src_dir=$1
    local dest_dir=$2

    mkdir -p -- "${dest_dir}"
    (cd "${src_dir}" && tar -cf - .) | (cd "${dest_dir}" && tar -xf -)
}


prepare_directories() {
    WORK_DIR="${SOURCE_CACHE_DIR}/${TARGET}"
    DEPS_DIR="${ROOT_DIR}/scripts/deps/${TARGET}"
    BUILD_DIR="${ROOT_DIR}/build/${TARGET}"
    DIST_DIR="${ROOT_DIR}/dist/${TARGET}"
    STAGE_DIR="${DIST_DIR}/${ARTIFACT_BASENAME}"

    rm -rf -- "${WORK_DIR}" "${DEPS_DIR}" "${BUILD_DIR}" "${STAGE_DIR}"
    mkdir -p -- "${WORK_DIR}" "${DEPS_DIR}/include" "${DEPS_DIR}/lib" "${BUILD_DIR}" "${DIST_DIR}"
}


configure_target() {
    local host_os
    local host_arch

    host_os=$(uname -s)
    host_arch=$(uname -m)

    case "${TARGET}" in
        linux-amd64)
            target_os="linux"
            target_arch="x86_64"
            cmake_processor="x86_64"
            ;;
        linux-aarch64)
            target_os="linux"
            target_arch="aarch64"
            cmake_processor="aarch64"
            ;;
        macos-amd64)
            target_os="macos"
            target_arch="x86_64"
            cmake_processor="x86_64"
            autoconf_host="x86_64-apple-darwin"
            openssl_target="darwin64-x86_64-cc"
            ;;
        macos-arm64)
            target_os="macos"
            target_arch="arm64"
            cmake_processor="arm64"
            autoconf_host="aarch64-apple-darwin"
            openssl_target="darwin64-arm64-cc"
            ;;
        *)
            usage
            die "unsupported target: ${TARGET}"
            ;;
    esac

    case "${target_os}" in
        linux)
            [ "${host_os}" = "Linux" ] || die "${TARGET} must be built on Linux. Run it via scripts/cross-build.sh from macOS."

            case "${TARGET}:${host_arch}" in
                linux-amd64:x86_64|linux-amd64:amd64|linux-aarch64:aarch64|linux-aarch64:arm64)
                    ;;
                *)
                    die "${TARGET} requires a Linux ${target_arch} environment, got ${host_arch}"
                    ;;
            esac
            ;;
        macos)
            [ "${host_os}" = "Darwin" ] || die "${TARGET} must be built on macOS"
            ;;
    esac
}


configure_macos_env() {
    local deployment_target

    deployment_target="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

    export MACOSX_DEPLOYMENT_TARGET="${deployment_target}"
    export CC="${CC:-clang}"
    export CXX="${CXX:-clang++}"
    export AR="${AR:-ar}"
    export RANLIB="${RANLIB:-ranlib}"
    export STRIP="${STRIP:-strip}"
    export CFLAGS="-arch ${target_arch} -mmacosx-version-min=${deployment_target}"
    export CXXFLAGS="${CFLAGS}"
    export LDFLAGS="${CFLAGS}"
}


configure_linux_env() {
    export CC="${LINUX_CC:-gcc}"
    export CXX="${LINUX_CXX:-g++}"
    export ASM="${LINUX_ASM:-gcc}"
    export AR="${LINUX_AR:-ar}"
    export RANLIB="${LINUX_RANLIB:-ranlib}"
    export STRIP="${LINUX_STRIP:-strip}"
}


build_libuv() {
    local archive
    local src_dir
    local build_triple

    archive="${SOURCE_CACHE_DIR}/v${UV_VERSION}.tar.gz"
    download_file "https://dist.libuv.org/dist/v${UV_VERSION}/libuv-v${UV_VERSION}.tar.gz" "${archive}"
    extract_archive "${archive}" "${WORK_DIR}" "libuv-v${UV_VERSION}"
    src_dir="${WORK_DIR}/libuv-v${UV_VERSION}"

    (
        cd "${src_dir}"

        if [ "${target_os}" = "macos" ]; then
            build_triple=$(host_build_triple)
            LIBTOOLIZE="${LIBTOOLIZE:-glibtoolize}" sh autogen.sh
            ./configure --disable-shared --host="${autoconf_host}" --build="${build_triple}"
        else
            sh autogen.sh
            ./configure --disable-shared
        fi

        make -j"${JOBS}"
        copy_tree_contents "${src_dir}/include" "${DEPS_DIR}/include"
        cp -f -- "${src_dir}/.libs/libuv.a" "${DEPS_DIR}/lib/"
    )
}


build_hwloc() {
    local archive
    local src_dir
    local build_triple
    local configure_args

    archive="${SOURCE_CACHE_DIR}/hwloc-${HWLOC_VERSION}.tar.gz"
    download_file "https://download.open-mpi.org/release/hwloc/v2.12/hwloc-${HWLOC_VERSION}.tar.gz" "${archive}"
    extract_archive "${archive}" "${WORK_DIR}" "hwloc-${HWLOC_VERSION}"
    src_dir="${WORK_DIR}/hwloc-${HWLOC_VERSION}"

    configure_args=(--disable-shared --enable-static --disable-cairo --disable-io --disable-libudev --disable-libxml2)

    (
        cd "${src_dir}"

        if [ "${target_os}" = "macos" ]; then
            build_triple=$(host_build_triple)
            ./configure "${configure_args[@]}" --host="${autoconf_host}" --build="${build_triple}"
        else
            ./configure "${configure_args[@]}"
        fi

        make -j"${JOBS}"
        copy_tree_contents "${src_dir}/include" "${DEPS_DIR}/include"
        cp -f -- "${src_dir}/hwloc/.libs/libhwloc.a" "${DEPS_DIR}/lib/"
    )
}


build_openssl() {
    local archive
    local src_dir

    archive="${SOURCE_CACHE_DIR}/openssl-${OPENSSL_VERSION}.tar.gz"
    download_file "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" "${archive}"
    extract_archive "${archive}" "${WORK_DIR}" "openssl-${OPENSSL_VERSION}"
    src_dir="${WORK_DIR}/openssl-${OPENSSL_VERSION}"

    (
        cd "${src_dir}"

        if [ "${target_os}" = "macos" ]; then
            perl ./Configure "${openssl_target}" no-shared no-asm no-zlib no-comp no-dgram no-filenames no-cms no-tests
        else
            ./config -no-shared -no-asm -no-zlib -no-comp -no-dgram -no-filenames -no-cms -no-tests
        fi

        make -j"${JOBS}"
        copy_tree_contents "${src_dir}/include" "${DEPS_DIR}/include"
        cp -f -- "${src_dir}/libcrypto.a" "${DEPS_DIR}/lib/"
        cp -f -- "${src_dir}/libssl.a" "${DEPS_DIR}/lib/"
    )
}


build_xmrig() {
    local cmake_args

    cmake_args=(
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_SYSTEM_PROCESSOR="${cmake_processor}"
        -DXMRIG_DEPS="${DEPS_DIR}"
    )

    if [ "${target_arch}" = "x86_64" ]; then
        # Apple cross-compiles can still inherit the host ARM auto-detection.
        # Pinning ARM_TARGET below 7 disables the ARM-specific flag path.
        cmake_args+=(-DARM_TARGET=5)
    fi

    if [ "${target_os}" = "linux" ]; then
        cmake_args+=(
            -DBUILD_STATIC=ON
            -DWITH_OPENCL=OFF
            -DWITH_CUDA=OFF
        )
    else
        cmake_args+=(
            -DCMAKE_OSX_ARCHITECTURES="${target_arch}"
            -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET}"
            -DWITH_CUDA=OFF
        )
    fi

    cmake -S "${ROOT_DIR}" -B "${BUILD_DIR}" "${cmake_args[@]}"
    cmake --build "${BUILD_DIR}" --parallel "${JOBS}"
}


package_artifact() {
    local archive_path
    local checksum_path

    mkdir -p -- "${STAGE_DIR}"
    cp -f -- "${BUILD_DIR}/xmrig" "${STAGE_DIR}/"
    cp -f -- "${ROOT_DIR}/LICENSE" "${STAGE_DIR}/"
    cp -f -- "${ROOT_DIR}/README.md" "${STAGE_DIR}/"
    printf '%s\n' "${VERSION}" > "${STAGE_DIR}/version"

    archive_path="${DIST_DIR}/${ARTIFACT_BASENAME}.tar.gz"
    checksum_path="${archive_path}.sha256"

    rm -f -- "${archive_path}" "${checksum_path}"
    tar -czf "${archive_path}" -C "${DIST_DIR}" "${ARTIFACT_BASENAME}"
    shasum -a 256 "${archive_path}" > "${checksum_path}"
}


[ $# -eq 1 ] || {
    usage
    exit 1
}

TARGET=$1
VERSION=$(sed -n 's/^#define APP_VERSION   "\(.*\)"/\1/p' "${ROOT_DIR}/src/version.h")
[ -n "${VERSION}" ] || die "unable to read APP_VERSION from src/version.h"

ARTIFACT_BASENAME="xmrig-${VERSION}-${TARGET}"
JOBS="${JOBS:-$(detect_jobs)}"

configure_target

if [ "${target_os}" = "macos" ]; then
    configure_macos_env
else
    configure_linux_env
fi

prepare_directories

echo "Building dependencies for ${TARGET}"
build_libuv
build_hwloc
build_openssl

echo "Building xmrig for ${TARGET}"
build_xmrig

echo "Packaging ${TARGET}"
package_artifact

echo "Finished ${TARGET}: ${DIST_DIR}/${ARTIFACT_BASENAME}.tar.gz"
