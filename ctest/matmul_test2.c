#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

//#define LP 10
#define LP 1000000
#define LP2 200
#define YSIZE 16
#define XSIZE 16
#define ZSIZE 16
// workaround for libm_nano.a
int __errno;
// workaround for using libc_nano.a
void _close(void) {}
void _lseek(void) {}
void _read(void) {}
void _write(void) {}
void _sbrk_r(void) {}
void abort(void) {}
void _kill_r(void) {}
void _getpid_r(void) {}
void _fstat_r(void) {}
void _isatty_r(void) {}
void _isatty(void) {}
void pass();
void wait();
int mat_mul( double* mat1, double* mat2, double* result, int x, int y, int z);
int matrix_print( double* mat, int x, int y);
int double_print( char* cbuf, double value, int digit );
void uprint( char* buf, int length, int ret );

int main() {
	double mat1[ZSIZE*YSIZE];
	double mat2[XSIZE*ZSIZE];
	double result[XSIZE*YSIZE];
	
	for (int j = 0; j < YSIZE; j++) {
		for (int i = 0; i < ZSIZE; i++) {
			mat1[j*ZSIZE+i] = sqrt((double)(j*ZSIZE+i+1));
		}
	}
	for (int j = 0; j < ZSIZE; j++) {
		for (int i = 0; i < XSIZE; i++) {
			mat2[j*XSIZE+i] = sqrt((double)(j*XSIZE+i+21));
		}
	}
	for (int j = 0; j < YSIZE; j++) {
		for (int i = 0; i < XSIZE; i++) {
			result[j*XSIZE+i] = 0.0;
		}
	}

	mat_mul( mat1, mat2, result, XSIZE, YSIZE, ZSIZE);

	uprint( "mat1\n", 6, 0 );
	matrix_print( mat1, ZSIZE, YSIZE);
	uprint( "\nmat2\n", 8, 0 );
	matrix_print( mat2, XSIZE, ZSIZE);
	uprint( "\nresult\n", 10, 0 );
	matrix_print( result, XSIZE, YSIZE);
	pass();
	return 0;
}

int mat_mul( double* mat1, double* mat2, double* result, int x, int y, int z) {
	for(int j = 0; j < y; j++) {
		for(int i = 0; i < x; i++) {
			for(int k = 0; k < z; k++) {
				result[j*x+i] += mat1[j*z+k] * mat2[k*x+i];
			}
		}
	}
	return 0;
}

int matrix_print( double* mat, int x, int y) {
	char cbuf2[32];
	char cbufe[32];
	for(int j = 0; j < y; j++) {
		for(int i = 0; i < x; i++) {
			float f = (float)mat[j*x+i];
			sprintf(cbuf2, " %e ",  f);
			int length = strlen(cbuf2);
			sprintf(cbufe, "l = %d ",  length);
 
			if ( i == x - 1 ) {
				uprint( cbuf2, length, 1 );
			}
			else {
				uprint( cbuf2, length, 2 );
			}
			uprint( cbufe, 20, 0 );
		}
	}
	return 0;
}

void uprint( char* buf, int length, int ret ) {
    unsigned int* led = (unsigned int*)0xc000fe00;
    unsigned int* uart_out = (unsigned int*)0xc000fc00;
    unsigned int* uart_status = (unsigned int*)0xc000fc04;

	for (int i = 0; i < length + 3; i++) {
		unsigned int flg = 1;
		while(flg == 1) {
			flg = *uart_status;
		}
		*uart_out = (i == length+2) ? 0 :
		            ((i == length+1)&&(ret != 1)) ? 0 :
		            ((i == length+1)&&(ret == 1)) ? 0x0a :
		            ((i == length)&&(ret == 0)) ? 0 :
		            ((i == length)&&(ret == 1)) ? 0x0d :
		            ((i == length)&&(ret == 2)) ? 0x20 : buf[i];
		*led = i;
	}
	//return 0;
}

void pass() {
    unsigned int* led = (unsigned int*)0xc000fe00;
    unsigned int val;
    unsigned int timer,timer2;
    val = 0;
    while(1) {
		wait();
		val++;
		*led = val & 0x7777;
    }
}

void wait() {
    unsigned int timer,timer2;
    timer = 0;
	timer2 = 0;
    while(timer2 < LP2) {
        while(timer < LP) {
            timer++;
    	}
        timer2++;
	}
}
