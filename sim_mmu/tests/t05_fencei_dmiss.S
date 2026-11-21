# t05_fencei_dmiss : fence.i right after a load / store that misses the D$,
# while the I$ is cold after an earlier fence.i
#   Before the fix : the front end hung (IF kept prefetching, ID never
#   advanced) after the retry jump of the 2nd fence.i.
#   NOFS (0..3) : number of nops before the sequence (moves it in the I$ line)
#include "common.inc"
#ifndef NOFS
#define NOFS 0
#endif
    .section .text.init
    .globl _start
_start:
    li   s0, 0
    .rept NOFS
    nop
    .endr
    # 1. load miss right before fence.i
    fence.i
    li   a1, 0x20040
    li   a0, 0xAAAA
    lw   a0, 0(a1)
    fence.i
    addi s0, s0, 1
    # 2. store miss right before fence.i
    fence.i
    li   a1, 0x21080
    li   a0, 0x5555
    sw   a0, 0(a1)
    fence.i
    addi s0, s0, 1
    # 3. the stored data must be visible after the flush
    li   a1, 0x21080
    lw   a2, 0(a1)
    CHECK a2, 0x5555, 2
    # 4. load miss + fence.i in a loop (different alignment every time)
    li   t2, 8
    li   a1, 0x22000
1:  fence.i
    lw   a0, 0(a1)
    fence.i
    addi a1, a1, 0x110
    addi t2, t2, -1
    bnez t2, 1b
    CHECK s0, 2, 3
    PASS
