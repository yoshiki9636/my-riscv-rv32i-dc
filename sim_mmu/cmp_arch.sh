#!/bin/bash
# compare the ARCHITECTURAL commit trace (register write backs + MMIO writes,
# without cycle numbers / D$ write backs) of the current RTL with a git revision
#   [VDEFS=...] [ASFLAGS=...] ./cmp_arch.sh <test.S> [ref_rev (default master)] [maxcyc]
# used when the cache organization differs (set associative D$ vs. direct map),
# so the cycle exact comparison (cmp.sh) can not be used.  Tests with timer
# interrupts / MTIME reads can differ legitimately.
set -e
cd "$(dirname "$0")"
source ./common.sh
SRC=$1; REF=${2:-master}; MAXCYC=${3:-100000}
NAME=$(basename "$SRC"); NAME=${NAME%.*}
build_test "$SRC"
TAG=$(echo "$VDEFS" | tr -c "A-Za-z0-9\n" "_")
REFDIR=$(export_ref $REF)
iverilog -g2005 $VDEFS -I$ROOT/fpga -o $OUT/tba_new$TAG.vvp -s tb_mmu tb_mmu.v sdram_if_sim.v $(rtl_list)
iverilog -g2005 $VDEFS -DTB_ORIG -I$ROOT/fpga -o $OUT/tba_org$TAG.vvp -s tb_mmu tb_mmu.v sdram_if_sim.v $(rtl_list $REFDIR)
vvp -n $OUT/tba_new$TAG.vvp +HEX=$OUT/$NAME.hex +MAXCYC=$MAXCYC +COMMIT | grep "^C " | grep -v " DCW " | cut -d' ' -f3- > $OUT/$NAME.new.arch || true
vvp -n $OUT/tba_org$TAG.vvp +HEX=$OUT/$NAME.hex +MAXCYC=$MAXCYC +COMMIT | grep "^C " | grep -v " DCW " | cut -d' ' -f3- > $OUT/$NAME.org.arch || true
NN=$(wc -l < $OUT/$NAME.new.arch); NO=$(wc -l < $OUT/$NAME.org.arch)
N=$(( NN < NO ? NN : NO ))
if cmp -s <(head -n $N $OUT/$NAME.new.arch) <(head -n $N $OUT/$NAME.org.arch); then
  echo "SAME : $NAME (common prefix $N events, new $NN / org $NO)"
else
  L=$(cmp <(head -n $N $OUT/$NAME.new.arch) <(head -n $N $OUT/$NAME.org.arch) | sed 's/.*line //')
  echo "DIFF : $NAME at event $L (new $NN / org $NO)"
fi
