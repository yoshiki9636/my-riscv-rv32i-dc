# t03_dcache_4way : 4 way set associative D$ (4KB / way)
#   1. 12 lines in the same set (stride 4KB) : evictions with dirty write back
#   2. byte / half stores, re-read after eviction
#   3. fence.i flush of all ways, then re-read from DRAM
#   4. flush / refill / evict / flush again sequence on one address (X must be B)
#   5. same with MMU (MPRV) : 8 VA pages -> PAs in the same set + PTE lines in the same set
#include "common.inc"
#include "mmu.inc"

.equ NLINE, 12
.equ BASE,  0x00020000       # set 0 of every way : BASE + k*0x1000

    .section .text.init
    .globl _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   s7, 0
    li   s9, 0

    # ---------------- 1. 12 lines in one set ----------------
    li   a1, BASE
    li   a2, 0
    li   t3, 0x1000
1:  slli a0, a2, 8
    addi a0, a0, 0x11
    sw   a0, 0(a1)
    addi a0, a0, 1
    sw   a0, 4(a1)
    addi a0, a0, 1
    sw   a0, 12(a1)
    add  a1, a1, t3
    addi a2, a2, 1
    li   t0, NLINE
    bne  a2, t0, 1b
    # read back (reverse order)
    li   a2, NLINE - 1
2:  li   a1, BASE
    mul  t1, a2, t3
    add  a1, a1, t1
    slli a3, a2, 8
    addi a3, a3, 0x11
    lw   a0, 0(a1)
    beq  a0, a3, 3f
    FAIL 0x10
3:  addi a3, a3, 1
    lw   a0, 4(a1)
    beq  a0, a3, 4f
    FAIL 0x11
4:  addi a3, a3, 1
    lw   a0, 12(a1)
    beq  a0, a3, 5f
    FAIL 0x12
5:  addi a2, a2, -1
    bgez a2, 2b

    # ---------------- 2. byte / half stores ----------------
    li   a1, BASE + 0x3000
    li   a0, 0xA5
    sb   a0, 1(a1)
    li   a0, 0xBEEF
    sh   a0, 6(a1)
    # evict the line : touch 5 other lines of the same set
    li   a4, BASE + 0x8000
    li   t2, 5
6:  lw   t0, 0(a4)
    add  a4, a4, t3
    addi t2, t2, -1
    bnez t2, 6b
    lw   a0, 0(a1)
    CHECK a0, 0x0000A511, 0x20     # 0x311 -> byte1 = 0xA5 : 0x0000A511 (0x311 & ~0xff00 | 0xA500)
    lhu  a0, 6(a1)
    CHECK a0, 0xBEEF, 0x21

    # ---------------- 3. fence.i flush, re-read from DRAM ----------------
    fence.i
    li   a2, 0
7:  li   a1, BASE
    mul  t1, a2, t3
    add  a1, a1, t1
    slli a3, a2, 8
    addi a3, a3, 0x13
    lw   a0, 12(a1)
    beq  a0, a3, 8f
    FAIL 0x30
8:  addi a2, a2, 1
    li   t0, NLINE
    bne  a2, t0, 7b

    # ---------------- 4. stale dirty bit after flush ----------------
    li   a1, BASE + 0x40     # set 4
    li   a0, 0xAAAA
    sw   a0, 0(a1)           # X = A (dirty)
    fence.i                  # write back + invalidate
    li   t0, BASE + 0x1040   # fill the set so that X goes to another way
    lw   t1, 0(t0)
    li   a0, 0xBBBB
    sw   a0, 0(a1)           # X = B (dirty, maybe another way)
    li   a4, BASE + 0x2040   # evict X (4 more lines of set 4)
    li   t2, 5
9:  lw   t0, 0(a4)
    add  a4, a4, t3
    addi t2, t2, -1
    bnez t2, 9b
    fence.i                  # a stale dirty copy of A must not be written back
    lw   a0, 0(a1)
    CHECK a0, 0xBBBB, 0x40

    # ---------------- 5. MMU : PTE lines and data lines in one set ----------------
    # root : VA 0x4000_0000 -> L0 @0x11000 ; L0[i] -> PA 0x30000 + i*0x1000 (i=0..7)
    PSTORE 0x10400, ((0x11 << 10) | PTE_V)
    li   t0, 0x11000
    li   t1, ((0x30 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    li   t2, 8
    li   t4, (1 << 10)
10: sw   t1, 0(t0)
    addi t0, t0, 4
    add  t1, t1, t4
    addi t2, t2, -1
    bnez t2, 10b
    li   t0, SATP_VAL
    csrw satp, t0
    sfence.vma
    MPRV_S
    li   a1, 0x40000000
    li   a2, 0
11: slli a0, a2, 4
    addi a0, a0, 7
    sw   a0, 0(a1)           # PTE line (0x11000) and data lines are all in set 0
    add  a1, a1, t3
    addi a2, a2, 1
    li   t0, 8
    bne  a2, t0, 11b
    li   a1, 0x40000000
    li   a2, 0
12: lw   a0, 0(a1)
    slli a3, a2, 4
    addi a3, a3, 7
    beq  a0, a3, 13f
    FAIL 0x50
13: add  a1, a1, t3
    addi a2, a2, 1
    li   t0, 8
    bne  a2, t0, 12b
    MPRV_OFF
    fence.i
    li   a1, 0x30000 + 7*0x1000
    lw   a0, 0(a1)
    CHECK a0, 0x77, 0x51
    EXPECT_NOPF 0x52

    PASS

    TRAP_HANDLER
