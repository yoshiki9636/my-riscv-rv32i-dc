OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
stack : ORIGIN = 0x01000000, LENGTH = 1M
}

_min_stack = 0x20000;
_stack_len = LENGTH(stack);
_stack_start = ORIGIN(stack) + LENGTH(stack);

SECTIONS
{
  . = 0x00001000;
  .text.init : { *(.text.init) }
  . = ALIGN(0x10);
  .text : { *(.text) *(.rodata .rodata.*) }
  . = ALIGN(0x10);
  .data : { *(.data) }

  .sbss : {
    . = ALIGN(16);
    PROVIDE(_bss_start = .);
    *(.sbss .sbss.*)
  }

  .bss :{
    *(.bss .bss.*)
    . = ALIGN(16);
    PROVIDE(_bss_end = .);
  }

  .stack (NOLOAD): {
	. = ALIGN(16);
	. = . * _min_stack;
	. = ALIGN(16);
 	stack = . ;
 	_stack = . ;
	}

  _end = .;
}

