# sbi_payload : S-mode payload for OpenSBI fw_jump (linked at 0x0040_0000)
#   ./run_sbi.sh <fw_jump.elf> tests/sbi_payload.S
#   1. SBI base : spec version, probe TIME / RFENCE / IPI / DBCN
#   2. SBI console (legacy putchar)
#   3. SBI set_timer -> S timer interrupt (scause 0x80000005), set_timer
#      clears STIP; a time in the past fires at once
#   4. time CSR from S (mcounteren.TM set by OpenSBI)
#   5. misaligned load / store : emulated by OpenSBI (not delegated)
#   6. rfence : remote fence.i / sfence.vma on this hart
#   PASS / FAIL through TOHOST (S-mode writes the MMIO directly : no PMP)
#
# register usage : s0 timer interrupt count, s1 other trap count
.equ TOHOST,   0xC000FFC0
.equ EXT_BASE, 0x10
.equ EXT_TIME, 0x54494D45
.equ EXT_RFNC, 0x52464E43
.equ EXT_IPI,  0x00735049
.equ EXT_DBCN, 0x4442434E
.equ SIE_STIE, 0x20
.equ SSTATUS_SIE, 0x2

.macro FAIL code
    li   t6, TOHOST
    li   t5, \code
    sw   t5, 0(t6)
96: j    96b
.endm

.macro CHECK reg, val, code
    li   t4, \val
    beq  \reg, t4, 99f
    FAIL \code
99:
.endm

.macro SBI ext, fid
    li   a7, \ext
    li   a6, \fid
    ecall
.endm

.macro PUTS str
    la   s2, \str
98: lbu  a0, 0(s2)
    beqz a0, 97f
    li   a7, 1                  # legacy console_putchar
    ecall
    addi s2, s2, 1
    j    98b
97:
.endm

    .section .text.init
    .globl _start
_start:
    la   sp, stack_top
    la   t0, s_trap
    csrw stvec, t0
    li   s0, 0
    li   s1, 0
    PUTS msg_hello

    # ---- 1. base ----
    SBI  EXT_BASE, 0            # get_spec_version
    CHECK a0, 0, 0x10
    li   t0, 0x01000000
    bgeu a1, t0, 1f             # >= v1.0
    FAIL 0x11
1:  li   a0, EXT_TIME
    SBI  EXT_BASE, 3            # probe_extension
    CHECK a0, 0, 0x12
    beqz a1, 2f
    li   a0, EXT_RFNC
    SBI  EXT_BASE, 3
    beqz a1, 2f
    li   a0, EXT_IPI
    SBI  EXT_BASE, 3
    beqz a1, 2f
    li   a0, EXT_DBCN
    SBI  EXT_BASE, 3
    bnez a1, 3f
2:  FAIL 0x13
3:
    # ---- 3. timer ----
    li   t0, SIE_STIE
    csrs sie, t0
    li   t0, SSTATUS_SIE
    csrs sstatus, t0
    rdtime a0
    rdtimeh a1
    li   t0, 20000              # 20000 cycles later (the SBI call itself takes a few
    add  a0, a0, t0             #  thousand cycles)
    sltu t0, a0, t0
    add  a1, a1, t0             # carry
    SBI  EXT_TIME, 0            # set_timer
    CHECK s0, 0, 0x30           # not yet
    li   t1, 100000
4:  bnez s0, 5f
    addi t1, t1, -1
    bnez t1, 4b
    FAIL 0x31                   # no timer interrupt
5:  li   t1, 3000
6:  addi t1, t1, -1
    bnez t1, 6b
    CHECK s0, 1, 0x32           # once (the handler set the timer to the max)
    # a time in the past : at once
    li   a0, 0
    li   a1, 0
    SBI  EXT_TIME, 0
    nop
    nop
    nop
    nop
    CHECK s0, 2, 0x33
    li   t0, SSTATUS_SIE
    csrc sstatus, t0
    PUTS msg_timer

    # ---- 4. time CSR ----
    rdtime a2
    bnez a2, 7f
    FAIL 0x40
7:
    # ---- 5. misaligned load / store (emulated by OpenSBI) ----
    la   a3, mis_data
    lw   a4, 1(a3)              # bytes 1..4
    CHECK a4, 0x44332211, 0x50
    lhu  a4, 3(a3)
    CHECK a4, 0x4433, 0x51
    li   a5, 0xA1B2C3D4
    sw   a5, 5(a3)
    lw   a4, 4(a3)
    CHECK a4, 0xB2C3D444, 0x52
    lw   a4, 8(a3)
    CHECK a4, 0xAAAAAAA1, 0x53
    CHECK s1, 0, 0x54           # nothing reached S
    PUTS msg_mis

    # ---- 6. rfence on this hart ----
    li   a0, 1                  # hart_mask
    li   a1, 0                  # hart_mask_base
    SBI  EXT_RFNC, 0            # remote_fence_i
    CHECK a0, 0, 0x60
    li   a0, 1
    li   a1, 0
    li   a2, 0
    li   a3, -1
    SBI  EXT_RFNC, 1            # remote_sfence_vma (all)
    CHECK a0, 0, 0x61
    CHECK s1, 0, 0x62

    PUTS msg_pass
    li   t6, TOHOST
    li   t5, 1
    sw   t5, 0(t6)
8:  j    8b

# ------------------------------------------------------------------------
    .balign 64
s_trap:
    addi sp, sp, -16
    sw   a0, 0(sp)
    sw   a1, 4(sp)
    sw   a6, 8(sp)
    sw   a7, 12(sp)
    csrr a0, scause
    li   a1, 0x80000005
    bne  a0, a1, 1f
    addi s0, s0, 1
    li   a0, -1                 # timer to the max : clears STIP
    li   a1, -1
    li   a7, EXT_TIME
    li   a6, 0
    ecall
    j    2f
1:  addi s1, s1, 1
    csrr a0, sepc
    addi a0, a0, 4
    csrw sepc, a0
2:  lw   a0, 0(sp)
    lw   a1, 4(sp)
    lw   a6, 8(sp)
    lw   a7, 12(sp)
    addi sp, sp, 16
    sret

    .section .data
    .balign 16
mis_data:
    .word 0x33221100, 0x77665544, 0xAAAAAAAA, 0
msg_hello: .asciz "sbi_payload : S-mode\n"
msg_timer: .asciz "timer OK\n"
msg_mis:   .asciz "misaligned OK\n"
msg_pass:  .asciz "sbi_payload PASS\n"

    .section .bss
    .balign 16
    .space 1024
stack_top:
