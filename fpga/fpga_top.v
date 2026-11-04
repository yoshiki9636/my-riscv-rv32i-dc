/*
 * My RISC-V RV32I CPU
 *   FPGA Top Module (board / main memory selected in fpga_config.vh)
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

`include "fpga_config.vh"

// FPGA_MODE : bidir pins are inout ports (tri-state buffers inside, for FPGA)
//   not defined : LSI mode, every bidir pin is split into _i / _o / _en ports
//   (same as swc1. io_led.v / qspi_if.v also have `define FPGA_MODE at the top :
//    comment out all three for LSI mode)
`define FPGA_MODE

`ifdef BOARD_CMOD_A7
  `ifdef MEM_MIG
    // CMOD A7 has no DDR3 : MEM_MIG can not be used with BOARD_CMOD_A7
    `define FPGA_CONFIG_ERROR
  `endif
`endif

// cache / scratch size per board
`ifdef BOARD_CMOD_A7
  `define FT_IWIDTH 10
  `define FT_DWIDTH 10
  `define FT_SWIDTH 4
`else // BOARD_ARTY_A7
  `define FT_IWIDTH 12
  `define FT_DWIDTH 12
  `define FT_SWIDTH 13
`endif

// external pins per board / memory (io_led : swc1 io version)
//   all                 : rgb_led[2:0] (inout, SPI output can be muxed), init_uart[1:0]
//   CMOD A7             : gpio[3:0], no rx2/tx2 pins, no SPI pins
//                         (syn/lab4_cmod_a7_io_pins.xdc)
//   Arty A7 + MEM_QSPI  : gpio[5:0], rx2/tx2, no SPI pins (spi_miso = init_qspicmd)
//                         (syn/lab4_arty_qspi_io_pins.xdc)
//   Arty A7 + MEM_MIG   : gpio[5:0], rx2/tx2, SPI pins
//                         (syn/lab4_arty_mig_io_pins.xdc)
`ifdef BOARD_CMOD_A7
  `define FT_NO_SPI_PINS
  `define FT_NO_UART2_PINS
  `define FT_GPIO_W 4
`elsif MEM_QSPI
  `define FT_NO_SPI_PINS
  `define FT_GPIO_W 6
`else
  `define FT_GPIO_W 6
`endif

module fpga_top
    #(parameter IWIDTH = `FT_IWIDTH,
      parameter DWIDTH = `FT_DWIDTH,
      parameter SWIDTH = `FT_SWIDTH)
    (
	input clkin,
`ifdef BOARD_CMOD_A7
	input rst_p, // CMOD A7 : push button, active high
`else
	input rst_n,
`endif
	input rx,
	output tx,
	input interrupt_0,
`ifdef FPGA_MODE
	inout [2:0] rgb_led,
	inout [`FT_GPIO_W-1:0] gpio, // see FT_GPIO_W
`else // FPGA_MODE
	input [2:0] rgb_led_i,
	output [2:0] rgb_led_o,
	output [2:0] rgb_led_en,
	input [`FT_GPIO_W-1:0] gpio_i, // see FT_GPIO_W
	output [`FT_GPIO_W-1:0] gpio_o,
	output [`FT_GPIO_W-1:0] gpio_en,
`endif // FPGA_MODE
	input [1:0] init_uart, // uart_term reset value select (see io_uart_out.v)
	input init_cpu_start, // 1 at reset release : auto start cpu from FT_INIT_START_ADR
`ifndef FT_NO_UART2_PINS
  `ifdef FPGA_MODE
	inout rx2,
	inout tx2,
  `else // FPGA_MODE
	input rx2_i,
	output rx2_o,
	output rx2_en,
	input tx2_i,
	output tx2_o,
	output tx2_en,
  `endif // FPGA_MODE
`endif
`ifndef FT_NO_SPI_PINS
	output spi_sck,
	output [1:0] spi_csn,
	output spi_mosi,
	input spi_miso,
`endif

`ifdef MEM_QSPI
// qspi signal
	output sck,
	output [2:0] ce_n,
  `ifdef FPGA_MODE
	inout [3:0] sio,
  `else // FPGA_MODE
	input [3:0] sio_i,
	output [3:0] sio_o,
	output [3:0] sio_en,
  `endif // FPGA_MODE
	input [1:0] init_latency,
	input init_qspicmd
`else // MEM_MIG
// ddr signal
	inout [15:0] ddr3_dq,
	inout [1:0] ddr3_dqs_n,
	inout [1:0] ddr3_dqs_p,
	output [13:0] ddr3_addr,
	output [2:0] ddr3_ba,
	output ddr3_ras_n,
	output ddr3_cas_n,
	output ddr3_we_n,
	output ddr3_reset_n,
	output [0:0] ddr3_ck_p,
	output [0:0] ddr3_ck_n,
	output [0:0] ddr3_cke,
	output [0:0] ddr3_cs_n,
	output [1:0] ddr3_dm,
	output [0:0] ddr3_odt
`endif

	);

`ifdef FPGA_CONFIG_ERROR
// intentionally undefined module : stops the build on an invalid fpga_config.vh
fpga_config_error_cmod_a7_has_no_ddr3 fpga_config_error ();
`endif

`ifdef BOARD_CMOD_A7
// CMOD A7 : active high reset button
wire rst_n = ~rst_p;
`endif

wire dma_wstart_rq; // input
wire [31:0] dma_win_addr; // input
wire [127:0] dma_in_wdata; // input
wire [15:0] dma_in_mask; // input
wire dma_finish_wresp; // output
wire dma_rstart_rq; // input
wire [31:0] dma_rin_addr; // input
wire [127:0] dma_rdat_m_data; // output
wire [15:0] dma_rdat_m_mask; // output
wire dma_rdat_m_valid; // output
wire dma_finish_mrd; // output

wire uart_wstart_rq; // input
wire [31:0] uart_win_addr; // input
wire [127:0] uart_in_wdata; // input
wire [15:0] uart_in_mask; // input
wire uart_finish_wresp; // output
wire uart_rstart_rq; // input
wire [31:0] uart_rin_addr; // input
wire [127:0] uart_rdat_m_data; // output
wire [15:0] uart_rdat_m_mask = 16'd0; // output
wire uart_rdat_m_valid; // output
wire uart_finish_mrd; // output

wire dc_wstart_rq; // input
wire [31:0] dc_win_addr; // input
wire [127:0] dc_in_wdata; // input
wire [15:0] dc_in_mask; // input
wire dc_finish_wresp; // output
wire dc_rstart_rq; // input
wire [31:0] dc_rin_addr; // input
wire [127:0] dc_rdat_m_data; // output
wire [15:0] dc_rdat_m_mask; // output
wire dc_rdat_m_valid; // output
wire dc_finish_mrd; // output

wire ic_rstart_rq; // output
wire [31:0] ic_rin_addr; // output
wire [127:0] ic_rdat_m_data; // input
wire [15:0] ic_rdat_m_mask; // input
wire ic_rdat_m_valid; // input
wire ic_finish_mrd; // input
//wire start_icflush; // input


// axi bus to DRAM
wire awvalid; // output
wire awready; // input
wire [3:0] awid; // output
wire [31:0] awaddr; // output
wire [5:0] awatop; // output
wire wvalid; // output
wire wready; // input
wire [31:0] wdata; // output
wire [3:0] wstrb; // output
wire wlast; // output
wire bvalid; // input
wire bready; // output
wire [3:0] bid; // input
wire bcomp; // input
wire arvalid; // output
wire arready; // input
wire [3:0] arid; // output
wire [31:0] araddr; // output
wire rvalid; // input
wire rready; // output
wire [3:0] rid; // input
wire [31:0] rdata; // input
wire rlast; // input

`ifdef MEM_QSPI
// qspi_if signals
wire qspi_read_req; // output
wire qspi_read_w; // output
wire qspi_read_hw; // output
wire qspi_read_valid; // input
wire [31:0] qspi_read_adr; // output
wire [31:0] qspi_read_data; // input
wire qspi_write_req; // output
wire qspi_write_w; // output
wire qspi_write_hw; // output
wire qspi_write_finish; // input
wire [31:0] qspi_write_adr; // output
wire [31:0] qspi_write_data; // output
wire [2:0] qspi_dbg_bpoint_en; // not used
`else // MEM_MIG
// mig i/f signals
wire [27:0] app_addr; // output
wire [2:0] app_cmd; // output
wire app_en; // output
wire app_rdy; // input
wire [127:0] app_wdf_data; // output
wire [15:0] app_wdf_mask; // output
wire app_wdf_wren; // output
wire app_wdf_end; // output
wire app_wdf_rdy; // input
wire [127:0] app_rd_data; // input
wire app_rd_data_end; // input
wire app_rd_data_valid; // input
`endif

//wire [DWIDTH+1:2] d_ram_radr = { DWIDTH{ 1'b0 }};
//wire [DWIDTH+1:2] d_ram_wadr = { DWIDTH{ 1'b0 }};
//wire [31:0] d_ram_wdata = 32'd0;
wire [SWIDTH+1:2] scr_ram_radr;
wire [SWIDTH+1:2] scr_ram_wadr;
wire [31:0] scr_ram_rdata;
wire [31:0] scr_ram_wdata;
wire scr_ram_wen;
wire scr_read_sel;
//wire d_ram_wen = 1'b0;
//wire d_read_sel = 1'b0;

wire [IWIDTH+1:2] i_ram_radr = 0;
wire [IWIDTH+1:2] i_ram_wadr = 0;
wire [31:0] i_ram_rdata;
wire [31:0] i_ram_wdata = 0;
wire i_ram_wen = 0;
wire i_read_sel = 0;

//wire dma_io_we;
//wire [15:2] dma_io_wadr;
//wire [31:0] dma_io_wdata;
//wire [15:2] dma_io_radr;
//wire dma_io_radr_en;
// io bus for all
wire dma_io_we; // output
wire [15:2] dma_io_wadr; // output
wire [31:0] dma_io_wdata; // output
wire [15:2] dma_io_radr; // output
wire dma_io_radr_en; // output
// io bus for uart
wire dma_io_we_u; // output
wire [15:2] dma_io_wadr_u; // output
wire [31:0] dma_io_wdata_u; // output
wire [15:2] dma_io_radr_u; // output
wire dma_io_radr_en_u; // output

// io bus logics
//wire dma_io_we = dma_io_we_c | dma_io_we_u;
//wire [15:2] dma_io_wadr = dma_io_we_u ? dma_io_wadr_u : dma_io_wadr_c;
//wire [31:0] dma_io_wdata = dma_io_we_u ? dma_io_wdata_u : dma_io_wdata_c;
//wire dma_io_radr_en = dma_io_radr_en_c | dma_io_radr_en_u;
//wire [15:2] dma_io_radr = dma_io_radr_en_u ? dma_io_radr_u : dma_io_radr_c;

wire [31:0] dma_io_rdata_u_fin;
wire [31:0] dma_io_rdata;
wire [31:0] dma_io_rdata_in = 32'hdeadbeef; // input
//wire [31:0] dma_io_rdata_in = 32'd0; // input
wire [31:0] dma_io_rdata_in_2; // input
wire [31:0] dma_io_rdata_in_3; // input
wire [31:0] dma_io_rdata_in_4; // input
wire [31:0] dma_io_rdata_in_5; // input
wire [31:0] dma_io_rdata_in_6; // input : io_spi_lite -> io_uart2
wire [31:0] dma_io_rdata_in_7; // input : io_uart2 -> qspi_if (MEM_QSPI) / dbg_bpoint_en reg (MEM_MIG)

wire ibus_ren;
wire [19:2] ibus_radr;
wire [15:0] ibus32_rdata = 16'd0;
wire ibus_wen;
wire [19:2] ibus_wadr;
wire [15:0] ibus32_wdata;

// csr monitor bus
wire csr_radr_en_mon; // output
wire [11:0] csr_radr_mon; // output
wire [11:0] csr_wadr_mon; // output
wire csr_we_mon; // output
wire [31:0] csr_wdata_mon; // output
wire [31:0] csr_rdata_mon; // input

// register file monitor bus
wire rf_radr_en_mon; // output
wire [4:0] rf_radr_mon; // output
wire [4:0] rf_wadr_mon; // output
wire rf_we_mon; // output
wire [31:0] rf_wdata_mon; // output
wire [31:0] rf_rdata_mon; // input

wire [31:2] start_adr;
wire cpu_start;
wire quit_cmd;
wire [31:0] pc_data;
// bus i/f logic signals
//wire dcw_start_rq; // output
//wire [31:0] dcw_in_addr; // output
//wire [15:0] dcw_in_mask; // output
//wire [127:0] dcw_in_data; // output
//wire dcw_finish_wresp; // input
//wire dcr_rstart_rq; // output
//wire [31:0] dcr_rin_addr; // output
wire rqfull_1; // output
//wire [127:0] rdat_m_data; // input
//wire rdat_m_valid; // input
//wire finish_mrd; // input
wire start_dcflush;
wire dcflush_running;

wire clk;
//wire mclk = clk;
//wire mclk_not_used;
// for debug
wire tx_fifo_full;
wire tx_fifo_overrun;
wire tx_fifo_underrun;

//wire init_calib_complete = 1'b1;

// for uart output
wire [7:0] uart_io_char;
wire uart_io_we;
wire uart_io_full;
wire rout_en;
wire [7:0] rout;
wire ext_uart_interrpt_1shot;
wire rx_disable_echoback;

wire locked;
`ifdef MEM_MIG
wire clk_200mhz; // Arty A7 : MIG reference clock
`endif

 // Instantiation of the clocking network
 //--------------------------------------
`ifndef FPGA_MODE
// LSI mode : no clk_wiz_0, clkin is used as clk directly
assign clk = clkin;
assign locked = 1'b1;
  `ifdef MEM_MIG
assign clk_200mhz = clkin; // MIG is FPGA only : not meaningful in LSI mode
  `endif
`elsif BOARD_CMOD_A7
  // CMOD A7 : 12MHz in, clk_out1 = clk (48MHz)
  clk_wiz_0 clknetwork
   (
    .clk_out1           (clk),
    .reset              (~rst_n),
    .locked             (locked),
    .clk_in1            (clkin)
    );
`elsif MEM_QSPI
  // Arty A7 + QSPI : 100MHz in, clk_out1 = clk (50MHz), no MIG reference clock
  clk_wiz_0 clknetwork
   (
    .clk_out1           (clk),
    .reset              (~rst_n),
    .locked             (locked),
    .clk_in1            (clkin)
    );
`else // BOARD_ARTY_A7 + MEM_MIG
  // Arty A7 : 100MHz in, clk_out1 = 200MHz (MIG ref), clk_out2 = clk (50MHz)
  clk_wiz_0 clknetwork
   (
    .clk_out1           (clk_200mhz),
    .clk_out2           (clk),
    .reset              (~rst_n),
    .locked             (locked),
    .clk_in1            (clkin)
    );
`endif // FPGA_MODE

`ifdef MEM_QSPI
// QSPI version : memory side runs on clk (MIG removed)
wire mclk = clk;
wire mrst_n = rst_n;
wire init_calib_complete = 1'b1;
`else // MEM_MIG
wire sys_clk_i = clkin; // input
//wire sys_clk_i = clk_166mhz; // input
wire clk_ref_i = clk_200mhz; // input
wire ui_clk;
wire ui_clk_sync_rst;
//wire mrst_n = rst_n;
wire mclk = ui_clk;
wire mrst_n = ~ui_clk_sync_rst;
//wire mrst_n = rst_n;

// MIG interface
wire app_sr_req = 1'b0; // input
wire app_ref_req = 1'b0; // input
wire app_zq_req = 1'b0; // input
wire app_sr_active; // output
wire app_ref_ack; // output
wire app_zq_ack; // output

wire init_calib_complete; // output
wire [11:0] device_temp; // output
wire calib_tap_req; // output
wire calib_tap_load = 1'b0; // input
wire [6:0] calib_tap_addr = 7'd0; // input
wire [7:0] calib_tap_val = 8'd0; // input
wire calib_tap_load_done = 1'b0; // input
wire sys_rst = rst_n; // input
`endif

wire cpu_run_state;

wire [15:0] uart_term; // from io_uart_out (reset value selected by init_uart)

wire cmd_ld_ma;
wire cmd_st_ma;
wire [31:0] rd_data_ma;
wire [2:0] dbg_bpoint;

//wire [7:0] gpio; // zantei

// for free run counter signals
wire csr_mtie;
wire csr_rmie;
wire csr_meie;
wire frc_cntr_val_leq;
wire frc_cntr_val_leq_1shot;

// spi select signal : SPI output is muxed to rgb_led[2:0] in io_led
wire spi_select_io;
`ifdef FT_NO_SPI_PINS
// CMOD A7 / Arty A7 + MEM_QSPI : no dedicated SPI pins (use rgb_led mux)
wire spi_sck;
wire [1:0] spi_csn;
wire spi_mosi;
  `ifdef MEM_QSPI
wire spi_miso = init_qspicmd; // same as swc1
  `else
wire spi_miso = 1'b0;
  `endif
`endif
`ifdef FT_NO_UART2_PINS
// CMOD A7 : rx2/tx2 are not connected to pins
  `ifdef FPGA_MODE
wire rx2; // not used
wire tx2; // not used
  `else // FPGA_MODE
wire rx2_i = 1'b0; // not used
wire rx2_o; // not used
wire rx2_en; // not used
wire tx2_i = 1'b0; // not used
wire tx2_o; // not used
wire tx2_en; // not used
  `endif // FPGA_MODE
`endif
`ifdef BOARD_CMOD_A7
// gpio[5:FT_GPIO_W] are not connected to pins
  `ifdef FPGA_MODE
wire [5:`FT_GPIO_W] gpio_nc; // not used
  `else // FPGA_MODE
wire [5:`FT_GPIO_W] gpio_i_nc = { (6-`FT_GPIO_W){ 1'b0 }}; // not used
wire [5:`FT_GPIO_W] gpio_o_nc; // not used
wire [5:`FT_GPIO_W] gpio_en_nc; // not used
  `endif // FPGA_MODE
`endif

// io_led : uart2 pin control / read only inputs
wire uart2_io_en;
wire rx2_org;
wire tx2_org;
wire ext_uart2_interrpt_1shot;
wire [2:0] dbg_bpoint_en;
`ifdef MEM_QSPI
assign dbg_bpoint_en = qspi_dbg_bpoint_en; // same as swc1
wire [1:0] gpi_init_latency = init_latency;
wire gpi_in = init_qspicmd;
`else
// MEM_MIG : no qspi_if, so dbg_bpoint_en register is placed here
//   same address / bits as qspi_if SYS_QSPI_SCKDIV (0xC000F40C) [23:21] : read / write
//   other bits : write ignored, read 0
`define FT_SYS_DBG_EN 14'h3D03
wire we_dbg_en_value = dma_io_we      & (dma_io_wadr == `FT_SYS_DBG_EN);
wire re_dbg_en_value = dma_io_radr_en & (dma_io_radr == `FT_SYS_DBG_EN);
reg [2:0] dbg_bpoint_en_reg;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		dbg_bpoint_en_reg <= 3'd0;
	else if (we_dbg_en_value)
		dbg_bpoint_en_reg <= dma_io_wdata[23:21];
end

reg re_dbg_en_value_dly;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		re_dbg_en_value_dly <= 1'b0;
	else
		re_dbg_en_value_dly <= re_dbg_en_value;
end

assign dma_io_rdata = re_dbg_en_value_dly ? { 8'd0, dbg_bpoint_en_reg, 21'd0 } : dma_io_rdata_in_7;

assign dbg_bpoint_en = dbg_bpoint_en_reg;
wire [1:0] gpi_init_latency = 2'b00;
wire gpi_in = spi_miso;
`endif

// auto start (same function as swc1 init_cpu_start)
//   if init_cpu_start pin is 1 after reset release, a cpu_start pulse is generated
//   once, same as the monitor 'g' command, with start address FT_INIT_START_ADR.
//   wait FT_INIT_START_WAIT cycles after clk_wiz locked (memory power-up / init).
//   MEM_MIG : cpu_status waits init_calib_complete by itself (cpu_start_lat).
`ifndef FT_INIT_START_ADR
  `define FT_INIT_START_ADR 32'h0000_1000 // ctest/link.ld ORIGIN
`endif
`define FT_INIT_START_WAIT 17'h1_0000 // 65536 cycles : about 1.3ms @50MHz

reg [1:0] init_cpu_start_sync;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		init_cpu_start_sync <= 2'b00;
	else
		init_cpu_start_sync <= { init_cpu_start_sync[0], init_cpu_start };
end

wire gpi_init_cpu_start = init_cpu_start_sync[1]; // also readable from io_led GPI_IN

reg [16:0] init_start_cntr;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		init_start_cntr <= 17'd0;
	else if (locked & (init_start_cntr != `FT_INIT_START_WAIT))
		init_start_cntr <= init_start_cntr + 17'd1;
end

wire init_start_pulse = (init_start_cntr == (`FT_INIT_START_WAIT - 17'd1)) & locked & gpi_init_cpu_start;

// cpu_start / start_adr to cpu : monitor command or auto start
wire cpu_start_mon; // from uart_top (monitor 'g' command)
wire [31:2] start_adr_mon; // from uart_top
wire [31:0] init_start_adr = `FT_INIT_START_ADR;
assign cpu_start = cpu_start_mon | init_start_pulse;
assign start_adr = init_start_pulse ? init_start_adr[31:2] : start_adr_mon;

// for interrupt
wire g_interrupt_1shot;
wire g_interrupt;
//wire ic_stall;
wire stall;

cpu_top #(.DWIDTH(DWIDTH), .IWIDTH(IWIDTH), .SWIDTH(SWIDTH)) cpu_top (
	.clk(clk),
	.rst_n(rst_n),
	.init_calib_complete(init_calib_complete),
	.cpu_start(cpu_start),
	.quit_cmd(quit_cmd),
	.start_adr(start_adr),
	.cpu_run_state(cpu_run_state),

	//.d_ram_radr(d_ram_radr),
	//.d_ram_wadr(d_ram_wadr),
	//.d_ram_rdata(d_ram_rdata),
	//.d_ram_wdata(d_ram_wdata),
    .scr_ram_radr(scr_ram_radr),
    .scr_ram_wadr(scr_ram_wadr),
    .scr_ram_wdata(scr_ram_wdata),
    .scr_ram_rdata(scr_ram_rdata),
	.scr_ram_wen(scr_ram_wen),
	.scr_read_sel(_read_sel),
	//.d_ram_wen(d_ram_wen),
	//.d_read_sel(d_read_sel),

	.i_ram_radr(i_ram_radr),
	.i_ram_wadr(i_ram_wadr),
	.i_ram_rdata(i_ram_rdata),
	.i_ram_wdata(i_ram_wdata),
	.i_ram_wen(i_ram_wen),
	.i_read_sel(i_read_sel),
	.pc_data(pc_data),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	//.dma_io_rdata_in(dma_io_rdata_in),
	.dma_io_rdata_in(dma_io_rdata),

	.dma_io_we_u(dma_io_we_u),
	.dma_io_wadr_u(dma_io_wadr_u),
	.dma_io_wdata_u(dma_io_wdata_u),
	.dma_io_radr_u(dma_io_radr_u),
	.dma_io_radr_en_u(dma_io_radr_en_u),
	.dma_io_rdata_in_u_fin(dma_io_rdata_u_fin),

	.dma_wstart_rq(dma_wstart_rq),
	.dma_win_addr(dma_win_addr),
	.dma_in_wdata(dma_in_wdata),
	.dma_in_mask(dma_in_mask),
	.dma_finish_wresp(dma_finish_wresp),
	.dma_rstart_rq(dma_rstart_rq),
	.dma_rin_addr(dma_rin_addr),
	.dma_rdat_m_data(dma_rdat_m_data),
	.dma_rdat_m_mask(dma_rdat_m_mask),
	.dma_rdat_m_valid(dma_rdat_m_valid),
	.dma_finish_mrd(dma_finish_mrd),

	.icr_start_rq(ic_rstart_rq),
	.ic_rin_addr(ic_rin_addr),
	.ic_rdat_m_data(ic_rdat_m_data),
	.ic_rdat_m_mask(ic_rdat_m_mask),
	.ic_rdat_m_valid(ic_rdat_m_valid),
	.ic_finish_mrd(ic_finish_mrd),
	// FPGA FIX (2026-07-19): was 1'b0 - the monitor had NO way to
	// invalidate the I$, so a reflash/restart without an FPGA
	// reconfigure executed stale old-kernel lines out of the 16KB I$.
	// The existing D$-flush monitor command (zcmd_setdfl) now flushes
	// BOTH caches; issue it after quit and before loading a new image.
	.start_icflush(start_dcflush),

    .csr_radr_en_mon(csr_radr_en_mon),
    .csr_radr_mon(csr_radr_mon),
    .csr_wadr_mon(csr_wadr_mon),
    .csr_we_mon(csr_we_mon),
    .csr_wdata_mon(csr_wdata_mon),
    .csr_rdata_mon(csr_rdata_mon),

    .rf_radr_en_mon(rf_radr_en_mon),
    .rf_radr_mon(rf_radr_mon),
    .rf_wadr_mon(rf_wadr_mon),
    .rf_we_mon(rf_we_mon),
    .rf_wdata_mon(rf_wdata_mon),
    .rf_rdata_mon(rf_rdata_mon),

	.dcw_start_rq(dc_wstart_rq),
	.dcw_in_addr(dc_win_addr),
	.dcw_in_mask(dc_in_mask),
	.dcw_in_data(dc_in_wdata),
	.dcw_finish_wresp(dc_finish_wresp),
	.dcr_start_rq(dc_rstart_rq),
	.dcr_rin_addr(dc_rin_addr),
	.rqfull_1(rqfull_1),
	.rdat_m_data(dc_rdat_m_data),
	.rdat_m_valid(dc_rdat_m_valid),
	.finish_mrd(dc_finish_mrd),
	.start_dcflush(start_dcflush),
	.dcflush_running(dcflush_running),
	//.interrupt_0(interrupt_0),
	.cmd_ld_ma(cmd_ld_ma),
	.cmd_st_ma(cmd_st_ma),
	.rd_data_ma(rd_data_ma),
	.csr_mtie(csr_mtie),
	.frc_cntr_val_leq(frc_cntr_val_leq),
    .frc_cntr_val_leq_1shot(frc_cntr_val_leq_1shot),
    .csr_rmie(csr_rmie),
    .csr_meie(csr_meie),
    .g_interrupt_1shot(g_interrupt_1shot),
    .g_interrupt(g_interrupt),
    //.ic_stall(ic_stall),
    .stall(stall)
	);

axi_bus_top axi_bus_top (
	.clk(clk),
	.rst_n(rst_n),
	.dma_wstart_rq(dma_wstart_rq),
	.dma_win_addr(dma_win_addr),
	.dma_in_wdata(dma_in_wdata),
	.dma_in_mask(dma_in_mask),
	.dma_finish_wresp(dma_finish_wresp),
	.dma_rstart_rq(dma_rstart_rq),
	.dma_rin_addr(dma_rin_addr),
	.dma_rdat_m_data(dma_rdat_m_data),
	.dma_rdat_m_mask(dma_rdat_m_mask),
	.dma_rdat_m_valid(dma_rdat_m_valid),
	.dma_finish_mrd(dma_finish_mrd),
	.uart_wstart_rq(uart_wstart_rq),
	.uart_win_addr(uart_win_addr),
	.uart_in_wdata(uart_in_wdata),
	.uart_in_mask(uart_in_mask),
	.uart_finish_wresp(uart_finish_wresp),
	.uart_rstart_rq(uart_rstart_rq),
	.uart_rin_addr(uart_rin_addr),
	.uart_rdat_m_data(uart_rdat_m_data),
	.uart_rdat_m_mask(uart_rdat_m_mask),
	.uart_rdat_m_valid(uart_rdat_m_valid),
	.uart_finish_mrd(uart_finish_mrd),
	.dc_wstart_rq(dc_wstart_rq),
	.dc_win_addr(dc_win_addr),
	.dc_in_wdata(dc_in_wdata),
	.dc_in_mask(dc_in_mask),
	.dc_finish_wresp(dc_finish_wresp),
	.dc_rstart_rq(dc_rstart_rq),
	.dc_rin_addr(dc_rin_addr),
	.dc_rdat_m_data(dc_rdat_m_data),
	.dc_rdat_m_mask(dc_rdat_m_mask),
	.dc_rdat_m_valid(dc_rdat_m_valid),
	.dc_finish_mrd(dc_finish_mrd),

	.ic_rstart_rq(ic_rstart_rq),
	.ic_rin_addr(ic_rin_addr),
	.ic_rdat_m_data(ic_rdat_m_data),
	.ic_rdat_m_mask(ic_rdat_m_mask),
	.ic_rdat_m_valid(ic_rdat_m_valid),
	.ic_finish_mrd(ic_finish_mrd),

	.awvalid(awvalid),
	.awready(awready),
	.awid(awid),
	.awaddr(awaddr),
	.awatop(awatop),
	.wvalid(wvalid),
	.wready(wready),
	.wdata(wdata),
	.wstrb(wstrb),
	.wlast(wlast),
	.bvalid(bvalid),
	.bready(bready),
	.bid(bid),
	.bcomp(bcomp),
	.arvalid(arvalid),
	.arready(arready),
	.arid(arid),
	.araddr(araddr),
	.rvalid(rvalid),
	.rready(rready),
	.rid(rid),
	.rdata(rdata),
	.rlast(rlast)
	);

dram_top dram_top (
	.mclk(mclk),
	.mrst_n(mrst_n),
`ifdef MEM_QSPI
	.read_req(qspi_read_req),
	.read_w(qspi_read_w),
	.read_hw(qspi_read_hw),
	.read_valid(qspi_read_valid),
	.read_adr(qspi_read_adr),
	.read_data(qspi_read_data),
	.write_req(qspi_write_req),
	.write_w(qspi_write_w),
	.write_hw(qspi_write_hw),
	.write_finish(qspi_write_finish),
	.write_adr(qspi_write_adr),
	.write_data(qspi_write_data),
`else // MEM_MIG
	.app_addr(app_addr),
	.app_cmd(app_cmd),
	.app_en(app_en),
	.app_rdy(app_rdy),
	.app_wdf_data(app_wdf_data),
	.app_wdf_mask(app_wdf_mask),
	.app_wdf_wren(app_wdf_wren),
	.app_wdf_end(app_wdf_end),
	.app_wdf_rdy(app_wdf_rdy),
	.app_rd_data(app_rd_data),
	.app_rd_data_end(app_rd_data_end),
	.app_rd_data_valid(app_rd_data_valid),
`endif
	.clk(clk),
	.rst_n(rst_n),
	.awvalid(awvalid),
	.awready(awready),
	.awid(awid),
	.awaddr(awaddr),
	.awatop(awatop),
	.wvalid(wvalid),
	.wready(wready),
	.wdata(wdata),
	.wstrb(wstrb),
	.wlast(wlast),
	.bvalid(bvalid),
	.bready(bready),
	.bid(bid),
	.bcomp(bcomp),
	.arvalid(arvalid),
	.arready(arready),
	.arid(arid),
	.araddr(araddr),
	.rvalid(rvalid),
	.rready(rready),
	.rid(rid),
	.rdata(rdata),
	.rlast(rlast)
	);

`ifdef MEM_QSPI
qspi_if qspi_if (
	.clk(clk),
	.rst_n(rst_n),
	.sck(sck),
	.ce_n(ce_n),
`ifdef FPGA_MODE
	.sio(sio),
`else // FPGA_MODE
	.sio_i(sio_i),
	.sio_o(sio_o),
	.sio_en(sio_en),
`endif // FPGA_MODE
	.dbg_bpoint_en(qspi_dbg_bpoint_en),
	.init_latency(init_latency),
	.init_qspicmd(init_qspicmd),
	.read_req(qspi_read_req),
	.read_w(qspi_read_w),
	.read_hw(qspi_read_hw),
	.read_valid(qspi_read_valid),
	.read_adr(qspi_read_adr),
	.read_data(qspi_read_data),
	.write_req(qspi_write_req),
	.write_w(qspi_write_w),
	.write_hw(qspi_write_hw),
	.write_finish(qspi_write_finish),
	.write_adr(qspi_write_adr),
	.write_data(qspi_write_data),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in_7),
	.dma_io_rdata(dma_io_rdata)
	);
`else // MEM_MIG
mig_7series_0 mig_7series_0 (
	.ddr3_dq(ddr3_dq),
	.ddr3_dqs_n(ddr3_dqs_n),
	.ddr3_dqs_p(ddr3_dqs_p),
	.ddr3_addr(ddr3_addr),
	.ddr3_ba(ddr3_ba),
	.ddr3_ras_n(ddr3_ras_n),
	.ddr3_cas_n(ddr3_cas_n),
	.ddr3_we_n(ddr3_we_n),
	.ddr3_reset_n(ddr3_reset_n),
	.ddr3_ck_p(ddr3_ck_p),
	.ddr3_ck_n(ddr3_ck_n),
	.ddr3_cke(ddr3_cke),
	.ddr3_cs_n(ddr3_cs_n),
	.ddr3_dm(ddr3_dm),
	.ddr3_odt(ddr3_odt),
	.sys_clk_i(sys_clk_i),
	.clk_ref_i(clk_ref_i),
	.app_addr(app_addr),
	.app_cmd(app_cmd),
	.app_en(app_en),
	.app_wdf_data(app_wdf_data),
	.app_wdf_end(app_wdf_end),
	.app_wdf_mask(app_wdf_mask),
	.app_wdf_wren(app_wdf_wren),
	.app_rd_data(app_rd_data),
	.app_rd_data_end(app_rd_data_end),
	.app_rd_data_valid(app_rd_data_valid),
	.app_rdy(app_rdy),
	.app_wdf_rdy(app_wdf_rdy),
	.app_sr_req(app_sr_req),
	.app_ref_req(app_ref_req),
	.app_zq_req(app_zq_req),
	.app_sr_active(app_sr_active),
	.app_ref_ack(app_ref_ack),
	.app_zq_ack(app_zq_ack),
	.ui_clk(ui_clk),
	.ui_clk_sync_rst(ui_clk_sync_rst),
	.init_calib_complete(init_calib_complete),
	.device_temp(device_temp),
	//.calib_tap_req(calib_tap_req),
	//.calib_tap_load(calib_tap_load),
	//.calib_tap_addr(calib_tap_addr),
	//.calib_tap_val(calib_tap_val),
	//.calib_tap_load_done(calib_tap_load_done),
	.sys_rst(sys_rst)
	);
`endif

/*
dummy_mig dummy_mig (
	.mclk(mclk),
	.mrst_n(mrst_n),
	.app_addr(app_addr),
	.app_cmd(app_cmd),
	.app_en(app_en),
	.app_rdy(app_rdy),
	.app_wdf_data(app_wdf_data),
	.app_wdf_mask(app_wdf_mask),
	.app_wdf_wren(app_wdf_wren),
	.app_wdf_end(app_wdf_end),
	.app_wdf_rdy(app_wdf_rdy),
	.app_rd_data(app_rd_data),
	.app_rd_data_end(app_rd_data_end),
	.app_rd_data_valid(app_rd_data_valid)
	);
*/

uart_top #(.DWIDTH(DWIDTH), .IWIDTH(IWIDTH), .SWIDTH(SWIDTH)) uart_top (
	.clk(clk),
	.rst_n(rst_n),
	.rx(rx),
	.tx(tx),

    .d_ram_radr(uart_rin_addr),
    .d_ram_wadr(uart_win_addr),
    .d_ram_rdata(uart_rdat_m_data),
    .d_ram_wdata(uart_in_wdata),
    .d_ram_wen(uart_wstart_rq),
    .uart_finish_wresp(uart_finish_wresp),
    .scr_ram_radr(scr_ram_radr),
    .scr_ram_wadr(scr_ram_wadr),
    .scr_ram_wdata(scr_ram_wdata),
    .scr_ram_rdata(scr_ram_rdata),
	.scr_ram_wen(scr_ram_wen),
	.scr_read_sel(_read_sel),
    //.d_read_sel(uart_d_read_sel),
    .d_ram_mask(uart_in_mask),
    .u_read_req(uart_rstart_rq),
    .read_valid(uart_rdat_m_valid),
	//.d_ram_radr(d_ram_radr),
	//.dread_start(dread_start),
	//.d_ram_rdata(d_ram_rdata),
	//.read_valid(read_valid),
	//.d_ram_wadr(d_ram_wadr),
	//.d_ram_wdata(d_ram_wdata),
	//.d_ram_mask(d_ram_mask),
	//.d_ram_wen(d_ram_wen),
	//.uart_finish_wresp(uart_finish_wresp),
	//.d_read_sel(d_read_sel),

	.dma_io_we(dma_io_we_u),
	.dma_io_wadr(dma_io_wadr_u),
	.dma_io_wdata(dma_io_wdata_u),
	.dma_io_radr(dma_io_radr_u),
	.dma_io_radr_en(dma_io_radr_en_u),
	.dma_io_rdata_in(dma_io_rdata_u_fin),

	.csr_radr_en_mon(csr_radr_en_mon),
	.csr_radr_mon(csr_radr_mon),
	.csr_wadr_mon(csr_wadr_mon),
	.csr_we_mon(csr_we_mon),
	.csr_wdata_mon(csr_wdata_mon),
	.csr_rdata_mon(csr_rdata_mon),

	.rf_radr_en_mon(rf_radr_en_mon),
	.rf_radr_mon(rf_radr_mon),
	.rf_wadr_mon(rf_wadr_mon),
	.rf_we_mon(rf_we_mon),
	.rf_wdata_mon(rf_wdata_mon),
	.rf_rdata_mon(rf_rdata_mon),

	.pc_data(pc_data),
	.cmd_ld_ma(cmd_ld_ma),
	.cmd_st_ma(cmd_st_ma),
	.rd_data_ma(rd_data_ma),
	.dbg_bpoint(dbg_bpoint),

	.cpu_start(cpu_start_mon),
	.cpu_run_state(cpu_run_state),
	.quit_cmd(quit_cmd),
	.start_adr(start_adr_mon),
	.uart_io_char(uart_io_char),
	.uart_io_we(uart_io_we),
	.uart_io_full(uart_io_full),
	.uart_term(uart_term),
	.rout_en(rout_en),
	.rout(rout),
	.rx_disable_echoback(rx_disable_echoback),
	.start_dcflush(start_dcflush)
	);

io_led io_led (
	.clk(clk),
	.rst_n(rst_n),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in_2),
	.dma_io_rdata(dma_io_rdata_in_3),
	.spi_mosi(spi_mosi),
	.spi_csn(spi_csn),
	.spi_sck(spi_sck),
	.spi_select_io(spi_select_io),
	.uart2_io_en(uart2_io_en),
	.rx2_org(rx2_org),
	.tx2_org(tx2_org),
`ifdef FPGA_MODE
	.rgb_led(rgb_led),
	.rx2(rx2),
	.tx2(tx2),
`else // FPGA_MODE
	.rgb_led_i(rgb_led_i),
	.rgb_led_o(rgb_led_o),
	.rgb_led_en(rgb_led_en),
	.rx2_i(rx2_i),
	.rx2_o(rx2_o),
	.rx2_en(rx2_en),
	.tx2_i(tx2_i),
	.tx2_o(tx2_o),
	.tx2_en(tx2_en),
`endif // FPGA_MODE
	.dbg_bpoint_en(dbg_bpoint_en),
	.dbg_bpoint(dbg_bpoint),
	.cpu_start(cpu_start),
	.init_uart(init_uart),
	.init_latency(gpi_init_latency),
	.init_cpu_start(gpi_init_cpu_start),
	.gpi_in(gpi_in),
`ifdef FPGA_MODE
  `ifdef BOARD_CMOD_A7
	.gpio({ gpio_nc, gpio })
  `else
	.gpio(gpio)
  `endif
`else // FPGA_MODE
  `ifdef BOARD_CMOD_A7
	.gpio_i({ gpio_i_nc, gpio_i }),
	.gpio_o({ gpio_o_nc, gpio_o }),
	.gpio_en({ gpio_en_nc, gpio_en })
  `else
	.gpio_i(gpio_i),
	.gpio_o(gpio_o),
	.gpio_en(gpio_en)
  `endif
`endif // FPGA_MODE
	);

io_uart_out io_uart_out (
    .clk(clk),
    .rst_n(rst_n),
    .dma_io_we(dma_io_we),
    .dma_io_wadr(dma_io_wadr),
    .dma_io_wdata(dma_io_wdata),
    .dma_io_radr(dma_io_radr),
    .dma_io_radr_en(dma_io_radr_en),
    .dma_io_rdata_in(dma_io_rdata_in),
    .dma_io_rdata(dma_io_rdata_in_2),
    .uart_io_char(uart_io_char),
    .uart_io_we(uart_io_we),
    .uart_io_full(uart_io_full),
    .init_uart(init_uart),
    .uart_term(uart_term),
    .cpu_run_state(cpu_run_state),
    .rout_en(rout_en),
    .rout(rout),
    .ext_uart_interrpt_1shot(ext_uart_interrpt_1shot),
    .rx_disable_echoback(rx_disable_echoback)
    );

io_frc io_frc (
    .clk(clk),
    .rst_n(rst_n),
    .dma_io_we(dma_io_we),
    .dma_io_wadr(dma_io_wadr),
    .dma_io_wdata(dma_io_wdata),
    .dma_io_radr(dma_io_radr),
    .dma_io_radr_en(dma_io_radr_en),
    .dma_io_rdata_in(dma_io_rdata_in_3),
    .dma_io_rdata(dma_io_rdata_in_4),
    .csr_mtie(csr_mtie),
    .csr_rmie(csr_rmie),
    .frc_cntr_val_leq(frc_cntr_val_leq),
    .frc_cntr_val_leq_1shot(frc_cntr_val_leq_1shot),
    .stall(stall)
    );

interrupter interrupter (
    .clk(clk),
    .rst_n(rst_n),
    .interrupt_0(interrupt_0),
    .ext_uart_interrpt_1shot(ext_uart_interrpt_1shot),
    .ext_uart2_interrpt_1shot(ext_uart2_interrpt_1shot),
    .csr_rmie(csr_rmie),
    .csr_meie(csr_meie),
    .g_interrupt_1shot(g_interrupt_1shot),
    .g_interrupt(g_interrupt),
    //.ic_stall(ic_stall),
    .stall(stall),
    .dma_io_we(dma_io_we),
    .dma_io_wadr(dma_io_wadr),
    .dma_io_wdata(dma_io_wdata),
    .dma_io_radr(dma_io_radr),
    .dma_io_radr_en(dma_io_radr_en),
    .dma_io_rdata_in(dma_io_rdata_in_4),
    .dma_io_rdata(dma_io_rdata_in_5)
    );

io_spi_lite io_spi_lite(
    .clk(clk),
    .rst_n(rst_n),
    .dma_io_we(dma_io_we),
    .dma_io_wadr(dma_io_wadr),
    .dma_io_wdata(dma_io_wdata),
    .dma_io_radr(dma_io_radr),
    .dma_io_radr_en(dma_io_radr_en),
    .dma_io_rdata_in(dma_io_rdata_in_5),
    .dma_io_rdata(dma_io_rdata_in_6), // -> io_uart2
    .spi_select_io(spi_select_io),
    .spi_sck(spi_sck),
    .spi_csn(spi_csn),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso)
    );

io_uart2 io_uart2 (
    .clk(clk),
    .rst_n(rst_n),
    .rx2(rx2_org),
    .tx2(tx2_org),
    .uart2_io_en(uart2_io_en),
    .dma_io_we(dma_io_we),
    .dma_io_wadr(dma_io_wadr),
    .dma_io_wdata(dma_io_wdata),
    .dma_io_radr(dma_io_radr),
    .dma_io_radr_en(dma_io_radr_en),
    .dma_io_rdata_in(dma_io_rdata_in_6),
    .dma_io_rdata(dma_io_rdata_in_7), // -> qspi_if (MEM_QSPI) / dbg_bpoint_en reg (MEM_MIG)
    .ext_uart2_interrpt_1shot(ext_uart2_interrpt_1shot)
    );

endmodule

