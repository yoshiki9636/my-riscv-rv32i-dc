# common settings for run.sh / cmp.sh / cmp_arch.sh (sourced)
#   ROOT     : repository top
#   TC       : RISC-V toolchain prefix
#   rtl_list <dir> : RTL file list (rtl_files.txt) under <dir> (default ROOT)
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SIMDIR=$ROOT/sim_mmu
OUT=$SIMDIR/out
TC=${TC:-/opt/riscv32im/bin/riscv32-unknown-elf}
mkdir -p $OUT

rtl_list() {
    local base=${1:-$ROOT}
    grep -v -e '^#' -e '^\s*$' $SIMDIR/rtl_files.txt | while read f; do
        [ -f $base/$f ] && echo $base/$f
    done
}

# build_test <src.S> : out/<name>.elf / .hex / .dump  (ASFLAGS : extra options)
build_test() {
    local src=$1
    local name=$(basename "$src"); name=${name%.*}
    $TC-gcc -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles \
        -I$SIMDIR/tests $ASFLAGS -T $SIMDIR/tests/link.ld -o $OUT/$name.elf "$src"
    $TC-objcopy -O verilog --verilog-data-width=4 $OUT/$name.elf $OUT/$name.hex
    $TC-objdump -d $OUT/$name.elf > $OUT/$name.dump
}

# export_ref <git rev> : the RTL of <rev> into out/ref_<rev>/ (same paths)
export_ref() {
    local rev=$1
    local dir=$OUT/ref_$(echo $rev | tr -c 'A-Za-z0-9\n' '_')
    rm -rf $dir; mkdir -p $dir
    grep -v -e '^#' -e '^\s*$' $SIMDIR/rtl_files.txt | while read f; do
        if git -C $ROOT cat-file -e $rev:$f 2>/dev/null; then
            mkdir -p $dir/$(dirname $f)
            git -C $ROOT show $rev:$f > $dir/$f
        fi
    done
    echo $dir
}
