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

nop
nop
nop

; test mul
:fail_test1
ori x3, x0, 0xf85 ; -123
lui x4, 0xd0f1e ;
addi x4, x4, 0xb05 ; -789,456,123
mul x3, x3, x4
lui x4, 0x9bcbc ;
addi x4, x4, 0x499 ; 97,103,103,129 's lower
bne x4, x3, fail_test1
; next value
addi x1, x0, 6 ; LED value
sw x1, 0x0(x2) ; set LED

; test mulh
:fail_test2
ori x3, x0, 0xf85 ; -123
lui x4, 0xd0f1e ;
addi x4, x4, 0xb05 ; -789,456,123
mulh x3, x3, x4
ori x4, x0, 0x16 ; 97,103,103,129 's upper
bne x4, x3, fail_test2
; next value
addi x1, x0, 5 ; LED value
sw x1, 0x0(x2) ; set LED

; test mulhsu
:fail_test3
ori x3, x0, 0xf85 ; -123
lui x4, 0xd0f1e ;
addi x4, x4, 0xb05 ; 3,505,511,173
mulhsu x3, x3, x4
ori x4, x0, 0xf9B; -431,177,874,279 's upper
bne x4, x3, fail_test3
; next value
addi x1, x0, 4 ; LED value
sw x1, 0x0(x2) ; set LED

; test mulhu
:fail_test4
ori x3, x0, 0xf85 ; 4,294,967,173
lui x4, 0xd0f1e ;
addi x4, x4, 0xb05 ; 3,505,511,173
mulhu x3, x3, x4
lui x4, 0xd0f1e ;
addi x4, x4, 0xaa0 ; 
bne x4, x3, fail_test4
; next value
addi x1, x0, 3 ; LED value
sw x1, 0x0(x2) ; set LED

; test div
:fail_test5
lui x3, 0xd0f1e ; 
addi x3, x3, 0xb05 ;  -789,456,123
ori x4, x0, 0x7b ; 123 
div x3, x3, x4
lui x4, 0xff9e1 ;
addi x4, x4, 0x05a ;  -6,418,342
bne x4, x3, fail_test5
; next value
addi x1, x0, 2 ; LED value
sw x1, 0x0(x2) ; set LED

; test divu
:fail_test6
lui x3, 0xd0f1e ; 
addi x3, x3, 0xb05 ;  3,505,511,173
ori x4, x0, 0x7b ; 123 
divu x3, x3, x4
lui x4, 0x01b2e ;
addi x4, x4, 0x07a ;  28,500,090
bne x4, x3, fail_test6
; next value
addi x1, x0, 1 ; LED value
sw x1, 0x0(x2) ; set LED

; test div
:fail_test7
lui x3, 0xd0f1e ; 
addi x3, x3, 0xb05 ;  -789,456,123
ori x4, x0, 0x7b ; 123 
rem x3, x3, x4
ori x4, x0, 0x42 ;  66
bne x4, x3, fail_test7
; next value
addi x1, x0, 0 ; LED value
sw x1, 0x0(x2) ; set LED

; test div
:fail_test8
lui x3, 0xd0f1e ; 
addi x3, x3, 0xb05 ; 3,505,511,173
ori x4, x0, 0x7b ; 123 
remu x3, x3, x4
ori x4, x0, 0x67 ;  103
bne x4, x3, fail_test8
; next value
addi x1, x0, 0x17 ; LED value
sw x1, 0x0(x2) ; set LED

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
