/*
 * My Systolic array
 *   ram for async fifo
 *    Verilog code
 * @auther      Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight   2023 Yoshiki Kurokawa
 * @license     https://opensource.org/licenses/MIT     MIT license
 * @version     0.1
 */

module afifo_1r1w
	#(parameter AFIFODW = 32)
	(
	input iclk,
	input oclk,
	input [1:0] ram_radr,
	output [AFIFODW-1:0] ram_rdata,
	input [1:0] ram_wadr,
	input [AFIFODW-1:0] ram_wdata,
	input ram_wen
	);

// 16x1024 1r1w RAM
reg[AFIFODW-1:0] ram[0:3];
reg[1:0] radr;

always @ (posedge iclk) begin
	if (ram_wen)
		ram[ram_wadr] <= ram_wdata;
end

always @ (posedge oclk) begin
	radr <= ram_radr;
end

assign ram_rdata = ram[radr];

endmodule
