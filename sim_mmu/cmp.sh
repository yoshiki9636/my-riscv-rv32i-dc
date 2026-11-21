#!/bin/bash
# compare the commit log (cycle exact) of the current RTL with a git revision
#   [VDEFS=...] [ASFLAGS=...] ./cmp.sh <test.S | test.hex> [ref_rev (default master)] [maxcyc]
# MMU off (e.g. VDEFS="-DTB_DWAYS=1") : the logs must be identical
#   The reference RTL is taken with `git show <rev>:<path>` for the files in
#   rtl_files.txt.  fpga_config.vh is the current one for both.
set -e
cd "$(dirname "$0")"
source ./common.sh
SRC=$1; REF=${2:-master}; MAXCYC=${3:-100000}
NAME=$(basename "$SRC"); NAME=${NAME%.*}
case "$SRC" in
  *.S) build_test "$SRC"; HEX=$OUT/$NAME.hex ;;
  *) HEX=$SRC ;;
esac
REFDIR=$(export_ref $REF)
iverilog -g2005 $VDEFS -I$ROOT/fpga -o $OUT/tb_new.vvp -s tb_mmu tb_mmu.v sdram_if_sim.v $(rtl_list)
iverilog -g2005 $VDEFS -DTB_ORIG -I$ROOT/fpga -o $OUT/tb_org.vvp -s tb_mmu tb_mmu.v sdram_if_sim.v $(rtl_list $REFDIR)
vvp -n $OUT/tb_new.vvp +HEX=$HEX +MAXCYC=$MAXCYC +COMMIT | grep "^C " > $OUT/$NAME.new.commit || true
vvp -n $OUT/tb_org.vvp +HEX=$HEX +MAXCYC=$MAXCYC +COMMIT | grep "^C " > $OUT/$NAME.org.commit || true
N=$(wc -l < $OUT/$NAME.new.commit)
if cmp -s $OUT/$NAME.new.commit $OUT/$NAME.org.commit; then
  echo "SAME : $NAME ($N events)"
else
  echo "DIFF : $NAME"; diff $OUT/$NAME.org.commit $OUT/$NAME.new.commit | head -10
fi
