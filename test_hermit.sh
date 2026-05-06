#! /usr/bin/env bash
set -ex

SCRIPT_PATH=$(realpath "$0")
IPERF_SRC=$(dirname "${SCRIPT_PATH}")
KERNEL_DIR="${IPERF_SRC}"/../hermit-rs/kernel
: "${ARCH:=x86_64}"
PROFILE=release

pushd "${KERNEL_DIR}"
PROFILE_ARG="--profile="$([[ "${PROFILE}" == 'release' ]] && echo 'release' || echo 'dev')
cargo xtask build --arch "${ARCH}" "${PROFILE_ARG}" --no-default-features --features acpi,dns,mman,newlib,pci,tcp,udp,virtio-net
popd

IPERF_DST=/usr/local/src/iperf
LIBHERMIT_DST="${IPERF_DST}"/lib
function hermit-c-run() {
    LIBHERMIT_SRC="${KERNEL_DIR}"/target/"${ARCH}"/"${PROFILE}"
    podman run --rm \
        --mount type=bind,src="${IPERF_SRC}",dst="${IPERF_DST}",Z \
        --mount type=bind,src="${LIBHERMIT_SRC}",dst="${LIBHERMIT_DST}",readonly,Z \
        --workdir "${IPERF_DST}" \
        ghcr.io/hermit-os/hermit-gcc:"${ARCH}" \
        "$@"
}

HOST="${ARCH}"-hermit
hermit-c-run ./configure --host="${HOST}" --disable-shared
hermit-c-run make --directory=src --jobs iperf3

sudo qemu-system-"${ARCH}" \
    -enable-kvm \
    -cpu host \
    -smp 1 \
    -m 1G \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -display none -serial stdio \
    -kernel "${IPERF_SRC}"/../loader/target/release/hermit-loader-"${ARCH}"-multiboot \
    -initrd "${IPERF_SRC}"/src/iperf3 \
    -global virtio-mmio.force-legacy=off \
    -netdev tap,id=net0,script="${KERNEL_DIR}"/xtask/hermit-ifup,vhost=on \
    -device virtio-net-pci,netdev=net0,disable-legacy=on,packed=on,mq=on \
    -append "-ip 10.0.5.3 $*"
