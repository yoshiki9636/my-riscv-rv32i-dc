/*
 * My RISC-V RV32I CPU
 *  request channel subordinate
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module req_chan_subo (
	input clk,
	input rst_n,
	// bus signals
	input a_valid,
	output  a_ready,
	input [3:0] a_id,
	input [31:0] a_addr,
	input [5:0] a_atop, // currently not used
	// signals other side
	input qfull_1,
	output reqc_s_valid,
	output [3:0] reqc_s_id,
	output [31:0] reqc_s_addr

	);

// no address decoder : just 1 subordinate exists
assign a_ready = ~qfull_1;

wire id_addr_wen = a_valid & a_ready;
reg [35:0] id_addr_lat;
reg id_addr_wen_1lat;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        id_addr_lat <= 36'd0;
    else if (id_addr_wen)
		id_addr_lat <= { a_id, a_addr };
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        id_addr_wen_1lat <= 1'b0;
    else
		id_addr_wen_1lat <= id_addr_wen;
end

assign reqc_s_valid = id_addr_wen_1lat;
assign reqc_s_id = id_addr_lat[35:32];
assign reqc_s_addr = id_addr_lat[31:0];

endmodule
