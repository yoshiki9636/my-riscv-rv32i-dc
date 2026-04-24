#include <stdio.h>
#include <stdlib.h>
#include <math.h>

//#define LP 10
#define LP 1000
#define LP2 200

#include "add_for_cmpl_all.c"
#include "add_for_cmpl2.c"

int main() {
	char cbuf2[32];

	while(1) {
		int a, b, ans;
		a = rand() - 0x20000000;
		b = rand() - 0x20000000;
		b = b >> 4;
		ans = a / b;

		uprint( "div a = ", 8, 0 );
		int length = double_print( cbuf2, a, 0 );
		uprint( cbuf2, length, 0 );
		uprint( " b = ", 5, 0 );
		length = double_print( cbuf2, b, 0 );
		uprint( cbuf2, length, 0 );
		uprint( " ans = ", 7, 0 );
		length = double_print( cbuf2, ans, 0 );
		uprint( cbuf2, length, 2 );
	}
	pass();
	return 0;
}

