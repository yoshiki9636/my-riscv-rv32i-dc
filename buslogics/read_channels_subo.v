/*
 * My RISC-V RV32I CPU
 *  request channel subordinate
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module read_channels_subo (
	input clk,
	input rst_n,

	// read request signals
	input arvalid,
	output  arready,
	input [3:0] arid,
	input [31:0] araddr,
	// bus signals
	output rvalid,
	input  rready,
	output [3:0] rid,
	output [31:0] rdata,
	output rlast,

	// signals other side
	input rqfull_1,
	output rreqc_s_valid,
	output [3:0] rreqc_s_id,
	output [31:0] rreqc_s_addr,

	// signals other side
	input rdata_s_valid, //level
	input [3:0] rdata_s_id,
	input [127:0] rdata_s_data,
	output finish_rdata_s

	);

wire [5:0] aratop;

req_chan_subo read_req_chan_subo (
	.clk(clk),
	.rst_n(rst_n),
	.a_valid(arvalid),
	.a_ready(arready),
	.a_id(arid),
	.a_addr(araddr),
	.a_atop(aratop),
	.qfull_1(rqfull_1),
	.reqc_s_valid(rreqc_s_valid),
	.reqc_s_id(rreqc_s_id),
	.reqc_s_addr(rreqc_s_addr)
	);

rdata_chan_subo rdata_chan_subo (
	.clk(clk),
	.rst_n(rst_n),
	.rvalid(rvalid),
	.rready(rready),
	.rid(rid),
	.rdata(rdata),
	.rlast(rlast),
	.rdata_s_valid(rdata_s_valid),
	.rdata_s_id(rdata_s_id),
	.rdata_s_data(rdata_s_data),
	.finish_rdata_s(finish_rdata_s)
	);


endmodule
