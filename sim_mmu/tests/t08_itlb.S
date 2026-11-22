# t08_itlb : instruction fetch translation (ITLB) in S-mode
#   (needs FT_SMODE = 1 : VDEFS="-DTB_SMODE=1")
#   1. S-mode code runs at VA 0x4000_0000 (PA = s_page0), calls into the next
#      page (VA 0x4000_1000)
#   2. instruction page faults (12) delegated to S : no X, invalid, U page
#   3. 20 code pages (all aliases of ret_page) called twice : ITLB refills,
#      interleaved with data page accesses (D side walks)
#   4. remap a code page (sfence.vma + fence.i) : the new code runs
#
# register usage
#   M handler : s9 count, s10 mcause, s11 mtval
#   S handler : s4 count, s5 scause, s6 stval, s7 sepc
#   an instruction page fault returns to ra (the caller)
#include "common.inc"
#include "mmu.inc"

.equ NCODE, 20

# PTE of a 4KB page : PA of label, flags
.macro MAPPAGE pte_addr, label, flags
    la   t1, \label
    srli t1, t1, 12
    slli t1, t1, 10
    ori  t1, t1, \flags
    li   t0, \pte_addr
    sw   t1, 0(t0)
.endm

.macro TO_M label
    lui  a0, %hi(\label)
    addi a0, a0, %lo(\label)
    li   a7, 1
    ecall
.endm

.equ RX,  (PTE_V | PTE_R | PTE_X | PTE_A)
.equ RW,  (PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
.equ RWX, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)

    .section .text.init
    .globl _start
_start:
    la   t0, m_handler
    csrw mtvec, t0
    la   t0, s_handler
    csrw stvec, t0
    li   s9, 0
    li   s4, 0
    li   a7, 0

    # root @0x10000
    #   VA 0x0000_0000 megapage -> PA 0 (identity, RWX, S) : handlers / data
    #   VA 0xC000_0000 megapage -> I/O
    #   VA 0x4000_0000 -> L0 @0x11000
    PSTORE 0x10000, RWX
    PSTORE 0x10C00, ((0xC0000 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    PSTORE 0x10400, ((0x11 << 10) | PTE_V)
    # L0 @0x11000
    MAPPAGE 0x11000, s_page0, RX                # 0x4000_0000 code
    MAPPAGE 0x11004, s_page1, RX                # 0x4000_1000 code
    MAPPAGE 0x11008, data_page, RW              # 0x4000_2000 no X
    PSTORE  0x1100C, 0                          # 0x4000_3000 invalid
    MAPPAGE 0x11010, ret_page, (RX | PTE_U)     # 0x4000_4000 U page
    MAPPAGE 0x11014, data_page, RW              # 0x4000_5000 data (D side)
    MAPPAGE 0x11018, ver_a, RX                  # 0x4000_6000 remapped in 4.
    # 0x4001_0000 + i*4K (i = 0..19) -> ret_page
    la   t1, ret_page
    srli t1, t1, 12
    slli t1, t1, 10
    ori  t1, t1, RX
    li   t2, 0
    li   t3, 0x11040
1:  sw   t1, 0(t3)
    addi t3, t3, 4
    addi t2, t2, 1
    li   t0, NCODE
    bne  t2, t0, 1b

    li   t0, SATP_VAL
    csrw satp, t0
    sfence.vma
    li   t0, (1 << 12) | (1 << 13) | (1 << 15)
    csrw medeleg, t0

    # enter S-mode at VA 0x4000_0000
    li   t0, MSTATUS_MPP
    csrc mstatus, t0
    li   t0, MPP_S
    csrs mstatus, t0
    li   t0, 0x40000000
    csrw mepc, t0
    mret

m_done:
    CHECK s9, 0, 0x90                 # no M-mode exception
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
    csrs mstatus, t0                  # MPP = M
    mret
m_rec:
    csrr s10, mcause
    csrr s11, mtval
    addi s9, s9, 1
    FAIL 0x99                         # unexpected M-mode trap

    .balign 64
s_handler:
    csrr s5, scause
    csrr s6, stval
    csrr s7, sepc
    addi s4, s4, 1
    li   t0, 12
    bne  s5, t0, 2f
    csrw sepc, ra                     # instruction page fault : back to the caller
    sret
2:  addi s7, s7, 4
    csrw sepc, s7
    sret

# ------------------------------------------------------------------------
# S-mode code : runs at VA 0x4000_0000 / 0x4000_1000
    .balign 4096
s_page0:
    # ---- 1. call into the next page ----
    li   a0, 5
    call s_func1                      # VA 0x4000_1000 + ofs
    CHECK a0, 6, 0x10
    CHECK s4, 0, 0x11

    # ---- 2. instruction page faults ----
    li   t0, 0x40002000               # no X
    jalr ra, t0
    CHECK s4, 1, 0x20
    CHECK s5, 12, 0x21
    CHECK s6, 0x40002000, 0x22
    CHECK s7, 0x40002000, 0x23
    li   t0, 0x40003004               # invalid
    jalr ra, t0
    CHECK s4, 2, 0x24
    CHECK s6, 0x40003004, 0x25
    li   t0, 0x40004000               # U page from S
    jalr ra, t0
    CHECK s4, 3, 0x26
    CHECK s6, 0x40004000, 0x27

    # ---- 3. 20 code pages twice, with data accesses ----
    li   a1, 0
    li   s0, 0                        # round
3:  li   s1, 0                        # page
4:  slli t0, s1, 12
    li   t1, 0x40010000
    add  t0, t0, t1
    jalr ra, t0                       # ret_page : addi a1, a1, 1 ; ret
    li   t2, 0x40005000
    slli t3, s1, 2
    add  t2, t2, t3
    sw   s1, 0(t2)                    # data page (D side)
    addi s1, s1, 1
    li   t0, NCODE
    bne  s1, t0, 4b
    addi s0, s0, 1
    li   t0, 2
    bne  s0, t0, 3b
    CHECK a1, 2 * NCODE, 0x30
    li   t2, 0x40005000 + 4 * (NCODE - 1)
    lw   t3, 0(t2)
    CHECK t3, NCODE - 1, 0x31
    CHECK s4, 3, 0x32

    # ---- 4. remap 0x4000_6000 : ver_a -> ver_b ----
    li   t0, 0x40006000
    jalr ra, t0
    CHECK a2, 0xA, 0x40
    TO_M m_remap
s_after_remap:
    li   t0, 0x40006000
    jalr ra, t0
    CHECK a2, 0xB, 0x41
    CHECK s4, 3, 0x42
    TO_M m_done

s_func0_end:
    .balign 4096
s_page1:
    nop
    nop
s_func1:
    addi a0, a0, 1
    ret

# M-mode : remap the page and go back to S-mode
m_remap:
    MAPPAGE 0x11018, ver_b, RX
    sfence.vma
    fence.i
    li   t0, MSTATUS_MPP
    csrc mstatus, t0
    li   t0, MPP_S
    csrs mstatus, t0
    # s_after_remap at its VA : 0x4000_0000 + (s_after_remap - s_page0)
    la   t0, s_after_remap
    la   t1, s_page0
    sub  t0, t0, t1
    li   t1, 0x40000000
    add  t0, t0, t1
    csrw mepc, t0
    mret

    .balign 4096
ret_page:
    addi a1, a1, 1
    ret

    .balign 4096
ver_a:
    li   a2, 0xA
    ret

    .balign 4096
ver_b:
    li   a2, 0xB
    ret

    .balign 4096
data_page:
    .word 0
    .balign 4096
