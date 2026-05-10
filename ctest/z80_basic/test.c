#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "z80.h"

/* ────── テストフレームワーク ────── */
static int g_pass = 0, g_fail = 0;
static const char *g_suite = "";

static void suite(const char *name) { g_suite = name; }

static void check(const char *name, int cond) {
    if (cond) {
        g_pass++;
    } else {
        printf("  FAIL [%s] %s\n", g_suite, name);
        g_fail++;
    }
}

/* CPU セットアップ & 実行 */
static void run(const uint8_t *code, size_t len, int max_steps) {
    memset(mem, 0, sizeof mem);
    memcpy(mem, code, len);
    z80_reset();
    SP = 0xDFFE;
    for (int i = 0; i < max_steps && !cpu.halted; i++)
        z80_step();
}

/* ────── LD r, n ────── */
static void test_ld_r_n(void) {
    suite("LD r,n");
    static const uint8_t c[] = {
        0x3E,0x12, /* LD A,0x12 */
        0x06,0x34, /* LD B,0x34 */
        0x0E,0x56, /* LD C,0x56 */
        0x16,0x78, /* LD D,0x78 */
        0x1E,0x9A, /* LD E,0x9A */
        0x26,0xBC, /* LD H,0xBC */
        0x2E,0xDE, /* LD L,0xDE */
        0x76
    };
    run(c, sizeof c, 20);
    check("A=0x12", A == 0x12);
    check("B=0x34", B == 0x34);
    check("C=0x56", C == 0x56);
    check("D=0x78", D == 0x78);
    check("E=0x9A", E == 0x9A);
    check("H=0xBC", H == 0xBC);
    check("L=0xDE", L == 0xDE);
}

/* ────── LD r, r ────── */
static void test_ld_r_r(void) {
    suite("LD r,r");
    static const uint8_t c[] = {
        0x3E,0x42, /* LD A,0x42 */
        0x47,      /* LD B,A    */
        0x48,      /* LD C,B    */
        0x51,      /* LD D,C    */
        0x5A,      /* LD E,D    */
        0x63,      /* LD H,E    */
        0x6C,      /* LD L,H    */
        0x7D,      /* LD A,L    */
        0x76
    };
    run(c, sizeof c, 20);
    check("B=0x42", B == 0x42);
    check("C=0x42", C == 0x42);
    check("D=0x42", D == 0x42);
    check("E=0x42", E == 0x42);
    check("H=0x42", H == 0x42);
    check("L=0x42", L == 0x42);
    check("A=0x42 (via L)", A == 0x42);
}

/* ────── LD (HL), r / LD r, (HL) ────── */
static void test_ld_hl_mem(void) {
    suite("LD (HL),r / LD r,(HL)");
    static const uint8_t c[] = {
        0x21,0x00,0xC0, /* LD HL,0xC000   */
        0x3E,0xAB,      /* LD A,0xAB      */
        0x77,           /* LD (HL),A      */
        0x3E,0x00,      /* LD A,0x00      */
        0x7E,           /* LD A,(HL)      */
        0x76
    };
    run(c, sizeof c, 20);
    check("mem[C000]=0xAB", mem[0xC000] == 0xAB);
    check("A=0xAB via (HL)", A == 0xAB);

    static const uint8_t c2[] = {
        0x21,0x00,0xC0, /* LD HL,0xC000   */
        0x26,0xBB,      /* LD H,0xBB      -> HL=0xBB00? いや H=0xBB に上書き */
        0x74,           /* LD (HL),H      */
        0x7E,           /* LD A,(HL)      */
        0x76
    };
    run(c2, sizeof c2, 20);
    /* HL=0xBB00 after 0x26,0xBB; (HL)=H=0xBB; A=0xBB */
    check("LD (HL),H", mem[0xBB00] == 0xBB);
}

/* ────── LD rr, nn ────── */
static void test_ld_rr_nn(void) {
    suite("LD rr,nn");
    static const uint8_t c[] = {
        0x01,0x34,0x12, /* LD BC,0x1234 */
        0x11,0x78,0x56, /* LD DE,0x5678 */
        0x21,0xBC,0x9A, /* LD HL,0x9ABC */
        0x31,0xFE,0xDF, /* LD SP,0xDFFE */
        0x76
    };
    run(c, sizeof c, 20);
    check("BC=0x1234", BC == 0x1234);
    check("DE=0x5678", DE == 0x5678);
    check("HL=0x9ABC", HL == 0x9ABC);
    check("SP=0xDFFE", SP == 0xDFFE);
}

/* ────── INC / DEC r ────── */
static void test_inc_dec_r(void) {
    suite("INC/DEC r");
    /* INC A: 0x0F -> 0x10 (half-carry), then DEC A -> 0x0F */
    {
        static const uint8_t c[] = { 0x3E,0x0F, 0x3C, 0x3D, 0x76 };
        run(c, sizeof c, 10);
        check("A=0x0F after INC/DEC", A == 0x0F);
    }
    /* INC B: 0xFF -> 0x00 (Z and H) — check flags right after, before anything else */
    {
        static const uint8_t c[] = { 0x06,0xFF, 0x04, 0x76 };
        run(c, sizeof c, 10);
        check("B=0x00 after INC 0xFF", B == 0x00);
        check("FLAG_Z after INC 0xFF", F & FLAG_Z);
        check("FLAG_H after INC 0xFF", F & FLAG_H);
    }
    /* INC C: 0x7F -> 0x80 (S and PV) */
    {
        static const uint8_t c[] = { 0x0E,0x7F, 0x0C, 0x76 };
        run(c, sizeof c, 10);
        check("C=0x80 after INC 0x7F", C == 0x80);
        check("FLAG_PV after INC 0x7F", F & FLAG_PV);
        check("FLAG_S after INC 0x7F", F & FLAG_S);
    }
}

/* ────── ADD A, r / n ────── */
static void test_add(void) {
    suite("ADD");
    static const uint8_t c[] = {
        0x3E,0x10, /* LD A,0x10 */
        0x06,0x20, /* LD B,0x20 */
        0x80,      /* ADD A,B -> 0x30 */
        0x0E,0x05, /* LD C,0x05 */
        0x81,      /* ADD A,C -> 0x35 */
        0xC6,0x01, /* ADD A,1 -> 0x36 */
        0x76
    };
    run(c, sizeof c, 20);
    check("A=0x36", A == 0x36);
    check("no carry", !(F & FLAG_C));

    /* オーバーフローテスト */
    static const uint8_t c2[] = {
        0x3E,0x7F, /* LD A,0x7F */
        0xC6,0x01, /* ADD A,1 -> 0x80 (overflow) */
        0x76
    };
    run(c2, sizeof c2, 10);
    check("A=0x80 overflow", A == 0x80);
    check("PV set on overflow", F & FLAG_PV);
    check("S set", F & FLAG_S);

    /* キャリーテスト */
    static const uint8_t c3[] = {
        0x3E,0xFF, /* LD A,0xFF */
        0xC6,0x01, /* ADD A,1 -> 0x00 carry */
        0x76
    };
    run(c3, sizeof c3, 10);
    check("A=0x00 after 0xFF+1", A == 0x00);
    check("C set", F & FLAG_C);
    check("Z set", F & FLAG_Z);
}

/* ────── ADC A, r ────── */
static void test_adc(void) {
    suite("ADC");
    static const uint8_t c[] = {
        0x3E,0xFF, /* LD A,0xFF */
        0xC6,0x01, /* ADD A,1 -> A=0, C=1 */
        0xCE,0x00, /* ADC A,0 -> A=1 (carry in) */
        0x76
    };
    run(c, sizeof c, 10);
    check("ADC with carry: A=1", A == 1);
    check("no carry after ADC", !(F & FLAG_C));
}

/* ────── SUB / SBC ────── */
static void test_sub_sbc(void) {
    suite("SUB/SBC");
    static const uint8_t c[] = {
        0x3E,0x10, /* LD A,0x10 */
        0x06,0x05, /* LD B,0x05 */
        0x90,      /* SUB B -> 0x0B */
        0xD6,0x03, /* SUB 3 -> 0x08 */
        0x76
    };
    run(c, sizeof c, 10);
    check("A=0x08 after SUBs", A == 0x08);
    check("N flag set", F & FLAG_N);

    /* SUB A -> 0 */
    static const uint8_t c2[] = {
        0x3E,0x55, /* LD A,0x55 */
        0x97,      /* SUB A -> 0 */
        0x76
    };
    run(c2, sizeof c2, 10);
    check("SUB A gives 0", A == 0x00);
    check("Z set", F & FLAG_Z);

    /* SBC with borrow */
    static const uint8_t c3[] = {
        0x3E,0x05, /* LD A,0x05 */
        0x37,      /* SCF (set carry) */
        0xDE,0x02, /* SBC A,2 -> 5-2-1=2 */
        0x76
    };
    run(c3, sizeof c3, 10);
    check("SBC A,2 with carry: A=2", A == 0x02);
}

/* ────── AND / OR / XOR / CP ────── */
static void test_logic(void) {
    suite("Logic");
    /* AND C: check H flag before running CP */
    {
        static const uint8_t c[] = { 0x3E,0xFF, 0x0E,0x0F, 0xA1, 0x76 };
        run(c, sizeof c, 10);
        check("AND C: A=0x0F", A == 0x0F);
        check("H set after AND", F & FLAG_H);
    }
    /* CP: check Z flag when A==C */
    {
        static const uint8_t c[] = { 0x3E,0x0F, 0x0E,0x0F, 0xB9, 0x76 };
        run(c, sizeof c, 10);
        check("CP A==C: Z set", F & FLAG_Z);
    }

    static const uint8_t c2[] = {
        0x3E,0xF0, /* LD A,0xF0 */
        0x16,0x0F, /* LD D,0x0F */
        0xB2,      /* OR D -> 0xFF */
        0x76
    };
    run(c2, sizeof c2, 10);
    check("OR D: A=0xFF", A == 0xFF);

    static const uint8_t c3[] = {
        0x3E,0xFF, /* LD A,0xFF */
        0x1E,0x0F, /* LD E,0x0F */
        0xAB,      /* XOR E -> 0xF0 */
        0x76
    };
    run(c3, sizeof c3, 10);
    check("XOR E: A=0xF0", A == 0xF0);

    /* XOR A -> zero */
    static const uint8_t c4[] = {
        0x3E,0x42, /* LD A,0x42 */
        0xAF,      /* XOR A -> 0 */
        0x76
    };
    run(c4, sizeof c4, 10);
    check("XOR A: A=0", A == 0x00);
    check("XOR A: Z set", F & FLAG_Z);
}

/* ────── INC / DEC rr ────── */
static void test_inc_dec_rr(void) {
    suite("INC/DEC rr");
    static const uint8_t c[] = {
        0x01,0xFF,0x00, /* LD BC,0x00FF */
        0x03,           /* INC BC -> 0x0100 */
        0x0B,           /* DEC BC -> 0x00FF */
        0x76
    };
    run(c, sizeof c, 10);
    check("BC=0x00FF after INC/DEC", BC == 0x00FF);
}

/* ────── ADD HL, rr ────── */
static void test_add_hl(void) {
    suite("ADD HL,rr");
    static const uint8_t c[] = {
        0x21,0x00,0x10, /* LD HL,0x1000 */
        0x01,0x00,0x01, /* LD BC,0x0100 */
        0x09,           /* ADD HL,BC -> 0x1100 */
        0x19,           /* ADD HL,DE (DE=0) -> 0x1100 */
        0x76
    };
    run(c, sizeof c, 10);
    check("HL=0x1100", HL == 0x1100);

    /* キャリー */
    static const uint8_t c2[] = {
        0x21,0xFF,0xFF, /* LD HL,0xFFFF */
        0x01,0x01,0x00, /* LD BC,0x0001 */
        0x09,           /* ADD HL,BC -> 0x0000 carry */
        0x76
    };
    run(c2, sizeof c2, 10);
    check("ADD HL carry: HL=0", HL == 0x0000);
    check("C set", F & FLAG_C);
}

/* ────── JR / JP / DJNZ ────── */
static void test_jumps(void) {
    suite("Jumps");
    /* JR NZ ループで B を 5 回カウント */
    static const uint8_t c[] = {
        0x06,0x05,  /* LD B,5         @ 0x00 */
        0x3E,0x00,  /* LD A,0         @ 0x02 */
        0x3C,       /* INC A          @ 0x04  <- loop */
        0x05,       /* DEC B          @ 0x05 */
        0x20,0xFC,  /* JR NZ,-4 (->0x04) @ 0x06 */
        0x76        /*                @ 0x08 */
    };
    run(c, sizeof c, 100);
    check("DJNZ-style loop: A=5", A == 5);
    check("B=0 after loop", B == 0);

    /* DJNZ */
    static const uint8_t c2[] = {
        0x06,0x03,  /* LD B,3         @ 0x00 */
        0x3E,0x00,  /* LD A,0         @ 0x02 */
        0x3C,       /* INC A          @ 0x04 <- loop */
        0x10,0xFD,  /* DJNZ -3 (->0x04) @ 0x05 */
        0x76        /*                @ 0x07 */
    };
    run(c2, sizeof c2, 30);
    check("DJNZ: A=3", A == 3);
    check("DJNZ: B=0", B == 0);

    /* JP 絶対ジャンプ */
    static const uint8_t c3[] = {
        0xC3,0x05,0x00, /* JP 0x0005 */
        0x3E,0xFF,       /* LD A,0xFF (skipped) */
        0x3E,0x42,       /* LD A,0x42 @ 0x05 */
        0x76
    };
    run(c3, sizeof c3, 10);
    check("JP: A=0x42 (not 0xFF)", A == 0x42);
}

/* ────── CALL / RET ────── */
static void test_call_ret(void) {
    suite("CALL/RET");
    /* subroutine at 0x0010: adds 1 to A, returns */
    static const uint8_t c[] = {
        /* 0x00 */ 0x3E,0x10,       /* LD A,0x10 */
        /* 0x02 */ 0xCD,0x10,0x00,  /* CALL 0x0010 */
        /* 0x05 */ 0xCD,0x10,0x00,  /* CALL 0x0010 */
        /* 0x08 */ 0x76,
        /* 0x09..0x0F: padding */
        [0x10] = 0x3C,              /* INC A */
        0xC9                        /* RET */
    };
    run(c, sizeof c, 20);
    check("A=0x12 after two CALLs", A == 0x12);

    /* CALL Z / RET Z */
    static const uint8_t c2[] = {
        /* 0x00 */ 0xAF,            /* XOR A (Z flag set) */
        /* 0x01 */ 0xCC,0x10,0x00,  /* CALL Z,0x0010 */
        /* 0x04 */ 0x76,
        [0x10] = 0x3E,0x99,         /* LD A,0x99 */
        0xC9                        /* RET */
    };
    run(c2, sizeof c2, 20);
    check("CALL Z taken: A=0x99", A == 0x99);
}

/* ────── PUSH / POP ────── */
static void test_push_pop(void) {
    suite("PUSH/POP");
    static const uint8_t c[] = {
        0x01,0x34,0x12, /* LD BC,0x1234 */
        0x11,0x78,0x56, /* LD DE,0x5678 */
        0xC5,           /* PUSH BC */
        0xD5,           /* PUSH DE */
        0xC1,           /* POP BC (gets 0x5678) */
        0xD1,           /* POP DE (gets 0x1234) */
        0x76
    };
    run(c, sizeof c, 20);
    check("POP BC=0x5678 (was DE)", BC == 0x5678);
    check("POP DE=0x1234 (was BC)", DE == 0x1234);
}

/* ────── PUSH AF / POP AF ────── */
static void test_push_pop_af(void) {
    suite("PUSH/POP AF");
    static const uint8_t c[] = {
        0x3E,0xAA, /* LD A,0xAA */
        0xAF,      /* XOR A -> A=0,F=Z|PV */
        0xF5,      /* PUSH AF */
        0x3E,0x55, /* LD A,0x55 (clear A) */
        0xF1,      /* POP AF */
        0x76
    };
    run(c, sizeof c, 20);
    check("POP AF restores A=0", A == 0x00);
    check("POP AF restores Z flag", F & FLAG_Z);
}

/* ────── CB: BIT / SET / RES ────── */
static void test_cb_bit_set_res(void) {
    suite("CB BIT/SET/RES");
    /* SET 7,A then check A immediately */
    {
        static const uint8_t c[] = { 0x3E,0x00, 0xCB,0xFF, 0x76 };
        run(c, sizeof c, 10);
        check("SET 7,A: A=0x80", A == 0x80);
    }
    /* Full sequence: SET -> BIT -> RES -> BIT */
    {
        static const uint8_t c[] = {
            0x3E,0x00,      /* LD A,0x00 */
            0xCB,0xFF,      /* SET 7,A -> 0x80 */
            0xCB,0x7F,      /* BIT 7,A (set)   */
            0xCB,0xBF,      /* RES 7,A -> 0x00 */
            0xCB,0x7F,      /* BIT 7,A (clear) -> Z=1 */
            0x76
        };
        run(c, sizeof c, 20);
        /* After RES 7,A A=0, last BIT check should set Z */
        check("BIT 7 clear: Z set", F & FLAG_Z);
    }

    /* BIT on register B */
    static const uint8_t c2[] = {
        0x06,0x01,      /* LD B,0x01 */
        0xCB,0x40,      /* BIT 0,B -> not zero */
        0x76
    };
    run(c2, sizeof c2, 10);
    check("BIT 0,B: Z clear", !(F & FLAG_Z));
}

/* ────── CB: ローテーション ────── */
static void test_cb_rot(void) {
    suite("CB Rotations");
    static const uint8_t c[] = {
        0x3E,0x80,  /* LD A,0x80 */
        0xCB,0x07,  /* RLC A -> 0x01, C=1 */
        0x76
    };
    run(c, sizeof c, 10);
    check("RLC A: 0x80->0x01", A == 0x01);
    check("RLC: C set", F & FLAG_C);

    static const uint8_t c2[] = {
        0x06,0x01,  /* LD B,0x01 */
        0xCB,0x00,  /* RLC B -> 0x02 */
        0x76
    };
    run(c2, sizeof c2, 10);
    check("RLC B: 0x01->0x02", B == 0x02);

    static const uint8_t c3[] = {
        0x3E,0x01,  /* LD A,0x01 */
        0xCB,0x3F,  /* SRL A -> 0x00, C=1 */
        0x76
    };
    run(c3, sizeof c3, 10);
    check("SRL A: 0x01->0x00", A == 0x00);
    check("SRL: C set", F & FLAG_C);
    check("SRL: Z set", F & FLAG_Z);
}

/* ────── RLCA / RRCA / RLA / RRA ────── */
static void test_rot_acc(void) {
    suite("RLCA/RRCA/RLA/RRA");
    static const uint8_t c[] = {
        0x3E,0x80, /* LD A,0x80 */
        0x07,      /* RLCA -> 0x01, C=1 */
        0x76
    };
    run(c, sizeof c, 10);
    check("RLCA: 0x80->0x01", A == 0x01);
    check("RLCA: C set", F & FLAG_C);

    static const uint8_t c2[] = {
        0x3E,0x01, /* LD A,0x01 */
        0x0F,      /* RRCA -> 0x80, C=1 */
        0x76
    };
    run(c2, sizeof c2, 10);
    check("RRCA: 0x01->0x80", A == 0x80);
    check("RRCA: C set", F & FLAG_C);

    static const uint8_t c3[] = {
        0x3E,0x00, /* LD A,0x00 */
        0x37,      /* SCF */
        0x17,      /* RLA -> 0x01 (carry in), C=0 */
        0x76
    };
    run(c3, sizeof c3, 10);
    check("RLA: 0x00+carry->0x01", A == 0x01);
    check("RLA: C clear", !(F & FLAG_C));
}

/* ────── EX DE, HL / EX AF, AF' / EXX ────── */
static void test_exchange(void) {
    suite("EX/EXX");
    static const uint8_t c[] = {
        0x21,0x34,0x12, /* LD HL,0x1234 */
        0x11,0x78,0x56, /* LD DE,0x5678 */
        0xEB,           /* EX DE,HL */
        0x76
    };
    run(c, sizeof c, 10);
    check("EX DE,HL: HL=0x5678", HL == 0x5678);
    check("EX DE,HL: DE=0x1234", DE == 0x1234);

    static const uint8_t c2[] = {
        0x3E,0xAB,      /* LD A,0xAB */
        0x08,           /* EX AF,AF' */
        0x3E,0x00,      /* LD A,0x00 */
        0x08,           /* EX AF,AF' */
        0x76
    };
    run(c2, sizeof c2, 10);
    check("EX AF,AF': A=0xAB restored", A == 0xAB);

    static const uint8_t c3[] = {
        0x01,0x11,0x11, /* LD BC,0x1111 */
        0xD9,           /* EXX */
        0x01,0x22,0x22, /* LD BC,0x2222 */
        0xD9,           /* EXX */
        0x76
    };
    run(c3, sizeof c3, 10);
    check("EXX: BC=0x1111 restored", BC == 0x1111);
}

/* ────── SCF / CCF / CPL ────── */
static void test_misc_flags(void) {
    suite("SCF/CCF/CPL");
    static const uint8_t c[] = {
        0x37,  /* SCF -> C=1 */
        0x3F,  /* CCF -> C=0 (complement) */
        0x76
    };
    run(c, sizeof c, 10);
    check("CCF after SCF: C=0", !(F & FLAG_C));

    static const uint8_t c2[] = {
        0x3E,0x55, /* LD A,0x55 */
        0x2F,      /* CPL -> 0xAA */
        0x76
    };
    run(c2, sizeof c2, 10);
    check("CPL: 0x55->0xAA", A == 0xAA);
    check("CPL: H set", F & FLAG_H);
    check("CPL: N set", F & FLAG_N);
}

/* ────── LD (nn), A / LD A, (nn) ────── */
static void test_ld_nn(void) {
    suite("LD (nn),A / LD A,(nn)");
    static const uint8_t c[] = {
        0x3E,0x77,       /* LD A,0x77 */
        0x32,0x00,0xC0,  /* LD (0xC000),A */
        0x3E,0x00,       /* LD A,0 */
        0x3A,0x00,0xC0,  /* LD A,(0xC000) */
        0x76
    };
    run(c, sizeof c, 20);
    check("LD (nn),A: mem=0x77", mem[0xC000] == 0x77);
    check("LD A,(nn): A=0x77", A == 0x77);
}

/* ────── LD (nn), HL / LD HL, (nn) ────── */
static void test_ld_nn_hl(void) {
    suite("LD (nn),HL / LD HL,(nn)");
    static const uint8_t c[] = {
        0x21,0x34,0x12,  /* LD HL,0x1234 */
        0x22,0x00,0xC0,  /* LD (0xC000),HL */
        0x21,0x00,0x00,  /* LD HL,0 */
        0x2A,0x00,0xC0,  /* LD HL,(0xC000) */
        0x76
    };
    run(c, sizeof c, 20);
    check("LD (nn),HL: mem lo=0x34", mem[0xC000] == 0x34);
    check("LD (nn),HL: mem hi=0x12", mem[0xC001] == 0x12);
    check("LD HL,(nn): HL=0x1234", HL == 0x1234);
}

/* ────── IN / OUT ────── */
static uint8_t io_buf[256];
static uint8_t io_read_test(uint8_t port)              { return io_buf[port]; }
static void    io_write_test(uint8_t port, uint8_t val){ io_buf[port] = val; }

static void test_io(void) {
    suite("IN/OUT");
    io_register_read (0x10, io_read_test);
    io_register_write(0x10, io_write_test);
    io_buf[0x10] = 0xBE;

    static const uint8_t c[] = {
        0x3E,0xEF,      /* LD A,0xEF */
        0xD3,0x10,      /* OUT (0x10),A */
        0x3E,0x00,      /* LD A,0 */
        0xDB,0x10,      /* IN A,(0x10) */
        0x76
    };
    run(c, sizeof c, 20);
    check("OUT: io_buf[0x10]=0xEF", io_buf[0x10] == 0xEF);
    check("IN: A=0xEF", A == 0xEF);
}

/* ────── NMI ────── */
static void test_nmi(void) {
    suite("NMI");
    static const uint8_t c[] = {
        /* 0x0000 */ 0x3E,0x00,  /* LD A,0 */
        /* 0x0002 */ 0x76,       /* HALT -> NMI will wake */
        /* 0x0066 NMI handler */
        [0x66] = 0x3E,0xAB,      /* LD A,0xAB */
        0xED,0x45,               /* RETN */
    };
    memset(mem, 0, sizeof mem);
    memcpy(mem, c, sizeof c);
    z80_reset();
    SP = 0xDFFE;
    /* Run until HALT */
    for (int i = 0; i < 10 && !cpu.halted; i++) z80_step();
    /* Fire NMI */
    z80_nmi();
    for (int i = 0; i < 20; i++) z80_step();
    check("NMI handler: A=0xAB", A == 0xAB);
    check("RETN: halted again", cpu.halted);
}

/* ────── INT IM1 ────── */
static void test_int_im1(void) {
    suite("INT IM1");
    static const uint8_t c[] = {
        /* 0x0000 */ 0xED,0x56,   /* IM 1 */
        /* 0x0002 */ 0xFB,        /* EI */
        /* 0x0003 */ 0x76,        /* HALT */
        /* ISR @ 0x0038 */
        [0x38] = 0x3E,0xCC,       /* LD A,0xCC */
        0xED,0x4D,                /* RETI */
    };
    memset(mem, 0, sizeof mem);
    memcpy(mem, c, sizeof c);
    z80_reset();
    SP = 0xDFFE;
    for (int i = 0; i < 10 && !cpu.halted; i++) z80_step();
    z80_int(0xFF);
    for (int i = 0; i < 20; i++) z80_step();
    check("IM1 ISR: A=0xCC", A == 0xCC);
    check("RETI: halted again", cpu.halted);
}

/* ────── LDIR ────── */
static void test_ldir(void) {
    suite("LDIR");
    static const uint8_t c[] = {
        0x21,0x00,0xC0, /* LD HL,0xC000 (src) */
        0x11,0x00,0xD0, /* LD DE,0xD000 (dst) */
        0x01,0x04,0x00, /* LD BC,4 (count) */
        0xED,0xB0,      /* LDIR */
        0x76
    };
    /* run() clears all memory first, so load source data after calling reset manually */
    memset(mem, 0, sizeof mem);
    memcpy(mem, c, sizeof c);
    mem[0xC000] = 0x11; mem[0xC001] = 0x22;
    mem[0xC002] = 0x33; mem[0xC003] = 0x44;
    z80_reset();
    SP = 0xDFFE;
    for (int i = 0; i < 20 && !cpu.halted; i++) z80_step();
    check("LDIR [0]=0x11", mem[0xD000] == 0x11);
    check("LDIR [1]=0x22", mem[0xD001] == 0x22);
    check("LDIR [2]=0x33", mem[0xD002] == 0x33);
    check("LDIR [3]=0x44", mem[0xD003] == 0x44);
    check("LDIR BC=0", BC == 0);
    check("LDIR PV clear", !(F & FLAG_PV));
}

/* ────── main ────── */
int main(void) {
    printf("=== Z80 Emulator Test Suite ===\n\n");

    test_ld_r_n();
    test_ld_r_r();
    test_ld_hl_mem();
    test_ld_rr_nn();
    test_inc_dec_r();
    test_add();
    test_adc();
    test_sub_sbc();
    test_logic();
    test_inc_dec_rr();
    test_add_hl();
    test_jumps();
    test_call_ret();
    test_push_pop();
    test_push_pop_af();
    test_cb_bit_set_res();
    test_cb_rot();
    test_rot_acc();
    test_exchange();
    test_misc_flags();
    test_ld_nn();
    test_ld_nn_hl();
    test_io();
    test_nmi();
    test_int_im1();
    test_ldir();

    printf("\n===========================\n");
    printf("  PASS: %d\n", g_pass);
    if (g_fail)
        printf("  FAIL: %d\n", g_fail);
    printf("===========================\n");
    return g_fail ? 1 : 0;
}
