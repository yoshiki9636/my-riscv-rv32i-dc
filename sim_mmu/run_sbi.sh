#!/bin/bash
# OpenSBI (fw_payload / fw_jump ELF) on tb_mmu : ./run_sbi.sh <elf> [vvp plusargs]
#   memory 16MB (TB_LINEBITS=20), FT_SMODE = 1.  The console output (io_uart_out
#   writes) is printed by the tb.  Build OpenSBI with ../sbi/build.sh.
set -e
cd "$(dirname "$0")"
source ./common.sh
#   ./run_sbi.sh <fw_jump.elf> tests/sbi_payload.S [plusargs] : with an S-mode
#   payload (linked at 0x0040_0000 by tests/link_payload.ld)
ELF=${1:-$ROOT/sbi/opensbi/build/platform/jasa/firmware/fw_payload.elf}; shift || true
NAME=$(basename "$ELF" .elf)
$TC-objcopy -O verilog --verilog-data-width=4 "$ELF" $OUT/sbi_$NAME.hex
if [ -n "$1" ] && [ "${1#+}" = "$1" ]; then
    PL=$1; shift
    PN=$(basename "$PL"); PN=${PN%.*}
    $TC-gcc -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles \
        -T $SIMDIR/tests/link_payload.ld -o $OUT/$PN.elf "$PL"
    $TC-objdump -d $OUT/$PN.elf > $OUT/$PN.dump
    $TC-objcopy -O verilog --verilog-data-width=4 $OUT/$PN.elf $OUT/$PN.hex
    cat $OUT/$PN.hex >> $OUT/sbi_$NAME.hex
    NAME=${NAME}_$PN
    mv $OUT/sbi_$(basename "$ELF" .elf).hex $OUT/sbi_$NAME.hex
fi
VDEFS="-DTB_SMODE=1 -DTB_LINEBITS=20 $VDEFS"
RTL=$(rtl_list)
TAG=$(echo "$VDEFS" | tr -c "A-Za-z0-9\n" "_")
VVP=$OUT/tb$TAG.vvp
if [ ! -f $VVP ] || [ -n "$(find $RTL $ROOT/fpga/fpga_config.vh tb_mmu.v sdram_if_sim.v rtl_files.txt -newer $VVP)" ]; then
    iverilog -g2005 $VDEFS -I$ROOT/fpga -o $VVP -s tb_mmu tb_mmu.v sdram_if_sim.v $RTL
fi
stdbuf -oL vvp -n $VVP +HEX=$OUT/sbi_$NAME.hex "$@" | tee $OUT/sbi_$NAME.log | grep -v "^VCD" | tail -60
