/*
 * My RISC-V RV32I CPU
 *  read channels manager
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module read_channels_mngr
    #(parameter REQC_M_ID = 2'b00)
	(
	input clk,
	input rst_n,

	//bus controls
	output req_rq,
	input gnt_rq,

	// read request signals
	output arvalid,
	input  arready,
	output [3:0] arid,
	output [31:0] araddr,
	// read data signals
	input rvalid,
	output  rready,
	input [3:0] rid,
	input [31:0] rdata,
	input rlast,

	// signals other side
	input rstart_rq,
	input [31:0] rin_addr,
	output rnext_rq,
	output [3:0] rnext_id,

	// signals other side
	//input next_rrq,
	input [3:0] next_rid,
	input rqfull_1,
	output [127:0] rdat_m_data,
	output rdat_m_valid,
	output finish_mrd

	);

wire [5:0] aratop;
wire [127:0] rin_data = 128'd0;
wire [15:0] rnext_mask;
wire [127:0] next_data;

req_chan_mngr #(.REQC_M_ID(REQC_M_ID)) read_req_chan_mngr (
	.clk(clk),
	.rst_n(rst_n),
	.req_rq(req_rq),
	.gnt_rq(gnt_rq),
	.a_valid(arvalid),
	.a_ready(arready),
	.a_id(arid),
	.a_addr(araddr),
	.a_atop(aratop),
	.start_rq(rstart_rq),
	.in_addr(rin_addr),
	.in_mask(16'd0),
	.in_data(rin_data),
	.next_rq(rnext_rq),
	.next_id(rnext_id),
	.next_mask(rnext_mask),
	.next_data(next_data),
	.ren_id_data(finish_mrd)
	);

rdata_chan_mngr rdata_chan_mngr (
	.clk(clk),
	.rst_n(rst_n),
	.rvalid(rvalid),
	.rready(rready),
	.rid(rid),
	.rdata(rdata),
	.rlast(rlast),
	.next_rrq(rnext_rq),
	.next_rid(next_rid),
	.rqfull_1(rqfull_1),
	.rdat_m_data(rdat_m_data),
	.rdat_m_valid(rdat_m_valid),
	.finish_mrd(finish_mrd)
	);

endmodule
