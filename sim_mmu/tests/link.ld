OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS
{
  . = 0x00000000;
  .text : { *(.text.init) *(.text*) }
  . = ALIGN(16);
  .data : { *(.data*) *(.rodata*) *(.bss*) }
}
