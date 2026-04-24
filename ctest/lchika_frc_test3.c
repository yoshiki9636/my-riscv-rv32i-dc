#include <stdio.h>

//#define LP 10
#define LP 1000
#define LP2 200
#define TESTNUM 0x3c00
#define TICK1 0x2faf080

#include "add_for_cmpl_all.c"
#include "add_for_cmpl2.c"

void __attribute__((interrupt)) interrupt_h();

unsigned long long next_timer;

int main() {
	void (*p_func)();
    volatile unsigned int* led = (unsigned int*)0xc000fe00;
    volatile unsigned int* int_enable = (unsigned int*)0xc000fa00;
    volatile unsigned int* frc_cmp_low  = (unsigned int*)0xc000f808;
    volatile unsigned int* frc_cmp_high = (unsigned int*)0xc000f80c;
    volatile unsigned int* frc_ctrl = (unsigned int*)0xc000f810;

	*led = 7;

	unsigned int val = 12345678;
	printf("gpio test = %ld\n",val);

	// for frc setup
	next_timer = (unsigned long long)TICK1;
	*frc_cmp_low = TICK1; // 1sec @ 50MHz
	*frc_cmp_high = 0;
	// start frc
	*frc_ctrl = 3;

	p_func = interrupt_h;
	__asm__ volatile("csrw mtvec, %0" : "=r"(p_func));
	// enable MTIE
	unsigned int value = 0x80;
	__asm__ volatile("csrw mie, %0" : "=r"(value));
	// mstatus
	value = 0x8;
	__asm__ volatile("csrw mstatus, %0" : "=r"(value));

	uprint( "start\n", 7, 0);
	*led = 6;
	while(1) { wait(); }
	return 0;

}

void __attribute__((interrupt)) interrupt_h() {


    char buf[ 40 ];
	int length;
    uprint( "dbg call trap" , 14, 2 );
    unsigned int mepc;
    __asm__ volatile("csrr %0, mepc" : "=r"(mepc));
    length = sprintf( buf, "mepc %x : ", mepc);
    uprint( buf, length, 2 );
    unsigned int mcause;
    __asm__ volatile("csrr %0, mcause" : "=r"(mcause));
    length = sprintf( buf, "mcause %x : ", mcause);
    uprint( buf, length, 2 );

    unsigned int* led = (unsigned int*)0xc000fe00;
    unsigned int* frc_low  = (unsigned int*)0xc000f800;
    unsigned int* frc_high = (unsigned int*)0xc000f804;
    unsigned int* frc_ctrl = (unsigned int*)0xc000f810;
    unsigned int* frc_cmp_low  = (unsigned int*)0xc000f808;
    unsigned int* frc_cmp_high = (unsigned int*)0xc000f80c;
    unsigned int* gpio_test = (unsigned int*)0xc000fe10;
	static int value;
	uprint( "ringing timer!\n", 16, 0);

	char cbuf[64];
	//int length;
	unsigned int val = *frc_low;
	length = sprintf(cbuf,"low  counter = %8x\n",val);
	uprint( cbuf, length, 0);
	val = *frc_high;
	printf("high counter = %8x\n",val);
	val = *frc_cmp_low;
	printf("cmp low  counter = %8x\n",val);
	val = *frc_cmp_high;
	printf("cmp high counter = %8x\n",val);

	// change compare register
	*frc_cmp_low = 0xffffffff;
	val = *frc_cmp_low;
	printf("cmp low  counter = %8x\n",val);

	*frc_cmp_high = (unsigned int)(next_timer >> 32ULL);
	val = *frc_cmp_high;
	printf("cmp high  counter = %8x\n",val);

	*frc_cmp_low = (unsigned int)(next_timer & 0xffffffffULL);
	val = *frc_cmp_low;
	printf("cmp low  counter = %8x\n",val);

	*gpio_test = (unsigned int)0xffffffff;
	//val = *gpio_test;
	val = 0x12345678;
	printf("gpio test = %8x\n",val);

	// clear interrupt bit
	*frc_ctrl = 1;

	// add tick
	next_timer += (unsigned long long)TICK1;

	value++;
	*led = value;
}

