#pragma once
#include <stddef.h>
#include <stdint.h>

/* addr のバイト列を逆アセンブルして buf に書き込む。
 * 戻り値: 消費バイト数 */
int  z80_disasm(uint16_t addr, char *buf, size_t bufsz);

/* 全レジスタ状態を stderr に出力する */
void z80_print_state(void);
