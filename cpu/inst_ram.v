/*
 * My RISC-V RV32I CPU
 *   CPU Instruction RAM Module in MA Stage
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module inst_ram
	#(parameter IWIDTH = 14)
	(
	input clk,
	input rst_n,
	input [IWIDTH-1:0] ram_radr_part,
	output [31:0] ram_rdata,
	input [IWIDTH-3:0] ram_wadr_all,
	input [127:0] ram_wdata_all,
	input ram_wen_all
	);

wire [IWIDTH-3:0] ram_radr = ram_radr_part[IWIDTH-1:2];
wire [31:0] ram_rdata0;
wire [31:0] ram_rdata1;
wire [31:0] ram_rdata2;
wire [31:0] ram_rdata3;

assign ram_rdata_all = {ram_rdata3, ram_rdata2, ram_rdata1, ram_rdata0};

reg [1:0] ram_rd_sel;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ram_rd_sel <= 2'd0;
    else
        ram_rd_sel <= ram_radr_part[1:0];
end

assign ram_rdata = (ram_rd_sel == 2'd0) ? ram_rdata0 :
                   (ram_rd_sel == 2'd1) ? ram_rdata1 :
                   (ram_rd_sel == 2'd2) ? ram_rdata2 : ram_rdata3;

inst_1r1w #(.IRWIDTH(IWIDTH-2)) ram0 (
	.clk(clk),
	.ram_radr(ram_radr),
	.ram_rdata(ram_rdata0),
	.ram_wadr(ram_wadr_all),
	.ram_wdata(ram_wdata_all[31:0]),
	.ram_wen(ram_wen_all)
	);

inst_1r1w #(.IRWIDTH(IWIDTH-2)) ram1 (
	.clk(clk),
	.ram_radr(ram_radr),
	.ram_rdata(ram_rdata1),
	.ram_wadr(ram_wadr_all),
	.ram_wdata( ram_wdata_all[63:32]),
	.ram_wen(ram_wen_all)
	);

inst_1r1w #(.IRWIDTH(IWIDTH-2)) ram2 (
	.clk(clk),
	.ram_radr(ram_radr),
	.ram_rdata(ram_rdata2),
	.ram_wadr(ram_wadr_all),
	.ram_wdata(ram_wdata_all[95:64]),
	.ram_wen(ram_wen_all)
	);

inst_1r1w #(.IRWIDTH(IWIDTH-2)) ram3 (
	.clk(clk),
	.ram_radr(ram_radr),
	.ram_rdata(ram_rdata3),
	.ram_wadr(ram_wadr_all),
	.ram_wdata( ram_wdata_all[127:96]),
	.ram_wen(ram_wen_all)
	);

endmodule
