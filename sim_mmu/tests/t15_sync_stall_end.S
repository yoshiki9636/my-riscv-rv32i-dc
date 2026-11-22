# t15_sync_stall_end : an I stall and a D stall starting and ending together
#   (needs FT_SMODE = 1 : VDEFS="-DTB_SMODE=1")
#   Linux proc_register (preempt_disable) at a code page end :
#       0xFF8 : lw   a5, 4(tp)     page B : micro-DTLB miss, DTLB hit (5 cycles)
#       0xFFC : addi a5, a5, 1     load-use
#       next page : sw a5, 4(tp)   the fetch misses the micro-ITLB, ITLB hit
#   The D stall (lw) and the I stall (fetch of the next page) start in the
#   same cycle and end in the same cycle; the addi was lost (the store wrote
#   the loaded value).  The code runs from N code VA pages (aliases of the
#   same 2 PA pages : the next page is always a micro-ITLB miss), twice.
#
# register usage (S-mode) : s1 page A pointer, tp page B pointer,
#   s2 expected count, s3 page, s4 round
#include "common.inc"
#include "mmu.inc"

.equ N, 4                      # 8 code pages : they stay in the 16 entry ITLB (ITLB hit)

.macro TO_M label
    lui  a0, %hi(\label)
    addi a0, a0, %lo(\label)
    li   a7, 1
    ecall
.endm

.equ RX, (PTE_V | PTE_R | PTE_X | PTE_A)

    .section .text.init
    .globl _start
_start:
    la   t0, m_handler
    csrw mtvec, t0
    li   s9, 0
    li   a7, 0
    # root @0x10000 : VA 0 megapage -> PA 0 (RWX, S), VA 0xC000_0000 -> I/O,
    #   VA 0x0040_0000 megapage -> PA 0 (RW) : data page B,
    #   VA 0x4000_0000 -> L0 @0x11000 : code pages
    PSTORE 0x10000, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
    PSTORE 0x10004, (PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
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
    lw   t0, 0(s1)
    li   s2, 0
    li   s4, 0
2:  li   s3, 0
3:  slli t0, s3, 13             # page pair i : VA 0x4000_0000 + i * 8K
    li   t1, 0x40000FF8
    add  t0, t0, t1
    lbu  a5, 98(s1)             # page A into the micro-DTLB
    jalr ra, t0                 # jump right onto the lw (Linux : a branch target)
    addi s2, s2, 1
    addi s3, s3, 1
    li   t0, N
    bne  s3, t0, 3b
    addi s4, s4, 1
    li   t0, 3                  # round 1 : ITLB walks, rounds 2, 3 : ITLB hits
    bne  s4, t0, 2b
    lw   t1, 4(tp)
    bne  t1, s2, 4f
    TO_M m_done
4:  TO_M m_fail

m_done:
    CHECK s9, 0, 0x11
    li   t0, 0
    csrw satp, t0
    PASS
m_fail:
    FAIL 0x10

# ------------------------------------------------------------------------
    .balign 4096
cp0:
    .space 0xFF8
    lw   a5, 4(tp)              # 0xFF8 : page B -> micro-DTLB miss (jump target)
    addi a5, a5, 1              # 0xFFC : load-use
cp1:
    sw   a5, 4(tp)              # next page : micro-ITLB miss
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
    .p2align 17                 # 0x20000 : clear of the page tables
dat_a:
    .space 128
    .balign 4096
dat_b:
    .space 64
