;*
;* My RISC-V RV32I CPU
;*   Test Code IF/ID Instructions : No.1
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

; test setup
lui x3, 0x00010 ; test data address
addi x4, x0, 0xa ; test value a
sw x4, 0x0(x3)  ; store test data a to address

addi x5, x0, 0x9 ; test value b 

;test
lr.w x6, (x3) ; lr.w to 0x10000
addi x4, x0, 0xb ; test value b
sw x4, 0x0(x3)  ; store test data a to address : for fail
sc.w x7, x5, (x3) ; lr.w to 0x10000

beq x7, x0, failed ; check1
lw x8, 0x0(x3) ; 
bne x8, x4, failed2 ; check2
; pass
jalr x0, x0, finished

:failed
addi x1, x0, 1 ; LED value
sw x1, 0x0(x2) ; set LED
jalr x0, x0, failed
:failed2
addi x1, x0, 2 ; LED value
sw x1, 0x0(x2) ; set LED
jalr x0, x0, failed2

; test finished
nop
nop
:finished
;lui x2, 01000 ; loop max
ori x2, x0, 10 ; small loop for sim
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
:modify
addi x3, x3, 0x10 ; modify code
nop
nop
nop
