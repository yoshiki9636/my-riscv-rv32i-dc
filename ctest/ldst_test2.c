#include <stdio.h>

//#define LP 10
#define LP 1000000
#define LP2 200
#define TESTNUM 0x3f8
void pass();
void fail(unsigned int val1, unsigned int val2, unsigned int val3);
void wait();

unsigned int bufa[TESTNUM];
unsigned int bufb[TESTNUM];

int main() {
    unsigned int* led = (unsigned int*)0xc000fe00;
	*led = 0x7;
	for(register unsigned int i = 0; i < TESTNUM; i++) {
		bufa[i] = i;
		//wait();
	}
	*led = 0x6;
	for(register unsigned int i = 0; i < TESTNUM; i++) {
		//bufb[i] = i;
		bufb[i] = TESTNUM - 1 - i;
		//wait();
	}
	*led = 0x5;
	for(register unsigned int i = 0; i < TESTNUM; i++) {
		*led = i;
		register unsigned int c = bufa[i];
		register unsigned int d = bufb[TESTNUM-1-i];
		//unsigned int c = 0xff & bufb[TESTNUM-1-i];
		//unsigned int c = 0x20000 + TESTNUM - 1 - bufb[i];
		//unsigned int c = (0xffff) & ( TESTNUM - 1 - bufb[i]);
		//if (bufa[i] != c) {
		//if (bufa[i] & 0xffffffff != bufb[i] & 0xffffffff) {
		if (c != d) {
		//if ((c & 0xffffffff) != (d & 0xffffffff)) {
		//if (c != d & 0xffffffff) {
		//if (bufa[i] != bufb[i]) {
		//if (bufa[i] != ((TESTNUM - 1) & (TESTNUM - 1 - bufb[i]))) {
			//fail(i,bufa[i],bufb[i]);
			//fail(i,bufa[i],(TESTNUM - 1 - bufb[i]));
			//fail(i,bufa[i]>>1,(TESTNUM - 1 - bufb[i])>>1);
			fail(i,bufa[i],bufb[i]);
		}
	}
	//fail(1,bufa[0],bufb[0]);
	pass();
	return 0;

}

void pass() {
    unsigned int* led = (unsigned int*)0xc000fe00;
    unsigned int val;
    unsigned int timer,timer2;
    val = 0;
    while(1) {
        timer = 0;
		timer2 = 0;
        while(timer2 < LP2) {
            while(timer < LP) {
                timer++;
	    	}
            timer2++;
		}
		val++;
		*led = val & 0x7777;
    }
}

void fail(unsigned int val1, unsigned int val2, unsigned int val3) {
    unsigned int* led = (unsigned int*)0xc000fe00;
    unsigned int val;
    unsigned int timer,timer2;
    val = 0;
    unsigned int sw = 0;
    while(1) {
		*led = 0x0;
        timer = 0;
		timer2 = 0;
        while(timer2 < LP2) {
            while(timer < LP) {
                timer++;
	    	}
            timer2++;
		}
		*led =val1 & 0x7777;
		//*led =val & 0x7777;
        timer = 0;
		timer2 = 0;
        while(timer2 < LP2) {
            while(timer < LP) {
                timer++;
	    	}
            timer2++;
		}
		*led = 0x0;
        timer = 0;
		timer2 = 0;
        while(timer2 < LP2) {
            while(timer < LP) {
                timer++;
	    	}
            timer2++;
		}
		//*led = (val2 & 0x77777777) >> 16;
		//*led = (bufa[val&0xf] & 0x77777777 ) >> 16;
		*led =bufa[val&0xf] & 0x7777;
        timer = 0;
		timer2 = 0;
        while(timer2 < LP2) {
            while(timer < LP) {
                timer++;
	    	}
            timer2++;
		}
		*led = 0x0;
        timer = 0;
		timer2 = 0;
        while(timer2 < LP2) {
            while(timer < LP) {
                timer++;
	    	}
            timer2++;
		}
		//*led = val3 & 0x7777;
		//*led = (val3 & 0x77777777) >> 16;
		//*led = (bufb[val&0xf] & 0x77777777 ) >> 16;
		*led =bufb[val&0xf] & 0x7777;
        timer = 0;
		timer2 = 0;
        while(timer2 < LP2) {
            while(timer < LP) {
                timer++;
	    	}
            timer2++;
		}
		*led = 0x0;
        timer = 0;
		timer2 = 0;
        while(timer2 < LP2) {
            while(timer < LP) {
                timer++;
	    	}
            timer2++;
		}
		*led = 0x7777;
        timer = 0;
		timer2 = 0;
        while(timer2 < LP2) {
            while(timer < LP) {
                timer++;
	    	}
            timer2++;
		}

		val++;
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
