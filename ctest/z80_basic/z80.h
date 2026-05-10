#pragma once
#include <stdint.h>

/* ────── メモリ ────── */
extern uint8_t mem[65536];

/* ────── レジスタ ────── */
typedef union { uint16_t w; struct { uint8_t lo, hi; } b; } reg16;

typedef struct {
    reg16 af, bc, de, hl;
    reg16 af2, bc2, de2, hl2;  /* シャドウ */
    reg16 ix, iy, sp, pc;
    uint8_t i, r;
    uint8_t iff1, iff2;         /* 割り込みフリップフロップ */
    uint8_t im;                 /* 割り込みモード 0/1/2 */
    uint8_t halted;
    uint8_t nmi_pending;
    uint8_t int_pending;
    uint8_t int_vector;         /* IM2 用データバス値 */
} Z80;

/* ────── フラグ ────── */
#define FLAG_C  0x01
#define FLAG_N  0x02
#define FLAG_PV 0x04
#define FLAG_H  0x10
#define FLAG_Z  0x40
#define FLAG_S  0x80

/* ────── レジスタ別名 ────── */
#define A   (cpu.af.b.hi)
#define F   (cpu.af.b.lo)
#define B   (cpu.bc.b.hi)
#define C   (cpu.bc.b.lo)
#define D   (cpu.de.b.hi)
#define E   (cpu.de.b.lo)
#define H   (cpu.hl.b.hi)
#define L   (cpu.hl.b.lo)
#define HL  (cpu.hl.w)
#define BC  (cpu.bc.w)
#define DE  (cpu.de.w)
#define SP  (cpu.sp.w)
#define PC  (cpu.pc.w)
#define IXH (cpu.ix.b.hi)
#define IXL (cpu.ix.b.lo)
#define IX  (cpu.ix.w)
#define IYH (cpu.iy.b.hi)
#define IYL (cpu.iy.b.lo)
#define IY  (cpu.iy.w)

/* ────── メモリアクセス ────── */
#define RB(a)      (mem[(uint16_t)(a)])
#define WB(a,v)    (mem[(uint16_t)(a)] = (uint8_t)(v))
#define RW(a)      ((uint16_t)(RB(a) | (RB((uint16_t)((a)+1)) << 8)))
#define WW(a,v)    do { WB(a,(v)&0xFF); WB((uint16_t)((a)+1),(v)>>8); } while(0)
#define FETCH()    (RB(PC++))

/* ────── I/O コールバック ────── */
typedef uint8_t (*io_read_fn) (uint8_t port);
typedef void    (*io_write_fn)(uint8_t port, uint8_t val);

#define IO_PORTS 256
extern io_read_fn  io_rd[IO_PORTS];
extern io_write_fn io_wr[IO_PORTS];

void io_register_read (uint8_t port, io_read_fn  fn);
void io_register_write(uint8_t port, io_write_fn fn);

/* ────── CPU ────── */
extern Z80 cpu;

void z80_reset(void);
void z80_step(void);
void z80_nmi(void);          /* NMI を要求 */
void z80_int(uint8_t vec);   /* INT を要求 (vec は IM2 用) */
