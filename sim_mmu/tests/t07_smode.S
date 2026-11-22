# t07_smode : S-mode / U-mode (needs FT_SMODE = 1 : VDEFS="-DTB_SMODE=1")
#   1. misa has S and U
#   2. mret M -> S (MPP=S) clears MPRV, S-mode CSR access / M-mode CSR = illegal
#   3. ecall from S (9) / from U (8), sret / mret privilege checks
#   4. medeleg : exceptions from U / S go to S (stvec, sepc, scause, stval)
#   5. S-mode with Sv32 : U page / SUM, page fault delegated to S
#   6. S-level interrupts : delegated SSIP -> S, not delegated STIP -> M
#      (taken in S-mode even with mstatus.MIE = 0)
#
# instruction fetch is not translated yet (ITLB : next step), so the code is
# identity mapped (VA = PA megapage) when paging is on.
#
# register usage
#   M handler : s9 count, s10 mcause, s11 mtval, s8 mepc
#   S handler : s4 count, s5 scause, s6 stval
#   a7 = 1 / a0 = target : "switch to M-mode at a0" request (ecall)
#include "common.inc"
#include "mmu.inc"

.equ MSTATUS_MIE,  0x8
.equ MSTATUS_SIE,  0x2
.equ MSTATUS_SPP,  0x100
.equ MIP_SSIP,     0x2
.equ MIP_STIP,     0x20

# go to M-mode at label (from S or U : ecall with a7 = 1)
.macro TO_M label
    la   a0, \label
    li   a7, 1
    ecall
.endm

# mret to label in mode mpp (MPP_S / MPP_U)
.macro MRET_TO label, mpp
    li   t0, MSTATUS_MPP
    csrc mstatus, t0
    li   t0, \mpp
    csrs mstatus, t0
    la   t0, \label
    csrw mepc, t0
    mret
.endm

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

    # ---------------- 1. misa ----------------
    csrr t0, misa
    li   t1, (1 << 18) | (1 << 20)      # S, U
    and  t0, t0, t1
    CHECK t0, (1 << 18) | (1 << 20), 0x10

    # ---------------- 2. M -> S, MPRV cleared ----------------
    li   t0, MSTATUS_MPRV
    csrs mstatus, t0
    MRET_TO s_code1, MPP_S
s_code1:
    csrr t1, sstatus                    # OK in S
    csrr t1, mstatus                    # illegal -> M (cause 2)
    CHECK s9, 1, 0x20
    CHECK s10, 2, 0x21
    li   t0, 0x30002373                 # mtval = the instruction (csrr t1, mstatus)
    bne  s11, t0, 1f
    j    2f
1:  TO_M fail_22
2:  mret                                # illegal in S (cause 2)
    CHECK s9, 2, 0x23
    ecall                               # ecall from S : cause 9
    CHECK s9, 3, 0x24
    CHECK s10, 9, 0x25
    TO_M m_code2
fail_22:
    FAIL 0x22
m_code2:
    csrr t0, mstatus
    li   t1, MSTATUS_MPRV
    and  t0, t0, t1
    CHECK t0, 0, 0x26                   # mret to S cleared MPRV

    # ---------------- 3. M -> U, ecall from U (not delegated) ----------------
    MRET_TO u_code1, MPP_U
u_code1:
    ecall                               # cause 8 -> M
    CHECK s10, 8, 0x30
    sret                                # illegal in U
    CHECK s10, 2, 0x31
    csrr t1, sstatus                    # illegal in U
    CHECK s10, 2, 0x32
    sfence.vma                          # illegal in U
    CHECK s10, 2, 0x33
    CHECK s9, 7, 0x34
    TO_M m_code3

m_code3:
    # ---------------- 4. delegation to S ----------------
    li   t0, (1 << 2) | (1 << 8) | (1 << 12) | (1 << 13) | (1 << 15)
    csrw medeleg, t0
    csrr t1, medeleg
    CHECK t1, (1 << 2) | (1 << 8) | (1 << 12) | (1 << 13) | (1 << 15), 0x40
    MRET_TO u_code2, MPP_U
u_code2:
    ecall                               # cause 8 -> S
    CHECK s4, 1, 0x41
    CHECK s5, 8, 0x42
    csrr t1, sstatus                    # illegal -> S, stval = instruction
    CHECK s4, 2, 0x43
    CHECK s5, 2, 0x44
    li   t0, 0x10002373                 # csrr t1, sstatus
    beq  s6, t0, 3f
    TO_M fail_45
3:  CHECK s9, 7, 0x46                   # no M trap
    TO_M m_code4                        # via S (a7 = 1 : S forwards with ecall from S)
fail_45:
    FAIL 0x45

m_code4:
    # ---------------- 5. S-mode paging : U page / SUM / delegated page fault ----------------
    # root : VA 0x0000_0000 megapage -> PA 0 (RWX, code / data, U=0)
    #        VA 0xC000_0000 megapage -> PA 0xC000_0000 (I/O)
    #        VA 0x4000_0000 -> L0 @0x11000 : 0x4000_0000 -> 0x20000 (U page)
    PSTORE 0x10000, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
    PSTORE 0x10C00, ((0xC0000 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    PSTORE 0x10400, ((0x11 << 10) | PTE_V)
    PSTORE 0x11000, ((0x20 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D | PTE_U)
    PSTORE 0x20000, 0x600D600D
    li   t0, SATP_VAL
    csrw satp, t0
    sfence.vma
    MRET_TO s_code5, MPP_S
s_code5:
    li   a1, 0x40000000
    lw   a2, 0(a1)                      # S -> U page, SUM=0 : load page fault 13 -> S
    CHECK s4, 3, 0x50
    CHECK s5, 13, 0x51
    CHECK s6, 0x40000000, 0x52
    li   t0, MSTATUS_SUM
    csrs sstatus, t0
    lw   a2, 0(a1)                      # SUM=1 : OK
    CHECK a2, 0x600D600D, 0x53
    li   t0, MSTATUS_SUM
    csrc sstatus, t0
    # S -> U with sret (SPP = 0)
    li   t0, MSTATUS_SPP
    csrc sstatus, t0
    la   t0, u_code5
    csrw sepc, t0
    sret
u_code5:
    li   a1, 0x40000000
    lw   a2, 0(a1)                      # U -> U page : OK
    CHECK a2, 0x600D600D, 0x54
    li   a3, 0x00008000
    lw   a2, 0(a3)                      # U -> S page (megapage 0, U=0) : fault 13 -> S
    CHECK s4, 4, 0x55
    CHECK s5, 13, 0x56
    CHECK s6, 0x00008000, 0x57
    CHECK s9, 7, 0x58
    TO_M m_code6

m_code6:
    # ---------------- 6. S-level interrupts ----------------
    li   t0, 0
    csrw satp, t0
    sfence.vma
    # delegated SSIP : taken in S when SIE = 1
    li   t0, MIP_SSIP
    csrw mideleg, t0
    li   t0, MIP_SSIP | MIP_STIP
    csrs mie, t0                        # SSIE, STIE
    li   t0, MIP_SSIP
    csrs mip, t0                        # SSIP pending
    li   s3, 0
    MRET_TO s_code6, MPP_S
s_code6:
    nop
    nop
    CHECK s3, 0, 0x60                   # SIE = 0 : not taken
    li   t0, MSTATUS_SIE
    csrs sstatus, t0                    # -> taken now, the handler clears SSIP
    nop
    nop
    CHECK s3, 0x80000001, 0x61
    li   t0, MSTATUS_SIE
    csrc sstatus, t0
    TO_M m_code7
m_code7:
    # STIP not delegated : taken in S-mode as an M interrupt (MIE = 0)
    li   t0, MSTATUS_MIE
    csrc mstatus, t0
    li   s2, 0
    li   t0, MIP_STIP
    csrs mip, t0
    nop
    nop
    CHECK s2, 0, 0x70                   # in M with MIE = 0 : not taken
    MRET_TO s_code7, MPP_S
s_code7:
    nop
    nop
    CHECK s2, 0x80000005, 0x71          # taken (priv < M), the M handler cleared STIP
    TO_M m_done
m_done:
    PASS

# ------------------------------------------------------------------------
    .balign 64
m_handler:
    csrr t0, mcause
    bltz t0, m_int
    li   t1, 9
    beq  t0, t1, m_ecall
    li   t1, 8
    beq  t0, t1, m_ecall
    j    m_rec
m_ecall:
    li   t1, 1
    bne  a7, t1, m_rec
    # switch to M-mode at a0
    li   a7, 0
    csrw mepc, a0
    li   t0, MSTATUS_MPP
    csrs mstatus, t0                    # MPP = M
    mret
m_rec:
    csrr s10, mcause
    csrr s11, mtval
    csrr s8, mepc
    addi s9, s9, 1
    addi s8, s8, 4
    csrw mepc, s8
    mret
m_int:
    mv   s2, t0
    li   t0, MIP_STIP | MIP_SSIP
    csrc mip, t0
    mret

    .balign 64
s_handler:
    csrr t0, scause
    bltz t0, s_int
    li   t1, 8
    bne  t0, t1, s_rec
    li   t1, 1
    bne  a7, t1, s_rec
    ecall                               # forward the "to M" request (ecall from S)
s_rec:
    csrr s5, scause
    csrr s6, stval
    addi s4, s4, 1
    csrr t0, sepc
    addi t0, t0, 4
    csrw sepc, t0
    sret
s_int:
    mv   s3, t0
    li   t0, MIP_SSIP
    csrc sip, t0
    sret
