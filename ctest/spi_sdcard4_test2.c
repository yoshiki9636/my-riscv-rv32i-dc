#include <stdio.h>

//#define LP 10
#define LP 1000
#define LP2 200
#define SWAIT 1000
#define TESTNUM 0x3c00

#include "add_for_cmpl_all.c"
#include "add_for_cmpl2.c"

void swait() {
    unsigned int timer,timer2;
    timer = 0;
    while(timer < SWAIT) {
        timer++;
    }
}

char calc_sd_crc7(char *buf) {
	int crc, crc_prev;
	int i,j;
	crc = buf[1];
	for(i=2; i<7; i++) {
		for(j=7; j>=0; j--) {
			crc <<= 1;
			crc_prev = crc;
			if (i<6) crc |= (buf[i]>>j) & 1;
			if (crc & 0x80) { crc ^= 0x89; }	// Generator
		}
	}
	return crc_prev | 1;
}


int cmd_dispatch(char *outbuf, char *inbuf, int len, int ce_on) {
	static volatile unsigned int* spi_mosi = (unsigned int*)0xc000f208;
	static volatile unsigned int* spi_miso = (unsigned int*)0xc000f20c;
	static volatile unsigned int* gpio_out_value = (unsigned int*)0xc000fe10;
	unsigned int check;
	unsigned int dbg;

	// reset miso fifo
	//*spi_miso = 0x400;
	unsigned int rdata = 0x200;
	char data;

	// print outbuf
	printf("\nmosi:");
	for (int i = 0; i < len; i++) {
		printf(" %02x",outbuf[i]);
	}
	printf("\n");
	// CE = low
	if ( ce_on > 0) {
		*gpio_out_value =  0x00;
	}

	if(len < 8) {

		// wiret mosi fiio
		for (int i = 0; i < len; i++) {
			check = *spi_mosi;
			while ((check & 0x100) != 0) {
				check = *spi_mosi;
			}
			*spi_mosi = outbuf[i];
			//printf(" %02x",outbuf[i]);
		}
		// read miso fiio
		for (int i = 0; i < len; i++) {
			rdata = *spi_miso;
			printf(" d:%04x",rdata);
			while ((rdata & 0x400) != 0) {
				//swait();
				rdata = *spi_miso;
				printf(" d:%04x",rdata);
			}
			if ((rdata & 0x100) != 0) {
				printf("fifo error d:%04x\n",rdata);
				while(1);
			}
			data = (char)(rdata & 0xff);
			inbuf[i] = data;
			//printf(" %02x",data);
		}
	}
	else {
		// wiret mosi fiio only 4 data
		for (int i = 0; i < 4; i++) {
			check = *spi_mosi;
			while ((check & 0x100) != 0) {
				check = *spi_mosi;
			}
			*spi_mosi = outbuf[i];
			//printf(" %02x",outbuf[i]);
		}
		// read and wirte both data
		for (int i = 4; i < len; i++) {
			check = *spi_mosi;
			while ((check & 0x100) != 0) {
				check = *spi_mosi;
				printf(" s:%04x\n",check);
			}
			*spi_mosi = outbuf[i];
			swait();
			printf(" s:%04x\n",check);
			//printf(" %02x",outbuf[i]);
			rdata = *spi_miso;
			printf(" d:%04x",rdata);
			while ((rdata & 0x400) != 0) {
				//swait();
				rdata = *spi_miso;
				printf(" d:%04x",rdata);
			}
			if ((rdata & 0x100) != 0) {
				printf("fifo error d:%04x\n",rdata);
				while(1);
			}
			data = (char)(rdata & 0xff);
			inbuf[i-4] = data;
			//printf(" %02x",data);
		}
		// read miso fiio
		for (int i = 0; i < 4; i++) {
			rdata = *spi_miso;
			printf(" d:%04x",rdata);
			while ((rdata & 0x400) != 0) {
				//swait();
				rdata = *spi_miso;
				printf(" d:%04x",rdata);
			}
			if ((rdata & 0x100) != 0) {
				printf("fifo error d:%04x\n",rdata);
				while(1);
			}
			data = (char)(rdata & 0xff);
			inbuf[i+len-4] = data;
			//printf(" %02x",data);
		}
	}
	// CE = high
	if ( ce_on != 2) {
		*gpio_out_value =  0x01;
	}
	// print inbuf
	printf("miso:");
	for (int i = 0; i < len; i++) {
		printf(" %02x",inbuf[i]);
	}
	printf("\n");
	// for debug
	dbg = *spi_mosi;
	printf("status:%04x\n",dbg);
	return len;
}

int cmd_polling(unsigned char pol_val1, unsigned char pol_val2) {
	static volatile unsigned int* spi_mosi = (unsigned int*)0xc000f208;
	static volatile unsigned int* spi_miso = (unsigned int*)0xc000f20c;
	unsigned int rdata;
	unsigned int check;
	unsigned char rchar;
	int flg = 0;
	int cntr = 0;
	while (1) {
		check = *spi_mosi;
		while ((check & 0x400) != 0) {
			check = *spi_mosi;
		}
		if ((rdata & 0x100) != 0) {
			printf("fifo error d:%04x\n",rdata);
			while(1);
		}
		*spi_mosi = 0xff;
		swait();
		rdata =*spi_miso;
		printf("%ld:%04x ",cntr,rdata);
		if (rdata < 0x400) { cntr++; }
		rchar = (unsigned char)(rdata & 0xff);
		if ((rdata < 0x400)&&(rchar == pol_val1)) { flg = 1; break; }
		else if ((rdata < 0x400)&&(rchar == pol_val2)) { flg = 2; break; }
	}
	return flg; 
}

int spi_init() {
	static volatile unsigned int* spi_mode = (unsigned int*)0xc000f200;
	static volatile unsigned int* spi_sckdiv = (unsigned int*)0xc000f204;
	static volatile unsigned int* spi_mosi = (unsigned int*)0xc000f208;
	static volatile unsigned int* spi_miso = (unsigned int*)0xc000f20c;

	static volatile unsigned int* gpio_enable = (unsigned int*)0xc000fe18;
	static volatile unsigned int* gpio_out_value = (unsigned int*)0xc000fe10;
	char dummy[8] = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
	char inbuf[64];

	// initialization
	// sck : 250kHz
	printf("SPI register initialzation");
	*spi_sckdiv = 500;
	//*spi_sckdiv = 10;
	//*spi_sckdiv = 20;
	// CPOL=0 CPHA=0
	// SPI enable, big endian
	//*spi_mode = 0x9;
	*spi_mode = 0x00220009;
	// GPIO[0] for CE : workaround
	*gpio_out_value =  0x01;
	*gpio_enable = 0x01;

	// wait over 100 cycles
	for (int i = 0; i < 100; i++) {
		printf("w");
	}
	// dummy clock with CE=high
	for (int i = 0; i < 5; i++) {
		cmd_dispatch(dummy, inbuf, 8, 0);
	}
	// wait over 100 cycles
	for (int i = 0; i < 100; i++) {
		printf("w");
	}
	printf("\n");
	// reset miso fifo
	*spi_miso = 0x400;

	return 0;
}


int main() {
	static volatile unsigned int* spi_mode = (unsigned int*)0xc000f200;
	static volatile unsigned int* spi_sckdiv = (unsigned int*)0xc000f204;
	static volatile unsigned int* spi_mosi = (unsigned int*)0xc000f208;
	static volatile unsigned int* spi_miso = (unsigned int*)0xc000f20c;

	char test[4] = { 0x87, 0x65, 0x43, 0x21 };
	//char cmd0[9] = { 0xff, 0x40, 0x00, 0x00, 0x00, 0x00, 0x95, 0xff, 0xff };
	char cmd0[17] = { 0xff, 0x40, 0x00, 0x00, 0x00, 0x00, 0x95, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
	char cmd8[17] = { 0xff, 0x48, 0x00, 0x00, 0x01, 0xaa, 0x87, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
	char cmd9[17] = { 0xff, 0x49, 0x00, 0x00, 0x00, 0x00, 0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
	char cmd10[17] = { 0xff, 0x4a, 0x00, 0x00, 0x00, 0x00, 0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
	char cmd16[9] = { 0xff, 0x50, 0x00, 0x00, 0x02, 0x00, 0x01, 0xff, 0xff }; // set block size to 512
	char cmd17[11] = { 0xff, 0x51, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff }; // read block
	char cmd5541[20] = { 0xff, 0x77, 0x00, 0x00, 0x00, 0x00, 0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0x69, 0x40, 0x00, 0x00, 0x00, 0x01, 0xff, 0xff };
	char cmd55[8] = { 0xff, 0x77, 0x00, 0x00, 0x00, 0x00, 0x01, 0xff };
	char acmd41[8] = { 0xff, 0x69, 0x40, 0x00, 0x00, 0x00, 0x01, 0xff };
	char cmd58[17] = { 0xff, 0x7A, 0x00, 0x00, 0x00, 0x00, 0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
	char dummy[8] = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
	char dummy16[16] = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };

	char inbuf[64];
	int flg;

	//char tmp = calc_sd_crc7(cmd0);
	//cmd0[6] = tmp;

	printf("SPI init\n");
	spi_init();
	//cmd_dispatch(test, inbuf, 4, 1);
	//pass();

//for(int k = 0; k < 10; k++) {
	// CMD 0
	printf("\nSPI SEND CMD0\n");
	flg = 0;

	while(flg == 0) {
		cmd_dispatch(cmd0, inbuf, 7, 1);
		if ( cmd_polling( 0x01, 0x01 )) { flg = 1; }
	}
	cmd_dispatch(dummy, inbuf, 8, 0);
	wait();

	// CMD 8
	printf("\nSPI SEND CMD8\n");
	flg = 0;

	cmd_dispatch(cmd8, inbuf, 17, 1);
	fflush(stdout);

	cmd_dispatch(dummy16, inbuf, 16, 0);
	cmd_dispatch(dummy16, inbuf, 16, 0);
	wait();

	// CMD 55  ACMD41
	printf("\nSPI SEND CMD55 ACMD41\n");
	flg = 0;

	while(flg == 0) {
		//cmd_dispatch(cmd5541, inbuf, 20, 1);
		cmd_dispatch(cmd55, inbuf, 7, 1);
		cmd_polling( 0x01, 0x01 );
		cmd_dispatch(acmd41, inbuf, 7, 1);
		int check = cmd_polling( 0x00, 0x01 );
		flg = (check == 1) ? 1 : 0;
		cmd_dispatch(dummy, inbuf, 8, 0);
		wait();
	}

	// CMD 58
	//printf("\nSPI SEND CMD58\n");
	//cmd_dispatch(cmd58, inbuf, 17, 1);
	//cmd_polling( 0x00, 0x01 );

	// CMD 9
	//printf("\nSPI SEND CMD9\n");
	//cmd_dispatch(cmd9, inbuf, 17, 1);
	//cmd_polling( 0x00, 0x01 );

	// CMD 10
	//printf("\nSPI SEND CMD10\n");
	//cmd_dispatch(cmd10, inbuf, 8, 1);
	//cmd_polling( 0x00, 0x01 );

	// CMD 16 to change block size = 512
	//printf("\nSPI SEND CMD16\n");
	//cmd_dispatch(cmd16, inbuf, 9, 1);
	//cmd_polling( 0x01, 0x01 );

	// read MBR 512bytes
	printf("\nSPI SEND CMD17 : MBR\n");
	cmd17[2] = 0x00;
	cmd17[3] = 0x00;
	cmd17[4] = 0x00;
	cmd17[5] = 0x00;
	cmd_dispatch(cmd17, inbuf, 7, 2);

	cmd_polling( 0xfe, 0xfe );
	for (int i = 0; i < 65; i++) {
		printf("\n%ld\n",i);
		if (i == 64) {
			cmd_dispatch(dummy, inbuf, 2, 1);
		}
		else {
			cmd_dispatch(dummy, inbuf, 8, 2);
		}
	}

	// read 1st partition 0x00002000
	printf("\nSPI SEND CMD17 : 0x00002000\n");
	cmd17[2] = 0x00;
	cmd17[3] = 0x00;
	cmd17[4] = 0x20;
	cmd17[5] = 0x00;
	cmd_dispatch(cmd17, inbuf, 7, 2);

	cmd_polling( 0xfe, 0xfe );
	for (int i = 0; i < 65; i++) {
		if (i == 64) {
			cmd_dispatch(dummy, inbuf, 2, 1);
		}
		else {
			cmd_dispatch(dummy, inbuf, 8, 2);
		}
	}

	// read 1st partition FAT1 0x00002c6e
	printf("\nSPI SEND CMD17 : 0x00002c6e\n");
	cmd17[2] = 0x00;
	cmd17[3] = 0x00;
	cmd17[4] = 0x2c;
	cmd17[5] = 0x6e;
	cmd_dispatch(cmd17, inbuf, 7, 2);

	cmd_polling( 0xfe, 0xfe );
	for (int i = 0; i < 65; i++) {
		if (i == 64) {
			cmd_dispatch(dummy, inbuf, 2, 1);
		}
		else {
			cmd_dispatch(dummy, inbuf, 8, 2);
		}
	}

	// read 1st partition Cluster 0x0000a000
	printf("\nSPI SEND CMD17 : 0x0000a000\n");
	cmd17[2] = 0x00;
	cmd17[3] = 0x00;
	cmd17[4] = 0xa0;
	cmd17[5] = 0x00;
	cmd_dispatch(cmd17, inbuf, 7, 2);

	cmd_polling( 0xfe, 0xfe );
	for (int i = 0; i < 65; i++) {
		if (i == 64) {
			cmd_dispatch(dummy, inbuf, 2, 1);
		}
		else {
			cmd_dispatch(dummy, inbuf, 8, 2);
		}
	}

	// read 1st partition Cluster 0x0000a080
	printf("\nSPI SEND CMD17 : 0x0000a080\n");
	cmd17[2] = 0x00;
	cmd17[3] = 0x00;
	cmd17[4] = 0xa0;
	cmd17[5] = 0x80;
	cmd_dispatch(cmd17, inbuf, 7, 2);

	cmd_polling( 0xfe, 0xfe );
	for (int i = 0; i < 65; i++) {
		if (i == 64) {
			cmd_dispatch(dummy, inbuf, 2, 1);
		}
		else {
			cmd_dispatch(dummy, inbuf, 8, 2);
		}
	}

	while(1);
	return 0;

}

