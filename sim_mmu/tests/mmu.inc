# MMU test helpers (Sv32, M-mode + MPRV)
#
# register usage (do not use in test bodies):
#   s7  : expected page fault count
#   s8  : mepc of the last trap
#   s9  : trap count (incremented by the handler)
#   s10 : mcause of the last trap
#   s11 : mtval of the last trap
#
# memory map (physical)
#   0x0001_0000 : root page table  (satp.PPN = 0x10)
#   0x0001_1000 : L0 table for VA 0x4000_0000 - 0x403F_FFFF
#   0x0001_2000 : L0 table for VA 0x4040_0000 - 0x407F_FFFF
#   0x0002_0000 - : data pages

.equ PTE_V, 0x01
.equ PTE_R, 0x02
.equ PTE_W, 0x04
.equ PTE_X, 0x08
.equ PTE_U, 0x10
.equ PTE_G, 0x20
.equ PTE_A, 0x40
.equ PTE_D, 0x80

.equ MSTATUS_MPRV, 0x00020000
.equ MSTATUS_SUM,  0x00040000
.equ MSTATUS_MXR,  0x00080000
.equ MSTATUS_MPP,  0x00001800
.equ MPP_S,        0x00000800
.equ MPP_U,        0x00000000

.equ SATP_VAL, 0x80000010

# store a word to a physical address (MPRV must be off)
.macro PSTORE addr, val
    li   t0, \addr
    li   t1, \val
    sw   t1, 0(t0)
.endm

# MPRV = 1, MPP = S
.macro MPRV_S
    li   t0, MSTATUS_MPP
    csrc mstatus, t0
    li   t0, MSTATUS_MPRV | MPP_S
    csrs mstatus, t0
.endm

# MPRV = 1, MPP = U
.macro MPRV_U
    li   t0, MSTATUS_MPP
    csrc mstatus, t0
    li   t0, MSTATUS_MPRV | MPP_U
    csrs mstatus, t0
.endm

.macro MPRV_OFF
    li   t0, MSTATUS_MPRV
    csrc mstatus, t0
.endm

# check that exactly one more page fault happened with cause / tval
.macro EXPECT_PF cause, tval, code
    addi s7, s7, 1
    beq  s9, s7, 10f
    FAIL \code
10: li   t4, \cause
    beq  s10, t4, 11f
    FAIL (\code + 1)
11: li   t4, \tval
    beq  s11, t4, 12f
    FAIL (\code + 2)
12:
.endm

# check that no new trap happened
.macro EXPECT_NOPF code
    beq  s9, s7, 13f
    FAIL \code
13:
.endm

# trap handler : record and skip the faulting instruction
.macro TRAP_HANDLER
    .balign 64
trap_handler:
    csrr s10, mcause
    csrr s11, mtval
    csrr s8, mepc
    addi s9, s9, 1
    addi s8, s8, 4
    csrw mepc, s8
    mret
.endm
