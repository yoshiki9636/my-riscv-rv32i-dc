/*
 * My RISC-V RV32I CPU
 *   dram interface top
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module dram_top (
	// mig ingerface
	input mclk,
	input mrst_n,
	// address/command
	output [27:0] app_addr,
	output [2:0] app_cmd,
	output app_en,
	input app_rdy,
	// write data
	output [127:0] app_wdf_data,
	output [15:0] app_wdf_mask,
	output app_wdf_wren,
	output app_wdf_end,
	input app_wdf_rdy,
	// read data
	input [127:0] app_rd_data,
	input app_rd_data_end,
	input app_rd_data_valid,

	// bus clock
	input clk,
	input rst_n,
	// write request
    input awvalid,
    output  awready,
    input [3:0] awid,
    input [31:0] awaddr,
    input [5:0] awatop,
	// write data
    input wvalid,
    output  wready,
    input [31:0] wdata,
    input [3:0] wstrb,
    input wlast,
	// write response
    output bvalid,
    input  bready,
    output [3:0] bid,
    output bcomp,
	// read request
    input arvalid,
    output  arready,
    input [3:0] arid,
    input [31:0] araddr,
	// read data
    output rvalid,
    input  rready,
    output [3:0] rid,
    output [31:0] rdata,
    output rlast

	);

wire wqfull_1; // input
wire wreqc_s_valid; // output
wire [31:0] wreqc_s_addr; // output
wire sqfull_1; // input
wire [127:0] wdat_s_data; // output
wire [15:0] wdat_s_mask; // output
wire wdat_s_valid; // output

wire rqfull_1; // input
wire rreqc_s_valid; // output
wire [31:0] rreqc_s_addr; // output
wire [3:0] rreqc_s_id; // output

//wire rdqfull_1; // not used
wire rdata_s_valid; // input
wire [3:0] rdata_s_id; // input
wire [127:0] rdata_s_data; // input
wire finish_rdata_s; // output

// write bus interface
write_channels_subo write_channels_subo (
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
	.wqfull_1(wqfull_1),
	.wreqc_s_valid(wreqc_s_valid),
	.wreqc_s_addr(wreqc_s_addr),
	.sqfull_1(sqfull_1),
	.wdat_s_data(wdat_s_data),
	.wdat_s_mask(wdat_s_mask),
	.wdat_s_valid(wdat_s_valid)
	);

// read bus interface
read_channels_subo read_channels_subo (
	.clk(clk),
	.rst_n(rst_n),
	.arvalid(arvalid),
	.arready(arready),
	.arid(arid),
	.araddr(araddr),
	.rvalid(rvalid),
	.rready(rready),
	.rid(rid),
	.rdata(rdata),
	.rlast(rlast),
	.rqfull_1(rqfull_1),
	.rreqc_s_valid(rreqc_s_valid),
	.rreqc_s_id(rreqc_s_id),
	.rreqc_s_addr(rreqc_s_addr),
	.rdata_s_valid(rdata_s_valid),
	.rdata_s_id(rdata_s_id),
	.rdata_s_data(rdata_s_data),
	.finish_rdata_s(finish_rdata_s)
	);

// write address queue
//wire req_wqfull; // output
wire wadr_rqempty;
wire wcmd_wen;
wire wcmd_ack;
wire [31:0] waddr;

afifo #(.AFIFODW(32)) write_addr_queue (
	.wclk(clk),
	.wrst_n(rst_n),
	.rclk(mclk),
	.rrst_n(mrst_n),
	.wen(wreqc_s_valid),
	.wqfull(wqfull_1),
	.wdata(wreqc_s_addr),
	.rnext(wcmd_ack),
	.rqempty(wadr_rqempty),
	.rdata(waddr)
	);

assign wcmd_wen = ~wadr_rqempty;

// read address queue
wire radr_rqempty;
wire rcmd_wen;
wire rcmd_ack;
wire [31:0] raddr;

afifo #(.AFIFODW(32)) read_addr_queue (
	.wclk(clk),
	.wrst_n(rst_n),
	.rclk(mclk),
	.rrst_n(mrst_n),
	.wen(rreqc_s_valid),
	.wqfull(rqfull_1),
	.wdata(rreqc_s_addr),
	.rnext(rcmd_ack),
	.rqempty(radr_rqempty),
	.rdata(raddr)
	);

assign rcmd_wen = ~radr_rqempty;

// write data queue
wire wdq_rnext;
wire wdq_rqempty;
wire [143:0] wdat_s_mask_data = { wdat_s_mask, wdat_s_data};
wire [143:0] wdq_mask_rdata;

afifo #(.AFIFODW(144)) write_data_queue (
	.wclk(clk),
	.wrst_n(rst_n),
	.rclk(mclk),
	.rrst_n(mrst_n),
	.wen(wdat_s_valid),
	.wqfull(sqfull_1),
	.wdata(wdat_s_mask_data),
	.rnext(wdq_rnext),
	.rqempty(wdq_rqempty),
	.rdata(wdq_mask_rdata)
	);

// read data queue
wire rdq_wen;
wire [127:0] rdq_wdata;
wire rdq_wqfull;
wire rdq_rqempty;

afifo #(.AFIFODW(128)) read_data_queue (
	.wclk(mclk),
	.wrst_n(mrst_n),
	.rclk(clk),
	.rrst_n(rst_n),
	.wen(rdq_wen),
	.wqfull(rdq_wqfull),
	.wdata(rdq_wdata),
	.rnext(finish_rdata_s),
	.rqempty(rdq_rqempty),
	.rdata(rdata_s_data)
	);

assign rdata_s_valid = ~rdq_rqempty;

// read id wait queue
wire wid_wqfull; // not used
wire wid_rqempty;

sfifo
    #(.SFIFODW(4),
      .SFIFOAW(2),
      .SFIFODP(4)
	) read_id_wait_queue (
	.clk(clk),
	.rst_n(rst_n),
	.wen(rreqc_s_valid),
	.wqfull(wid_wqfull),
	.wdata(rreqc_s_id),
	.rnext(finish_rdata_s),
	.rqempty(wid_rqempty),
	.rdata(rdata_s_id)
	);

// request queue in mclk
wire req_rnext;
wire req_rqempty;
wire [31:0] req_qraddr;
wire req_rd_bwt;

req_queue req_queue (
	.mclk(mclk),
	.mrst_n(mrst_n),
	.wcmd_wen(wcmd_wen),
	.rcmd_wen(rcmd_wen),
	.wcmd_ack(wcmd_ack),
	.rcmd_ack(rcmd_ack),
	.waddr(waddr),
	.raddr(raddr),
	.rnext(req_rnext),
	.rqempty(req_rqempty),
	.qraddr(req_qraddr),
	.rd_bwt(req_rd_bwt)
	);

// MIG interface
mig_if mig_if (
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
	.req_rnext(req_rnext),
	.req_rqempty(req_rqempty),
	.req_qraddr(req_qraddr),
	.req_rd_bwt(req_rd_bwt),
	.wdq_rnext(wdq_rnext),
	.wdq_rqempty(wdq_rqempty),
	.wdq_mask_rdata(wdq_mask_rdata),
	.rdq_wen(rdq_wen),
	.rdq_wdata(rdq_wdata)
	);


endmodule
