#!/bin/bash
# MMU Linux (S-mode) for my-riscv-rv32i-dc + OpenSBI fw_payload
#   KSRC   kernel source (default ~/linux/linux-mmu : a clean copy, NOT the nommu tree)
#   KOUT   build directory (default ~/linux/build-mmu)
#   CPIO   initramfs (default ~/linux/linux/initramfs.cpio : the static-pie busybox)
#   BASE   base .config (default ~/linux/linux/.config : the nommu config) + mmu.config
#   ./build.sh            config (first time) + Image + dtb + fw_payload
#   ./build.sh config     redo the config from BASE + mmu.config
#   output : $KOUT/arch/riscv/boot/Image, $KOUT/my_fpga_mmu.dtb,
#            ../sbi/opensbi/build/platform/jasa/firmware/fw_payload.{elf,bin,hex}
set -e
cd "$(dirname "$0")"
HERE=$PWD
KSRC=${KSRC:-$HOME/linux/linux-mmu}
KOUT=${KOUT:-$HOME/linux/build-mmu}
CPIO=${CPIO:-$HOME/linux/linux/initramfs.cpio}
BASE=${BASE:-$HOME/linux/linux/.config}
CROSS=${CROSS_COMPILE:-/opt/riscv32im.linux/bin/riscv32-unknown-linux-gnu-}
MK="make -C $KSRC O=$KOUT ARCH=riscv CROSS_COMPILE=$CROSS"

# the driver into the kernel tree
cp $HERE/myuart.c $KSRC/drivers/tty/serial/myuart.c
if ! grep -q SERIAL_MYUART $KSRC/drivers/tty/serial/Kconfig; then
    python3 - $KSRC/drivers/tty/serial/Kconfig <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
add = '''
config SERIAL_MYUART
	tristate "my-riscv-rv32i-dc UART"
	depends on OF
	select SERIAL_CORE
	help
	  UART of the my-riscv-rv32i-dc FPGA RISC-V.

config SERIAL_MYUART_CONSOLE
	bool "Console on the my-riscv-rv32i-dc UART"
	depends on SERIAL_MYUART=y
	select SERIAL_CORE_CONSOLE
	select SERIAL_EARLYCON

endmenu
'''
i = s.rindex('endmenu')
s = s[:i] + add.lstrip('\n') + s[i + len('endmenu'):]
open(p, 'w').write(s)
PY
    echo 'obj-$(CONFIG_SERIAL_MYUART)		+= myuart.o' >> $KSRC/drivers/tty/serial/Makefile
fi

mkdir -p $KOUT
if [ ! -f $KOUT/.config ] || [ "$1" = config ]; then
    cp $BASE $KOUT/.config
    cat $HERE/mmu.config >> $KOUT/.config
    echo "CONFIG_INITRAMFS_SOURCE=\"$CPIO\"" >> $KOUT/.config
    $MK olddefconfig
fi
$MK -j8 Image
${CROSS}cpp -nostdinc -undef -x assembler-with-cpp $HERE/my_fpga_mmu.dts | \
    $KOUT/scripts/dtc/dtc -I dts -O dtb -o $KOUT/my_fpga_mmu.dtb -
ls -la $KOUT/arch/riscv/boot/Image $KOUT/my_fpga_mmu.dtb
$HERE/../sbi/build.sh FW_PAYLOAD_PATH=$KOUT/arch/riscv/boot/Image FW_FDT_PATH=$KOUT/my_fpga_mmu.dtb
