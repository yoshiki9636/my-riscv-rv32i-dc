# t10_satp_switch : satp write in S-mode with VA != PA (Linux relocate_enable_mmu)
#   (needs FT_SMODE = 1 : VDEFS="-DTB_SMODE=1")
#   S-mode runs from PA with satp = 0 (bare), points stvec at the VA of the
#   instruction after the satp write and writes satp (VA 0xC000_0000 -> PA 0,
#   no identity map).  The fetch right after the write must use the new
#   translation : it traps to stvec (instruction page fault) and continues at
#   the VA.  The code at the VA reads its own PC with auipc (la) : it must be
#   the VA, never the PA (instructions fetched before the satp write must not
#   execute).
#   2. a satp write with an identity map falls through (no trap)
#   3. satp = 0 again from the VA side : the trap goes to a PA stvec
#
# register usage
#   M handler : s9 count
#   S code    : s4 = 1 when the VA code ran
#include "common.inc"
#include "mmu.inc"

.equ KVA, 0xC0000000            # kernel VA of PA 0

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
    li   s4, 0
    li   a7, 0
    li   t0, (1 << 12) | (1 << 13) | (1 << 15)
    csrw medeleg, t0

    # trampoline root @0x10000 : VA 0xC000_0000 megapage -> PA 0 (RWX, S),
    #   VA 0x8000_0000 megapage -> I/O (TOHOST through 0x8000_FFC0)
    PSTORE 0x10C00, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
    PSTORE 0x10800, ((0xC0000 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    # identity root @0x12000 : VA 0 -> PA 0 and VA 0xC000_0000 -> PA 0
    PSTORE 0x12000, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
    PSTORE 0x12C00, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
    PSTORE 0x12800, ((0xC0000 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    sfence.vma

    # to S-mode at s_entry (PA, satp = 0)
    li   t0, MSTATUS_MPP
    csrc mstatus, t0
    li   t0, MPP_S
    csrs mstatus, t0
    la   t0, s_entry
    csrw mepc, t0
    mret

# ------------------------------------------------------------------------
# S-mode, PA
    .balign 64
s_entry:
    # ---- 1. relocate : the same sequence as Linux ----
    la   a2, 1f
    li   a1, KVA
    add  a2, a2, a1
    csrw stvec, a2              # stvec = VA of 1:
    li   a0, (0x80000000 | (0x10000 >> 12))
    sfence.vma
    csrw satp, a0
    .balign 4
1:  la   a0, s_park             # auipc : must be the VA
    csrw stvec, a0
    auipc a3, 0                 # the PC of this instruction
    li   t0, KVA
    bgeu a3, t0, 2f
    # still at the PA : the old fetch ran on
    li   t6, 0x8000FFC0
    li   t5, 0x10
    sw   t5, 0(t6)
3:  j    3b
2:  csrr t1, stvec
    bgeu t1, t0, 4f
    li   t6, 0x8000FFC0
    li   t5, 0x11
    sw   t5, 0(t6)
5:  j    5b
4:  li   s4, 1
    # ---- 2. identity map : falls through (stvec = park would catch a trap) ----
    li   a0, (0x80000000 | (0x12000 >> 12))
    csrw satp, a0
    sfence.vma
    auipc a3, 0
    li   t0, KVA
    bgeu a3, t0, 6f
    li   t6, 0x8000FFC0
    li   t5, 0x20
    sw   t5, 0(t6)
7:  j    7b
6:  TO_M m_done                 # a0 : PA of m_done (M-mode, bare)

    .balign 64
s_park:                         # unexpected trap after the relocation
    li   t6, 0x8000FFC0
    li   t5, 0x30
    sw   t5, 0(t6)
8:  j    8b

m_done:
    CHECK s4, 1, 0x40
    CHECK s9, 0, 0x41           # no unexpected M trap
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
