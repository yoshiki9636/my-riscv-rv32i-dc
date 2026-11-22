/* S-mode payload of OpenSBI fw_jump (FW_JUMP_ADDR = 0x0040_0000) */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
    . = 0x00400000;
    .text : { *(.text.init) *(.text*) }
    .data : { *(.data*) *(.rodata*) }
    .bss  : { *(.bss*) *(COMMON) }
}
