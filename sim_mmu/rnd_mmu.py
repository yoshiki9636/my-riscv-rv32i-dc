#!/usr/bin/env python3
"""rnd_mmu.py <seed> <out.S> : random program for the MMU pipeline check

The same program is assembled twice (rnd_mmu.sh) :
  TRANS=1 : S-mode, Sv32 with 4KB identity pages (VA = PA) : micro-TLB / TLB
            misses, ITLB / DTLB walks, short MMU stalls everywhere
  TRANS=0 : M-mode, no translation
and the architectural commit traces of the code region (register write backs
in order, with values) must be identical : an instruction that is lost or
executed twice in one of them shows up as a difference.

memory : 0x00000 stub / trap, 0x10000 root page table, 0x11000 L0 table
         (identity 4KB pages for VA 0 .. 4MB), 0x38000 entry / checksum,
         0x40000 - 0x5FFFF code blocks
         (32 pages), 0x60000 - 0x7FFFF data (32 pages)
"""
import random
import sys

seed = int(sys.argv[1])
out = sys.argv[2]
# --hw : FPGA version (hw_rnd.sh) : no start-up stub, the checksum is stored at
# CSUM_ADR and the program returns to the runner with ecall; half of the ALU
# operations depend on their own destination (a duplicated instruction changes
# the result)
HW = '--hw' in sys.argv[3:]
CSUM_ADR = 0x37FF0
rnd = random.Random(seed)

CODE_BASE, CODE_PAGES = 0x40000, 32
DATA_BASE, DATA_PAGES = 0x60000, 32
NBLOCK = 48
ROUNDS = 3
NOFS = 12                       # word offsets used per data page
ENTRY_BASE = 0x38000            # entry / checksum code (traced, before the blocks)

# registers : random results in t0-t6, a0-a7 ; data page pointers in s2-s7 ;
# s11 round counter, s10 checksum, s9 trap count (stub), s8 scratch pointer
RREGS = ['t0', 't1', 't2', 'a0', 'a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7',
         't3', 't4', 't5', 't6']
BASES = ['s2', 's3', 's4', 's5', 's6', 's7']

pages = rnd.sample(range(DATA_PAGES), len(BASES))
page_of = {b: DATA_BASE + p * 4096 for b, p in zip(BASES, pages)}
MID = 2048                      # base registers point to page + MID (12-bit offsets)
offs = {b: sorted(rnd.sample(range(0, 4096, 4), NOFS)) for b in BASES}
# a 7th set of pages reached through s8 (rewritten often : micro-DTLB misses,
# DTLB pressure)
far_pages = rnd.sample([p for p in range(DATA_PAGES) if p not in pages], 12)
far_offs = sorted(rnd.sample(range(0, 4096, 4), NOFS))


def r():
    return rnd.choice(RREGS)


def mem_ref(width):
    """a (base, offset) pair, aligned to width"""
    if rnd.random() < 0.2:
        return None             # s8 far page access (set up by the caller)
    b = rnd.choice(BASES)
    o = rnd.choice(offs[b])
    if width == 1:
        o += rnd.randrange(4)
    elif width == 2:
        o += rnd.choice([0, 2])
    return b, o


def gen_insn(lines, lbl):
    """one random instruction (or a short pattern)"""
    k = rnd.random()
    if k < 0.30:
        op = rnd.choice(['add', 'sub', 'xor', 'or', 'and', 'sll', 'srl', 'sra', 'slt', 'sltu'])
        d = r()
        a = d if (HW and rnd.random() < 0.5) else r()
        if HW and op in ('and', 'or', 'slt', 'sltu') and a == d:
            op = rnd.choice(['add', 'sub', 'xor'])      # (not idempotent)
        lines.append(f'    {op} {d}, {a}, {r()}')
    elif k < 0.45:
        op = rnd.choice(['addi', 'xori', 'ori', 'andi', 'slti'])
        d = r()
        if HW and rnd.random() < 0.5:
            lines.append(f'    addi {d}, {d}, {rnd.randrange(-2048, 2048) | 1}')
        else:
            lines.append(f'    {op} {d}, {r()}, {rnd.randrange(-2048, 2048)}')
    elif k < 0.70:
        # load (+ load-use right after, often)
        w = rnd.choice([4, 4, 4, 2, 1])
        op = {4: 'lw', 2: rnd.choice(['lh', 'lhu']), 1: rnd.choice(['lb', 'lbu'])}[w]
        d = r()
        m = mem_ref(w)
        if m is None:
            p = rnd.choice(far_pages)
            o = rnd.choice(far_offs)
            lines.append(f'    li   s8, {DATA_BASE + p * 4096 + MID}')
            lines.append(f'    {op} {d}, {o - MID}(s8)')
        else:
            lines.append(f'    {op} {d}, {m[1] - MID}({m[0]})')
        if rnd.random() < 0.6:
            lines.append(f'    add  {r()}, {d}, {r()}')
    elif k < 0.88:
        w = rnd.choice([4, 4, 2, 1])
        op = {4: 'sw', 2: 'sh', 1: 'sb'}[w]
        m = mem_ref(w)
        if m is None:
            p = rnd.choice(far_pages)
            o = rnd.choice(far_offs)
            lines.append(f'    li   s8, {DATA_BASE + p * 4096 + MID}')
            lines.append(f'    {op} {r()}, {o - MID}(s8)')
        else:
            lines.append(f'    {op} {r()}, {m[1] - MID}({m[0]})')
    else:
        # short forward branch over 1 .. 2 instructions
        op = rnd.choice(['beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu'])
        n = rnd.randrange(1, 3)
        lines.append(f'    {op} {r()}, {r()}, {lbl}')
        for _ in range(n):
            lines.append(f'    addi {r()}, {r()}, {rnd.randrange(-64, 64)}')
        lines.append(f'{lbl}:')


# ---- blocks : random sizes, placed at random addresses (some cross a page) ----
blocks = []
used = []
for i in range(NBLOCK):
    body = []
    n = rnd.randrange(6, 20)
    for j in range(n):
        gen_insn(body, f'b{i}_{j}')
    size = (len(body) + 4) * 4 + 16
    while True:
        # bias towards page ends so that blocks cross page boundaries
        pg = rnd.randrange(CODE_PAGES)
        if rnd.random() < 0.5:
            ofs = 4096 - rnd.randrange(4, size // 4 + 4) * 4
        else:
            ofs = rnd.randrange(0, 4096 - 64, 4)
        a = CODE_BASE + pg * 4096 + ofs
        if a + size > CODE_BASE + CODE_PAGES * 4096:
            continue
        if all(a + size <= u or a >= u + us for u, us in used):
            break
    used.append((a, size))
    blocks.append((a, body))

order = list(range(NBLOCK))
rnd.shuffle(order)

L = []
L.append('# generated by rnd_mmu.py, seed %d' % seed)
# no linker relaxation : the .org addresses are exact and the same for every TRANS
L.append('    .option norelax')
L.append('    .equ TIMER_IV, %d' % (300 + (seed * 37) % 600))
if HW:
    L.append('    .section .text')
else:
    L.append('''    .section .text
    .globl _start
_start:
    la   t0, trap
    csrw mtvec, t0
    li   s9, 0
#if TRANS
    # root : VA 0 .. 4MB -> L0 @0x11000, VA 0xC000_0000 megapage -> I/O
    li   t0, 0x10000
    li   t1, (0x11 << 10) | 1
    sw   t1, 0(t0)
    li   t1, (0xC0000 << 10) | 0xC7
    li   t2, 0xC00
    add  t2, t2, t0
    sw   t1, 0(t2)
    # L0 : identity 4KB pages (V R W X A D)
    li   t0, 0x11000
    li   t1, 0xCF
    li   t2, 1024
    li   t3, 0x400
1:  sw   t1, 0(t0)
    addi t0, t0, 4
    add  t1, t1, t3
    addi t2, t2, -1
    bnez t2, 1b
    li   t0, 0x80000010
    csrw satp, t0
    sfence.vma
    li   t0, 0x1800
    csrc mstatus, t0
    li   t0, 0x0800
    csrs mstatus, t0             # MPP = S
    la   t0, entry
    csrw mepc, t0
#if TRANS == 2
    # U-mode + demand faults (Linux after fork : old PTEs, no HW A/D update)
    #   L0 for VA 0x37000 .. 0x7FFFF (relaxation moves entry below 0x38000) : U pages with A = D = 0 (V R W X U)
    li   t0, 0x11000 + (0x37 * 4)
    li   t1, (0x37 << 10) | 0x1F
    li   t2, 0x80 - 0x37
    li   t3, 0x400
1:  sw   t1, 0(t0)
    addi t0, t0, 4
    add  t1, t1, t3
    addi t2, t2, -1
    bnez t2, 1b
    li   t0, 0x10C00
    li   t1, (0xC0000 << 10) | 0xD7  # I/O megapage : U
    sw   t1, 0(t0)
    sfence.vma
    la   t0, strap
    csrw stvec, t0
    li   t0, (1 << 12) | (1 << 13) | (1 << 15)
    csrw medeleg, t0
    li   t0, 0x1800
    csrc mstatus, t0             # MPP = U
    # timer (OpenSBI-like) : MTI -> M handler sets STIP -> STI (delegated) to
    # the S handler -> ecall (from S) -> M clears STIP and re-arms the timer
    la   t0, mtrap
    csrw mtvec, t0
    li   t0, 0x20
    csrw mideleg, t0             # STI -> S
    li   t0, 0xA0
    csrs mie, t0                 # MTIE | STIE
    li   t0, 0xC000F808
    li   t1, TIMER_IV
    sw   t1, 0(t0)
    li   t0, 0xC000F810
    li   t1, 3
    sw   t1, 0(t0)
#endif
    mret
#else
    j    entry
#endif
trap:
    addi s9, s9, 1
    li   t6, 0xC000FFC0
    li   t5, 0x99
    sw   t5, 0(t6)
1:  j    1b
#if TRANS == 2
# S handler (page faults from U) : registers saved at 0x30000 (S page)
#   checks SPP = 0 (FAIL 0x9D : the trap came from S = U code ran as S)
#   sets A (and D for a store) of the page, every 8th fault clears A / D of
#   all U pages (aging), sfence.vma, sret
    .balign 64
strap:
    csrw sscratch, t0
    li   t0, 0x30000
    sw   t1, 0(t0)
    sw   t2, 4(t0)
    sw   t3, 8(t0)
    csrr t1, sstatus
    andi t1, t1, 0x100
    beqz t1, 2f
    li   t1, 0xC000FFC0
    li   t2, 0x9D
    sw   t2, 0(t1)
1:  j    1b
2:  csrr t1, scause
    bgez t1, 7f
    # S timer interrupt : must be cause 0x80000005
    li   t2, 0x80000005
    beq  t1, t2, 8f
    li   t1, 0xC000FFC0
    li   t2, 0x9E
    sw   t2, 0(t1)
1:  j    1b
8:  ecall                        # M : clear STIP, re-arm
    j    srest                   # (no sfence.vma : restore and sret)
7:  csrr t1, stval
    srli t1, t1, 12
    slli t1, t1, 2
    li   t2, 0x11000
    add  t1, t1, t2
    lw   t2, 0(t1)
    ori  t2, t2, 0x40
    csrr t3, scause
    addi t3, t3, -15
    bnez t3, 3f
    ori  t2, t2, 0x80
3:  sw   t2, 0(t1)
    lw   t3, 12(t0)
    addi t3, t3, 1
    sw   t3, 12(t0)
    andi t3, t3, 7
    bnez t3, 5f
    # aging : clear A / D of all U pages except the faulting one
    li   t3, 0x11000 + (0x37 * 4)
4:  beq  t3, t1, 6f
    lw   t2, 0(t3)
    andi t2, t2, -193            # ~(A | D)
    sw   t2, 0(t3)
6:  addi t3, t3, 4
    li   t2, 0x11000 + (0x80 * 4)
    bne  t3, t2, 4b
5:  sfence.vma
srest:
    lw   t1, 0(t0)
    lw   t2, 4(t0)
    lw   t3, 8(t0)
    csrr t0, sscratch
    sret
# M handler : MTI (sets STIP, masks MTIE) / ecall from S (clears STIP,
#   re-arms the timer, unmasks MTIE); anything else FAIL 0x99
    .balign 64
mtrap:
    csrw mscratch, t0
    li   t0, 0x30100
    sw   t1, 0(t0)
    sw   t2, 4(t0)
    csrr t1, mcause
    bgez t1, 2f
    li   t2, 0x80000007
    bne  t1, t2, 9f
    li   t1, 0x80
    csrc mie, t1
    li   t1, 0x20
    csrs mip, t1
    j    3f
2:  li   t2, 9
    bne  t1, t2, 9f
    li   t1, 0x20
    csrc mip, t1
    li   t1, 0xC000F800
    lw   t2, 0(t1)
    addi t2, t2, TIMER_IV
    sw   t2, 8(t1)               # mtimecmp
    li   t2, 1
    sw   t2, 16(t1)              # FRC control : clear
    li   t1, 0x80
    csrs mie, t1
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
3:  lw   t1, 0(t0)
    lw   t2, 4(t0)
    csrr t0, mscratch
    mret
9:  li   t1, 0xC000FFC0
    li   t2, 0x99
    sw   t2, 0(t1)
1:  j    1b
#endif
''')

# entry : in the code region (traced)
L.append('    .org 0x%x' % ENTRY_BASE)
L.append('entry:')
for i, reg in enumerate(RREGS):
    L.append(f'    li   {reg}, {rnd.randrange(-2**31, 2**31)}')
for b in BASES:
    L.append(f'    li   {b}, {page_of[b] + MID}')
L.append(f'    li   s11, {ROUNDS}')
L.append(f'    j    blk{order[0]}')

# checksum + end (traced : before the code blocks' region end)
L.append('checksum:')
L.append('    li   s10, 0')
for b in BASES:
    for o in offs[b]:
        L.append(f'    lw   t0, {o - MID}({b})')
        L.append('    add  s10, s10, t0')
for p in far_pages:
    L.append(f'    li   s8, {DATA_BASE + p * 4096 + MID}')
    for o in far_offs:
        L.append(f'    lw   t0, {o - MID}(s8)')
        L.append('    add  s10, s10, t0')
L.append('    mv   a0, s10')
if HW:
    L.append(f'    li   t6, {CSUM_ADR}')
    L.append('    sw   s10, 0(t6)')
    L.append('    ecall                        # back to the runner')
else:
    L.append('    li   t6, 0xC000FFC0')
    L.append('    li   t5, 1')
    L.append('    sw   t5, 0(t6)')
L.append('1:  j    1b')

# blocks in address order
pos = {order[k]: k for k in range(NBLOCK)}
for i in sorted(range(NBLOCK), key=lambda i: blocks[i][0]):
    a, body = blocks[i]
    L.append('    .org 0x%x' % a)
    L.append(f'blk{i}:')
    L.extend(body)
    k = pos[i]
    if k + 1 < NBLOCK:
        L.append(f'    j    blk{order[k + 1]}')
    else:
        L.append('    addi s11, s11, -1')
        L.append(f'    beqz s11, 2f')
        L.append(f'    j    blk{order[0]}')
        L.append('2:  j    checksum')

# data : random words
L.append('    .org 0x%x' % DATA_BASE)
L.append('data:')
words = [rnd.randrange(2**32) for _ in range(DATA_PAGES * 1024)]
for k in range(0, len(words), 8):
    L.append('    .word ' + ', '.join('0x%08x' % w for w in words[k:k + 8]))

open(out, 'w').write('\n'.join(L) + '\n')
