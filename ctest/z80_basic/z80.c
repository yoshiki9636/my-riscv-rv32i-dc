#include <stdio.h>
#include <string.h>
#include "z80.h"

uint8_t    mem[65536];
Z80        cpu;
io_read_fn  io_rd[IO_PORTS];
io_write_fn io_wr[IO_PORTS];

/* ────── I/O 登録 ────── */
void io_register_read (uint8_t port, io_read_fn  fn) { io_rd[port] = fn; }
void io_register_write(uint8_t port, io_write_fn fn) { io_wr[port] = fn; }

static uint8_t io_in(uint8_t port) {
    return io_rd[port] ? io_rd[port](port) : 0xFF;
}
static void io_out(uint8_t port, uint8_t val) {
    if (io_wr[port]) io_wr[port](port, val);
}

/* ────── スタック ────── */
static void     push16(uint16_t v) { SP -= 2; WW(SP, v); }
static uint16_t pop16 (void)       { uint16_t v = RW(SP); SP += 2; return v; }

/* ────── フラグ計算 ────── */
static uint8_t parity(uint8_t v) {
    v ^= v >> 4; v ^= v >> 2; v ^= v >> 1; return (~v) & 1;
}
static void szp_flags(uint8_t v) {
    F = (F & (FLAG_C | FLAG_N | FLAG_H))
      | (v & 0x80 ? FLAG_S : 0)
      | (v == 0   ? FLAG_Z : 0)
      | (parity(v) ? FLAG_PV : 0);
}

/* INC/DEC で使うヘルパ (FLAG_C を保存) */
static uint8_t inc8(uint8_t a) {
    uint8_t r = a + 1;
    F = (F & FLAG_C)
      | (r & 0x80 ? FLAG_S : 0)
      | (r == 0   ? FLAG_Z : 0)
      | ((a & 0xF) == 0xF ? FLAG_H : 0)
      | (a == 0x7F ? FLAG_PV : 0);
    return r;
}
static uint8_t dec8(uint8_t a) {
    uint8_t r = a - 1;
    F = (F & FLAG_C) | FLAG_N
      | (r & 0x80 ? FLAG_S : 0)
      | (r == 0   ? FLAG_Z : 0)
      | ((a & 0xF) == 0x00 ? FLAG_H : 0)
      | (a == 0x80 ? FLAG_PV : 0);
    return r;
}

static uint8_t add8(uint8_t a, uint8_t b) {
    uint16_t r = a + b;
    F = ((r & 0x80) ? FLAG_S : 0)
      | ((r & 0xFF) == 0 ? FLAG_Z : 0)
      | ((a & 0xF) + (b & 0xF) > 0xF ? FLAG_H : 0)
      | (((a ^ b ^ 0x80) & (b ^ r) & 0x80) ? FLAG_PV : 0)
      | (r > 0xFF ? FLAG_C : 0);
    return (uint8_t)r;
}
static uint8_t adc8(uint8_t a, uint8_t b) {
    uint8_t c = (F & FLAG_C) ? 1 : 0;
    uint16_t r = a + b + c;
    F = ((r & 0x80) ? FLAG_S : 0)
      | ((r & 0xFF) == 0 ? FLAG_Z : 0)
      | ((a & 0xF) + (b & 0xF) + c > 0xF ? FLAG_H : 0)
      | (((a ^ b ^ 0x80) & (b ^ r) & 0x80) ? FLAG_PV : 0)
      | (r > 0xFF ? FLAG_C : 0);
    return (uint8_t)r;
}
static uint8_t sub8(uint8_t a, uint8_t b) {
    uint16_t r = a - b;
    F = FLAG_N
      | ((r & 0x80) ? FLAG_S : 0)
      | ((r & 0xFF) == 0 ? FLAG_Z : 0)
      | ((a & 0xF) < (b & 0xF) ? FLAG_H : 0)
      | (((a ^ b) & (a ^ r) & 0x80) ? FLAG_PV : 0)
      | (r > 0xFF ? FLAG_C : 0);
    return (uint8_t)r;
}
static uint8_t sbc8(uint8_t a, uint8_t b) {
    uint8_t c = (F & FLAG_C) ? 1 : 0;
    uint16_t r = a - b - c;
    F = FLAG_N
      | ((r & 0x80) ? FLAG_S : 0)
      | ((r & 0xFF) == 0 ? FLAG_Z : 0)
      | (((a & 0xF) - (b & 0xF) - c) & 0x10 ? FLAG_H : 0)
      | (((a ^ b) & (a ^ r) & 0x80) ? FLAG_PV : 0)
      | (r > 0xFF ? FLAG_C : 0);
    return (uint8_t)r;
}

/* ────── 16ビット加算 (フラグ更新、結果を返す) ────── */
static uint16_t add16_flags(uint16_t a, uint16_t b) {
    uint32_t r = (uint32_t)a + b;
    F = (F & (FLAG_S | FLAG_Z | FLAG_PV))
      | ((a & 0xFFF) + (b & 0xFFF) > 0xFFF ? FLAG_H : 0)
      | (r > 0xFFFF ? FLAG_C : 0);
    return (uint16_t)r;
}

/* ADD HL, rr */
static void add_hl16(uint16_t rr) { HL = add16_flags(HL, rr); }

/* ADC HL, rr (ED prefix) */
static void adc16(uint16_t rr) {
    uint8_t  c = (F & FLAG_C) ? 1 : 0;
    uint16_t h = HL;
    uint32_t r = (uint32_t)h + rr + c;
    F = (r & 0x8000 ? FLAG_S : 0)
      | ((r & 0xFFFF) == 0 ? FLAG_Z : 0)
      | (((h & 0xFFF) + (rr & 0xFFF) + c) > 0xFFF ? FLAG_H : 0)
      | (((h ^ rr ^ 0x8000) & (rr ^ r) & 0x8000) ? FLAG_PV : 0)
      | (r > 0xFFFF ? FLAG_C : 0);
    HL = (uint16_t)r;
}

/* SBC HL, rr (ED prefix) */
static void sbc16(uint16_t rr) {
    uint8_t  c = (F & FLAG_C) ? 1 : 0;
    uint16_t h = HL;
    uint32_t r = (uint32_t)h - rr - c;
    F = FLAG_N
      | (r & 0x8000 ? FLAG_S : 0)
      | ((r & 0xFFFF) == 0 ? FLAG_Z : 0)
      | (((h & 0xFFF) - (rr & 0xFFF) - c) & 0x1000 ? FLAG_H : 0)
      | (((h ^ rr) & (h ^ r) & 0x8000) ? FLAG_PV : 0)
      | (r > 0xFFFF ? FLAG_C : 0);
    HL = (uint16_t)r;
}

/* ローテーション */
static uint8_t rlc8(uint8_t v) {
    uint8_t c = v >> 7;
    v = (v << 1) | c;
    F = (c ? FLAG_C : 0); szp_flags(v); F &= ~FLAG_N; F &= ~FLAG_H;
    return v;
}
static uint8_t rrc8(uint8_t v) {
    uint8_t c = v & 1;
    v = (v >> 1) | (c << 7);
    F = (c ? FLAG_C : 0); szp_flags(v); F &= ~FLAG_N; F &= ~FLAG_H;
    return v;
}
static uint8_t rl8(uint8_t v) {
    uint8_t old_c = (F & FLAG_C) ? 1 : 0;
    uint8_t new_c = v >> 7;
    v = (v << 1) | old_c;
    F = (new_c ? FLAG_C : 0); szp_flags(v); F &= ~FLAG_N; F &= ~FLAG_H;
    return v;
}
static uint8_t rr8(uint8_t v) {
    uint8_t old_c = (F & FLAG_C) ? 1 : 0;
    uint8_t new_c = v & 1;
    v = (v >> 1) | (old_c << 7);
    F = (new_c ? FLAG_C : 0); szp_flags(v); F &= ~FLAG_N; F &= ~FLAG_H;
    return v;
}
static uint8_t sla8(uint8_t v) {
    uint8_t c = v >> 7;
    v <<= 1;
    F = (c ? FLAG_C : 0); szp_flags(v); F &= ~FLAG_N; F &= ~FLAG_H;
    return v;
}
static uint8_t sra8(uint8_t v) {
    uint8_t c = v & 1;
    v = (v & 0x80) | (v >> 1);
    F = (c ? FLAG_C : 0); szp_flags(v); F &= ~FLAG_N; F &= ~FLAG_H;
    return v;
}
static uint8_t srl8(uint8_t v) {
    uint8_t c = v & 1;
    v >>= 1;
    F = (c ? FLAG_C : 0); szp_flags(v); F &= ~FLAG_N; F &= ~FLAG_H;
    return v;
}

/* ────── リセット ────── */
void z80_reset(void) {
    memset(&cpu, 0, sizeof cpu);
    PC = 0x0000;
    SP = 0xFFFF;
}

/* ────── 割り込み要求 ────── */
void z80_nmi(void) { cpu.nmi_pending = 1; }
void z80_int(uint8_t vec) { cpu.int_pending = 1; cpu.int_vector = vec; }

/* ────── 割り込み受け付け ────── */
static void handle_nmi(void) {
    cpu.nmi_pending = 0;
    cpu.halted = 0;
    cpu.iff2 = cpu.iff1;
    cpu.iff1 = 0;
    push16(PC);
    PC = 0x0066;
}
static void handle_int(void) {
    if (!cpu.iff1) return;
    cpu.int_pending = 0;
    cpu.halted = 0;
    cpu.iff1 = cpu.iff2 = 0;
    push16(PC);
    switch (cpu.im) {
    case 0:
    case 1: PC = 0x0038; break;
    case 2: PC = RW((cpu.i << 8) | cpu.int_vector); break;
    }
}

/* ────── CB プレフィックス命令 ────── */
static void exec_cb(void) {
    uint8_t op  = FETCH();
    uint8_t bit = (op >> 3) & 7;
    uint8_t reg = op & 7;
    uint8_t mask = (uint8_t)(1 << bit);

    /* レジスタポインタ配列 (6=(HL)) */
    uint8_t *rp[8] = { &B, &C, &D, &E, &H, &L, NULL, &A };
    uint8_t val = (reg == 6) ? RB(HL) : *rp[reg];
    uint8_t res = val;

    switch (op >> 6) {
    case 0: /* ローテーション / シフト */
        switch (bit) {
        case 0: res = rlc8(val); break;
        case 1: res = rrc8(val); break;
        case 2: res = rl8(val);  break;
        case 3: res = rr8(val);  break;
        case 4: res = sla8(val); break;
        case 5: res = sra8(val); break;
        case 7: res = srl8(val); break;
        default: break;
        }
        if (reg == 6) WB(HL, res); else *rp[reg] = res;
        break;
    case 1: /* BIT b, r */
        F = (F & FLAG_C) | FLAG_H | (!(val & mask) ? FLAG_Z | FLAG_PV : 0)
          | (val & mask & 0x80 ? FLAG_S : 0);
        break;
    case 2: /* RES b, r */
        res = val & (uint8_t)~mask;
        if (reg == 6) WB(HL, res); else *rp[reg] = res;
        break;
    case 3: /* SET b, r */
        res = val | mask;
        if (reg == 6) WB(HL, res); else *rp[reg] = res;
        break;
    }
}

/* ────── DD/FD プレフィックス命令 (IX/IY) ────── */
static void exec_dd_fd(reg16 *xy) {
    uint8_t op = FETCH();
    switch (op) {
    /* LD xy, nn */
    case 0x21: xy->w = RW(PC); PC += 2; break;
    /* LD (nn), xy */
    case 0x22: { uint16_t n=RW(PC); PC+=2; WW(n,xy->w); break; }
    /* LD xy, (nn) */
    case 0x2A: { uint16_t n=RW(PC); PC+=2; xy->w=RW(n); break; }
    /* ADD xy, rr */
    case 0x09: xy->w = add16_flags(xy->w, BC); break;
    case 0x19: xy->w = add16_flags(xy->w, DE); break;
    case 0x29: { uint16_t t=xy->w; xy->w = add16_flags(t, t); break; }
    case 0x39: xy->w = add16_flags(xy->w, SP); break;
    /* INC/DEC xy */
    case 0x23: xy->w++; break;
    case 0x2B: xy->w--; break;
    /* PUSH/POP xy */
    case 0xE5: push16(xy->w); break;
    case 0xE1: xy->w = pop16(); break;
    /* JP (xy) */
    case 0xE9: PC = xy->w; break;
    /* EX (SP), xy */
    case 0xE3: { uint16_t t=RW(SP); WW(SP,xy->w); xy->w=t; break; }
    /* LD SP, xy */
    case 0xF9: SP = xy->w; break;
    /* INC (xy+d) */
    case 0x34: { int8_t d=(int8_t)FETCH(); uint16_t a=(uint16_t)(xy->w+d); uint8_t t=inc8(RB(a)); WB(a,t); break; }
    /* DEC (xy+d) */
    case 0x35: { int8_t d=(int8_t)FETCH(); uint16_t a=(uint16_t)(xy->w+d); uint8_t t=dec8(RB(a)); WB(a,t); break; }
    /* LD (xy+d), n */
    case 0x36: { int8_t d=(int8_t)FETCH(); uint8_t n=FETCH(); WB((uint16_t)(xy->w+d), n); break; }
    /* LD r, (xy+d) */
    case 0x46: { int8_t d=(int8_t)FETCH(); B=RB((uint16_t)(xy->w+d)); break; }
    case 0x4E: { int8_t d=(int8_t)FETCH(); C=RB((uint16_t)(xy->w+d)); break; }
    case 0x56: { int8_t d=(int8_t)FETCH(); D=RB((uint16_t)(xy->w+d)); break; }
    case 0x5E: { int8_t d=(int8_t)FETCH(); E=RB((uint16_t)(xy->w+d)); break; }
    case 0x66: { int8_t d=(int8_t)FETCH(); H=RB((uint16_t)(xy->w+d)); break; }
    case 0x6E: { int8_t d=(int8_t)FETCH(); L=RB((uint16_t)(xy->w+d)); break; }
    case 0x7E: { int8_t d=(int8_t)FETCH(); A=RB((uint16_t)(xy->w+d)); break; }
    /* LD (xy+d), r */
    case 0x70: { int8_t d=(int8_t)FETCH(); WB((uint16_t)(xy->w+d), B); break; }
    case 0x71: { int8_t d=(int8_t)FETCH(); WB((uint16_t)(xy->w+d), C); break; }
    case 0x72: { int8_t d=(int8_t)FETCH(); WB((uint16_t)(xy->w+d), D); break; }
    case 0x73: { int8_t d=(int8_t)FETCH(); WB((uint16_t)(xy->w+d), E); break; }
    case 0x74: { int8_t d=(int8_t)FETCH(); WB((uint16_t)(xy->w+d), H); break; }
    case 0x75: { int8_t d=(int8_t)FETCH(); WB((uint16_t)(xy->w+d), L); break; }
    case 0x77: { int8_t d=(int8_t)FETCH(); WB((uint16_t)(xy->w+d), A); break; }
    /* ALU A, (xy+d) */
    case 0x86: { int8_t d=(int8_t)FETCH(); A=add8(A,RB((uint16_t)(xy->w+d))); break; }
    case 0x8E: { int8_t d=(int8_t)FETCH(); A=adc8(A,RB((uint16_t)(xy->w+d))); break; }
    case 0x96: { int8_t d=(int8_t)FETCH(); A=sub8(A,RB((uint16_t)(xy->w+d))); break; }
    case 0x9E: { int8_t d=(int8_t)FETCH(); A=sbc8(A,RB((uint16_t)(xy->w+d))); break; }
    case 0xA6: { int8_t d=(int8_t)FETCH(); A&=RB((uint16_t)(xy->w+d)); F=FLAG_H; szp_flags(A); break; }
    case 0xAE: { int8_t d=(int8_t)FETCH(); A^=RB((uint16_t)(xy->w+d)); F=0; szp_flags(A); break; }
    case 0xB6: { int8_t d=(int8_t)FETCH(); A|=RB((uint16_t)(xy->w+d)); F=0; szp_flags(A); break; }
    case 0xBE: { int8_t d=(int8_t)FETCH(); sub8(A,RB((uint16_t)(xy->w+d))); break; }
    /* 非公式: INC/DEC/LD xyH / xyL */
    case 0x24: xy->b.hi = inc8(xy->b.hi); break;
    case 0x25: xy->b.hi = dec8(xy->b.hi); break;
    case 0x26: xy->b.hi = FETCH(); break;
    case 0x2C: xy->b.lo = inc8(xy->b.lo); break;
    case 0x2D: xy->b.lo = dec8(xy->b.lo); break;
    case 0x2E: xy->b.lo = FETCH(); break;
    /* 非公式: LD r,xyH / LD r,xyL */
    case 0x44: B = xy->b.hi; break;  case 0x45: B = xy->b.lo; break;
    case 0x4C: C = xy->b.hi; break;  case 0x4D: C = xy->b.lo; break;
    case 0x54: D = xy->b.hi; break;  case 0x55: D = xy->b.lo; break;
    case 0x5C: E = xy->b.hi; break;  case 0x5D: E = xy->b.lo; break;
    case 0x7C: A = xy->b.hi; break;  case 0x7D: A = xy->b.lo; break;
    /* 非公式: LD xyH,r / LD xyL,r */
    case 0x60: xy->b.hi = B; break;  case 0x61: xy->b.hi = C; break;
    case 0x62: xy->b.hi = D; break;  case 0x63: xy->b.hi = E; break;
    case 0x64: break;                case 0x65: xy->b.hi = xy->b.lo; break;
    case 0x67: xy->b.hi = A; break;
    case 0x68: xy->b.lo = B; break;  case 0x69: xy->b.lo = C; break;
    case 0x6A: xy->b.lo = D; break;  case 0x6B: xy->b.lo = E; break;
    case 0x6C: xy->b.lo = xy->b.hi; break; case 0x6D: break;
    case 0x6F: xy->b.lo = A; break;
    /* 非公式: ALU A,xyH / ALU A,xyL */
    case 0x84: A=add8(A,xy->b.hi); break; case 0x85: A=add8(A,xy->b.lo); break;
    case 0x8C: A=adc8(A,xy->b.hi); break; case 0x8D: A=adc8(A,xy->b.lo); break;
    case 0x94: A=sub8(A,xy->b.hi); break; case 0x95: A=sub8(A,xy->b.lo); break;
    case 0x9C: A=sbc8(A,xy->b.hi); break; case 0x9D: A=sbc8(A,xy->b.lo); break;
    case 0xA4: A&=xy->b.hi; F=FLAG_H; szp_flags(A); break;
    case 0xA5: A&=xy->b.lo; F=FLAG_H; szp_flags(A); break;
    case 0xAC: A^=xy->b.hi; F=0; szp_flags(A); break;
    case 0xAD: A^=xy->b.lo; F=0; szp_flags(A); break;
    case 0xB4: A|=xy->b.hi; F=0; szp_flags(A); break;
    case 0xB5: A|=xy->b.lo; F=0; szp_flags(A); break;
    case 0xBC: sub8(A,xy->b.hi); break; case 0xBD: sub8(A,xy->b.lo); break;
    /* DDCB / FDCB プレフィックス */
    case 0xCB: {
        int8_t   d    = (int8_t)FETCH();
        uint8_t  op2  = FETCH();
        uint16_t addr = (uint16_t)(xy->w + d);
        uint8_t  val  = RB(addr);
        uint8_t  bit  = (op2 >> 3) & 7;
        uint8_t  mask = (uint8_t)(1u << bit);
        uint8_t  res  = val;
        switch (op2 >> 6) {
        case 0:
            switch (bit) {
            case 0: res=rlc8(val); break; case 1: res=rrc8(val); break;
            case 2: res=rl8(val);  break; case 3: res=rr8(val);  break;
            case 4: res=sla8(val); break; case 5: res=sra8(val); break;
            case 7: res=srl8(val); break; default: break;
            }
            WB(addr, res);
            break;
        case 1: /* BIT */
            F = (F & FLAG_C) | FLAG_H
              | (!(val & mask) ? FLAG_Z | FLAG_PV : 0)
              | (val & mask & 0x80 ? FLAG_S : 0);
            break;
        case 2: WB(addr, val & (uint8_t)~mask); break; /* RES */
        case 3: WB(addr, val | mask);            break; /* SET */
        }
        break;
    }
    default:
        /* 未知の DD/FD: プレフィックスを無視して再実行 */
        PC--;
        break;
    }
}

/* ────── メインステップ ────── */
void z80_step(void) {
    if (cpu.nmi_pending)             { handle_nmi(); return; }
    if (cpu.int_pending && cpu.iff1) { handle_int(); return; }
    if (cpu.halted) return;

    uint8_t op = FETCH();
    switch (op) {

    /* --- 制御 --- */
    case 0x00: break;                           /* NOP */
    case 0x76: cpu.halted = 1; PC--; break;     /* HALT: PC stays at HALT addr */
    case 0xF3: cpu.iff1 = cpu.iff2 = 0; break; /* DI */
    case 0xFB: cpu.iff1 = cpu.iff2 = 1; break; /* EI */

    /* --- プレフィックス --- */
    case 0xDD: exec_dd_fd(&cpu.ix); break;      /* IX プレフィックス */
    case 0xFD: exec_dd_fd(&cpu.iy); break;      /* IY プレフィックス */
    case 0xCB: exec_cb(); break;

    /* --- ED プレフィックス --- */
    case 0xED: {
        uint8_t op2 = FETCH();
        switch (op2) {
        case 0x46: cpu.im = 0; break;                        /* IM 0 */
        case 0x56: cpu.im = 1; break;                        /* IM 1 */
        case 0x5E: cpu.im = 2; break;                        /* IM 2 */
        case 0x47: cpu.i = A;  break;                        /* LD I, A */
        case 0x4F: cpu.r = A;  break;                        /* LD R, A */
        case 0x57: A = cpu.i; szp_flags(A); break;           /* LD A, I */
        case 0x5F: A = cpu.r; szp_flags(A); break;           /* LD A, R */
        case 0x44: case 0x4C: case 0x54: case 0x5C:
        case 0x64: case 0x6C: case 0x74: case 0x7C:          /* NEG (全バリアント) */
            A = sub8(0, A); break;
        case 0x4D: PC = pop16(); cpu.iff1 = cpu.iff2; break; /* RETI */
        case 0x45: case 0x55: case 0x65: case 0x75:          /* RETN (全バリアント) */
            PC = pop16(); cpu.iff1 = cpu.iff2; break;
        /* SBC HL, rr */
        case 0x42: sbc16(BC); break;
        case 0x52: sbc16(DE); break;
        case 0x62: sbc16(HL); break;
        case 0x72: sbc16(SP); break;
        /* ADC HL, rr */
        case 0x4A: adc16(BC); break;
        case 0x5A: adc16(DE); break;
        case 0x6A: adc16(HL); break;
        case 0x7A: adc16(SP); break;
        /* IN r, (C) */
        case 0x40: { uint8_t v=io_in(C); B=v; F=(F&FLAG_C)|(parity(v)?FLAG_PV:0)|(v&0x80?FLAG_S:0)|(v==0?FLAG_Z:0); break; }
        case 0x48: { uint8_t v=io_in(C); C=v; F=(F&FLAG_C)|(parity(v)?FLAG_PV:0)|(v&0x80?FLAG_S:0)|(v==0?FLAG_Z:0); break; }
        case 0x50: { uint8_t v=io_in(C); D=v; F=(F&FLAG_C)|(parity(v)?FLAG_PV:0)|(v&0x80?FLAG_S:0)|(v==0?FLAG_Z:0); break; }
        case 0x58: { uint8_t v=io_in(C); E=v; F=(F&FLAG_C)|(parity(v)?FLAG_PV:0)|(v&0x80?FLAG_S:0)|(v==0?FLAG_Z:0); break; }
        case 0x60: { uint8_t v=io_in(C); H=v; F=(F&FLAG_C)|(parity(v)?FLAG_PV:0)|(v&0x80?FLAG_S:0)|(v==0?FLAG_Z:0); break; }
        case 0x68: { uint8_t v=io_in(C); L=v; F=(F&FLAG_C)|(parity(v)?FLAG_PV:0)|(v&0x80?FLAG_S:0)|(v==0?FLAG_Z:0); break; }
        case 0x70: { uint8_t v=io_in(C);     F=(F&FLAG_C)|(parity(v)?FLAG_PV:0)|(v&0x80?FLAG_S:0)|(v==0?FLAG_Z:0); break; } /* IN F,(C) */
        case 0x78: { uint8_t v=io_in(C); A=v; F=(F&FLAG_C)|(parity(v)?FLAG_PV:0)|(v&0x80?FLAG_S:0)|(v==0?FLAG_Z:0); break; }
        /* OUT (C), r */
        case 0x41: io_out(C, B); break;
        case 0x49: io_out(C, C); break;
        case 0x51: io_out(C, D); break;
        case 0x59: io_out(C, E); break;
        case 0x61: io_out(C, H); break;
        case 0x69: io_out(C, L); break;
        case 0x71: io_out(C, 0); break;  /* OUT (C),0 (非公式) */
        case 0x79: io_out(C, A); break;
        /* ブロック転送 */
        case 0xA0: /* LDI */
            WB(DE, RB(HL)); HL++; DE++; BC--;
            F = (F & ~(FLAG_H | FLAG_N | FLAG_PV)) | (BC ? FLAG_PV : 0);
            break;
        case 0xB0: /* LDIR */
            do { WB(DE, RB(HL)); HL++; DE++; BC--; } while (BC);
            F &= ~(FLAG_H | FLAG_N | FLAG_PV);
            break;
        case 0xA8: /* LDD */
            WB(DE, RB(HL)); HL--; DE--; BC--;
            F = (F & ~(FLAG_H | FLAG_N | FLAG_PV)) | (BC ? FLAG_PV : 0);
            break;
        case 0xB8: /* LDDR */
            do { WB(DE, RB(HL)); HL--; DE--; BC--; } while (BC);
            F &= ~(FLAG_H | FLAG_N | FLAG_PV);
            break;
        /* ブロック比較 */
        case 0xA1: { /* CPI */
            uint8_t v=RB(HL); HL++; BC--;
            uint8_t r=A-v;
            F = (F&FLAG_C)|FLAG_N|(r&0x80?FLAG_S:0)|(r==0?FLAG_Z:0)|((A&0xF)<(v&0xF)?FLAG_H:0)|(BC?FLAG_PV:0);
            break;
        }
        case 0xB1: { /* CPIR */
            uint8_t zf=0;
            do {
                uint8_t v=RB(HL); HL++; BC--;
                uint8_t r=A-v;
                F = (F&FLAG_C)|FLAG_N|(r&0x80?FLAG_S:0)|(r==0?FLAG_Z:0)|((A&0xF)<(v&0xF)?FLAG_H:0)|(BC?FLAG_PV:0);
                if (r==0) { zf=1; break; }
            } while (BC);
            (void)zf;
            break;
        }
        case 0xA9: { /* CPD */
            uint8_t v=RB(HL); HL--; BC--;
            uint8_t r=A-v;
            F = (F&FLAG_C)|FLAG_N|(r&0x80?FLAG_S:0)|(r==0?FLAG_Z:0)|((A&0xF)<(v&0xF)?FLAG_H:0)|(BC?FLAG_PV:0);
            break;
        }
        case 0xB9: { /* CPDR */
            do {
                uint8_t v=RB(HL); HL--; BC--;
                uint8_t r=A-v;
                F = (F&FLAG_C)|FLAG_N|(r&0x80?FLAG_S:0)|(r==0?FLAG_Z:0)|((A&0xF)<(v&0xF)?FLAG_H:0)|(BC?FLAG_PV:0);
                if (r==0) break;
            } while (BC);
            break;
        }
        /* ブロック入出力 */
        case 0xA2: WB(HL, io_in(C)); HL++; B--; F=(F&FLAG_C)|FLAG_N|(B==0?FLAG_Z:0); break; /* INI */
        case 0xB2: do { WB(HL,io_in(C)); HL++; B--; } while(B); F=(F&FLAG_C)|FLAG_N|FLAG_Z; break; /* INIR */
        case 0xAA: WB(HL, io_in(C)); HL--; B--; F=(F&FLAG_C)|FLAG_N|(B==0?FLAG_Z:0); break; /* IND */
        case 0xBA: do { WB(HL,io_in(C)); HL--; B--; } while(B); F=(F&FLAG_C)|FLAG_N|FLAG_Z; break; /* INDR */
        case 0xA3: io_out(C,RB(HL)); HL++; B--; F=(F&FLAG_C)|FLAG_N|(B==0?FLAG_Z:0); break; /* OUTI */
        case 0xB3: do { io_out(C,RB(HL)); HL++; B--; } while(B); F=(F&FLAG_C)|FLAG_N|FLAG_Z; break; /* OTIR */
        case 0xAB: io_out(C,RB(HL)); HL--; B--; F=(F&FLAG_C)|FLAG_N|(B==0?FLAG_Z:0); break; /* OUTD */
        case 0xBB: do { io_out(C,RB(HL)); HL--; B--; } while(B); F=(F&FLAG_C)|FLAG_N|FLAG_Z; break; /* OTDR */
        /* LD (nn), rr / LD rr, (nn) */
        case 0x43: { uint16_t n=RW(PC); PC+=2; WW(n, BC); break; } /* LD (nn), BC */
        case 0x53: { uint16_t n=RW(PC); PC+=2; WW(n, DE); break; } /* LD (nn), DE */
        case 0x63: { uint16_t n=RW(PC); PC+=2; WW(n, HL); break; } /* LD (nn), HL */
        case 0x73: { uint16_t n=RW(PC); PC+=2; WW(n, SP); break; } /* LD (nn), SP */
        case 0x4B: { uint16_t n=RW(PC); PC+=2; BC=RW(n); break; }  /* LD BC, (nn) */
        case 0x5B: { uint16_t n=RW(PC); PC+=2; DE=RW(n); break; }  /* LD DE, (nn) */
        case 0x6B: { uint16_t n=RW(PC); PC+=2; HL=RW(n); break; }  /* LD HL, (nn) */
        case 0x7B: { uint16_t n=RW(PC); PC+=2; SP=RW(n); break; }  /* LD SP, (nn) */
        default: printf("[z80] unknown ED %02X @ PC=0x%04X\n", op2, PC-2); break;
        }
        break;
    }

    /* --- LD r, n --- */
    case 0x06: B = FETCH(); break;
    case 0x0E: C = FETCH(); break;
    case 0x16: D = FETCH(); break;
    case 0x1E: E = FETCH(); break;
    case 0x26: H = FETCH(); break;
    case 0x2E: L = FETCH(); break;
    case 0x36: WB(HL, FETCH()); break;   /* LD (HL), n */
    case 0x3E: A = FETCH(); break;

    /* --- LD rr, nn --- */
    case 0x01: BC = RW(PC); PC += 2; break;
    case 0x11: DE = RW(PC); PC += 2; break;
    case 0x21: HL = RW(PC); PC += 2; break;
    case 0x31: SP = RW(PC); PC += 2; break;

    /* --- LD r, r (0x40-0x7F) --- */
    case 0x40: break;              case 0x41: B = C; break;
    case 0x42: B = D; break;       case 0x43: B = E; break;
    case 0x44: B = H; break;       case 0x45: B = L; break;
    case 0x46: B = RB(HL); break;  case 0x47: B = A; break;
    case 0x48: C = B; break;       case 0x49: break;
    case 0x4A: C = D; break;       case 0x4B: C = E; break;
    case 0x4C: C = H; break;       case 0x4D: C = L; break;
    case 0x4E: C = RB(HL); break;  case 0x4F: C = A; break;
    case 0x50: D = B; break;       case 0x51: D = C; break;
    case 0x52: break;              case 0x53: D = E; break;
    case 0x54: D = H; break;       case 0x55: D = L; break;
    case 0x56: D = RB(HL); break;  case 0x57: D = A; break;
    case 0x58: E = B; break;       case 0x59: E = C; break;
    case 0x5A: E = D; break;       case 0x5B: break;
    case 0x5C: E = H; break;       case 0x5D: E = L; break;
    case 0x5E: E = RB(HL); break;  case 0x5F: E = A; break;
    case 0x60: H = B; break;       case 0x61: H = C; break;
    case 0x62: H = D; break;       case 0x63: H = E; break;
    case 0x64: break;              case 0x65: H = L; break;
    case 0x66: H = RB(HL); break;  case 0x67: H = A; break;
    case 0x68: L = B; break;       case 0x69: L = C; break;
    case 0x6A: L = D; break;       case 0x6B: L = E; break;
    case 0x6C: L = H; break;       case 0x6D: break;
    case 0x6E: L = RB(HL); break;  case 0x6F: L = A; break;
    /* LD (HL), r */
    case 0x70: WB(HL, B); break;   case 0x71: WB(HL, C); break;
    case 0x72: WB(HL, D); break;   case 0x73: WB(HL, E); break;
    case 0x74: WB(HL, H); break;   case 0x75: WB(HL, L); break;
    case 0x77: WB(HL, A); break;
    /* LD A, r */
    case 0x78: A = B; break;       case 0x79: A = C; break;
    case 0x7A: A = D; break;       case 0x7B: A = E; break;
    case 0x7C: A = H; break;       case 0x7D: A = L; break;
    case 0x7E: A = RB(HL); break;  case 0x7F: break;

    /* --- LD (rr), A / LD A, (rr) --- */
    case 0x02: WB(BC, A); break;    /* LD (BC), A */
    case 0x12: WB(DE, A); break;    /* LD (DE), A */
    case 0x0A: A = RB(BC); break;   /* LD A, (BC) */
    case 0x1A: A = RB(DE); break;   /* LD A, (DE) */
    case 0x32: { uint16_t n=RW(PC); PC+=2; WB(n, A); break; }  /* LD (nn), A */
    case 0x3A: { uint16_t n=RW(PC); PC+=2; A=RB(n);  break; }  /* LD A, (nn) */
    case 0x22: { uint16_t n=RW(PC); PC+=2; WW(n, HL); break; } /* LD (nn), HL */
    case 0x2A: { uint16_t n=RW(PC); PC+=2; HL=RW(n);  break; } /* LD HL, (nn) */
    case 0xF9: SP = HL; break;                                  /* LD SP, HL */

    /* --- INC r --- */
    case 0x04: B = inc8(B); break;  case 0x0C: C = inc8(C); break;
    case 0x14: D = inc8(D); break;  case 0x1C: E = inc8(E); break;
    case 0x24: H = inc8(H); break;  case 0x2C: L = inc8(L); break;
    case 0x34: { uint8_t t=inc8(RB(HL)); WB(HL,t); break; }
    case 0x3C: A = inc8(A); break;

    /* --- DEC r --- */
    case 0x05: B = dec8(B); break;  case 0x0D: C = dec8(C); break;
    case 0x15: D = dec8(D); break;  case 0x1D: E = dec8(E); break;
    case 0x25: H = dec8(H); break;  case 0x2D: L = dec8(L); break;
    case 0x35: { uint8_t t=dec8(RB(HL)); WB(HL,t); break; }
    case 0x3D: A = dec8(A); break;

    /* --- INC / DEC rr --- */
    case 0x03: BC++; break;  case 0x0B: BC--; break;
    case 0x13: DE++; break;  case 0x1B: DE--; break;
    case 0x23: HL++; break;  case 0x2B: HL--; break;
    case 0x33: SP++; break;  case 0x3B: SP--; break;

    /* --- ADD HL, rr --- */
    case 0x09: add_hl16(BC); break;
    case 0x19: add_hl16(DE); break;
    case 0x29: add_hl16(HL); break;
    case 0x39: add_hl16(SP); break;

    /* --- ローテーション (accumulator) --- */
    case 0x07: { uint8_t c=A>>7; A=(A<<1)|c; F=(F&~(FLAG_H|FLAG_N|FLAG_C))|(c?FLAG_C:0); break; } /* RLCA */
    case 0x0F: { uint8_t c=A&1;  A=(A>>1)|(c<<7); F=(F&~(FLAG_H|FLAG_N|FLAG_C))|(c?FLAG_C:0); break; } /* RRCA */
    case 0x17: { uint8_t c=A>>7; A=(A<<1)|((F&FLAG_C)?1:0); F=(F&~(FLAG_H|FLAG_N|FLAG_C))|(c?FLAG_C:0); break; } /* RLA */
    case 0x1F: { uint8_t c=A&1;  A=(A>>1)|(((F&FLAG_C)?1:0)<<7); F=(F&~(FLAG_H|FLAG_N|FLAG_C))|(c?FLAG_C:0); break; } /* RRA */

    /* --- 雑命令 --- */
    case 0x27: { /* DAA */
        uint8_t a = A, f = F, corr = 0;
        if ((f & FLAG_H) || (!(f & FLAG_N) && (a & 0xF)  > 9)) corr |= 0x06;
        if ((f & FLAG_C) || (!(f & FLAG_N) && a > 0x99)) { corr |= 0x60; F |= FLAG_C; }
        A = (f & FLAG_N) ? A - corr : A + corr;
        F = (F & (FLAG_C | FLAG_N))
          | (A & 0x80 ? FLAG_S : 0) | (A == 0 ? FLAG_Z : 0)
          | (parity(A) ? FLAG_PV : 0)
          | ((A ^ a) & 0x10 ? FLAG_H : 0);
        break;
    }
    case 0x2F: A = ~A; F |= (FLAG_H | FLAG_N); break;           /* CPL */
    case 0x37: F = (F & (FLAG_S|FLAG_Z|FLAG_PV)) | FLAG_C; break; /* SCF */
    case 0x3F: F = (F & (FLAG_S|FLAG_Z|FLAG_PV)) | ((F&FLAG_C)?FLAG_H:FLAG_C); break; /* CCF */
    case 0x08: { uint16_t t=cpu.af.w; cpu.af.w=cpu.af2.w; cpu.af2.w=t; break; } /* EX AF, AF' */
    case 0xD9: { /* EXX */
        uint16_t t;
        t=BC; BC=cpu.bc2.w; cpu.bc2.w=t;
        t=DE; DE=cpu.de2.w; cpu.de2.w=t;
        t=HL; HL=cpu.hl2.w; cpu.hl2.w=t;
        break;
    }
    case 0xEB: { uint16_t t=HL; HL=DE; DE=t; break; }            /* EX DE, HL */
    case 0xE3: { uint16_t t=RW(SP); WW(SP,HL); HL=t; break; }   /* EX (SP), HL */

    /* --- ALU A, n --- */
    case 0xC6: A = add8(A, FETCH()); break;               /* ADD A, n */
    case 0xCE: A = adc8(A, FETCH()); break;               /* ADC A, n */
    case 0xD6: A = sub8(A, FETCH()); break;               /* SUB n */
    case 0xDE: A = sbc8(A, FETCH()); break;               /* SBC A, n */
    case 0xE6: { uint8_t n=FETCH(); A&=n; F=FLAG_H; szp_flags(A); break; } /* AND n */
    case 0xEE: { uint8_t n=FETCH(); A^=n; F=0;      szp_flags(A); break; } /* XOR n */
    case 0xF6: { uint8_t n=FETCH(); A|=n; F=0;      szp_flags(A); break; } /* OR n */
    case 0xFE: sub8(A, FETCH()); break;                   /* CP n */

    /* --- ALU A, r (ADD 0x80-0x87) --- */
    case 0x80: A=add8(A,B); break;  case 0x81: A=add8(A,C); break;
    case 0x82: A=add8(A,D); break;  case 0x83: A=add8(A,E); break;
    case 0x84: A=add8(A,H); break;  case 0x85: A=add8(A,L); break;
    case 0x86: A=add8(A,RB(HL)); break; case 0x87: A=add8(A,A); break;
    /* ADC 0x88-0x8F */
    case 0x88: A=adc8(A,B); break;  case 0x89: A=adc8(A,C); break;
    case 0x8A: A=adc8(A,D); break;  case 0x8B: A=adc8(A,E); break;
    case 0x8C: A=adc8(A,H); break;  case 0x8D: A=adc8(A,L); break;
    case 0x8E: A=adc8(A,RB(HL)); break; case 0x8F: A=adc8(A,A); break;
    /* SUB 0x90-0x97 */
    case 0x90: A=sub8(A,B); break;  case 0x91: A=sub8(A,C); break;
    case 0x92: A=sub8(A,D); break;  case 0x93: A=sub8(A,E); break;
    case 0x94: A=sub8(A,H); break;  case 0x95: A=sub8(A,L); break;
    case 0x96: A=sub8(A,RB(HL)); break; case 0x97: A=sub8(A,A); break;
    /* SBC 0x98-0x9F */
    case 0x98: A=sbc8(A,B); break;  case 0x99: A=sbc8(A,C); break;
    case 0x9A: A=sbc8(A,D); break;  case 0x9B: A=sbc8(A,E); break;
    case 0x9C: A=sbc8(A,H); break;  case 0x9D: A=sbc8(A,L); break;
    case 0x9E: A=sbc8(A,RB(HL)); break; case 0x9F: A=sbc8(A,A); break;
    /* AND 0xA0-0xA7 */
    case 0xA0: A&=B; F=FLAG_H; szp_flags(A); break;
    case 0xA1: A&=C; F=FLAG_H; szp_flags(A); break;
    case 0xA2: A&=D; F=FLAG_H; szp_flags(A); break;
    case 0xA3: A&=E; F=FLAG_H; szp_flags(A); break;
    case 0xA4: A&=H; F=FLAG_H; szp_flags(A); break;
    case 0xA5: A&=L; F=FLAG_H; szp_flags(A); break;
    case 0xA6: A&=RB(HL); F=FLAG_H; szp_flags(A); break;
    case 0xA7: A&=A; F=FLAG_H; szp_flags(A); break;
    /* XOR 0xA8-0xAF */
    case 0xA8: A^=B; F=0; szp_flags(A); break;
    case 0xA9: A^=C; F=0; szp_flags(A); break;
    case 0xAA: A^=D; F=0; szp_flags(A); break;
    case 0xAB: A^=E; F=0; szp_flags(A); break;
    case 0xAC: A^=H; F=0; szp_flags(A); break;
    case 0xAD: A^=L; F=0; szp_flags(A); break;
    case 0xAE: A^=RB(HL); F=0; szp_flags(A); break;
    case 0xAF: A^=A; F=FLAG_Z; break;                    /* XOR A */
    /* OR 0xB0-0xB7 */
    case 0xB0: A|=B; F=0; szp_flags(A); break;
    case 0xB1: A|=C; F=0; szp_flags(A); break;
    case 0xB2: A|=D; F=0; szp_flags(A); break;
    case 0xB3: A|=E; F=0; szp_flags(A); break;
    case 0xB4: A|=H; F=0; szp_flags(A); break;
    case 0xB5: A|=L; F=0; szp_flags(A); break;
    case 0xB6: A|=RB(HL); F=0; szp_flags(A); break;
    case 0xB7: A|=A; F=0; szp_flags(A); break;
    /* CP 0xB8-0xBF */
    case 0xB8: sub8(A,B); break;    case 0xB9: sub8(A,C); break;
    case 0xBA: sub8(A,D); break;    case 0xBB: sub8(A,E); break;
    case 0xBC: sub8(A,H); break;    case 0xBD: sub8(A,L); break;
    case 0xBE: sub8(A,RB(HL)); break; case 0xBF: sub8(A,A); break;

    /* --- ジャンプ --- */
    case 0xC3: { uint16_t n=RW(PC); PC=n; break; }
    case 0xC2: { uint16_t n=RW(PC); if(!(F&FLAG_Z)) PC=n; else PC+=2; break; } /* JP NZ */
    case 0xCA: { uint16_t n=RW(PC); if( (F&FLAG_Z)) PC=n; else PC+=2; break; } /* JP Z  */
    case 0xD2: { uint16_t n=RW(PC); if(!(F&FLAG_C)) PC=n; else PC+=2; break; } /* JP NC */
    case 0xDA: { uint16_t n=RW(PC); if( (F&FLAG_C)) PC=n; else PC+=2; break; } /* JP C  */
    case 0xE2: { uint16_t n=RW(PC); if(!(F&FLAG_PV))PC=n; else PC+=2; break; } /* JP PO */
    case 0xEA: { uint16_t n=RW(PC); if( (F&FLAG_PV))PC=n; else PC+=2; break; } /* JP PE */
    case 0xF2: { uint16_t n=RW(PC); if(!(F&FLAG_S)) PC=n; else PC+=2; break; } /* JP P  */
    case 0xFA: { uint16_t n=RW(PC); if( (F&FLAG_S)) PC=n; else PC+=2; break; } /* JP M  */
    case 0xE9: PC = HL; break;                                                  /* JP (HL) */

    case 0x18: { int8_t e=(int8_t)FETCH(); PC+=e; break; }                      /* JR */
    case 0x20: { int8_t e=(int8_t)FETCH(); if(!(F&FLAG_Z)) PC+=e; break; }     /* JR NZ */
    case 0x28: { int8_t e=(int8_t)FETCH(); if( (F&FLAG_Z)) PC+=e; break; }     /* JR Z  */
    case 0x30: { int8_t e=(int8_t)FETCH(); if(!(F&FLAG_C)) PC+=e; break; }     /* JR NC */
    case 0x38: { int8_t e=(int8_t)FETCH(); if( (F&FLAG_C)) PC+=e; break; }     /* JR C  */
    case 0x10: { int8_t e=(int8_t)FETCH(); if(--B) PC+=e; break; }             /* DJNZ */

    /* --- CALL / RET --- */
    case 0xCD: { uint16_t n=RW(PC); PC+=2; push16(PC); PC=n; break; }          /* CALL */
    case 0xC4: { uint16_t n=RW(PC); PC+=2; if(!(F&FLAG_Z)){push16(PC);PC=n;} break; } /* CALL NZ */
    case 0xCC: { uint16_t n=RW(PC); PC+=2; if( (F&FLAG_Z)){push16(PC);PC=n;} break; } /* CALL Z  */
    case 0xD4: { uint16_t n=RW(PC); PC+=2; if(!(F&FLAG_C)){push16(PC);PC=n;} break; } /* CALL NC */
    case 0xDC: { uint16_t n=RW(PC); PC+=2; if( (F&FLAG_C)){push16(PC);PC=n;} break; } /* CALL C  */
    case 0xE4: { uint16_t n=RW(PC); PC+=2; if(!(F&FLAG_PV)){push16(PC);PC=n;} break; }/* CALL PO */
    case 0xEC: { uint16_t n=RW(PC); PC+=2; if( (F&FLAG_PV)){push16(PC);PC=n;} break; }/* CALL PE */
    case 0xF4: { uint16_t n=RW(PC); PC+=2; if(!(F&FLAG_S)){push16(PC);PC=n;} break; } /* CALL P  */
    case 0xFC: { uint16_t n=RW(PC); PC+=2; if( (F&FLAG_S)){push16(PC);PC=n;} break; } /* CALL M  */
    case 0xC9: PC=pop16(); break;                                                /* RET */
    case 0xC0: if(!(F&FLAG_Z)) PC=pop16(); break;  /* RET NZ */
    case 0xC8: if( (F&FLAG_Z)) PC=pop16(); break;  /* RET Z  */
    case 0xD0: if(!(F&FLAG_C)) PC=pop16(); break;  /* RET NC */
    case 0xD8: if( (F&FLAG_C)) PC=pop16(); break;  /* RET C  */
    case 0xE0: if(!(F&FLAG_PV))PC=pop16(); break;  /* RET PO */
    case 0xE8: if( (F&FLAG_PV))PC=pop16(); break;  /* RET PE */
    case 0xF0: if(!(F&FLAG_S)) PC=pop16(); break;  /* RET P  */
    case 0xF8: if( (F&FLAG_S)) PC=pop16(); break;  /* RET M  */

    /* --- PUSH / POP --- */
    case 0xC5: push16(BC); break;        case 0xC1: BC=pop16(); break;
    case 0xD5: push16(DE); break;        case 0xD1: DE=pop16(); break;
    case 0xE5: push16(HL); break;        case 0xE1: HL=pop16(); break;
    case 0xF5: push16(cpu.af.w); break;  case 0xF1: cpu.af.w=pop16(); break;

    /* --- RST --- */
    case 0xC7: push16(PC); PC=0x00; break;
    case 0xCF: push16(PC); PC=0x08; break;
    case 0xD7: push16(PC); PC=0x10; break;
    case 0xDF: push16(PC); PC=0x18; break;
    case 0xE7: push16(PC); PC=0x20; break;
    case 0xEF: push16(PC); PC=0x28; break;
    case 0xF7: push16(PC); PC=0x30; break;
    case 0xFF: push16(PC); PC=0x38; break;

    /* --- I/O --- */
    case 0xDB: { uint8_t p=FETCH(); A=io_in(p);   break; } /* IN A, (n)  */
    case 0xD3: { uint8_t p=FETCH(); io_out(p, A); break; } /* OUT (n), A */

    default:
        printf("[z80] unknown opcode 0x%02X @ PC=0x%04X\n", op, PC-1);
        cpu.halted = 1;
        break;
    }
}
