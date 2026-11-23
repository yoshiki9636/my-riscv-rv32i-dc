# hw_rnd_runner.S : FPGA version of the random MMU check (hw_rnd.sh)
#   M-mode runner at 0x0030_0000.  Seed slot i (image of 0x38000 - 0x7FFFF of
#   "rnd_mmu.py <seed> --hw") is at SLOT_BASE + i * SLOT_SIZE.  For each slot :
#     1. copy it to 0x38000, run it in M-mode without translation -> checksum A
#     2. copy it again, build the identity page tables (4KB pages, VA 0 - 4MB),
#        run it in S-mode with Sv32 -> checksum B
#     3. print "seed <n> : <A> <B> OK / NG" on the UART
#   The program stores its checksum at CSUM_ADR and returns with ecall.
#   Any other trap : printed (cause / epc / tval), counted as NG.
#   At the end : "done : ok <n> ng <m>"; TOHOST (simulation) = 1 / 0x10.
#   NSEED, SEED0 (the first seed number, printed) : --defsym

.equ RUNNER,    0x00300000
.equ VARS,      0x002FF000      # +0 slot, +4 A, +8 phase, +12 ok, +16 ng
.equ SLOT_BASE, 0x00400000
.equ SLOT_SIZE, 0x00048000
.equ EXEC_BASE, 0x00038000
.equ CSUM_ADR,  0x00037FF0
.equ UART,      0xC000FC00
.equ TOHOST,    0xC000FFC0

# putc of the byte in a0 (t5, t6 used)
.macro PUTC
    li   t6, UART
91: lw   t5, 4(t6)
    andi t5, t5, 1
    bnez t5, 91b
    sw   a0, 0(t6)
.endm

.macro PUTCH ch
    li   a0, \ch
    PUTC
.endm

# print the string at label (a1, a0, t5, t6 used)
.macro PUTS label
    la   a1, \label
92: lbu  a0, 0(a1)
    beqz a0, 93f
    PUTC
    addi a1, a1, 1
    j    92b
93:
.endm

# print reg as 8 hex digits (a1, a2, a0, t5, t6 used; reg must not be one of them)
.macro PUTHEX reg
    mv   a1, \reg
    li   a2, 8
94: srli a0, a1, 28
    slli a1, a1, 4
    addi a0, a0, '0'
    li   t5, '9' + 1
    blt  a0, t5, 95f
    addi a0, a0, 'A' - '9' - 1
95: PUTC
    addi a2, a2, -1
    bnez a2, 94b
.endm

    .section .text
    .globl _start
_start:
    li   t0, RUNNER
    jr   t0

    .org RUNNER
runner:
    la   t0, handler
    csrw mtvec, t0
    csrw medeleg, zero
    csrw mideleg, zero
    csrw mie, zero
    csrw satp, zero
    li   t0, VARS
    sw   zero, 0(t0)
    sw   zero, 12(t0)
    sw   zero, 16(t0)
    PUTS msg_title

next_seed:
    li   t0, VARS
    lw   s0, 0(t0)
    li   t1, NSEED
    bge  s0, t1, all_done
    # ---- run 1 : M-mode, no translation ----
    jal  s1, copy_slot
    li   t0, VARS
    sw   zero, 8(t0)
    csrw satp, zero
    sfence.vma
    li   t0, 0x1800
    csrs mstatus, t0            # MPP = M
    li   t0, EXEC_BASE
    csrw mepc, t0
    mret

# ------------------------------------------------------------------------
handler:
    csrr s2, mcause
    li   t1, 11                 # ecall from M
    beq  s2, t1, prog_end
    li   t1, 9                  # ecall from S
    beq  s2, t1, prog_end
    # unexpected trap
    csrw satp, zero
    sfence.vma
    PUTS msg_trap
    PUTHEX s2
    PUTCH ' '
    csrr s3, mepc
    PUTHEX s3
    PUTCH ' '
    csrr s3, mtval
    PUTHEX s3
    PUTCH ' '
    li   t0, VARS
    lw   s3, 8(t0)
    PUTHEX s3                   # phase (0 : M-mode run, 1 : S-mode run)
    PUTCH '\n'
    li   t0, VARS
    lw   t1, 16(t0)
    addi t1, t1, 1
    sw   t1, 16(t0)
    j    seed_done

prog_end:
    csrw satp, zero
    sfence.vma
    li   t0, VARS
    lw   t1, 8(t0)
    bnez t1, phase1
    # ---- end of run 1 : keep A, run 2 : S-mode, Sv32 ----
    li   t2, CSUM_ADR
    lw   t3, 0(t2)
    sw   t3, 4(t0)
    li   t1, 1
    sw   t1, 8(t0)
    lw   s0, 0(t0)
    jal  s1, copy_slot
    jal  s1, build_pt
    li   t0, 0x80000010         # satp : Sv32, root at 0x10000
    csrw satp, t0
    sfence.vma
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0            # MPP = S
    li   t0, EXEC_BASE
    csrw mepc, t0
    mret

phase1:
    li   t2, CSUM_ADR
    lw   s3, 0(t2)              # B
    lw   s4, 4(t0)              # A
    PUTS msg_seed
    li   t0, VARS
    lw   s5, 0(t0)
    li   t1, SEED0
    add  s5, s5, t1
    PUTHEX s5
    PUTS msg_colon
    PUTHEX s4
    PUTCH ' '
    PUTHEX s3
    li   t0, VARS
    bne  s3, s4, 1f
    lw   t1, 12(t0)
    addi t1, t1, 1
    sw   t1, 12(t0)
    PUTS msg_ok
    j    seed_done
1:  lw   t1, 16(t0)
    addi t1, t1, 1
    sw   t1, 16(t0)
    PUTS msg_ng

seed_done:
    li   t0, VARS
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)
    j    next_seed

all_done:
    PUTS msg_done
    li   t0, VARS
    lw   s3, 12(t0)
    PUTHEX s3
    PUTS msg_ng2
    li   t0, VARS
    lw   s3, 16(t0)
    PUTHEX s3
    PUTCH '\n'
    li   t6, TOHOST
    li   t5, 1
    beqz s3, 2f
    li   t5, 0x10
2:  sw   t5, 0(t6)
3:  j    3b

# ------------------------------------------------------------------------
# copy slot s0 to EXEC_BASE, then fence.i (return : jr s1)
copy_slot:
    li   t0, SLOT_SIZE
    mul  t1, s0, t0
    li   t2, SLOT_BASE
    add  t1, t1, t2             # source
    li   t2, EXEC_BASE          # destination
    srli t3, t0, 2              # words
4:  lw   t4, 0(t1)
    sw   t4, 0(t2)
    addi t1, t1, 4
    addi t2, t2, 4
    addi t3, t3, -1
    bnez t3, 4b
    fence.i
    jr   s1

# identity page tables : root 0x10000 ([0] -> L0 0x11000, [0x300] -> I/O
# megapage), L0 : 1024 4KB pages (V R W X A D)  (return : jr s1)
build_pt:
    li   t0, 0x10000
    li   t1, (0x11 << 10) | 1
    sw   t1, 0(t0)
    li   t1, (0xC0000 << 10) | 0xC7
    li   t2, 0xC00
    add  t2, t2, t0
    sw   t1, 0(t2)
    li   t0, 0x11000
    li   t1, 0xCF
    li   t2, 1024
    li   t3, 0x400
5:  sw   t1, 0(t0)
    addi t0, t0, 4
    add  t1, t1, t3
    addi t2, t2, -1
    bnez t2, 5b
    jr   s1

    .section .rodata
msg_title: .asciz "\nrnd mmu test (M-mode / S-mode Sv32 checksums)\n"
msg_seed:  .asciz "seed "
msg_colon: .asciz " : "
msg_ok:    .asciz " OK\n"
msg_ng:    .asciz " NG\n"
msg_trap:  .asciz "TRAP cause / epc / tval / phase : "
msg_done:  .asciz "done : ok "
msg_ng2:   .asciz " ng "
