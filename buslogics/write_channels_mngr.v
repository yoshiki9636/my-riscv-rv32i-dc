/*
 * My RISC-V RV32I CPU
 *  weite channels manager
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module write_channels_mngr
    #(parameter REQC_M_ID = 2'b00)
	(
	input clk,
	input rst_n,
	//bus controls
	output req_rq,
	input gnt_rq,

	// write request signals
	output awvalid,
	input  awready,
	output [3:0] awid,
	output [31:0] awaddr,
	output [5:0] awatop,
	// write data signals
	output wvalid,
	input  wready,
	output [31:0] wdata,
	output [3:0] wstrb,
	output wlast,
	// write response signals
	input bvalid,
	output  bready,
	input [3:0] bid,
	input bcomp,

	// weite request 
	input wstart_rq,
	input [31:0] win_addr,
	// write data
	input [127:0] in_wdata,
	input [15:0] in_mask,
	// write response
	output finish_wresp

	);

wire wnext_rq;
wire [3:0] wnext_id;
wire [127:0] wnext_data;
wire [15:0] wnext_mask;
wire finish_wd;
wire [3:0] finish_id;

req_chan_mngr #(.REQC_M_ID(REQC_M_ID)) write_req_chan_mngr (
	.clk(clk),
	.rst_n(rst_n),
	.req_rq(req_rq),
	.gnt_rq(gnt_rq),
	.a_valid(awvalid),
	.a_ready(awready),
	.a_id(awid),
	.a_addr(awaddr),
	.a_atop(awatop),
	.start_rq(wstart_rq),
	.in_addr(win_addr),
	.in_data(in_wdata),
	.in_mask(in_mask),
	.next_rq(wnext_rq),
	.next_id(wnext_id),
	.next_data(wnext_data),
	.next_mask(wnext_mask),
	.ren_id_data(finish_wd)
	);

wdata_chan_mngr wdata_chan_mngr (
	.clk(clk),
	.rst_n(rst_n),
	.wvalid(wvalid),
	.wready(wready),
	.wdata(wdata),
	.wstrb(wstrb),
	.wlast(wlast),
	.next_rq(wnext_rq),
	.next_id(wnext_id),
	.next_wdata(wnext_data),
	.next_mask(wnext_mask),
	.finish_wd(finish_wd),
	.finish_id(finish_id)
	);

wresp_chan_mngr wresp_chan_mngr (
	.clk(clk),
	.rst_n(rst_n),
	.bvalid(bvalid),
	.bready(bready),
	.bid(bid),
	.bcomp(bcomp),
	.finish_wd(finish_wd),
	.finish_id(finish_id),
	.finish_wresp(finish_wresp)
	);


endmodule
