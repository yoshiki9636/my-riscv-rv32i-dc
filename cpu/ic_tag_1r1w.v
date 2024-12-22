/*
 * My RISC-V RV32I CPU
 *   CPU Instruction RAM Module in IF Stage
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module ic_tag_1r1w
	#(parameter IRWIDTH = 12)
	(
	input clk,
	input [IRWIDTH-1:0] ram_radr,
	output [23-IRWIDTH:0] ram_rdata,
	input [IRWIDTH-1:0] ram_wadr,
	input [23-IRWIDTH:0] ram_wdata,
	input ram_wen
	);

// 4x1024 1r1w RAM

reg[23-IRWIDTH:0] ram[0:(2**IRWIDTH)-1];
reg[IRWIDTH-1:0] radr;

always @ (posedge clk) begin
	if (ram_wen)
		ram[ram_wadr] <= ram_wdata;
	radr <= ram_radr;
end

assign ram_rdata = ram[radr];

endmodule
