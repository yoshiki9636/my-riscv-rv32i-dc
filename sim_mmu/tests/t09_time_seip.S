# t09_time_seip : time CSR and the external interrupt to S-mode (SEIP)
#   (needs FT_SMODE = 1 : VDEFS="-DTB_SMODE=1")
#   1. time / timeh = io_frc counter (MTIME MMIO), counting
#   2. time access : S needs mcounteren.TM, U needs mcounteren.TM & scounteren.TM,
#      write = illegal
#   3. SEIP : external interrupt (tb EXTINT) with MEIE = 0, SEIE = 1,
#      mideleg.SEI = 1 -> S-mode interrupt 0x80000009, sip.SEIP
#   4. csrrc / csrrs on mip do not latch the external SEIP into the software bit
#   5. unimplemented CSRs are illegal (stimecmp, cycle, pmpaddr0, menvcfg),
#      mhartid / mvendorid / marchid / mimpid read 0
#
# register usage
#   M handler : s9 count, s10 mcause
#   S handler : s4 count, s5 scause, s3 interrupt cause
#include "common.inc"
#include "mmu.inc"

.equ CLINT_MTIME,    0xC000F800
.equ CLINT_FRC_CTRL, 0xC000F810
.equ EXTINT,         0xC000FFC8
.equ MSTATUS_SIE,    0x2
.equ MIP_SEIP,       0x200

.macro TO_M label
    lui  a0, %hi(\label)
    addi a0, a0, %lo(\label)
    li   a7, 1
    ecall
.endm

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

    # ---------------- 1. time = MTIME, counting ----------------
    li   t0, CLINT_FRC_CTRL
    li   t1, 3                         # run, reset
    sw   t1, 0(t0)
    li   t1, 1                         # run
    sw   t1, 0(t0)
    rdtime a1
    nop
    nop
    nop
    rdtime a2
    bltu a1, a2, 81f
    FAIL 0x10                          # not counting
81: rdtimeh a3
    CHECK a3, 0, 0x11
    li   t0, CLINT_MTIME
    lw   a4, 0(t0)                     # MMIO view of the same counter
    nop                                # (the MMIO value is taken in WB, rdtime in EX)
    nop
    rdtime a5
    bgeu a4, a2, 82f
    FAIL 0x12
82: bgeu a5, a4, 83f
    FAIL 0x13
83: csrw time, zero                    # read only : illegal (2)
    CHECK s9, 1, 0x14
    CHECK s10, 2, 0x15

    # ---------------- 2. time access from S / U ----------------
    MRET_TO s_code2, MPP_S
s_code2:
    rdtime a1                          # mcounteren.TM = 0 : illegal
    CHECK s9, 2, 0x20
    TO_M m_code2
m_code2:
    li   t0, 2
    csrw mcounteren, t0                # TM
    MRET_TO s_code2b, MPP_S
s_code2b:
    rdtime a1                          # OK
    CHECK s9, 2, 0x21
    li   t0, 0x8000                    # SPP = U : sret to U
    li   t0, 0x100
    csrc sstatus, t0
    la   t0, u_code2
    csrw sepc, t0
    sret
u_code2:
    rdtime a1                          # scounteren.TM = 0 : illegal
    CHECK s9, 3, 0x22
    TO_M m_code2c
m_code2c:
    li   t0, 2
    csrw scounteren, t0
    MRET_TO u_code2d, MPP_U
u_code2d:
    rdtime a1                          # OK
    CHECK s9, 3, 0x23
    TO_M m_code3

m_code3:
    # ---------------- 3. SEIP to S ----------------
    li   t0, MIP_SEIP
    csrw mideleg, t0
    csrs mie, t0                       # SEIE (MEIE = 0)
    li   s3, 0
    li   t0, EXTINT
    li   t1, 1
    sw   t1, 0(t0)                     # assert the external interrupt
    nop
    nop
    csrr t1, mip
    li   t2, MIP_SEIP
    and  t1, t1, t2
    CHECK t1, MIP_SEIP, 0x30           # mip.SEIP (external)
    CHECK s3, 0, 0x31                  # in M : not taken (delegated to S)
    MRET_TO s_code3, MPP_S
s_code3:
    csrr t1, sip
    li   t2, MIP_SEIP
    and  t1, t1, t2
    CHECK t1, MIP_SEIP, 0x32
    CHECK s3, 0, 0x33                  # SIE = 0
    li   t0, MSTATUS_SIE
    csrs sstatus, t0                   # taken now : the handler clears EXTINT
    nop
    nop
    CHECK s3, 0x80000009, 0x34
    li   t0, MSTATUS_SIE
    csrc sstatus, t0
    TO_M m_code4

m_code4:
    # ---------------- 4. mip RMW does not latch the external SEIP ----------------
    li   t0, EXTINT
    li   t1, 1
    sw   t1, 0(t0)                     # assert
    nop
    nop
    li   t1, 0x2                       # csrrc on SSIP (read-modify-write of mip)
    csrc mip, t1
    li   t1, 0x2
    csrs mip, t1
    csrc mip, t1
    li   t0, EXTINT
    sw   zero, 0(t0)                   # clear
    nop
    nop
    csrr t1, mip
    li   t2, MIP_SEIP
    and  t1, t1, t2
    CHECK t1, 0, 0x40                  # the software SEIP stayed 0
    li   t1, MIP_SEIP
    csrs mip, t1                       # software SEIP
    csrr t2, mip
    and  t2, t2, t1
    CHECK t2, MIP_SEIP, 0x41
    csrc mip, t1
    csrr t2, mip
    and  t2, t2, t1
    CHECK t2, 0, 0x42

    # ---------------- 5. unimplemented CSRs trap, mhartid & co read 0 ----------------
    li   s9, 0
    csrr t1, mhartid
    CHECK t1, 0, 0x60
    csrr t1, mvendorid
    csrr t1, marchid
    csrr t1, mimpid
    CHECK s9, 0, 0x61
    csrr t1, 0x14D                     # stimecmp (Sstc) : illegal
    CHECK s9, 1, 0x62
    CHECK s10, 2, 0x63
    csrr t1, cycle                     # not implemented : illegal
    CHECK s9, 2, 0x64
    csrr t1, pmpaddr0                  # no PMP : illegal
    CHECK s9, 3, 0x65
    csrr t1, menvcfg                   # illegal
    CHECK s9, 4, 0x66

    CHECK s4, 0, 0x50                  # no S exception
    PASS

# ------------------------------------------------------------------------
    .balign 64
m_handler:
    csrr t0, mcause
    li   t1, 9
    beq  t0, t1, m_ecall
    li   t1, 8
    beq  t0, t1, m_ecall
    j    m_rec
m_ecall:
    li   t1, 1
    bne  a7, t1, m_rec
    li   a7, 0
    csrw mepc, a0
    li   t0, MSTATUS_MPP
    csrs mstatus, t0
    mret
m_rec:
    csrr s10, mcause
    addi s9, s9, 1
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

    .balign 64
s_handler:
    csrr t0, scause
    bltz t0, s_int
    csrr s5, scause
    addi s4, s4, 1
    csrr t0, sepc
    addi t0, t0, 4
    csrw sepc, t0
    sret
s_int:
    mv   s3, t0
    li   t0, EXTINT
    sw   zero, 0(t0)                   # clear the external interrupt
    nop
    nop
    sret
