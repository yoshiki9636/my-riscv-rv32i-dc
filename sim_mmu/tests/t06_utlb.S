# t06_utlb : micro-TLB miss / DTLB hit path (TLBL -> RPCK)
#   - 8 pages accessed alternately : the 1 entry micro-TLB misses every time,
#     the 16 entry DTLB hits (after the first walk)
#   - load / store / byte store / AMO on that path
#   - permission fault found on that path (read only page : load OK, then a
#     store after another page was accessed)
#   - I/O through a megapage alternating with data pages : each character
#     must be written exactly once
#include "common.inc"
#include "mmu.inc"

.equ NPG, 8

    .section .text.init
    .globl _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   s7, 0
    li   s9, 0

    # root : VA 0x4000_0000 -> L0 @0x11000, VA 0x8040_0000 megapage -> I/O
    PSTORE 0x10400, ((0x11 << 10) | PTE_V)
    PSTORE 0x10804, ((0xC0000 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    # L0[i] : VA 0x4000_0000 + i*4K -> PA 0x30000 + i*4K (RW), i = 0..7
    li   t0, 0x11000
    li   t1, ((0x30 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    li   t2, NPG
    li   t3, (1 << 10)
1:  sw   t1, 0(t0)
    addi t0, t0, 4
    add  t1, t1, t3
    addi t2, t2, -1
    bnez t2, 1b
    # L0[8] : VA 0x4000_8000 -> PA 0x38000 read only
    PSTORE 0x11020, ((0x38 << 10) | PTE_V | PTE_R | PTE_A)
    PSTORE 0x38000, 0x0000ABCD
    li   t0, SATP_VAL
    csrw satp, t0
    sfence.vma
    MPRV_S

    # ---- 1. alternate stores over 8 pages, 4 rounds ----
    li   s0, 0                  # round
2:  li   s1, 0                  # page
3:  slli a1, s1, 12
    li   t0, 0x40000000
    add  a1, a1, t0
    slli t1, s0, 2
    add  a1, a1, t1             # offset = round * 4
    slli a0, s1, 8
    or   a0, a0, s0
    sw   a0, 0(a1)
    addi s1, s1, 1
    li   t0, NPG
    bne  s1, t0, 3b
    addi s0, s0, 1
    li   t0, 4
    bne  s0, t0, 2b
    # ---- 2. read back alternately (pages in reverse order) ----
    li   s0, 0
4:  li   s1, NPG - 1
5:  slli a1, s1, 12
    li   t0, 0x40000000
    add  a1, a1, t0
    slli t1, s0, 2
    add  a1, a1, t1
    lw   a0, 0(a1)
    slli a2, s1, 8
    or   a2, a2, s0
    beq  a0, a2, 6f
    FAIL 0x10
6:  addi s1, s1, -1
    bgez s1, 5b
    addi s0, s0, 1
    li   t0, 4
    bne  s0, t0, 4b
    EXPECT_NOPF 0x11

    # ---- 3. byte store / AMO alternating pages ----
    li   a1, 0x40000040
    li   a3, 0x40001040
    li   a0, 0x5A
    sb   a0, 1(a1)              # page 0
    li   a2, 7
    sw   a2, 0(a3)              # page 1
    li   a2, 3
    amoadd.w a4, a2, (a3)       # page 1 : utlb hit
    amoadd.w a4, a2, (a1)       # page 0 : utlb miss, DTLB hit (old value 0x5A00)
    CHECK a4, 0x5A00, 0x20
    lw   a0, 0(a3)
    CHECK a0, 10, 0x21
    lw   a0, 0(a1)
    CHECK a0, 0x5A03, 0x22
    EXPECT_NOPF 0x23

    # ---- 4. permission fault on the DTLB hit path ----
    li   a1, 0x40008000
    lw   a0, 0(a1)              # walk, read only page : OK
    CHECK a0, 0xABCD, 0x30
    li   a3, 0x40000000
    lw   a2, 0(a3)              # another page into the micro-TLB
    sw   a0, 0(a1)              # utlb miss -> DTLB hit -> store fault 15
    EXPECT_PF 15, 0x40008000, 0x31
    MPRV_S
    lw   a0, 0(a1)
    CHECK a0, 0xABCD, 0x34

    # ---- 5. I/O alternating with a data page ----
    # (the characters are immediates : the code area is not mapped by MPRV)
.macro PUTC_ALT ch
    lw   a2, 0(a3)              # data page into the micro-TLB
    li   a0, \ch
    sw   a0, 0(a1)              # utlb miss -> DTLB hit -> I/O write (once)
.endm
    li   a1, 0x8040FFC4         # PUTC through the megapage
    li   a3, 0x40002000
    PUTC_ALT 'u'
    PUTC_ALT 'T'
    PUTC_ALT 'L'
    PUTC_ALT 'B'
    PUTC_ALT '\n'
    EXPECT_NOPF 0x40
    MPRV_OFF
    CHECK s9, 1, 0x41
    PASS

    TRAP_HANDLER
