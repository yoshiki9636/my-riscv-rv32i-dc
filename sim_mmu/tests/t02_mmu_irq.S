# t02_mmu_irq : DTLB / PTW stress with timer interrupts and page faults
#   - 32 pages (> 16 TLB entries) -> TLB refill on almost every access
#   - page table lines and data lines conflict in the 4KB D$ (dirty evictions)
#   - timer interrupt every TIMER_INTERVAL cycles during the translated accesses
#   - page faults mixed in (invalid page)
#   The CPU is M-mode only : the handler returns with a "software mret"
#   (MPP=S / MPRV=1 / MIE=1 then jr mepc) while the main code uses MPRV,
#   because mret clears MPRV when MPP != M.
#include "common.inc"
#include "mmu.inc"

.equ CLINT_MTIME,    0xC000F800
.equ CLINT_MTIMECMP, 0xC000F808
.equ CLINT_FRC_CTRL, 0xC000F810
.equ MSTATUS_MIE,    0x8
.equ MIE_MTIE,       0x80
#ifndef TIMER_INTERVAL
#define TIMER_INTERVAL 1001
#endif
.equ NLOOP,          6
.equ NPAGE,          32
.equ STACK_TOP,      0x0000F000

# reserved : s3 s4 (handler), s5 (MPRV active flag), s6 (irq count), s7-s11 (mmu.inc)

    .section .text.init
    .globl _start
_start:
    li   sp, STACK_TOP
    la   t0, trap_handler
    csrw mtvec, t0
    li   s5, 0
    li   s6, 0
    li   s7, 0
    li   s9, 0

    # root : VA 0x4040_0000 -> L0 @0x12000
    PSTORE 0x10404, ((0x12 << 10) | PTE_V)
    # L0 : 0x4040_0000 + i*4K -> 0x30000 + i*4K (i = 0..31), entry 32 invalid
    li   t0, 0x12000
    li   t1, ((0x30 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    li   t2, NPAGE
    li   t3, (1 << 10)
1:  sw   t1, 0(t0)
    addi t0, t0, 4
    add  t1, t1, t3
    addi t2, t2, -1
    bnez t2, 1b
    sw   zero, 0(t0)
    li   t0, SATP_VAL
    csrw satp, t0
    sfence.vma

    # timer
    li   t0, MIE_MTIE
    csrs mie, t0
    li   t0, MSTATUS_MIE
    csrs mstatus, t0
    li   t0, CLINT_MTIMECMP
    li   t1, TIMER_INTERVAL
    sw   t1, 0(t0)
    li   t0, CLINT_FRC_CTRL
    li   t1, 3
    sw   t1, 0(t0)

    li   s5, 1
    MPRV_S

    li   s0, 0                  # k
loop_k:
    # offset in the page = (k * 52) & 0x7f0
    li   t0, 52
    mul  s1, s0, t0
    andi s1, s1, 0x7f0
    # ---- write ----
    li   s2, 0                  # i
    li   a5, 0x40400000
    add  a5, a5, s1
wr_loop:
    slli a0, s2, 16
    or   a0, a0, s0
    sw   a0, 0(a5)
    andi t0, s2, 7
    bnez t0, 2f
    li   a1, 0x40420000         # invalid page : page fault 13
    li   a2, 0x5555
    lw   a2, 0(a1)
    addi s7, s7, 1
    li   t0, 0x5555
    beq  a2, t0, 2f
    FAIL 0x10                   # faulting load wrote rd
2:  li   t0, 0x1000
    add  a5, a5, t0
    addi s2, s2, 1
    li   t0, NPAGE
    bne  s2, t0, wr_loop
    # ---- read / check ----
    li   s2, 0
    li   a5, 0x40400000
    add  a5, a5, s1
rd_loop:
    lw   a0, 0(a5)
    slli a1, s2, 16
    or   a1, a1, s0
    beq  a0, a1, 3f
    FAIL 0x20
3:  li   t0, 0x1000
    add  a5, a5, t0
    addi s2, s2, 1
    li   t0, NPAGE
    bne  s2, t0, rd_loop
    addi s0, s0, 1
    li   t0, NLOOP
    bne  s0, t0, loop_k

    # ---- physical check of the last loop ----
    li   s5, 0
    MPRV_OFF
    li   t0, MSTATUS_MIE
    csrc mstatus, t0
    li   s0, (NLOOP - 1)
    li   t0, 52
    mul  s1, s0, t0
    andi s1, s1, 0x7f0
    li   s2, 0
    li   a5, 0x30000
    add  a5, a5, s1
4:  lw   a0, 0(a5)
    slli a1, s2, 16
    or   a1, a1, s0
    beq  a0, a1, 5f
    FAIL 0x30
5:  li   t0, 0x1000
    add  a5, a5, t0
    addi s2, s2, 1
    li   t0, NPAGE
    bne  s2, t0, 4b

    bne  s9, s7, 6f             # page fault count
    beqz s6, 7f                 # timer interrupts must have happened
    li   t0, PUTC
    li   t1, 'I'
    sw   t1, 0(t0)
    li   t1, 'R'
    sw   t1, 0(t0)
    li   t1, 'Q'
    sw   t1, 0(t0)
    li   t1, '\n'
    sw   t1, 0(t0)
    PASS
6:  FAIL 0x40
7:  FAIL 0x41

# ------------------------------------------------------------------------
    .balign 64
trap_handler:
    addi sp, sp, -16
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    sw   t2, 8(sp)
    csrr t0, mcause
    bltz t0, irq
    # page fault : record and skip
    csrr s10, mcause
    csrr s11, mtval
    li   t1, 13
    beq  s10, t1, 8f
    FAIL 0x50                   # unexpected exception
8:  csrr s8, mepc
    addi s9, s9, 1
    addi s8, s8, 4
    csrw mepc, s8
    j    trap_ret
irq:
    li   t1, 0x80000007
    beq  t0, t1, 9f
    FAIL 0x51
9:  li   t0, CLINT_MTIME
    lw   t1, 0(t0)
    li   t2, TIMER_INTERVAL
    add  t1, t1, t2
    li   t0, CLINT_MTIMECMP
    sw   t1, 0(t0)
    li   t0, CLINT_FRC_CTRL
    li   t1, 1
    sw   t1, 0(t0)
    addi s6, s6, 1
trap_ret:
    beqz s5, use_mret
    # software mret keeping MPRV : MPP = S, MPRV = 1, MIE = 1, jump to mepc
    # (restore the stack BEFORE MPRV is set : MPRV applies to the handler's
    #  own loads too)
    # An interrupt taken on sw_ret_jr (just after MIE = 1) has mepc =
    # sw_ret_jr : keep s4 (the target of the interrupted return).
    csrr t0, mepc
    la   t1, sw_ret_jr
    beq  t0, t1, 14f
    mv   s4, t0
14:
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    lw   t2, 8(sp)
    addi sp, sp, 16
    li   s3, MSTATUS_MPP
    csrc mstatus, s3
    li   s3, MSTATUS_MPRV | MPP_S
    csrs mstatus, s3
    li   s3, MSTATUS_MIE
    csrs mstatus, s3
sw_ret_jr:
    jr   s4
use_mret:
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    lw   t2, 8(sp)
    addi sp, sp, 16
    mret
