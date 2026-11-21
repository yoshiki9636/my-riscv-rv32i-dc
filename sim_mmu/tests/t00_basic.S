# t00_basic : sanity test without MMU (load / store / loop)
#include "common.inc"
    .section .text.init
    .globl _start
_start:
    li   a0, 0x8000
    li   a1, 0x12345678
    sw   a1, 0(a0)
    lw   a2, 0(a0)
    CHECK a2, 0x12345678, 2
    li   a3, 0
    li   a4, 10
1:  addi a3, a3, 1
    bne  a3, a4, 1b
    CHECK a3, 10, 3
    PASS
