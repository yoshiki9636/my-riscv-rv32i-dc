;*
;* My RISC-V RV32I CPU
;*   Test Code ALU Instructions : No.3
;*    RV32I code
;* @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
;* @copylight	2021 Yoshiki Kurokawa
;* @license		https://opensource.org/licenses/MIT     MIT license
;* @version		0.1
;*

nop
nop
; clear LED to black
addi x1, x0, 7 ; LED value
lui x2, 0xc0010 ; LED address
addi x2, x2, 0xe00 ;
sw x1, 0x0(x2) ; set LED

; test add
:fail_test1

lui x3, 0xc000e ; DMA register address
addi x3, x3, 0x004 ;
and x4, x0, x4
sw x4, 0x0(x3) ; set DMA scr address

addi x3, x3, 0x004 ; DMA mem address
and x4, x0, x4
sw x4, 0x0(x3) ; set DMA mem address

addi x3, x3, 0x004 ; DMA counter
addi x4, x0, 0x100
sw x4, 0x0(x3) ; set DMA counter

lui x3, 0xc000e ; DMA read start
addi x3, x3, 0x000 ;
addi x4, x0, 0x1 ; read DMA
sw x4, 0x0(x3) ; set DMA counter


:wait_loop
lw x4, 0x0(x3) ; set DMA counter
bne x4, x0, wait_loop

; test finished
nop
nop
;lui x2, 01000 ; loop max
ori x2, x0, 10 ; loop max
and x3, x0, x3 ; LED value
and x4, x0, x4 ;
lui x4, 0xc0010 ; LED address
addi x4, x4, 0xe00 ;
:label_led
and x1, x0, x1 ; loop counter
:label_waitloop
addi x1, x1, 1
blt x1, x2, label_waitloop
addi x3, x3, 1
sw x3, 0x0(x4)
jalr x0, x0, label_led
nop
nop
nop
nop
