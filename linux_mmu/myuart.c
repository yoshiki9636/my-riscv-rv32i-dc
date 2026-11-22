// SPDX-License-Identifier: GPL-2.0
/*
 * drivers/tty/serial/myuart.c : my-riscv-rv32i-dc UART (MMU / S-mode version)
 *
 * The registers are reached through ioremap (no fixed physical addresses).
 *   reg[0] io_uart_out  (0xC000_FC00)
 *     +0x00 OUTC  write a character
 *     +0x04 FULL  bit0 = 1 : TX FIFO full
 *     +0x0C RXCH  [7:0] data, [8] ready, [9] overrun (cleared by the read)
 *     +0x10 RXEC  bit0 = 1 : no hardware echo-back
 *   reg[1] interrupter  (0xC000_FA00, optional)
 *     +0x00 INT_ENABLE  bit0 RX, bit1 external pin
 *     +0x04 INT_STATUS  write 0 to clear a bit (1 leaves it alone)
 *   interrupt : riscv-intc hwirq 9 (S-mode external, mip.SEIP).  interrupter
 *     latches the RX status when INT_ENABLE.bit0 and mie.SEIE (or MEIE) are
 *     set; OpenSBI delegates SEIP to S-mode (mideleg).
 *   Without reg[1] / an interrupt, RX is polled every 10 ms.
 *
 * Early console : earlycon=myuart,mmio32,0xc000fc00 (fixmap, before probe).
 */
#include <linux/serial_core.h>
#include <linux/console.h>
#include <linux/of.h>
#include <linux/io.h>
#include <linux/platform_device.h>
#include <linux/module.h>
#include <linux/kfifo.h>
#include <linux/timer.h>
#include <linux/tty_flip.h>
#include <linux/interrupt.h>
#include <linux/percpu.h>

#define MYUART_OUTC	0x00
#define MYUART_FULL	0x04
#define MYUART_RXCH	0x0C
#define MYUART_RXEC	0x10
#define MYUART_RX_READY		(1U << 8)
#define MYUART_RX_OVERRUN	(1U << 9)

#define MYINT_ENABLE	0x00
#define MYINT_STATUS	0x04

/* serial_core : the port type must not be PORT_UNKNOWN (startup is skipped) */
#define PORT_MYUART	124

#define MYUART_MAX_PORTS 1

static struct uart_port myuart_ports[MYUART_MAX_PORTS];
static struct uart_driver myuart_driver;
static void __iomem *myint_base;	/* interrupter, NULL : RX polled */
static struct timer_list myuart_rx_timer;
static struct uart_port *myuart_rx_port;
static int myuart_rx_irq;
static DEFINE_PER_CPU(struct uart_port *, myuart_irq_cookie);

static void myuart_putc_base(void __iomem *base, unsigned char c)
{
	while (readl(base + MYUART_FULL) & 0x1)
		cpu_relax();
	writel(c, base + MYUART_OUTC);
}

static void myuart_putchar(struct uart_port *port, unsigned char c)
{
	myuart_putc_base(port->membase, c);
}

/* ---------------- early console ---------------- */

static void myuart_early_putc(struct uart_port *port, unsigned char c)
{
	myuart_putc_base(port->membase, c);
}

static void myuart_early_write(struct console *con, const char *s,
			       unsigned int n)
{
	struct earlycon_device *dev = con->data;

	uart_console_write(&dev->port, s, n, myuart_early_putc);
}

static int __init myuart_earlycon_setup(struct earlycon_device *dev,
					const char *options)
{
	if (!dev->port.membase)
		return -ENODEV;
	dev->con->write = myuart_early_write;
	return 0;
}
EARLYCON_DECLARE(myuart, myuart_earlycon_setup);
OF_EARLYCON_DECLARE(myuart, "myvendor,myuart", myuart_earlycon_setup);

/* ---------------- uart_ops ---------------- */

static void myuart_start_tx(struct uart_port *port)
{
	struct tty_port *tport = &port->state->port;
	unsigned char ch;

	while (kfifo_get(&tport->xmit_fifo, &ch)) {
		myuart_putchar(port, ch);
		port->icount.tx++;
	}
}

static unsigned int myuart_tx_empty(struct uart_port *port)
{
	return (readl(port->membase + MYUART_FULL) & 0x1) ? 0 : TIOCSER_TEMT;
}

static void myuart_set_mctrl(struct uart_port *port, unsigned int mctrl) {}
static unsigned int myuart_get_mctrl(struct uart_port *port) { return 0; }
static void myuart_stop_tx(struct uart_port *port) {}
static void myuart_stop_rx(struct uart_port *port) {}

static void myuart_rx_read(struct uart_port *port)
{
	u32 v;

	if (!port)
		return;
	v = readl(port->membase + MYUART_RXCH);	/* consumes the data */
	if (v & MYUART_RX_READY) {
		struct tty_port *tport = &port->state->port;

		if (v & MYUART_RX_OVERRUN)
			port->icount.overrun++;
		port->icount.rx++;
		tty_insert_flip_char(tport, v & 0xff, TTY_NORMAL);
		tty_flip_buffer_push(tport);
	}
}

static void myuart_rx_poll(struct timer_list *t)
{
	struct uart_port *port = READ_ONCE(myuart_rx_port);

	myuart_rx_read(port);
	if (port)
		mod_timer(&myuart_rx_timer, jiffies + msecs_to_jiffies(10));
}

static irqreturn_t myuart_rx_interrupt(int irq, void *dev_id)
{
	/* clear the latched RX status before the read : a byte that arrives
	 * after the read raises a new interrupt (bit1 written 1 : unchanged) */
	writel(0x2, myint_base + MYINT_STATUS);
	myuart_rx_read(READ_ONCE(myuart_rx_port));
	return IRQ_HANDLED;
}

static int myuart_startup(struct uart_port *port)
{
	writel(1, port->membase + MYUART_RXEC);	/* no hardware echo-back */
	(void)readl(port->membase + MYUART_RXCH);	/* flush a stale byte */
	WRITE_ONCE(myuart_rx_port, port);
	if (myuart_rx_irq) {
		writel(0x2, myint_base + MYINT_STATUS);
		writel(1, myint_base + MYINT_ENABLE);
		enable_percpu_irq(myuart_rx_irq, IRQ_TYPE_NONE);	/* sie.SEIE */
	} else {
		mod_timer(&myuart_rx_timer, jiffies + msecs_to_jiffies(10));
	}
	return 0;
}

static void myuart_shutdown(struct uart_port *port)
{
	if (myuart_rx_irq) {
		disable_percpu_irq(myuart_rx_irq);
		writel(0, myint_base + MYINT_ENABLE);
	}
	WRITE_ONCE(myuart_rx_port, NULL);
	timer_delete_sync(&myuart_rx_timer);
}

static void myuart_set_termios(struct uart_port *port, struct ktermios *new,
			       const struct ktermios *old) {}
static const char *myuart_type(struct uart_port *port) { return "myuart"; }
static void myuart_release_port(struct uart_port *port) {}
static int myuart_request_port(struct uart_port *port) { return 0; }

static void myuart_config_port(struct uart_port *port, int flags)
{
	if (flags & UART_CONFIG_TYPE)
		port->type = PORT_MYUART;
}

static int myuart_verify_port(struct uart_port *port,
			      struct serial_struct *ser) { return 0; }

static const struct uart_ops myuart_ops = {
	.tx_empty	= myuart_tx_empty,
	.set_mctrl	= myuart_set_mctrl,
	.get_mctrl	= myuart_get_mctrl,
	.stop_tx	= myuart_stop_tx,
	.start_tx	= myuart_start_tx,
	.stop_rx	= myuart_stop_rx,
	.startup	= myuart_startup,
	.shutdown	= myuart_shutdown,
	.set_termios	= myuart_set_termios,
	.type		= myuart_type,
	.release_port	= myuart_release_port,
	.request_port	= myuart_request_port,
	.config_port	= myuart_config_port,
	.verify_port	= myuart_verify_port,
};

/* ---------------- console (after probe) ---------------- */

#ifdef CONFIG_SERIAL_MYUART_CONSOLE
static void myuart_console_write(struct console *co, const char *s,
				 unsigned int n)
{
	struct uart_port *port = &myuart_ports[co->index];
	unsigned long flags;

	if (!port->membase)
		return;
	local_irq_save(flags);
	uart_console_write(port, s, n, myuart_putchar);
	local_irq_restore(flags);
}

static int myuart_console_setup(struct console *co, char *options)
{
	if (co->index < 0 || co->index >= MYUART_MAX_PORTS)
		co->index = 0;
	if (!myuart_ports[co->index].membase)
		return -ENODEV;
	return 0;
}

static struct console myuart_console = {
	.name	= "ttyMY",
	.write	= myuart_console_write,
	.device	= uart_console_device,
	.setup	= myuart_console_setup,
	.flags	= CON_PRINTBUFFER,
	.index	= -1,
	.data	= &myuart_driver,
};
#define MYUART_CONSOLE (&myuart_console)
#else
#define MYUART_CONSOLE NULL
#endif

static struct uart_driver myuart_driver = {
	.owner		= THIS_MODULE,
	.driver_name	= "myuart",
	.dev_name	= "ttyMY",
	.nr		= MYUART_MAX_PORTS,
	.cons		= MYUART_CONSOLE,
};

/* ---------------- platform driver ---------------- */

static int myuart_probe(struct platform_device *pdev)
{
	struct uart_port *port;
	struct resource *res;
	int ret, irq;

	port = &myuart_ports[0];
	memset(port, 0, sizeof(*port));

	port->membase = devm_platform_get_and_ioremap_resource(pdev, 0, &res);
	if (IS_ERR(port->membase))
		return PTR_ERR(port->membase);

	port->mapbase	= res->start;
	port->ops	= &myuart_ops;
	port->type	= PORT_MYUART;
	port->dev	= &pdev->dev;
	port->line	= 0;
	port->iotype	= UPIO_MEM32;
	port->flags	= UPF_BOOT_AUTOCONF;

	timer_setup(&myuart_rx_timer, myuart_rx_poll, 0);

	/* RX interrupt : needs the interrupter registers and an interrupt */
	if (platform_get_resource(pdev, IORESOURCE_MEM, 1)) {
		myint_base = devm_platform_ioremap_resource(pdev, 1);
		if (IS_ERR(myint_base))
			myint_base = NULL;
	}
	irq = platform_get_irq_optional(pdev, 0);
	if (myint_base && irq > 0) {
		/* riscv-intc interrupts are per-CPU (percpu_devid) */
		ret = request_percpu_irq(irq, myuart_rx_interrupt, "myuart",
					 &myuart_irq_cookie);
		if (ret)
			dev_warn(&pdev->dev, "irq %d request failed (%d)\n",
				 irq, ret);
		else
			myuart_rx_irq = port->irq = irq;
	}
	dev_info(&pdev->dev, "RX %s\n",
		 myuart_rx_irq ? "interrupt driven" : "polled");

	ret = uart_add_one_port(&myuart_driver, port);
	if (ret)
		return ret;

	platform_set_drvdata(pdev, port);
	return 0;
}

static void myuart_remove(struct platform_device *pdev)
{
	struct uart_port *port = platform_get_drvdata(pdev);

	uart_remove_one_port(&myuart_driver, port);
}

static const struct of_device_id myuart_of_match[] = {
	{ .compatible = "myvendor,myuart" },
	{}
};
MODULE_DEVICE_TABLE(of, myuart_of_match);

static struct platform_driver myuart_platform_driver = {
	.probe	= myuart_probe,
	.remove	= myuart_remove,
	.driver	= {
		.name		= "myuart",
		.of_match_table	= myuart_of_match,
	},
};

static int __init myuart_init(void)
{
	int ret;

	ret = uart_register_driver(&myuart_driver);
	if (ret)
		return ret;
	ret = platform_driver_register(&myuart_platform_driver);
	if (ret)
		uart_unregister_driver(&myuart_driver);
	return ret;
}

static void __exit myuart_exit(void)
{
	platform_driver_unregister(&myuart_platform_driver);
	uart_unregister_driver(&myuart_driver);
}

module_init(myuart_init);
module_exit(myuart_exit);

MODULE_DESCRIPTION("my-riscv-rv32i-dc UART driver (MMU)");
MODULE_LICENSE("GPL");
