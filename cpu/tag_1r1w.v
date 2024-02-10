/*
 * My RISC-V RV32I CPU
 *   CPU Instruction RAM Module in IF Stage
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module tag_1r1w
	#(parameter DRWIDTH = 9)
	(
	input clk,
	input [DRWIDTH-1:0] ram_radr,
	output [23-DRWIDTH:0] ram_rdata,
	input [DRWIDTH-1:0] ram_wadr,
	input [23-DRWIDTH:0] ram_wdata,
	input ram_wen
	);

// 4x1024 1r1w RAM

reg[23-DRWIDTH:0] ram[0:(2**DRWIDTH)-1];
reg[DRWIDTH-1:0] radr;

always @ (posedge clk) begin
	if (ram_wen)
		ram[ram_wadr] <= ram_wdata;
	radr <= ram_radr;
end

assign ram_rdata = ram[radr];

endmodule
