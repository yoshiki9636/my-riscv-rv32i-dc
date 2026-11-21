# common macros for lab7_mmu simulation tests
#   TOHOST : 1 = PASS / other = FAIL code
#   PUTC   : console character
.equ TOHOST, 0xC000FFC0
.equ PUTC,   0xC000FFC4

.macro PASS
    li   t6, TOHOST
    li   t5, 1
    sw   t5, 0(t6)
1:  j    1b
.endm

# FAIL with code (code must be != 1)
.macro FAIL code
    li   t6, TOHOST
    li   t5, \code
    sw   t5, 0(t6)
1:  j    1b
.endm

# compare register with immediate, FAIL code on mismatch
.macro CHECK reg, val, code
    li   t4, \val
    beq  \reg, t4, 2f
    FAIL \code
2:
.endm
