#!/bin/bash
# lab7 MMU simulation : [ASFLAGS=...] [VDEFS=...] ./run.sh tests/xxx.S [vvp plusargs]
#   RTL : the files in rtl_files.txt (cpu/, io/, buslogics/, mig/ ...),
#         board / memory from fpga/fpga_config.vh
#   ASFLAGS : extra assembler options (e.g. ASFLAGS=-DTIMER_INTERVAL=157)
#   VDEFS   : extra iverilog defines (e.g. VDEFS="-DTB_DWAYS=8")
#   prints RESULT: PASS / FAIL / TIMEOUT
set -e
cd "$(dirname "$0")"
source ./common.sh
SRC=$1; shift
NAME=$(basename "$SRC"); NAME=${NAME%.*}
build_test "$SRC"
RTL=$(rtl_list)
TAG=$(echo "$VDEFS" | tr -c "A-Za-z0-9\n" "_")
VVP=$OUT/tb$TAG.vvp
if [ ! -f $VVP ] || [ -n "$(find $RTL $ROOT/fpga/fpga_config.vh tb_mmu.v sdram_if_sim.v rtl_files.txt -newer $VVP)" ]; then
    iverilog -g2005 $VDEFS -I$ROOT/fpga -o $VVP -s tb_mmu tb_mmu.v sdram_if_sim.v $RTL
fi
vvp -n $VVP +HEX=$OUT/$NAME.hex "$@" | tee $OUT/$NAME.log | grep -v "^VCD" | tail -40
