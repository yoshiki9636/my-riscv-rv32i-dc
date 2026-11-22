#!/bin/bash
# random MMU pipeline check : ./rnd_mmu.sh <seed> [vvp plusargs]
#   the program of rnd_mmu.py <seed> runs with translation (S-mode, 4KB
#   identity pages) and without (M-mode); the register write backs of the
#   traced code (0x38000 - 0x5FFFF) must be identical.  VDEFS as run.sh
#   (default : the board's FT_SMODE / ways).  prints SAME / DIFF
set -e
cd "$(dirname "$0")"
source ./common.sh
SEED=$1; shift
D=$OUT/rnd; mkdir -p $D
python3 rnd_mmu.py $SEED $D/r$SEED.S
for T in 0 1; do
    $TC-gcc -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles -DTRANS=$T \
        -T $SIMDIR/tests/link.ld -o $D/r${SEED}_$T.elf $D/r$SEED.S
    $TC-objcopy -O verilog --verilog-data-width=4 $D/r${SEED}_$T.elf $D/r${SEED}_$T.hex
done
RTL=$(rtl_list)
TAG=$(echo "$VDEFS" | tr -c "A-Za-z0-9\n" "_")
VVP=$OUT/tb$TAG.vvp
if [ ! -f $VVP ] || [ -n "$(find $RTL $ROOT/fpga/fpga_config.vh tb_mmu.v sdram_if_sim.v rtl_files.txt -newer $VVP)" ]; then
    iverilog -g2005 $VDEFS -I$ROOT/fpga -o $VVP -s tb_mmu tb_mmu.v sdram_if_sim.v $RTL
fi
for T in 0 1; do
    vvp -n $VVP +HEX=$D/r${SEED}_$T.hex +MAXCYC=3000000 +COMMIT "$@" > $D/r${SEED}_$T.log 2>&1 || true
    grep "^C .* WB " $D/r${SEED}_$T.log | awk '{ pc = substr($NF, 4); v = strtonum("0x" pc); if (v >= 0x38000 && v < 0x60000) print $4, $5 }' > $D/r${SEED}_$T.arch
done
R0=$(grep -m1 RESULT $D/r${SEED}_0.log); R1=$(grep -m1 RESULT $D/r${SEED}_1.log)
N0=$(wc -l < $D/r${SEED}_0.arch); N1=$(wc -l < $D/r${SEED}_1.arch)
if [ "$R0" = "RESULT: PASS" ] && [ "$R1" = "RESULT: PASS" ] && cmp -s $D/r${SEED}_0.arch $D/r${SEED}_1.arch; then
    echo "SAME : seed $SEED ($N0 events)"
else
    L=$(cmp $D/r${SEED}_0.arch $D/r${SEED}_1.arch 2>/dev/null | sed 's/.*line //')
    echo "DIFF : seed $SEED at event ${L:-?} (trans0 $N0 [$R0] / trans1 $N1 [$R1])"
fi
