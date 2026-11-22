# t13_dtlb_icmiss : a short D stall (micro-DTLB miss) inside an I$ miss
#   (needs FT_SMODE = 1 : VDEFS="-DTB_SMODE=1")
#   lw a4 (D$ miss, page A) ; lw a5 (page B : micro-DTLB miss, DTLB hit -> a
#   4 cycle stall) ; add s2, s2, a5 (load-use) ; the next fetch misses the I$.
#   The D stall of the 2nd load starts and ends inside the I$ miss; the add
#   must run once (if_stage delivered it with the load/store replay and again
#   at the end of the I$ miss : Linux vprintk_store, "xor" of the stack canary
#   check ran twice).
#   The pattern is repeated (straight-line code, cold I$ lines) with 0 .. 3
#   nops before it, so the add sits at every position of an I$ line.
#
# register usage (S-mode) : s2 sum (a5 = 1 each), s3 copies, a1 page A
#   pointer (moves to a cold line each copy), a2 page B
#include "common.inc"
#include "mmu.inc"

.equ NCOPY, 32

.macro TO_M label
    lui  a0, %hi(\label)
    addi a0, a0, %lo(\label)
    li   a7, 1
    ecall
.endm

# one copy : nn nops, the pattern, then a jump over a cold gap (the next fetch
# misses the I$)
.macro PAT nn
    .rept \nn
    nop
    .endr
    lw   a4, 0(a1)              # page A : D$ miss (cold line)
    lw   a5, 0(a2)              # page B : micro-DTLB miss -> DTLB hit
    add  s2, s2, a5             # load-use
    addi s3, s3, 1
    addi a1, a1, 0x40           # next cold line
    j    1f
    .balign 64
    .space 64                   # never fetched
1:
.endm

    .section .text.init
    .globl _start
_start:
    la   t0, m_handler
    csrw mtvec, t0
    li   s9, 0
    li   a7, 0
    # root @0x10000 : VA 0 megapage -> PA 0 (RWX, S), VA 0xC000_0000 -> I/O,
    #   VA 0x0040_0000 megapage -> PA 0 (RW) : page B (another TLB entry)
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
    li   s2, 0
    li   s3, 0
    la   a1, dat_a
    la   a2, dat_b
    li   t0, 0x00400000         # page B through the second megapage
    add  a2, a2, t0
    lw   t0, 0(a2)              # warm the D$ line / DTLB entry of page B
    .rept NCOPY / 4
    PAT 0
    PAT 1
    PAT 2
    PAT 3
    .endr
    TO_M m_check

m_check:
    CHECK s3, NCOPY, 0x10
    CHECK s2, NCOPY, 0x11       # add ran once per copy
    CHECK s9, 0, 0x12
    li   t0, 0
    csrw satp, t0
    PASS

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
dat_b:
    .word 1
    .balign 4096
dat_a:
    .space NCOPY * 0x40
