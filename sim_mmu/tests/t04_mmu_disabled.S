# t04_mmu_disabled : 1 way > 4KB (e.g. VDEFS="-DTB_DWIDTH=12 -DTB_DWAYS=1")
#   the MMU is disabled : satp.MODE reads 0 and MPRV does not translate
# with the MMU enabled (DWIDTH <= 10) this test FAILs with code 2 (expected)
#include "common.inc"
#include "mmu.inc"
    .section .text.init
    .globl _start
_start:
    li   t0, SATP_VAL
    csrw satp, t0
    csrr t1, satp
    CHECK t1, 0x00000010, 2      # MODE bit is not set
    PSTORE 0x20000, 0x12345678
    MPRV_S
    li   a1, 0x20000
    lw   a0, 0(a1)               # not translated
    CHECK a0, 0x12345678, 3
    MPRV_OFF
    PASS
