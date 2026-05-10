#include <stdio.h>
#include <string.h>
#include "z80.h"
#include "z80_dis.h"

/* ────── テーブル ────── */
static const char *r8[8]    = {"B","C","D","E","H","L","(HL)","A"};
static const char *r16[4]   = {"BC","DE","HL","SP"};
static const char *r16af[4] = {"BC","DE","HL","AF"};
static const char *alu[8]   = {"ADD A,","ADC A,","SUB ","SBC A,","AND ","XOR ","OR ","CP "};
static const char *rot[8]   = {"RLC","RRC","RL","RR","SLA","SRA","SL1","SRL"};
static const char *cc[8]    = {"NZ","Z","NC","C","PO","PE","P","M"};

/* ────── ヘルパ ────── */
static uint16_t rw(uint16_t a) {
    return (uint16_t)(mem[a] | (mem[(uint16_t)(a+1)] << 8));
}

/* ────── DD/FD プレフィックス ────── */
static int dis_dd_fd(uint16_t addr, char *buf, size_t sz, const char *xy) {
    uint8_t op = mem[(uint16_t)(addr+1)];
    uint8_t n1 = mem[(uint16_t)(addr+2)];
    uint8_t n2 = mem[(uint16_t)(addr+3)];
    uint16_t nn = (uint16_t)(n1|(n2<<8));
    int8_t   d  = (int8_t)n1;   /* displacement (for most) */

    switch (op) {
    case 0x21: snprintf(buf,sz,"LD %s,0x%04X",xy,nn); return 4;
    case 0x22: snprintf(buf,sz,"LD (0x%04X),%s",nn,xy); return 4;
    case 0x2A: snprintf(buf,sz,"LD %s,(0x%04X)",xy,nn); return 4;
    case 0x09: snprintf(buf,sz,"ADD %s,BC",xy); return 2;
    case 0x19: snprintf(buf,sz,"ADD %s,DE",xy); return 2;
    case 0x29: snprintf(buf,sz,"ADD %s,%s",xy,xy); return 2;
    case 0x39: snprintf(buf,sz,"ADD %s,SP",xy); return 2;
    case 0x23: snprintf(buf,sz,"INC %s",xy); return 2;
    case 0x2B: snprintf(buf,sz,"DEC %s",xy); return 2;
    case 0xE5: snprintf(buf,sz,"PUSH %s",xy); return 2;
    case 0xE1: snprintf(buf,sz,"POP %s",xy);  return 2;
    case 0xE9: snprintf(buf,sz,"JP (%s)",xy);  return 2;
    case 0xE3: snprintf(buf,sz,"EX (SP),%s",xy); return 2;
    case 0xF9: snprintf(buf,sz,"LD SP,%s",xy); return 2;
    case 0x34: snprintf(buf,sz,"INC (%s%+d)",xy,(int)d); return 3;
    case 0x35: snprintf(buf,sz,"DEC (%s%+d)",xy,(int)d); return 3;
    case 0x36: snprintf(buf,sz,"LD (%s%+d),0x%02X",xy,(int)d,n2); return 4;
    case 0x46: snprintf(buf,sz,"LD B,(%s%+d)",xy,(int)d); return 3;
    case 0x4E: snprintf(buf,sz,"LD C,(%s%+d)",xy,(int)d); return 3;
    case 0x56: snprintf(buf,sz,"LD D,(%s%+d)",xy,(int)d); return 3;
    case 0x5E: snprintf(buf,sz,"LD E,(%s%+d)",xy,(int)d); return 3;
    case 0x66: snprintf(buf,sz,"LD H,(%s%+d)",xy,(int)d); return 3;
    case 0x6E: snprintf(buf,sz,"LD L,(%s%+d)",xy,(int)d); return 3;
    case 0x7E: snprintf(buf,sz,"LD A,(%s%+d)",xy,(int)d); return 3;
    case 0x70: snprintf(buf,sz,"LD (%s%+d),B",xy,(int)d); return 3;
    case 0x71: snprintf(buf,sz,"LD (%s%+d),C",xy,(int)d); return 3;
    case 0x72: snprintf(buf,sz,"LD (%s%+d),D",xy,(int)d); return 3;
    case 0x73: snprintf(buf,sz,"LD (%s%+d),E",xy,(int)d); return 3;
    case 0x74: snprintf(buf,sz,"LD (%s%+d),H",xy,(int)d); return 3;
    case 0x75: snprintf(buf,sz,"LD (%s%+d),L",xy,(int)d); return 3;
    case 0x77: snprintf(buf,sz,"LD (%s%+d),A",xy,(int)d); return 3;
    case 0x86: snprintf(buf,sz,"ADD A,(%s%+d)",xy,(int)d); return 3;
    case 0x8E: snprintf(buf,sz,"ADC A,(%s%+d)",xy,(int)d); return 3;
    case 0x96: snprintf(buf,sz,"SUB (%s%+d)",xy,(int)d);   return 3;
    case 0x9E: snprintf(buf,sz,"SBC A,(%s%+d)",xy,(int)d); return 3;
    case 0xA6: snprintf(buf,sz,"AND (%s%+d)",xy,(int)d);   return 3;
    case 0xAE: snprintf(buf,sz,"XOR (%s%+d)",xy,(int)d);   return 3;
    case 0xB6: snprintf(buf,sz,"OR (%s%+d)",xy,(int)d);    return 3;
    case 0xBE: snprintf(buf,sz,"CP (%s%+d)",xy,(int)d);    return 3;
    case 0xCB: { /* DDCB / FDCB */
        int8_t  cd = (int8_t)n1;
        uint8_t co = n2;
        int b = (co>>3)&7;
        switch(co>>6) {
        case 0: snprintf(buf,sz,"%s (%s%+d)",rot[b],xy,(int)cd); break;
        case 1: snprintf(buf,sz,"BIT %d,(%s%+d)",b,xy,(int)cd); break;
        case 2: snprintf(buf,sz,"RES %d,(%s%+d)",b,xy,(int)cd); break;
        case 3: snprintf(buf,sz,"SET %d,(%s%+d)",b,xy,(int)cd); break;
        }
        return 4;
    }
    default: snprintf(buf,sz,"%s?? %02X",xy,op); return 2;
    }
}

/* ────── z80_disasm ────── */
int z80_disasm(uint16_t addr, char *buf, size_t sz) {
    uint8_t  op = mem[addr];
    uint8_t  n1 = mem[(uint16_t)(addr+1)];
    uint8_t  n2 = mem[(uint16_t)(addr+2)];
    uint16_t nn = (uint16_t)(n1 | (n2 << 8));
    int8_t   e  = (int8_t)n1;

    /* --- DD/FD プレフィックス (IX/IY) --- */
    if (op == 0xDD) return dis_dd_fd(addr, buf, sz, "IX");
    if (op == 0xFD) return dis_dd_fd(addr, buf, sz, "IY");

    /* --- CB プレフィックス --- */
    if (op == 0xCB) {
        uint8_t cb = n1;
        int b = (cb >> 3) & 7, r = cb & 7;
        switch (cb >> 6) {
        case 0: snprintf(buf, sz, "%s %s",     rot[b], r8[r]); break;
        case 1: snprintf(buf, sz, "BIT %d,%s", b, r8[r]); break;
        case 2: snprintf(buf, sz, "RES %d,%s", b, r8[r]); break;
        case 3: snprintf(buf, sz, "SET %d,%s", b, r8[r]); break;
        }
        return 2;
    }

    /* --- ED プレフィックス --- */
    if (op == 0xED) {
        switch (n1) {
        case 0x46: snprintf(buf, sz, "IM 0"); return 2;
        case 0x56: snprintf(buf, sz, "IM 1"); return 2;
        case 0x5E: snprintf(buf, sz, "IM 2"); return 2;
        case 0x47: snprintf(buf, sz, "LD I,A"); return 2;
        case 0x4F: snprintf(buf, sz, "LD R,A"); return 2;
        case 0x57: snprintf(buf, sz, "LD A,I"); return 2;
        case 0x5F: snprintf(buf, sz, "LD A,R"); return 2;
        case 0x44: snprintf(buf, sz, "NEG");   return 2;
        case 0x4D: snprintf(buf, sz, "RETI");  return 2;
        case 0x45: snprintf(buf, sz, "RETN");  return 2;
        case 0x42: snprintf(buf, sz, "SBC HL,BC"); return 2;
        case 0x52: snprintf(buf, sz, "SBC HL,DE"); return 2;
        case 0x62: snprintf(buf, sz, "SBC HL,HL"); return 2;
        case 0x72: snprintf(buf, sz, "SBC HL,SP"); return 2;
        case 0x4A: snprintf(buf, sz, "ADC HL,BC"); return 2;
        case 0x5A: snprintf(buf, sz, "ADC HL,DE"); return 2;
        case 0x6A: snprintf(buf, sz, "ADC HL,HL"); return 2;
        case 0x7A: snprintf(buf, sz, "ADC HL,SP"); return 2;
        case 0x40: snprintf(buf, sz, "IN B,(C)");  return 2;
        case 0x48: snprintf(buf, sz, "IN C,(C)");  return 2;
        case 0x50: snprintf(buf, sz, "IN D,(C)");  return 2;
        case 0x58: snprintf(buf, sz, "IN E,(C)");  return 2;
        case 0x60: snprintf(buf, sz, "IN H,(C)");  return 2;
        case 0x68: snprintf(buf, sz, "IN L,(C)");  return 2;
        case 0x70: snprintf(buf, sz, "IN F,(C)");  return 2;
        case 0x78: snprintf(buf, sz, "IN A,(C)");  return 2;
        case 0x41: snprintf(buf, sz, "OUT (C),B"); return 2;
        case 0x49: snprintf(buf, sz, "OUT (C),C"); return 2;
        case 0x51: snprintf(buf, sz, "OUT (C),D"); return 2;
        case 0x59: snprintf(buf, sz, "OUT (C),E"); return 2;
        case 0x61: snprintf(buf, sz, "OUT (C),H"); return 2;
        case 0x69: snprintf(buf, sz, "OUT (C),L"); return 2;
        case 0x79: snprintf(buf, sz, "OUT (C),A"); return 2;
        case 0xA0: snprintf(buf, sz, "LDI");  return 2;
        case 0xA8: snprintf(buf, sz, "LDD");  return 2;
        case 0xB0: snprintf(buf, sz, "LDIR"); return 2;
        case 0xB8: snprintf(buf, sz, "LDDR"); return 2;
        case 0xA1: snprintf(buf, sz, "CPI");  return 2;
        case 0xA9: snprintf(buf, sz, "CPD");  return 2;
        case 0xB1: snprintf(buf, sz, "CPIR"); return 2;
        case 0xB9: snprintf(buf, sz, "CPDR"); return 2;
        case 0xA2: snprintf(buf, sz, "INI");  return 2;
        case 0xB2: snprintf(buf, sz, "INIR"); return 2;
        case 0xAA: snprintf(buf, sz, "IND");  return 2;
        case 0xBA: snprintf(buf, sz, "INDR"); return 2;
        case 0xA3: snprintf(buf, sz, "OUTI"); return 2;
        case 0xB3: snprintf(buf, sz, "OTIR"); return 2;
        case 0xAB: snprintf(buf, sz, "OUTD"); return 2;
        case 0xBB: snprintf(buf, sz, "OTDR"); return 2;
        /* LD (nn), rr */
        case 0x43: snprintf(buf, sz, "LD (0x%04X),BC", rw(addr+2)); return 4;
        case 0x53: snprintf(buf, sz, "LD (0x%04X),DE", rw(addr+2)); return 4;
        case 0x63: snprintf(buf, sz, "LD (0x%04X),HL", rw(addr+2)); return 4;
        case 0x73: snprintf(buf, sz, "LD (0x%04X),SP", rw(addr+2)); return 4;
        case 0x4B: snprintf(buf, sz, "LD BC,(0x%04X)", rw(addr+2)); return 4;
        case 0x5B: snprintf(buf, sz, "LD DE,(0x%04X)", rw(addr+2)); return 4;
        case 0x6B: snprintf(buf, sz, "LD HL,(0x%04X)", rw(addr+2)); return 4;
        case 0x7B: snprintf(buf, sz, "LD SP,(0x%04X)", rw(addr+2)); return 4;
        default:   snprintf(buf, sz, "ED %02X", n1); return 2;
        }
    }

    /* --- LD r, r  (0x40-0x7F, 0x76=HALT を除く) --- */
    if (op >= 0x40 && op <= 0x7F && op != 0x76) {
        snprintf(buf, sz, "LD %s,%s", r8[(op>>3)&7], r8[op&7]);
        return 1;
    }

    /* --- ALU A, r  (0x80-0xBF) --- */
    if (op >= 0x80 && op <= 0xBF) {
        snprintf(buf, sz, "%s%s", alu[(op>>3)&7], r8[op&7]);
        return 1;
    }

    /* --- その他 --- */
    switch (op) {
    /* 制御 */
    case 0x00: snprintf(buf, sz, "NOP");      return 1;
    case 0x76: snprintf(buf, sz, "HALT");     return 1;
    case 0xF3: snprintf(buf, sz, "DI");       return 1;
    case 0xFB: snprintf(buf, sz, "EI");       return 1;
    case 0x07: snprintf(buf, sz, "RLCA");     return 1;
    case 0x0F: snprintf(buf, sz, "RRCA");     return 1;
    case 0x17: snprintf(buf, sz, "RLA");      return 1;
    case 0x1F: snprintf(buf, sz, "RRA");      return 1;
    case 0x27: snprintf(buf, sz, "DAA");      return 1;
    case 0x2F: snprintf(buf, sz, "CPL");      return 1;
    case 0x37: snprintf(buf, sz, "SCF");      return 1;
    case 0x3F: snprintf(buf, sz, "CCF");      return 1;
    case 0x08: snprintf(buf, sz, "EX AF,AF'");return 1;
    case 0xD9: snprintf(buf, sz, "EXX");      return 1;
    case 0xEB: snprintf(buf, sz, "EX DE,HL"); return 1;
    case 0xE3: snprintf(buf, sz, "EX (SP),HL");return 1;
    case 0xF9: snprintf(buf, sz, "LD SP,HL"); return 1;

    /* LD r, n */
    case 0x06: snprintf(buf, sz, "LD B,0x%02X",   n1); return 2;
    case 0x0E: snprintf(buf, sz, "LD C,0x%02X",   n1); return 2;
    case 0x16: snprintf(buf, sz, "LD D,0x%02X",   n1); return 2;
    case 0x1E: snprintf(buf, sz, "LD E,0x%02X",   n1); return 2;
    case 0x26: snprintf(buf, sz, "LD H,0x%02X",   n1); return 2;
    case 0x2E: snprintf(buf, sz, "LD L,0x%02X",   n1); return 2;
    case 0x36: snprintf(buf, sz, "LD (HL),0x%02X",n1); return 2;
    case 0x3E: snprintf(buf, sz, "LD A,0x%02X",   n1); return 2;

    /* LD rr, nn */
    case 0x01: snprintf(buf, sz, "LD BC,0x%04X", nn); return 3;
    case 0x11: snprintf(buf, sz, "LD DE,0x%04X", nn); return 3;
    case 0x21: snprintf(buf, sz, "LD HL,0x%04X", nn); return 3;
    case 0x31: snprintf(buf, sz, "LD SP,0x%04X", nn); return 3;

    /* LD メモリ */
    case 0x02: snprintf(buf, sz, "LD (BC),A");           return 1;
    case 0x12: snprintf(buf, sz, "LD (DE),A");           return 1;
    case 0x0A: snprintf(buf, sz, "LD A,(BC)");           return 1;
    case 0x1A: snprintf(buf, sz, "LD A,(DE)");           return 1;
    case 0x32: snprintf(buf, sz, "LD (0x%04X),A",  nn);  return 3;
    case 0x3A: snprintf(buf, sz, "LD A,(0x%04X)",  nn);  return 3;
    case 0x22: snprintf(buf, sz, "LD (0x%04X),HL", nn);  return 3;
    case 0x2A: snprintf(buf, sz, "LD HL,(0x%04X)", nn);  return 3;

    /* INC r */
    case 0x04: snprintf(buf, sz, "INC B");    return 1;
    case 0x0C: snprintf(buf, sz, "INC C");    return 1;
    case 0x14: snprintf(buf, sz, "INC D");    return 1;
    case 0x1C: snprintf(buf, sz, "INC E");    return 1;
    case 0x24: snprintf(buf, sz, "INC H");    return 1;
    case 0x2C: snprintf(buf, sz, "INC L");    return 1;
    case 0x34: snprintf(buf, sz, "INC (HL)"); return 1;
    case 0x3C: snprintf(buf, sz, "INC A");    return 1;
    /* DEC r */
    case 0x05: snprintf(buf, sz, "DEC B");    return 1;
    case 0x0D: snprintf(buf, sz, "DEC C");    return 1;
    case 0x15: snprintf(buf, sz, "DEC D");    return 1;
    case 0x1D: snprintf(buf, sz, "DEC E");    return 1;
    case 0x25: snprintf(buf, sz, "DEC H");    return 1;
    case 0x2D: snprintf(buf, sz, "DEC L");    return 1;
    case 0x35: snprintf(buf, sz, "DEC (HL)"); return 1;
    case 0x3D: snprintf(buf, sz, "DEC A");    return 1;
    /* INC/DEC rr */
    case 0x03: snprintf(buf, sz, "INC BC"); return 1;
    case 0x0B: snprintf(buf, sz, "DEC BC"); return 1;
    case 0x13: snprintf(buf, sz, "INC DE"); return 1;
    case 0x1B: snprintf(buf, sz, "DEC DE"); return 1;
    case 0x23: snprintf(buf, sz, "INC HL"); return 1;
    case 0x2B: snprintf(buf, sz, "DEC HL"); return 1;
    case 0x33: snprintf(buf, sz, "INC SP"); return 1;
    case 0x3B: snprintf(buf, sz, "DEC SP"); return 1;
    /* ADD HL, rr */
    case 0x09: snprintf(buf, sz, "ADD HL,BC"); return 1;
    case 0x19: snprintf(buf, sz, "ADD HL,DE"); return 1;
    case 0x29: snprintf(buf, sz, "ADD HL,HL"); return 1;
    case 0x39: snprintf(buf, sz, "ADD HL,SP"); return 1;

    /* ALU A, n */
    case 0xC6: snprintf(buf, sz, "ADD A,0x%02X", n1); return 2;
    case 0xCE: snprintf(buf, sz, "ADC A,0x%02X", n1); return 2;
    case 0xD6: snprintf(buf, sz, "SUB 0x%02X",   n1); return 2;
    case 0xDE: snprintf(buf, sz, "SBC A,0x%02X", n1); return 2;
    case 0xE6: snprintf(buf, sz, "AND 0x%02X",   n1); return 2;
    case 0xEE: snprintf(buf, sz, "XOR 0x%02X",   n1); return 2;
    case 0xF6: snprintf(buf, sz, "OR 0x%02X",    n1); return 2;
    case 0xFE: snprintf(buf, sz, "CP 0x%02X",    n1); return 2;

    /* JP 絶対 */
    case 0xC3: snprintf(buf, sz, "JP 0x%04X",     nn); return 3;
    case 0xC2: snprintf(buf, sz, "JP NZ,0x%04X",  nn); return 3;
    case 0xCA: snprintf(buf, sz, "JP Z,0x%04X",   nn); return 3;
    case 0xD2: snprintf(buf, sz, "JP NC,0x%04X",  nn); return 3;
    case 0xDA: snprintf(buf, sz, "JP C,0x%04X",   nn); return 3;
    case 0xE2: snprintf(buf, sz, "JP PO,0x%04X",  nn); return 3;
    case 0xEA: snprintf(buf, sz, "JP PE,0x%04X",  nn); return 3;
    case 0xF2: snprintf(buf, sz, "JP P,0x%04X",   nn); return 3;
    case 0xFA: snprintf(buf, sz, "JP M,0x%04X",   nn); return 3;
    case 0xE9: snprintf(buf, sz, "JP (HL)");            return 1;

    /* JR 相対 (ターゲットアドレスを表示) */
    case 0x18: snprintf(buf, sz, "JR 0x%04X",    (uint16_t)(addr+2+e)); return 2;
    case 0x20: snprintf(buf, sz, "JR NZ,0x%04X", (uint16_t)(addr+2+e)); return 2;
    case 0x28: snprintf(buf, sz, "JR Z,0x%04X",  (uint16_t)(addr+2+e)); return 2;
    case 0x30: snprintf(buf, sz, "JR NC,0x%04X", (uint16_t)(addr+2+e)); return 2;
    case 0x38: snprintf(buf, sz, "JR C,0x%04X",  (uint16_t)(addr+2+e)); return 2;
    case 0x10: snprintf(buf, sz, "DJNZ 0x%04X",  (uint16_t)(addr+2+e)); return 2;

    /* CALL */
    case 0xCD: snprintf(buf, sz, "CALL 0x%04X",     nn); return 3;
    case 0xC4: snprintf(buf, sz, "CALL NZ,0x%04X",  nn); return 3;
    case 0xCC: snprintf(buf, sz, "CALL Z,0x%04X",   nn); return 3;
    case 0xD4: snprintf(buf, sz, "CALL NC,0x%04X",  nn); return 3;
    case 0xDC: snprintf(buf, sz, "CALL C,0x%04X",   nn); return 3;
    case 0xE4: snprintf(buf, sz, "CALL PO,0x%04X",  nn); return 3;
    case 0xEC: snprintf(buf, sz, "CALL PE,0x%04X",  nn); return 3;
    case 0xF4: snprintf(buf, sz, "CALL P,0x%04X",   nn); return 3;
    case 0xFC: snprintf(buf, sz, "CALL M,0x%04X",   nn); return 3;

    /* RET */
    case 0xC9: snprintf(buf, sz, "RET");    return 1;
    case 0xC0: snprintf(buf, sz, "RET NZ"); return 1;
    case 0xC8: snprintf(buf, sz, "RET Z");  return 1;
    case 0xD0: snprintf(buf, sz, "RET NC"); return 1;
    case 0xD8: snprintf(buf, sz, "RET C");  return 1;
    case 0xE0: snprintf(buf, sz, "RET PO"); return 1;
    case 0xE8: snprintf(buf, sz, "RET PE"); return 1;
    case 0xF0: snprintf(buf, sz, "RET P");  return 1;
    case 0xF8: snprintf(buf, sz, "RET M");  return 1;

    /* PUSH / POP */
    case 0xC5: snprintf(buf, sz, "PUSH BC"); return 1;
    case 0xD5: snprintf(buf, sz, "PUSH DE"); return 1;
    case 0xE5: snprintf(buf, sz, "PUSH HL"); return 1;
    case 0xF5: snprintf(buf, sz, "PUSH AF"); return 1;
    case 0xC1: snprintf(buf, sz, "POP BC");  return 1;
    case 0xD1: snprintf(buf, sz, "POP DE");  return 1;
    case 0xE1: snprintf(buf, sz, "POP HL");  return 1;
    case 0xF1: snprintf(buf, sz, "POP AF");  return 1;

    /* RST */
    case 0xC7: snprintf(buf, sz, "RST 00H"); return 1;
    case 0xCF: snprintf(buf, sz, "RST 08H"); return 1;
    case 0xD7: snprintf(buf, sz, "RST 10H"); return 1;
    case 0xDF: snprintf(buf, sz, "RST 18H"); return 1;
    case 0xE7: snprintf(buf, sz, "RST 20H"); return 1;
    case 0xEF: snprintf(buf, sz, "RST 28H"); return 1;
    case 0xF7: snprintf(buf, sz, "RST 30H"); return 1;
    case 0xFF: snprintf(buf, sz, "RST 38H"); return 1;

    /* I/O */
    case 0xDB: snprintf(buf, sz, "IN A,(0x%02X)",  n1); return 2;
    case 0xD3: snprintf(buf, sz, "OUT (0x%02X),A", n1); return 2;

    default:
        snprintf(buf, sz, "??? %02X", op);
        return 1;
    }

    /* suppress unused-variable warnings */
    (void)r16; (void)r16af; (void)cc;
    return 1;
}

/* ────── z80_print_state ────── */
void z80_print_state(void) {
    uint8_t f = cpu.af.b.lo;
    /* フラグ文字列: S Z - H - V N C */
    char fs[9];
    fs[0] = (f & FLAG_S)  ? 'S' : '.';
    fs[1] = (f & FLAG_Z)  ? 'Z' : '.';
    fs[2] = '-';
    fs[3] = (f & FLAG_H)  ? 'H' : '.';
    fs[4] = '-';
    fs[5] = (f & FLAG_PV) ? 'V' : '.';
    fs[6] = (f & FLAG_N)  ? 'N' : '.';
    fs[7] = (f & FLAG_C)  ? 'C' : '.';
    fs[8] = '\0';

    printf("  A=%02X  F=[%s]  BC=%04X  DE=%04X  HL=%04X"
           "  IX=%04X  IY=%04X  SP=%04X  PC=%04X\n",
           cpu.af.b.hi, fs,
           cpu.bc.w, cpu.de.w, cpu.hl.w,
           cpu.ix.w, cpu.iy.w, cpu.sp.w, cpu.pc.w);
    printf("  AF'=%04X BC'=%04X DE'=%04X HL'=%04X"
           "  I=%02X R=%02X  IFF=%d/%d  IM=%d\n",
           cpu.af2.w, cpu.bc2.w, cpu.de2.w, cpu.hl2.w,
           cpu.i, cpu.r,
           cpu.iff1, cpu.iff2, cpu.im);
}
