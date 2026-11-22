#!/bin/bash
# Buildroot userland for the MMU Linux : ./build.sh [make targets]
#   BR   Buildroot source (default ~/linux/buildroot-2026.08.2)
#   OUT  output directory (default ~/linux/br-out)
#   result : $OUT/images/rootfs.cpio
#   then the kernel / fw_payload : CPIO=$OUT/images/rootfs.cpio ../build.sh config
#   (WSL : PATH is cleaned, Buildroot refuses entries with spaces)
set -e
cd "$(dirname "$0")"
HERE=$PWD
BR=${BR:-$HOME/linux/buildroot-2026.08.2}
OUT=${OUT:-$HOME/linux/br-out}
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if [ ! -f $OUT/.config ]; then
    make -C $BR O=$OUT BR2_DEFCONFIG=$HERE/fpga_rv32ima_glibc_defconfig defconfig
fi
make -C $BR O=$OUT "$@"
ls -la $OUT/images/
