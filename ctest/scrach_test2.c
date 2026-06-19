#include <stdio.h>
//#include <stdlib.h>
#include <math.h>
//#include <string.h>

//#define LP 10
#define LP 1000
#define LP2 200
#define SIZE 4

#include "add_for_cmpl_all.c"
#include "add_for_cmpl2.c"

int* scr_pad = (int*)0x80000000;
int* main_ram = (int*)0x00000000;

int main() {
    unsigned int* led = (unsigned int*)0xc000fe00;
	
	int* scr_tmp = (int*)0x80000000;
	//int* scr_tmp = (int*)0x00100000;
	for (int i = 0x10000; i < 0x12000; i++) {
		*scr_tmp = i;
		printf( "write data : %x cntr : %x\n", *scr_tmp, i);
		scr_tmp++;
	}

	scr_tmp = (int*)0x80000000;
	//scr_tmp = (int*)0x00100000;
	for (int i = 0x10000; i < 0x12000; i++) {
		int tmp = *scr_tmp;
		if (tmp == i) {
			printf( "OK Addr 0x%x: data : %x cntr : %x\n", scr_tmp, tmp, i);
		}
		else {
			printf( "NG!! Addr 0x%x: data : %x cntr : %x\n", scr_tmp, tmp, i);
		}
		scr_tmp++;
	}
	fflush(stdout);

	pass();
	return 0;
}


