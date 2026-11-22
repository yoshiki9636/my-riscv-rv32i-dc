# t12_iwalk_dmiss : ITLB walks overlapping D$ misses / loads / stores
#   (needs FT_SMODE = 1 : VDEFS="-DTB_SMODE=1")
#   The last words of a code page : a D$-missing load of a pointer, two hits,
#   and (last word) a load through that pointer (load-use + another D$ miss),
#   like Linux riscv_intc_hwnode; the next code page starts with counters.
#   2. the same with stores in the head (cp2 / cp3) : a store reaches MA while
#      the walk runs and must be written once, to the right line
#   Crossing the page boundary misses the micro-ITLB (and the 16 entry ITLB :
#   40 code VA pages) : the walk for the fetch overlaps the D$ misses of the
#   instructions ahead, and loads / stores reach MA while the walk runs.
#   Every instruction must run exactly once (counters, sp) with the right data.
#   (Linux : "addi sp, 16" ran twice after a D$ miss + ITLB walk)
#
#   code VA 0x4000_0000 + 2i * 4K -> PA cp0 (head at +0xFF0),
#        VA 0x4000_1000 + 2i * 4K -> PA cp1 (tail),   i = 0 .. N-1
#        VA 0x4010_0000 + 2i * 4K -> PA cp2 / cp3 (store variant)
#
# register usage (S-mode loop)
#   s0 round, s1 i, a5 / s5 head / tail counts, s6 sum of the loads through
#   the pointers, s10 a hot data line
#include "common.inc"
#include "mmu.inc"

.equ N,      20
.equ STRIDE, 0x440            # data stride (different D$ sets / lines)

.macro TO_M label
    lui  a0, %hi(\label)
    addi a0, a0, %lo(\label)
    li   a7, 1
    ecall
.endm

.equ RX,  (PTE_V | PTE_R | PTE_X | PTE_A)

    .section .text.init
    .globl _start
_start:
    la   t0, m_handler
    csrw mtvec, t0
    li   s9, 0
    li   a7, 0
    # root @0x10000 : VA 0 megapage -> PA 0 (RWX, S), VA 0xC000_0000 -> I/O,
    #   VA 0x4000_0000 -> L0 @0x11000
    PSTORE 0x10000, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
    PSTORE 0x10C00, ((0xC0000 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    PSTORE 0x10400, ((0x11 << 10) | PTE_V)
    # L0[2i] -> cp0, L0[2i+1] -> cp1
    la   t1, cp0
    srli t1, t1, 12
    slli t1, t1, 10
    ori  t1, t1, RX
    la   t2, cp1
    srli t2, t2, 12
    slli t2, t2, 10
    ori  t2, t2, RX
    li   t3, 0x11000
    li   t4, N
1:  sw   t1, 0(t3)
    sw   t2, 4(t3)
    addi t3, t3, 8
    addi t4, t4, -1
    bnez t4, 1b
    la   t1, cp2
    srli t1, t1, 12
    slli t1, t1, 10
    ori  t1, t1, RX
    la   t2, cp3
    srli t2, t2, 12
    slli t2, t2, 10
    ori  t2, t2, RX
    li   t3, 0x11400            # VA 0x4010_0000
    li   t4, N
1:  sw   t1, 0(t3)
    sw   t2, 4(t3)
    addi t3, t3, 8
    addi t4, t4, -1
    bnez t4, 1b
    li   t0, SATP_VAL
    csrw satp, t0
    sfence.vma
    li   t0, MSTATUS_MPP
    csrc mstatus, t0
    li   t0, MPP_S
    csrs mstatus, t0
    la   t0, s_code
    csrw mepc, t0
    mret

# ------------------------------------------------------------------------
    .balign 64
s_code:
    li   a5, 0
    li   s5, 0
    li   s6, 0
    la   s10, hot
    lw   t0, 0(s10)             # make it hot
    # ---- 1. loads (cp0 / cp1), 2 rounds ----
    li   s0, 0
2:  li   s1, 0
3:  slli t0, s1, 13             # i * 8K
    li   t1, 0x40000FF0
    add  t0, t0, t1
    li   t2, STRIDE
    mul  t3, s1, t2
    la   a1, src
    add  a1, a1, t3
    jalr ra, t0                 # head (end of a code page) -> tail
    addi s1, s1, 1
    li   t0, N
    bne  s1, t0, 3b
    addi s0, s0, 1
    li   t0, 2
    bne  s0, t0, 2b
    # ---- 2. stores (cp2 / cp3), 1 round ----
    li   s1, 0
5:  slli t0, s1, 13
    li   t1, 0x40100FF0
    add  t0, t0, t1
    li   t2, STRIDE
    mul  t3, s1, t2
    la   a1, src
    add  a1, a1, t3
    la   a4, dst
    add  a4, a4, t3
    addi a2, s1, 0x100
    jalr ra, t0
    addi s1, s1, 1
    li   t0, N
    bne  s1, t0, 5b
    TO_M m_check

m_check:
    CHECK a5, 3 * N, 0x10       # tail first instruction ran once per call
    CHECK s5, 3 * N, 0x11       # tail second instruction
    CHECK s6, 3 * N * 0x33, 0x13
    # dst[i * STRIDE] = i + 0x100, dst[i * STRIDE + 4] = i + 0x100
    la   a4, dst
    li   s1, 0
    li   t5, 0
4:  lw   t0, 0(a4)
    add  t5, t5, t0
    addi a4, a4, STRIDE
    addi s1, s1, 1
    li   t0, N
    bne  s1, t0, 4b
    CHECK t5, (N * 0x100 + N * (N - 1) / 2), 0x15
    la   a4, dst + 4
    li   s1, 0
    li   t5, 0
6:  lw   t0, 0(a4)
    add  t5, t5, t0
    addi a4, a4, STRIDE
    addi s1, s1, 1
    li   t0, N
    bne  s1, t0, 6b
    CHECK t5, (N * 0x100 + N * (N - 1) / 2), 0x17
    CHECK s9, 0, 0x16
    li   t0, 0
    csrw satp, t0
    PASS

# ------------------------------------------------------------------------
# code pages : head at the end of cp0, tail at the start of cp1
    .balign 4096
cp0:
    .space 0xFF0
    lw   t4, 0(a1)              # pointer (D$ miss, cold line)
    lw   t5, 0(s10)             # hits
    lw   t6, 4(s10)
    lw   a3, 0(t4)              # last word : load-use + D$ miss (other line)
cp1:
    addi a5, a5, 1              # must run once
    addi s5, s5, 1
    add  s6, s6, a3
    ret
    .balign 4096
cp2:
    .space 0xFF0
    lw   t4, 0(a1)              # pointer (D$ miss)
    sw   a2, 0(a4)              # store (cold line)
    sw   a2, 4(a4)
    lw   a3, 0(t4)              # last word : load-use + D$ miss
cp3:
    addi a5, a5, 1
    addi s5, s5, 1
    add  s6, s6, a3
    ret
    .balign 4096

# ------------------------------------------------------------------------
    .balign 64
m_handler:
    csrr t0, mcause
    li   t1, 9
    bne  t0, t1, m_rec
    li   t1, 1
    bne  a7, t1, m_rec
    li   a7, 0
    csrw mepc, a0
    li   t0, MSTATUS_MPP
    csrs mstatus, t0            # MPP = M
    mret
m_rec:
    addi s9, s9, 1
    FAIL 0x99

# ------------------------------------------------------------------------
    .section .data
    .p2align 17                 # 0x20000 : clear of the page tables (0x10000 - 0x11FFF)
# src[i] : pointer to src2[i] (another line, value 0x33)
src:
    .irp i, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    .word src2 + \i * STRIDE + 0x20
    .space STRIDE - 4
    .endr
src2:
    .rept N
    .space 0x20
    .word 0x33
    .space STRIDE - 0x24
    .endr
dst:
    .space N * STRIDE
hot:
    .word 0, 0
