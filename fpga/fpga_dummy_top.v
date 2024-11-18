/*
 * My RISC-V RV32I CPU
 *   FPGA Top Module for Tang Premier
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

//`define TANG_PRIMER
`define ARTY_A7

module fpga_top
    #(parameter DWIDTH = 11)
    (
	input clkin,
	input rst_n,
	input rx,
	output tx,
	input interrupt_0,
	output [2:0] rgb_led,
	output [2:0] rgb_led1,
	output [2:0] rgb_led2,
	output [2:0] rgb_led3
/*
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
*/

	);

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

wire [12:2] d_ram_radr = 11'd0;
wire [12:2] d_ram_wadr = 11'd0;
wire [31:0] d_ram_rdata;
wire [31:0] d_ram_wdata = 12'd0;
wire d_ram_wen = 1'b0;
wire d_read_sel = 1'b0;

wire [13:2] i_ram_radr;
wire [13:2] i_ram_wadr;
wire [31:0] i_ram_rdata;
wire [31:0] i_ram_wdata;
wire i_ram_wen;
wire i_read_sel;

wire dma_io_we;
wire [15:2] dma_io_wadr;
wire [31:0] dma_io_wdata;
wire [15:2] dma_io_radr;
wire [31:0] dma_io_rdata;
wire [31:0] dma_io_rdata_in = 32'd0;
wire ibus_ren;
wire [19:2] ibus_radr;
wire [15:0] ibus32_rdata = 16'd0;
wire ibus_wen;
wire [19:2] ibus_wadr;
wire [15:0] ibus32_wdata;

wire [31:2] start_adr;
wire cpu_start;
wire quit_cmd;
wire [31:0] pc_data;
// bus i/f logic signals
wire dcw_start_rq; // output
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
wire mclk;
// for debug
wire tx_fifo_full;
wire tx_fifo_overrun;
wire tx_fifo_underrun;

wire init_calib_complete = 1'b1;

`ifdef ARTY_A7
wire locked;

 // Instantiation of the clocking network
 //--------------------------------------
  clk_wiz_0 clknetwork
   (
    // Clock out ports
    .clk_out1           (mclk),
    //.clk_out2           (clk_166mhz),
    //.clk_out3           (clk),
    .clk_out2           (clk),

    // Status and control signals
    .reset              (~rst_n),
    .locked             (locked),
   // Clock in ports
    .clk_in1            (clkin)
    );
`endif

`ifdef TANG_PRIMER
wire clklock;
pll pll (
	.refclk(clkin),
	.reset(~rst_n),
	//.stdby(stdby),
	.extlock(clklock),
	.clk0_out(clk)
	);
`endif

wire mrst_n = rst_n;

cpu_top cpu_top (
	.clk(clk),
	.rst_n(rst_n),
	.init_calib_complete(init_calib_complete),
	.cpu_start(cpu_start),
	.quit_cmd(quit_cmd),
	.start_adr(start_adr),
	.d_ram_radr(d_ram_radr),
	.d_ram_wadr(d_ram_wadr),
	.d_ram_rdata(d_ram_rdata),
	.d_ram_wdata(d_ram_wdata),
	.d_ram_wen(d_ram_wen),
	.d_read_sel(d_read_sel),
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
	.dma_io_rdata_in(dma_io_rdata_in),
	.ibus_ren(ibus_ren),
	.ibus_radr(ibus_radr),
	.ibus32_rdata(ibus32_rdata),
	.ibus_wen(ibus_wen),
	.ibus_wadr(ibus_wadr),
	.ibus32_wdata(ibus32_wdata),
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
	.interrupt_0(interrupt_0)
	);

axi_bus_top axi_bus_top (
	.clk(clk),
	.rst_n(rst_n),
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


//wire sys_clk_i = clk_166mhz; // input
//wire clk_ref_i = clk_200mhz; // input

/*
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
*/

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


uart_top #(.DWIDTH(DWIDTH)) uart_top (
    .clk(clk),
    .rst_n(rst_n),
    .rx(rx),
    .tx(tx),
    .d_ram_radr(uart_rin_addr),
    .d_ram_wadr(uart_win_addr),
    .d_ram_rdata(uart_rdat_m_data),
    .d_ram_wdata(uart_in_wdata),
    .d_ram_wen(uart_wstart_rq),
    .d_read_sel(uart_d_read_sel),
    .d_ram_mask(uart_in_mask),
    .dread_start(uart_rstart_rq),
    .read_valid(uart_rdat_m_valid),
    .i_ram_radr(i_ram_radr),
    .i_ram_wadr(i_ram_wadr),
    .i_ram_rdata(i_ram_rdata),
    .i_ram_wdata(i_ram_wdata),
    .i_ram_wen(i_ram_wen),
    .i_read_sel(i_read_sel),
    .pc_data(pc_data),
    .cpu_start(cpu_start),
	.start_dcflush(start_dcflush),
    .quit_cmd(quit_cmd),
	.dcflush_running(dcflush_running),
    .start_adr(start_adr)
    );

io_led io_led (
	.clk(clk),
	.rst_n(rst_n),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_rdata_in(dma_io_rdata_in),
	.dma_io_rdata(dma_io_rdata),
	.rgb_led(rgb_led),
	.rgb_led1(rgb_led1),
	.rgb_led2(rgb_led2),
	.rgb_led3(rgb_led3)

	);
endmodule
