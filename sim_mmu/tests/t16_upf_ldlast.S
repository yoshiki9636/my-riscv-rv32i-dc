# t16_upf_ldlast : U-mode load in the last word of a page, next page unmapped
#   (needs FT_SMODE = 1 : VDEFS="-DTB_SMODE=1")
#   Linux Oops (bash, 2026-11-23) : epc = 0x....fffc (a load of a U page),
#   status.SPP = 1, cause 13 -> the load was checked with priv = S.
#   Suspect : the fetch of the next page takes an instruction page fault
#   (cause 12, delegated -> priv = S) while the older load is still in MA
#   (micro-TLB miss / walk) and its permission check sees the new priv.
#   Expected : the load completes with U, then cause 12 for 0x4000_1000;
#   the S handler maps the page and srets, U code finishes with ecall.
#   cases (a6) : 0 = D not in the DTLB (PTW), 1 = D in DTLB / not in micro-TLB,
#                2 = D in micro-TLB, 3 = case 0 reached by a jump to the
#                last word (instead of falling through nops)
#include "common.inc"
#include "mmu.inc"

.equ UVA,   0x40000000
.equ L0,    0x00011000
.equ DPA,   0x00020000
.equ EPA,   0x00021000
.equ MAGIC, 0x12345678
.equ DPTE_OK, ((DPA >> 12) << 10 | PTE_V | PTE_R | PTE_W | PTE_U | PTE_A | PTE_D)
.equ NCASE, 8

    .section .text.init
    .globl _start
_start:
    la   t0, m_handler
    csrw mtvec, t0
    la   t0, s_handler
    csrw stvec, t0
    # root : VA 0 megapage -> PA 0 (S RWX), 0xC000_0000 -> I/O, 0x4000_0000 -> L0
    PSTORE 0x10000, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
    PSTORE 0x10C00, ((0xC0000 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    PSTORE 0x10400, ((L0 >> 12) << 10 | PTE_V)
    # L0[0] : ucode_p0 (U RX), L0[1] : ucode_p1 (mapped by the S handler)
    la   t0, ucode_p0
    srli t0, t0, 12
    slli t0, t0, 10
    ori  t0, t0, (PTE_V | PTE_R | PTE_X | PTE_U | PTE_A)
    li   t1, L0
    sw   t0, 0(t1)
    la   t0, ucode_p1
    srli t0, t0, 12
    slli t0, t0, 10
    ori  s4, t0, (PTE_V | PTE_R | PTE_X | PTE_U | PTE_A)
    # L0[3] : D, L0[4] : E (U RW)
    PSTORE (L0 + 12), DPTE_OK
    PSTORE (L0 + 16), ((EPA >> 12) << 10 | PTE_V | PTE_R | PTE_W | PTE_U | PTE_A | PTE_D)
    PSTORE DPA, MAGIC
    PSTORE EPA, 0x5555AAAA
    # page faults (12/13/15) -> S
    li   t0, (1 << 12) | (1 << 13) | (1 << 15)
    csrw medeleg, t0
    li   t0, SATP_VAL
    csrw satp, t0
    li   a6, 0

run_case:
    li   t0, L0 + 4
    sw   zero, 0(t0)            # unmap ucode_p1
    li   t0, DPTE_OK
    li   t1, 4
    blt  a6, t1, 31f
    li   t0, 0                  # case 4 / 5 : D invalid
    li   t1, 6
    blt  a6, t1, 31f
    li   t0, DPTE_OK & ~PTE_A   # case 6 / 7 : D with A = 0
31: li   t1, L0 + 12
    sw   t0, 0(t1)
    sfence.vma
    li   s5, 0
    li   s6, 0
    li   s3, 0
    li   t0, MSTATUS_MPP
    csrc mstatus, t0            # MPP = U
    li   t0, UVA
    csrw mepc, t0
    mret

m_handler:
    csrr t0, mcause
    li   t1, 8
    beq  t0, t1, 41f
    FAIL 0x99
41: CHECK s5, MAGIC, 0x20
    CHECK s6, 1, 0x30
    li   t1, 4
    blt  a6, t1, 43f
    CHECK s3, 1, 0x50           # cases 4.. : one load page fault
    j    42f
43: CHECK s3, 0, 0x51
42: addi a6, a6, 1
    li   t1, NCASE
    blt  a6, t1, run_case
    PASS

    .balign 64
s_handler:                      # a3 / a4 only (U code uses t0-t3)
    csrr a3, scause
    li   a4, 12
    beq  a3, a4, 51f
    li   a4, 13
    bne  a3, a4, 52f
    csrr a3, sepc
    li   a4, UVA + 0xffc
    beq  a3, a4, 54f
    FAIL 0x4C                   # load page fault at an unexpected pc
54: csrr a3, sstatus
    andi a3, a3, 0x100
    beqz a3, 55f
    FAIL 0x4D                   # SPP = 1 : the load was checked as S (Linux Oops)
55: csrr a3, stval
    li   a4, UVA + 0x3000
    beq  a3, a4, 56f
    FAIL 0x4E
56: addi s3, s3, 1
    li   a3, L0 + 12
    li   a4, DPTE_OK
    sw   a4, 0(a3)
    sfence.vma
    sret
52: FAIL 0x40
51: csrr a3, stval
    li   a4, UVA + 0x1000
    beq  a3, a4, 53f
    FAIL 0x41
53: addi s6, s6, 1
    li   a3, L0 + 4
    sw   s4, 0(a3)
    sfence.vma
    sret

# ------------------------------------------------------------------------
# U code : VA 0x4000_0000 (ucode_p0) / 0x4000_1000 (ucode_p1)
    .balign 4096
ucode_p0:
    li   t2, UVA + 0x3000       # D
    li   t3, UVA + 0x4000       # E
    li   t1, 0
    li   t0, 1
    beq  a6, t0, 1f
    li   t0, 2
    beq  a6, t0, 2f
    li   t0, 3
    beq  a6, t0, 3f
    li   t0, 5
    beq  a6, t0, 3f
    li   t0, 7
    beq  a6, t0, 4f
    j    9f
4:  j    uprev
1:  lw   t0, 0(t2)              # D -> DTLB
    lw   t0, 0(t3)              # E -> micro-TLB
    j    9f
2:  lw   t0, 0(t3)
    lw   t0, 0(t2)              # D -> micro-TLB
    j    9f
3:  j    ulast
9:
    .fill (ucode_p0 + 0xff4 - .) / 4, 4, 0x00000013
uprev:
    lw   t0, 0(t3)              # E (like lw a3,0(a4) / lbu a1,25(a0))
    lbu  t0, 1(t3)
ulast:
    lw   t1, 0(t2)
ucode_p1:
    mv   s5, t1
    ecall
