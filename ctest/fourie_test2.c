#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define PI 3.14159265358
#define N 128 //データ個数
//#define LP 10
#define LP 1000000
#define LP2 200
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
void uprint( char* buf, int length, int ret );
void pass();
void wait();

typedef struct{
	double r;
	double i;
}complex;

int main() {
	char cbuf[32];

	int n,k;
	int length;
	double R[128],max;
 	complex x[128], X;

 	for(n=0; n<128; n++){
 		x[n].r=0.5+sin(0.1*n)+0.3*sin(0.3*n)+0.15*sin(0.5*n);
 		x[n].i=0.0;
 	}
 	for(n=0; n<128; n++){
 		length = sprintf(cbuf, "sin[%d]=%3.3lf\n",n,x[n].r);
		uprint( cbuf, length, 0 );
 	}
	uprint( "\n", 2, 0 );

 	for(n=0; n<128; n++){
 		for(k=0; k<30+x[n].r*25; k++)
			uprint( "*", 1, 0 );
		uprint( "\n", 2, 0 );
 	}
 	max=0.0;
 	length = sprintf(cbuf, "Fourie transform output\n");
	uprint( cbuf, length, 0 );
 	for(n=0; n<N; n++){
 		X.r=0;
 		X.i=0;
 		for(k=0; k<N; k++){
 			X.r += x[k].r*cos(2.0*PI*n*k/N) + x[k].i*sin(2.0*PI*n*k/N);
 			X.i += x[k].i*cos(2.0*PI*n*k/N) - x[k].r*sin(2.0*PI*n*k/N);
 		}
 		R[n] = sqrt(X.r*X.r + X.i*X.i);
 		if(R[n]>max) max=R[n];
 		length = sprintf(cbuf, "X.r=%lf, X.i=%lf, R(%d)=%lf\n", X.r, X.i,n,R[n]);
		uprint( cbuf, length, 0 );
 	}
	uprint( "\n", 2, 0 );
 	length = sprintf(cbuf, "Fourie transform graph\n");
 	for(n=0; n<N; n++){
 		for( k=0; k<R[n]*60/max; k++)
			uprint( "*", 1, 0 );
		uprint( "\n", 2, 0 );
 	}
	pass();
	return 0;
} 

void uprint( char* buf, int length, int ret ) {
    unsigned int* uart_out = (unsigned int*)0xc000fc00;
    unsigned int* uart_status = (unsigned int*)0xc000fc04;

    for (int i = 0; i < length + ret; i++) {
        unsigned int flg = 1;
        while(flg == 1) {
            flg = *uart_status;
        }
        *uart_out = ((i == length+1)&&(ret == 2)) ? 0x0a :
                    ((i == length)&&(ret == 1)) ? 0x20 :
                    ((i == length)&&(ret == 2)) ? 0x0d : buf[i];
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

