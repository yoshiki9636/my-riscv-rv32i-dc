#!/bin/bash

NAME=`basename $1 .c`
echo $NAME

/opt/riscv32im/bin/riscv32-unknown-elf-as -march=rv32im -mabi=ilp32 -o start.o start.s
/opt/riscv32im/bin/riscv32-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -u _printf_float -mstrict-align -mpreferred-stack-boundary=4 -c -o ${NAME}.o ${NAME}.c -lgmp

/opt/riscv32im/bin/riscv32-unknown-elf-ld -b elf32-littleriscv start.o ${NAME}.o -T link.ld -Map=${NAME}.map -o ${NAME}  --no-warn-rwx-segments --no-relax /opt/riscv32im/riscv32-unknown-elf/lib/libm_nano.a /opt/riscv32im/riscv32-unknown-elf/lib/libc_nano.a /opt/riscv32im/riscv32-unknown-elf/lib/libg_nano.a /opt/riscv32im/lib/gcc/riscv32-unknown-elf/15.2.0/libgcc.a /opt/riscv32im/gmp/lib/libgmp.a -u _printf_float --gc-sections
/opt/riscv32im/bin/riscv32-unknown-elf-objdump -b elf32-littleriscv -D ${NAME} > ${NAME}.elf.dump
/opt/riscv32im/bin/riscv32-unknown-elf-objcopy -O binary ${NAME} ${NAME}.bin
od -An -tx4 -w4 -v ${NAME}.bin > ${NAME}.hex
cat ${NAME}.hex zero >  ${NAME}.2.hex

