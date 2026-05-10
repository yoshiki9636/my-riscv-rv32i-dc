#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "z80.h"
#include "z80_dis.h"

//#define LP 10
#define LP 1000
#define LP2 200

#include "../add_for_cmpl_all.c"
#include "../add_for_cmpl2.c"
#include "z80.c"
#include "z80_dis.c"


/* ─── I/O ハンドラ ─── */
static void port_putchar(uint8_t port, uint8_t val) { (void)port; putchar(val); }
static void port_puthex (uint8_t port, uint8_t val) { (void)port; printf("%02X", val); }
static void port_putuint(uint8_t port, uint8_t val) { (void)port; printf("%u",   val); }
static uint8_t port_getchar(uint8_t port)           { (void)port; return (uint8_t)getchar(); }

/*
 * テスト用 Z80 バイナリ
 *
 * 0x0000: IM 1 を設定し、EI してからカウントループ
 *   ED 56        IM 1           ; 割り込みモード1 -> ISR は 0x0038
 *   FB           EI
 *   01 0A 00     LD BC, 10      ; ループカウンタ
 * loop:
 *   3E 2E        LD A, '.'
 *   D3 01        OUT (1), A     ; '.' を出力
 *   0B           DEC BC
 *   78           LD A, B
 *   B1           OR C
 *   20 F7        JR NZ, loop
 *   3E 0A        LD A, '\n'
 *   D3 01        OUT (1), A
 *   76           HALT
 *
 * 0x0038: IM1 ISR
 *   3E 21        LD A, '!'
 *   D3 01        OUT (1), A     ; 割り込み発生時に '!' を出力
 *   ED 4D        RETI
 */

const uint8_t* rom = (uint8_t*)0x00100000;

/*
static const uint8_t rom[] = {
    // 0x0000 
    0xED, 0x56,              // IM 1           
    0xFB,                    // EI             
    0x01, 0x0A, 0x00,        // LD BC, 10      
    // loop: 0x0006
    0x3E, 0x2E,              // LD A, '.'      
    0xD3, 0x01,              // OUT (1), A     
    0x0B,                    // DEC BC         
    0x78,                    // LD A, B        
    0xB1,                    // OR C           
    0x20, 0xF7,              // JR NZ, loop    
    0x3E, 0x0A,              // LD A, '\n'     
    0xD3, 0x01,              // OUT (1), A     
    0x76,                    // HALT           

    // 0x0013 ~ 0x0037: パディング (0x00)
    [0x38] = 0x3E, 0x21,    // LD A, '!'      
             0xD3, 0x01,    // OUT (1), A     
             0xED, 0x4D,    // RETI           
};
*/

#define LOAD_ADDR  0x0000
#define MAX_STEPS  1000000
#define INT_AFTER  5        /* 何ステップ後に INT を発生させるか */

/* ────── verbose: 1 ステップ分のトレースを表示 ────── */
static void trace_pre(void) {
    /* 割り込み処理 / HALT の場合は特別表示 */
    if (cpu.nmi_pending) {
        printf("---- [NMI] PC=0x%04X -> 0x0066 ----\n", cpu.pc.w);
        return;
    }
    if (cpu.int_pending && cpu.iff1) {
        uint16_t vec = (cpu.im == 2)
            ? (uint16_t)(cpu.i << 8 | cpu.int_vector) : 0x0038;
        printf("---- [INT IM%d] PC=0x%04X -> 0x%04X ----\n",
               cpu.im, cpu.pc.w, vec);
        return;
    }
    if (cpu.halted) {
        printf("---- [HALTED] ----\n");
        return;
    }

    /* 通常命令: アドレス・バイト列・ニーモニック */
    char mnem[64];
    uint16_t pc = cpu.pc.w;
    int len = z80_disasm(pc, mnem, sizeof mnem);

    printf("%04X: ", pc);
    for (int i = 0; i < len; i++)
        printf("%02X ", mem[(uint16_t)(pc + i)]);
    /* バイト列を最大 4 バイト幅に揃える */
    for (int i = len; i < 4; i++)
        printf("   ");
    printf("  %s\n", mnem);
}

//int main(int argc, char *argv[]) {
int main() {
    int verbose = 0;
/*
    for (int i = 1; i < argc; i++) {
        if (argv[i][0] == '-' && argv[i][1] == 'v')
            verbose = 1;
        else {
            fprintf(stderr, "usage: %s [-v]\n", argv[0]);
            return 1;
        }
    }
*/
    verbose = 1;

    /* メモリ初期化 & バイナリロード */
    memset(mem, 0, sizeof mem);
    //memcpy(mem + LOAD_ADDR, rom, sizeof rom);
    memcpy(mem + LOAD_ADDR, rom, 0x2000); // tekitou

    /* CPU リセット */
    z80_reset();
    PC = LOAD_ADDR;
    SP = 0xDFFF;

    /* I/O ポート登録 */
    io_register_read (0x00, port_getchar);
    io_register_write(0x01, port_putchar);
    io_register_write(0x02, port_puthex);
    io_register_write(0x03, port_putuint);

    /* 実行ループ */
    int steps = 0;
    while (steps < MAX_STEPS && !cpu.halted) {
        if (steps == INT_AFTER) {
            if (verbose)
                printf("[host] asserting INT at step %d\n", steps);
            else
                printf("[host] INT asserting\n");
            z80_int(0xFF);
        }

        if (verbose) trace_pre();

        z80_step();
        steps++;

        if (verbose) z80_print_state();
    }

    /* HALT 後の最終状態 */
    if (verbose) {
        printf("\n=== FINAL STATE ===\n");
        z80_print_state();
    }
    printf("[done] steps=%d PC=0x%04X halted=%d\n",
           steps, PC, cpu.halted);

	pass();
    return 0;
}
