#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include "z80.h"
#include "z80_dis.h"

//#define LP 10
#define LP 1000
#define LP2 200

#include "../add_for_cmpl_all.c"
#include "../add_for_cmpl2.c"
#include "../add_for_keybuf.c"
#include "z80.c"
#include "z80_dis.c"


/* ─── シグナル処理 ─── */
static volatile int stop_flag = 0;
static void sigint_handler(int sig) { (void)sig; stop_flag = 1; }

/* ─── デモ用 I/O ハンドラ ─── */
static void port_putchar(uint8_t port, uint8_t val) { (void)port; putchar(val); }
static void port_puthex (uint8_t port, uint8_t val) { (void)port; printf("%02X", val); }
static void port_putuint(uint8_t port, uint8_t val) { (void)port; printf("%u",   val); }

/*
 * port 0x00 読み込み: scanf で 1 文字受け取り A に返す
 *   - fflush(stdout) で OUT 済みのプロンプトを確実に画面に出してから待つ
 *   - " %c" の先頭スペースで余分な改行・空白をスキップする
 */
static uint8_t port_getchar(uint8_t port) {
    (void)port;
    fflush(stdout);
    char c = '\0';
    if (scanf(" %c", &c) != 1) c = '\0';
    return (uint8_t)c;
}

/* ─── NASCOM BASIC 用 I/O ハンドラ ─── */

/*
 * BASIC 文字出力 (RST 08H 経由, port 0x01)
 *   0x0D (CR)  → 改行
 *   0x0A (LF)  → 無視 (CR の後に来るため)
 *   0x0C (CS)  → 画面クリア (エスケープシーケンス or 無視)
 *   0x00       → 無視
 *   その他      → そのまま出力
 */
static void basic_putchar(uint8_t port, uint8_t val) {
    (void)port;
    if      (val == 0x0D) { putchar('\n'); }  /* CR → newline */
    else if (val == 0x0A) { }                  /* LF after CR  → skip */
    else if (val == 0x0C) { }                  /* clear screen → skip */
    else if (val == 0x00) { }                  /* NUL          → skip */
    else                  { putchar((char)val); }
    fflush(stdout);
}

/*
 * BASIC 文字入力 (RST 10H 経由, port 0x00)
 *   stdin から 1 文字読み込み; LF(0x0A) → CR(0x0D) に変換して BASIC に渡す
 *   EOF → 0x1A (Ctrl+Z) を返す
 */
static uint8_t basic_getchar(uint8_t port) {
    (void)port;
    fflush(stdout);
    int c = getchar();
    if (c == EOF)  return 0x1A;   /* Ctrl+Z = BASIC EOF */
    if (c == '\n') return 0x0D;   /* LF → CR (BASIC の行終端) */
    return (uint8_t)c;
}

/* ─── Intel HEX ローダ ─── */
/*
 * ファイルを読み込んで mem[] に展開する
 * 戻り値: 0=成功, -1=エラー
 */
static int load_hex(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) { perror(path); return -1; }

    char line[1024];
    while (fgets(line, sizeof line, f)) {
        if (line[0] != ':') continue;

        unsigned byte_count, addr, rec_type;
        if (sscanf(line + 1, "%02x%04x%02x", &byte_count, &addr, &rec_type) != 3) continue;

        if (rec_type == 0x01) break;  /* EOF レコード */
        if (rec_type != 0x00) continue;  /* データ以外はスキップ */

        for (unsigned i = 0; i < byte_count; i++) {
            unsigned byte_val;
            if (sscanf(line + 9 + i * 2, "%02x", &byte_val) != 1) break;
            mem[(addr + i) & 0xFFFF] = (uint8_t)byte_val;
        }
    }
    fclose(f);
    return 0;
}

/*
 * テスト用 Z80 バイナリ
 *
 * ─── メインコード (0x0000) ───
 *   0x0000  21 80 00   LD HL, 0x0080   ; "Input: " の先頭アドレス
 *   0x0003  CD 20 00   CALL 0x0020     ; print_str でプロンプト表示
 *   0x0006  DB 00      IN A, (0x00)    ; port 0 から 1 文字入力 (scanf)
 *   0x0008  47         LD B, A         ; CALL で A が変わる前に B へ退避
 *   0x0009  21 88 00   LD HL, 0x0088   ; "Echo: " の先頭アドレス
 *   0x000C  CD 20 00   CALL 0x0020     ; print_str でプレフィックス表示
 *   0x000F  78         LD A, B         ; 入力文字を A に復元
 *   0x0010  D3 01      OUT (0x01), A   ; 入力文字を出力
 *   0x0012  3E 0A      LD A, '\n'
 *   0x0014  D3 01      OUT (0x01), A
 *   0x0016  76         HALT
 *
 * ─── print_str サブルーチン (0x0020) ───
 *   HL = ヌル終端文字列の先頭; A, HL を破壊
 *   0x0020  7E         LD A, (HL)
 *   0x0021  B7         OR A            ; A == 0 なら Z フラグが立つ
 *   0x0022  C8         RET Z           ; ヌル終端 → リターン
 *   0x0023  D3 01      OUT (0x01), A   ; 1 文字出力
 *   0x0025  23         INC HL
 *   0x0026  18 F8      JR 0x0020       ; (offset = 0x0020 - 0x0028 = -8 = 0xF8)
 *
 * ─── 文字列データ ───
 *   0x0080  "Input: \0"
 *   0x0088  "Echo: \0"
 */

const uint8_t* rom = (uint8_t*)0x01000000;

#define DEMO_LOAD_ADDR  0x0000
#define MAX_STEPS       1000000

/* ────── verbose: 1 ステップ分のトレースを表示 ────── */
static void trace_pre(void) {
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

    char mnem[64];
    uint16_t pc = cpu.pc.w;
    int len = z80_disasm(pc, mnem, sizeof mnem);

    printf("%04X: ", pc);
    for (int i = 0; i < len; i++)
        printf("%02X ", mem[(uint16_t)(pc + i)]);
    for (int i = len; i < 4; i++)
        printf("   ");
    printf("  %s\n", mnem);
}

/* ────── NASCOM BASIC モード ────── */
/*
 * ROM.HEX を読み込んで RST ベクタをパッチし、BASIC を実行する。
 *
 * パッチ内容 (6850 ACIA を直接 I/O ポートに置き換え):
 *   RST 08H (0x0008):  OUT ($01),A / RET    → basic_putchar
 *   RST 10H (0x0010):  IN  A,($00) / RET    → basic_getchar
 *   RST 18H (0x0018):  XOR A       / RET    → 常に「文字なし」を返す
 *   RST 38H (0x0038):  RETI                 → 割り込みハンドラ (使わない)
 *
 * ポートマップ:
 *   port 0x00 (IN)  : basic_getchar  (getchar + LF→CR 変換)
 *   port 0x01 (OUT) : basic_putchar  (CR→改行, LF 無視)
 */
//static int run_basic(const char *hex_path, int verbose) {
static int run_basic(int verbose) {
    /* メモリクリア & HEX ロード */
    memset(mem, 0, sizeof mem);
    memcpy(mem + DEMO_LOAD_ADDR, rom, 8192);
    //if (load_hex(hex_path) != 0) return 1;

    /* RST ベクタパッチ */
    /* 0x0008: RST 08H = 文字出力 → OUT ($01),A / RET */
    mem[0x0008] = 0xD3; mem[0x0009] = 0x01; mem[0x000A] = 0xC9;
    /* 0x0010: RST 10H = 文字入力 (ブロッキング) → IN A,($00) / RET */
    mem[0x0010] = 0xDB; mem[0x0011] = 0x00; mem[0x0012] = 0xC9;
    /* 0x0018: RST 18H = 文字チェック (ノンブロック) → XOR A / RET (常に 0) */
    mem[0x0018] = 0xAF; mem[0x0019] = 0xC9;
    /* 0x0038: RST 38H = IM1 割り込みハンドラ → RETI */
    mem[0x0038] = 0xED; mem[0x0039] = 0x4D;

    /* CPU リセット */
    z80_reset();
    PC = 0x0000;
    SP = 0xDFFF;

    /* I/O ポート登録 */
    io_register_read (0x00, basic_getchar);
    io_register_write(0x01, basic_putchar);

    /* Ctrl+C で停止 */
    signal(SIGINT, sigint_handler);

    //fprintf(stderr, "[basic] ROM loaded from %s, running...\n", hex_path);
    fprintf(stderr, "[basic] Press Ctrl+C to exit\n\n");

    /* 実行ループ (HALT か Ctrl+C まで無限実行) */
    while (!cpu.halted && !stop_flag) {
        if (verbose) trace_pre();
        z80_step();
        if (verbose) z80_print_state();
    }

    //if (verbose) {
        //printf("\n=== FINAL STATE ===\n");
        //z80_print_state();
    //}
    //if (stop_flag) fprintf(stderr, "\n[basic] Interrupted.\n");
	pass();
    return 0;
}

/* ────── main ────── */
//int main(int argc, char *argv[]) {
int main() {

	volatile unsigned int* rx_echoback = (unsigned int*)0xc000fc10;
	*rx_echoback = 1; // disable echoback
    key_interrupt_init();
    //int verbose  = 1;
    int verbose  = 0;
    //const char *hex_file = NULL;

    //for (int i = 1; i < argc; i++) {
        //if (argv[i][0] == '-') {
            //if (argv[i][1] == 'v') verbose = 1;
            //else {
                //fprintf(stderr, "usage: %s [-v] [hexfile]\n", argv[0]);
                //return 1;
            //}
        //} else {
            //hex_file = argv[i];
        //}
    //}

    run_basic(verbose);
	pass();

    /* ─── NASCOM BASIC モード ─── */
    //if (hex_file) {
        //return run_basic(hex_file, verbose);
    //}

    /* ─── デモモード (組み込み ROM) ─── */
    memset(mem, 0, sizeof mem);
    //memcpy(mem + DEMO_LOAD_ADDR, demo_rom, sizeof demo_rom);

    z80_reset();
    PC = DEMO_LOAD_ADDR;
    SP = 0xDFFF;

    io_register_read (0x00, port_getchar);
    io_register_write(0x01, port_putchar);
    io_register_write(0x02, port_puthex);
    io_register_write(0x03, port_putuint);

    int steps = 0;
    while (steps < MAX_STEPS && !cpu.halted) {
        if (verbose) trace_pre();
        z80_step();
        steps++;
        if (verbose) z80_print_state();
    }

    if (verbose) {
        printf("\n=== FINAL STATE ===\n");
        z80_print_state();
    }
    printf("[done] steps=%d PC=0x%04X halted=%d\n",
           steps, PC, cpu.halted);
    return 0;
}
