/*
 * My RISC-V RV32I CPU
 *  request channel subordinate
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module write_channels_subo (
	input clk,
	input rst_n,

	// request signals
	input awvalid,
	output  awready,
	input [3:0] awid,
	input [31:0] awaddr,
	input [5:0] awatop, // currently not used
	// wdata signals
	input wvalid,
	output  wready,
	input [31:0] wdata,
	input [3:0] wstrb,
	input wlast,
	// response signals
	output bvalid,
	input  bready,
	output [3:0] bid,
	output bcomp,

	// request signals other side
	input wqfull_1,
	output wreqc_s_valid,
	output [31:0] wreqc_s_addr,
	// wdata signals other side
	input sqfull_1,
	output [127:0] wdat_s_data,
	output [15:0] wdat_s_mask,
	output wdat_s_valid

	);

wire [3:0] wreqc_s_id;
wire finish_swd;

req_chan_subo write_req_chan_subo (
	.clk(clk),
	.rst_n(rst_n),
	.a_valid(awvalid),
	.a_ready(awready),
	.a_id(awid),
	.a_addr(awaddr),
	.a_atop(awatop),
	.qfull_1(wqfull_1),
	.reqc_s_valid(wreqc_s_valid),
	.reqc_s_id(wreqc_s_id),
	.reqc_s_addr(wreqc_s_addr)
	);

wdata_chan_subo wdata_chan_subo (
	.clk(clk),
	.rst_n(rst_n),
	.wvalid(wvalid),
	.wready(wready),
	.wdata(wdata),
	.wstrb(wstrb),
	.wlast(wlast),
	.next_srq(wreqc_s_valid),
	.sqfull_1(sqfull_1),
	.wdat_s_data(wdat_s_data),
	.wdat_s_mask(wdat_s_mask),
	.wdat_s_valid(wdat_s_valid),
	.finish_swd(finish_swd)
	);

wresp_chan_subo wresp_chan_subo (
	.clk(clk),
	.rst_n(rst_n),
	.bvalid(bvalid),
	.bready(bready),
	.bid(bid),
	.bcomp(bcomp),
	.reqc_s_valid(wreqc_s_valid),
	.reqc_s_id(wreqc_s_id),
	.finish_swd(finish_swd)
	);

endmodule
