# t14_dtlb_fwd : load (micro-DTLB miss) -> addi (load-use) -> store forwarding
#   (needs FT_SMODE = 1 : VDEFS="-DTB_SMODE=1")
#   Linux proc_register (preempt_disable) :
#       lbu  a5, 98(s1) ; ori a5, a5, 8 ; sb a5, 98(s1)       (page A)
#       lw   a5, 4(tp)  ; addi a5, a5, 1 ; sw a5, 4(tp)        (page B)
#   the lw misses the 1 entry micro-DTLB (page A -> page B, DTLB hit); the sw
#   stored the loaded value, not the addi result (the count was not raised).
#   Variants : the lw as a branch target (beqz taken) / falling through,
#   with / without the byte store before.
#
# register usage (S-mode) : s1 page A pointer, tp page B pointer,
#   s2 expected count, s3 loop
#include "common.inc"
#include "mmu.inc"

.equ NLOOP, 16

.macro TO_M label
    lui  a0, %hi(\label)
    addi a0, a0, %lo(\label)
    li   a7, 1
    ecall
.endm

    .section .text.init
    .globl _start
_start:
    la   t0, m_handler
    csrw mtvec, t0
    li   s9, 0
    li   a7, 0
    # root @0x10000 : VA 0 megapage -> PA 0 (RWX, S), VA 0xC000_0000 -> I/O,
    #   VA 0x0040_0000 megapage -> PA 0 (RW) : page B through another entry
    PSTORE 0x10000, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
    PSTORE 0x10004, (PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    PSTORE 0x10C00, ((0xC0000 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
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
    la   s1, dat_a
    la   tp, dat_b
    li   t0, 0x00400000
    add  tp, tp, t0             # page B through the second megapage
    sw   zero, 4(tp)
    lw   t0, 0(s1)              # both lines in the D$, both in the DTLB
    li   s2, 0
    # ---- 1. branch taken to the lw (a5 = 0 : beqz taken) ----
    li   s3, NLOOP
1:  li   a5, 0
    beqz a5, 2f
    lbu  a5, 98(s1)
    ori  a5, a5, 8
    sb   a5, 98(s1)
2:  lw   a5, 4(tp)
    addi a5, a5, 1
    sw   a5, 4(tp)
    addi s2, s2, 1
    addi s3, s3, -1
    bnez s3, 1b
    lw   t1, 4(tp)
    bne  t1, s2, fail_10
    # ---- 2. falling through (byte store on page A, then the lw) ----
    li   s3, NLOOP
3:  li   a5, 1
    beqz a5, 4f
    lbu  a5, 98(s1)
    ori  a5, a5, 8
    sb   a5, 98(s1)
4:  lw   a5, 4(tp)
    addi a5, a5, 1
    sw   a5, 4(tp)
    addi s2, s2, 1
    addi s3, s3, -1
    bnez s3, 3b
    lw   t1, 4(tp)
    bne  t1, s2, fail_11
    # ---- 3. the same with an unrolled body (cold I$ lines too) ----
    .rept 8
    lbu  a5, 98(s1)
    ori  a5, a5, 8
    sb   a5, 98(s1)
    lw   a5, 4(tp)
    addi a5, a5, 1
    sw   a5, 4(tp)
    addi s2, s2, 1
    .endr
    lw   t1, 4(tp)
    bne  t1, s2, fail_12
    TO_M m_done
fail_10:
    TO_M m_fail10
fail_11:
    TO_M m_fail11
fail_12:
    TO_M m_fail12

m_done:
    CHECK s9, 0, 0x13
    li   t0, 0
    csrw satp, t0
    PASS
m_fail10:
    FAIL 0x10
m_fail11:
    FAIL 0x11
m_fail12:
    FAIL 0x12

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
    .p2align 17                 # 0x20000 : clear of the page tables
dat_a:
    .space 128
    .balign 4096
dat_b:
    .space 64
