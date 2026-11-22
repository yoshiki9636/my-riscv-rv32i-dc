#!/bin/bash
# OpenSBI for my-riscv-rv32i-dc (platform/5stage, out-of-tree platform)
#   OPENSBI=<OpenSBI source> (default ~/linux/opensbi, tested : v1.8, 6767861c)
#   ./build.sh                      fw_jump + fw_payload (test payload)
#   ./build.sh FW_PAYLOAD_PATH=<Image> FW_FDT_PATH=<dtb>   Linux in fw_payload
#   ./build.sh FW_PAYLOAD_PATH=<payload.bin>               any S-mode payload
#   output : opensbi/build/platform/5stage/firmware/fw_{jump,payload}.{elf,bin}
#            fw_payload.hex (board loader format, see bin2hex.py)
set -e
cd "$(dirname "$0")"
OPENSBI=${OPENSBI:-$HOME/linux/opensbi}
CROSS=${CROSS_COMPILE:-/opt/riscv32im.linux/bin/riscv32-unknown-linux-gnu-}
make -C $OPENSBI PLATFORM_DIR=$PWD/opensbi/platform/5stage CROSS_COMPILE=$CROSS \
    O=$PWD/opensbi/build -j8 "$@"
FW=$PWD/opensbi/build/platform/5stage/firmware
python3 bin2hex.py $FW/fw_payload.bin $FW/fw_payload.hex
