# t01_mmu_mprv : Sv32 DTLB / PTW test in M-mode with mstatus.MPRV
#   - 4KiB page / 4MiB megapage translation, page table read through the D$
#   - load / store page faults (13 / 15) : V=0, R=0&W=1, A=0, D=0, no W,
#     U page from S (SUM), S page from U, X-only page (MXR),
#     misaligned megapage, non-leaf at level 0
#   - faulting load does not write rd, the instruction after the fault is
#     executed exactly once
#   - alias (2 VAs -> 1 PA), I/O access through a megapage
#   - TLB replacement (24 pages > 16 entries), sfence.vma
#   - AMO / LR / SC through the MMU, AMO page fault
#   - mret clears MPRV when MPP != M
#include "common.inc"
#include "mmu.inc"

    .section .text.init
    .globl _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   s7, 0
    li   s9, 0

    # ---------------- page tables (written through the D$) ----------------
    # root : VA 0x4000_0000 -> L0 @0x11000
    PSTORE 0x10400, ((0x11 << 10) | PTE_V)
    # root : VA 0x4040_0000 -> L0 @0x12000
    PSTORE 0x10404, ((0x12 << 10) | PTE_V)
    # root : VA 0x8000_0000 megapage -> PA 0x0000_0000 (RWX)
    PSTORE 0x10800, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
    # root : VA 0x8040_0000 megapage -> PA 0xC000_0000 (I/O)
    PSTORE 0x10804, ((0xC0000 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    # root : VA 0x8080_0000 misaligned megapage (PPN0 != 0)
    PSTORE 0x10808, ((0x1 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    # L0 @0x11000
    PSTORE 0x11000, ((0x20 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)          # 0x4000_0000 RW
    PSTORE 0x11004, ((0x21 << 10) | PTE_V | PTE_R | PTE_A)                          # 0x4000_1000 RO
    PSTORE 0x11008, ((0x22 << 10) | PTE_V | PTE_R | PTE_W | PTE_A)                  # 0x4000_2000 D=0
    PSTORE 0x1100C, 0                                                               # 0x4000_3000 invalid
    PSTORE 0x11010, ((0x24 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D | PTE_U)  # 0x4000_4000 U
    PSTORE 0x11014, ((0x25 << 10) | PTE_V | PTE_X | PTE_A)                          # 0x4000_5000 X only
    PSTORE 0x11018, ((0x20 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)          # 0x4000_6000 alias of 0x4000_0000
    PSTORE 0x1101C, ((0x27 << 10) | PTE_V | PTE_R | PTE_W | PTE_D)                  # 0x4000_7000 A=0
    PSTORE 0x11020, ((0x11 << 10) | PTE_V)                                          # 0x4000_8000 non-leaf at L0
    PSTORE 0x11024, ((0x20 << 10) | PTE_V | PTE_W)                                  # 0x4000_9000 W without R
    # L0 @0x12000 : 0x4040_0000 + i*4K -> 0x30000 + i*4K (i = 0..23)
    li   t0, 0x12000
    li   t1, ((0x30 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    li   t2, 24
    li   t3, (1 << 10)
1:  sw   t1, 0(t0)
    addi t0, t0, 4
    add  t1, t1, t3
    addi t2, t2, -1
    bnez t2, 1b

    # ---------------- data (physical) ----------------
    PSTORE 0x20000, 0x11111111
    PSTORE 0x21000, 0x22222222
    PSTORE 0x22000, 0x33333333
    PSTORE 0x24000, 0x44444444
    PSTORE 0x25000, 0x55555555

    li   t0, SATP_VAL
    csrw satp, t0
    sfence.vma
    csrr t1, satp
    CHECK t1, SATP_VAL, 0x10

    # ---------------- 1. basic 4KiB page ----------------
    MPRV_S
    li   a1, 0x40000000
    lw   a0, 0(a1)
    CHECK a0, 0x11111111, 0x20
    li   a2, 0xAAAA0001
    sw   a2, 4(a1)
    lw   a0, 4(a1)
    CHECK a0, 0xAAAA0001, 0x22
    sb   a2, 9(a1)          # byte store : 0x01 at offset 9
    lbu  a0, 9(a1)
    CHECK a0, 0x01, 0x24
    EXPECT_NOPF 0x26

    # ---------------- 2. read-only page : store fault ----------------
    li   a1, 0x40001000
    lw   a0, 0(a1)
    CHECK a0, 0x22222222, 0x30
    li   a3, 0
    li   a2, 0x99999999
    sw   a2, 0(a1)          # page fault 15
    addi a3, a3, 1          # must be executed exactly once
    addi a3, a3, 1
    EXPECT_PF 15, 0x40001000, 0x32
    CHECK a3, 2, 0x35
    MPRV_S
    lw   a0, 0(a1)
    CHECK a0, 0x22222222, 0x36   # the store must not have been done

    # ---------------- 3. D=0 page : load OK / store fault ----------------
    li   a1, 0x40002000
    lw   a0, 0(a1)
    CHECK a0, 0x33333333, 0x40
    EXPECT_NOPF 0x41
    sw   a0, 4(a1)          # page fault 15 (D=0)
    EXPECT_PF 15, 0x40002004, 0x42

    # ---------------- 4. invalid PTE : load fault, rd not written ----------------
    MPRV_S
    li   a1, 0x40003000
    li   a0, 0x1234
    lw   a0, 8(a1)          # page fault 13
    mv   a4, a0             # forwarding from the faulting load must not happen
    EXPECT_PF 13, 0x40003008, 0x50
    CHECK a0, 0x1234, 0x53
    CHECK a4, 0x1234, 0x54

    # ---------------- 5. U page / SUM / MPP=U ----------------
    MPRV_S
    li   a1, 0x40004000
    lw   a0, 0(a1)          # S access to a U page, SUM=0 : fault 13
    EXPECT_PF 13, 0x40004000, 0x60
    MPRV_S
    li   t0, MSTATUS_SUM
    csrs mstatus, t0
    lw   a0, 0(a1)          # SUM=1 : OK
    CHECK a0, 0x44444444, 0x63
    EXPECT_NOPF 0x64
    li   t0, MSTATUS_SUM
    csrc mstatus, t0
    MPRV_U
    lw   a0, 0(a1)          # U access to a U page : OK
    CHECK a0, 0x44444444, 0x65
    li   a1, 0x40000000
    lw   a0, 0(a1)          # U access to an S page : fault 13
    EXPECT_PF 13, 0x40000000, 0x66

    # ---------------- 6. X only page / MXR ----------------
    MPRV_S
    li   a1, 0x40005000
    lw   a0, 0(a1)          # fault 13
    EXPECT_PF 13, 0x40005000, 0x70
    MPRV_S
    li   t0, MSTATUS_MXR
    csrs mstatus, t0
    lw   a0, 0(a1)          # MXR=1 : OK
    CHECK a0, 0x55555555, 0x73
    li   t0, MSTATUS_MXR
    csrc mstatus, t0
    EXPECT_NOPF 0x74

    # ---------------- 7. structural faults ----------------
    li   a1, 0x40007000
    sw   a0, 0(a1)          # A=0 : fault 15
    EXPECT_PF 15, 0x40007000, 0x80
    MPRV_S
    li   a1, 0x40008000
    lw   a0, 0(a1)          # non-leaf PTE at level 0 : fault 13
    EXPECT_PF 13, 0x40008000, 0x83
    MPRV_S
    li   a1, 0x40009000
    lw   a0, 0(a1)          # W=1 R=0 : fault 13
    EXPECT_PF 13, 0x40009000, 0x86
    MPRV_S
    li   a1, 0x80800010
    lw   a0, 0(a1)          # misaligned megapage : fault 13
    EXPECT_PF 13, 0x80800010, 0x89
    MPRV_S
    li   a1, 0x40800000
    lw   a0, 0(a1)          # root PTE invalid : fault 13
    EXPECT_PF 13, 0x40800000, 0x8c

    # ---------------- 8. alias / megapage ----------------
    MPRV_S
    li   a1, 0x40000000
    li   a2, 0x5A5A5A5A
    sw   a2, 8(a1)
    li   a1, 0x40006000
    lw   a0, 8(a1)
    CHECK a0, 0x5A5A5A5A, 0x90
    li   a1, 0x80020000     # megapage -> PA 0x0002_0000
    lw   a0, 8(a1)
    CHECK a0, 0x5A5A5A5A, 0x91
    lw   a0, 4(a1)
    CHECK a0, 0xAAAA0001, 0x92
    EXPECT_NOPF 0x93

    # ---------------- 9. I/O through a megapage ----------------
    li   a1, 0x8040FFC4     # -> PA 0xC000_FFC4 (PUTC)
    li   a2, 'M'
    sw   a2, 0(a1)
    li   a2, 'M'
    sw   a2, 0(a1)
    li   a2, 'U'
    sw   a2, 0(a1)
    li   a2, '\n'
    sw   a2, 0(a1)
    EXPECT_NOPF 0x98

    # ---------------- 10. TLB replacement (24 pages) ----------------
    li   a1, 0x40400000
    li   a2, 0
    li   t2, 24
    li   t3, 0x1000
2:  addi a3, a2, 0x100
    sw   a3, 0(a1)
    add  a1, a1, t3
    addi a2, a2, 1
    bne  a2, t2, 2b
    li   a1, 0x40400000
    li   a2, 0
3:  lw   a0, 0(a1)
    addi a3, a2, 0x100
    beq  a0, a3, 4f
    FAIL 0xa0
4:  add  a1, a1, t3
    addi a2, a2, 1
    bne  a2, t2, 3b
    EXPECT_NOPF 0xa1

    # ---------------- 11. AMO / LR / SC ----------------
    li   a1, 0x40000010
    li   a2, 5
    sw   a2, 0(a1)
    li   a2, 3
    amoadd.w a0, a2, (a1)
    CHECK a0, 5, 0xb0
    lw   a0, 0(a1)
    CHECK a0, 8, 0xb1
    lr.w a0, (a1)
    CHECK a0, 8, 0xb2
    li   a2, 0x77
    sc.w a3, a2, (a1)
    CHECK a3, 0, 0xb3
    lw   a0, 0(a1)
    CHECK a0, 0x77, 0xb4
    EXPECT_NOPF 0xb5
    li   a1, 0x40001000     # read only page
    li   a2, 1
    li   a0, 0x4321
    amoadd.w a0, a2, (a1)   # store/AMO page fault 15, rd not written
    EXPECT_PF 15, 0x40001000, 0xb6
    CHECK a0, 0x4321, 0xb9
    MPRV_S
    lw   a0, 0(a1)
    CHECK a0, 0x22222222, 0xba

    # ---------------- 12. physical view ----------------
    MPRV_OFF
    li   a1, 0x20000
    lw   a0, 4(a1)
    CHECK a0, 0xAAAA0001, 0xc0
    lw   a0, 8(a1)
    CHECK a0, 0x5A5A5A5A, 0xc1
    lw   a0, 16(a1)
    CHECK a0, 0x77, 0xc2
    li   a1, 0x30000 + 23*0x1000
    lw   a0, 0(a1)
    CHECK a0, 0x117, 0xc3
    li   a1, 0x21000
    lw   a0, 0(a1)
    CHECK a0, 0x22222222, 0xc4

    # ---------------- 13. sfence.vma : remap 0x4000_0000 -> 0x21000 ----------------
    PSTORE 0x11000, ((0x21 << 10) | PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    sfence.vma
    MPRV_S
    li   a1, 0x40000000
    lw   a0, 0(a1)
    CHECK a0, 0x22222222, 0xd0
    EXPECT_NOPF 0xd1

    # ---------------- 14. mret clears MPRV (MPP != M) ----------------
    MPRV_S
    la   t0, 5f
    csrw mepc, t0
    mret
5:  csrr t0, mstatus
    li   t1, MSTATUS_MPRV
    and  t0, t0, t1
    CHECK t0, 0, 0xe0

    CHECK s9, 12, 0xf0      # total page faults
    PASS

    TRAP_HANDLER
