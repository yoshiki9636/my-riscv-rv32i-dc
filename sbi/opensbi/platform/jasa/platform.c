/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * OpenSBI platform : my-riscv-rv32i-dc (RV32IMA + Sv32 + S/U-mode, Arty A7)
 *
 *   console : io_uart_out  (0xC000_FC00)
 *     +0x00 OUTC  write a character
 *     +0x04 FULL  bit0 = 1 : TX FIFO full
 *     +0x0C RXCH  { rx_write_error(9), rx_valid(8), data(7:0) } (cleared by read)
 *   timer   : io_frc       (0xC000_F800)
 *     +0x00 VALLO / +0x04 VALHI  64-bit counter (also the time CSR)
 *     +0x08 CMPLO / +0x0C CMPHI  compare value
 *     +0x10 CNTRL bit0 = run, bit1 = reset the counter,
 *                 bit2 = 0 : clear the compare status (mip.MTIP)
 *     mip.MTIP = latched (counter >= compare) & run & mie.MTIE, until it is
 *     cleared by a CNTRL write with bit2 = 0.  The M timer interrupt is taken
 *     on its rising edge, so every new compare value is written together with
 *     a status clear.
 *   IPI     : none (single hart : OpenSBI handles self IPIs locally)
 *   irqchip : none (external interrupts : interrupter -> mip.MEIP / mip.SEIP,
 *             delegated to S-mode by Linux / SBI configuration)
 */

#include <sbi/riscv_asm.h>
#include <sbi/riscv_encoding.h>
#include <sbi/riscv_io.h>
#include <sbi/sbi_const.h>
#include <sbi/sbi_console.h>
#include <sbi/sbi_platform.h>
#include <sbi/sbi_timer.h>

#define JASA_UART_ADDR		0xC000FC00UL
#define JASA_UART_OUTC		0x00
#define JASA_UART_FULL		0x04
#define JASA_UART_RXCH		0x0C
#define JASA_UART_RX_VALID	(1U << 8)

#define JASA_FRC_ADDR		0xC000F800UL
#define JASA_FRC_VALLO		0x00
#define JASA_FRC_VALHI		0x04
#define JASA_FRC_CMPLO		0x08
#define JASA_FRC_CMPHI		0x0C
#define JASA_FRC_CNTRL		0x10
#define JASA_FRC_RUN		0x1	/* run, bit2 = 0 : clear MTIP */

/* clk of the CPU / io_frc (Arty A7 : 50MHz).  Keep in sync with the DTS
 * timebase-frequency. */
#ifndef JASA_TIMER_FREQ
#define JASA_TIMER_FREQ		50000000
#endif

/* ---------------- console ---------------- */

static volatile void *uart_base = (volatile void *)JASA_UART_ADDR;

static void jasa_uart_putc(char ch)
{
	while (readl(uart_base + JASA_UART_FULL) & 0x1)
		;
	writel((u32)(unsigned char)ch, uart_base + JASA_UART_OUTC);
}

static int jasa_uart_getc(void)
{
	u32 v = readl(uart_base + JASA_UART_RXCH);

	if (v & JASA_UART_RX_VALID)
		return v & 0xff;
	return -1;
}

static struct sbi_console_device jasa_console = {
	.name		= "jasa-uart",
	.console_putc	= jasa_uart_putc,
	.console_getc	= jasa_uart_getc,
};

/* ---------------- timer ---------------- */

static volatile void *frc_base = (volatile void *)JASA_FRC_ADDR;

static u64 jasa_timer_value(void)
{
	u32 hi, lo;

	do {
		hi = readl(frc_base + JASA_FRC_VALHI);
		lo = readl(frc_base + JASA_FRC_VALLO);
	} while (hi != readl(frc_base + JASA_FRC_VALHI));

	return ((u64)hi << 32) | lo;
}

static void jasa_set_cmp(u64 v)
{
	/* the high word first to max : no false match in between */
	writel(0xFFFFFFFFU, frc_base + JASA_FRC_CMPHI);
	writel((u32)v, frc_base + JASA_FRC_CMPLO);
	writel((u32)(v >> 32), frc_base + JASA_FRC_CMPHI);
	/* clear the status : it is set again (a new edge) if counter >= v */
	writel(JASA_FRC_RUN, frc_base + JASA_FRC_CNTRL);
}

static void jasa_timer_event_start(u64 next_event)
{
	jasa_set_cmp(next_event);
}

static void jasa_timer_event_stop(void)
{
	jasa_set_cmp(~0ULL);
}

static int jasa_timer_warm_init(void)
{
	jasa_timer_event_stop();
	return 0;
}

static struct sbi_timer_device jasa_timer = {
	.name			= "jasa-frc",
	.timer_freq		= JASA_TIMER_FREQ,
	.timer_value		= jasa_timer_value,
	.timer_event_start	= jasa_timer_event_start,
	.timer_event_stop	= jasa_timer_event_stop,
	.warm_init		= jasa_timer_warm_init,
};

/* ---------------- platform ---------------- */

static int jasa_early_init(bool cold_boot)
{
	if (cold_boot)
		sbi_console_set_device(&jasa_console);
	return 0;
}

static int jasa_final_init(bool cold_boot)
{
	return 0;
}

static int jasa_timer_init(void)
{
	/* start the counter (keep its value : the time CSR counts on) */
	writel(JASA_FRC_RUN, frc_base + JASA_FRC_CNTRL);
	sbi_timer_set_device(&jasa_timer);
	return 0;
}

/* 16-entry TLBs : a full flush is cheaper than many sfence.vma */
static u64 jasa_get_tlbr_flush_limit(void)
{
	return 16 * 4096;
}

static u32 jasa_get_tlb_num_entries(void)
{
	return 16;
}

const struct sbi_platform_operations platform_ops = {
	.early_init		= jasa_early_init,
	.final_init		= jasa_final_init,
	.timer_init		= jasa_timer_init,
	.get_tlbr_flush_limit	= jasa_get_tlbr_flush_limit,
	.get_tlb_num_entries	= jasa_get_tlb_num_entries,
};

const struct sbi_platform platform = {
	.opensbi_version	= OPENSBI_VERSION,
	.platform_version	= SBI_PLATFORM_VERSION(0x0, 0x01),
	.name			= "my-riscv-rv32i-dc (Arty A7)",
	.features		= SBI_PLATFORM_DEFAULT_FEATURES,
	.hart_count		= 1,
	.hart_stack_size	= SBI_PLATFORM_DEFAULT_HART_STACK_SIZE,
	.heap_size		= SBI_PLATFORM_DEFAULT_HEAP_SIZE(1),
	.platform_ops_addr	= (unsigned long)&platform_ops
};
