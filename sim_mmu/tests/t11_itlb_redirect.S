# t11_itlb_redirect : redirect while the next fetch misses the micro-ITLB
#   (needs FT_SMODE = 1 : VDEFS="-DTB_SMODE=1")
#   sfence.vma flushes the micro-ITLB; the jump right after it redirects
#   while the slot after the jump (dead) misses the micro-ITLB and starts a
#   translation (walk).  The jump target must run with its own PC : the
#   target is "jal ra, t_func", t_func checks ra = target + 4.
#   (Linux relocate_enable_mmu : sfence.vma ; ret -> "jal" at the return
#    address ran with the PC of the slot after ret)
#   jumps : jalr, jal, taken branch; targets in other pages / I$ indexes;
#   1..4 nops between sfence.vma and the jump
#   (sfence.vma itself refetches pc+4 now, see id_stage cmd_csr_satp_ex)
#   2. a jump in the last word of a page : the slot after it is in the next
#      page (micro-ITLB miss) in the cycle the jump redirects -> no walk for
#      the dead slot (ilu iw_kill)
#
# register usage
#   M handler : s9 count
#   s1 : test count, s2 : t_func calls
#include "common.inc"
#include "mmu.inc"

.macro TO_M label
    lui  a0, %hi(\label)
    addi a0, a0, %lo(\label)
    li   a7, 1
    ecall
.endm

# one case : sfence.vma, n nops, jump (kind) to tgt ; tgt : jal ra, t_func
#   t_func returns to tgt + 4 : "j 1f" back here
.macro CASE_JALR tgt, nn
    la   t3, \tgt
    la   s3, 91f                # where tgt jumps back to
    .rept \nn
    nop
    .endr
    sfence.vma
    jalr x0, t3
    addi s4, s4, 1              # dead slot (must not run)
    addi s4, s4, 1
91: addi s1, s1, 1
.endm

.macro CASE_JAL tgt, nn
    la   s3, 92f
    .rept \nn
    nop
    .endr
    sfence.vma
    jal  x0, \tgt
    addi s4, s4, 1
    addi s4, s4, 1
92: addi s1, s1, 1
.endm

.macro CASE_BR tgt, nn
    la   s3, 93f
    .rept \nn
    nop
    .endr
    sfence.vma
    beq  zero, zero, \tgt
    addi s4, s4, 1
    addi s4, s4, 1
93: addi s1, s1, 1
.endm

    .section .text.init
    .globl _start
_start:
    la   t0, m_handler
    csrw mtvec, t0
    la   t0, m_handler
    csrw stvec, t0              # S traps : unexpected (handled as failure in M? no : stvec)
    li   s9, 0
    li   a7, 0
    # root @0x10000 : VA 0 megapage -> PA 0 (RWX, S), VA 0xC000_0000 -> I/O
    PSTORE 0x10000, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
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
    li   s1, 0
    li   s2, 0
    li   s4, 0
    CASE_JALR tgt_a, 1
    CASE_JALR tgt_b, 2
    CASE_JALR tgt_c, 3
    CASE_JALR tgt_a, 4
    CASE_JAL  tgt_b, 1
    CASE_JAL  tgt_c, 2
    CASE_JAL  tgt_a, 3
    CASE_JAL  tgt_b, 4
    CASE_BR   tgt_c, 1
    CASE_BR   tgt_a, 2
    CASE_BR   tgt_b, 3
    CASE_BR   tgt_c, 4
    # ---- 2. jumps in the last word of a page ----
    la   t3, tgt_a
    la   s3, 94f
    j    pb_jalr
94: addi s1, s1, 1
    la   s3, 95f
    j    pb_jal
95: addi s1, s1, 1
    la   s3, 96f
    j    pb_br
96: addi s1, s1, 1
    TO_M m_done

m_done:
    CHECK s1, 15, 0x10          # all cases came back
    CHECK s2, 15, 0x11          # t_func called once per case
    CHECK s4, 0, 0x12           # no dead slot ran
    CHECK s9, 0, 0x13
    li   t0, 0
    csrw satp, t0
    PASS

# t_func : called by "jal ra, t_func" at a target : ra must be target + 4
    .balign 64
t_func:
    addi s2, s2, 1
    lw   t1, 0(ra)              # the instruction at ra = the one after the jal
    li   t2, 0x000980e7         # "jalr ra, 0(s3)" (the target's next instruction)
    beq  t1, t2, 1f
    TO_M fail_ra
1:  ret

fail_ra:
    FAIL 0x20

# targets (other pages, other I$ indexes)
    .balign 4096
    .space 0x340
tgt_a:
    jal  ra, t_func
    jalr ra, 0(s3)

    .balign 4096
    .space 0x780
tgt_b:
    jal  ra, t_func
    jalr ra, 0(s3)

    .balign 4096
    .space 0xBC0
tgt_c:
    jal  ra, t_func
    jalr ra, 0(s3)

# jumps in the last word of a page (the next page starts with dead slots)
    .balign 4096
    .space 4096 - 4
pb_jalr:
    jalr x0, t3
    addi s4, s4, 1
    addi s4, s4, 1
    .balign 4096
    .space 4096 - 4
pb_jal:
    jal  x0, tgt_b
    addi s4, s4, 1
    addi s4, s4, 1
    .balign 4096
    .space 4096 - 4
pb_br:
    beq  zero, zero, pb_br_t
    addi s4, s4, 1
    addi s4, s4, 1
    .space 0x100
pb_br_t:
    jal  x0, tgt_c

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
