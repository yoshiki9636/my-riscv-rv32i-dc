/*
 * My RISC-V RV32I CPU
 *   Verilog Simulation Top Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module simtop;

reg clk;
reg rst_n;

reg [31:0] rs1_sel; // input
reg [31:0] rs2_sel; // input
reg cmd_mul_ex; // input
reg cmd_mulh_ex; // input
reg cmd_mulhsu_ex; // input
reg cmd_mulhu_ex; // input
reg cmd_div_ex; // input
reg cmd_divu_ex; // input
reg cmd_rem_ex; // input
reg cmd_remu_ex; // input
reg cmd_mul_decode_ex; // input
reg cmd_div_decode_ex; // input
reg cmd_rem_decode_ex; // input

wire [31:0] m_result_ex; // output
wire div_stat_valid; // output
wire divide_by_zero; // output
wire div_stall; // output

mex_stage mex_stage (
	.clk(clk),
	.rst_n(rst_n),
	.rs1_sel(rs1_sel),
	.rs2_sel(rs2_sel),
	.cmd_mul_ex(cmd_mul_ex),
	.cmd_mulh_ex(cmd_mulh_ex),
	.cmd_mulhsu_ex(cmd_mulhsu_ex),
	.cmd_mulhu_ex(cmd_mulhu_ex),
	.cmd_div_ex(cmd_div_ex),
	.cmd_divu_ex(cmd_divu_ex),
	.cmd_rem_ex(cmd_rem_ex),
	.cmd_remu_ex(cmd_remu_ex),
	.cmd_mul_decode_ex(cmd_mul_decode_ex),
	.cmd_div_decode_ex(cmd_div_decode_ex),
	.cmd_rem_decode_ex(cmd_rem_decode_ex),
	.m_result_ex(m_result_ex),
	.div_stat_valid(div_stat_valid),
	.divide_by_zero(divide_by_zero),
	.div_stall(div_stall)
	);
initial clk = 0;

always #5 clk <= ~clk;


initial begin
	rst_n = 1'b1;
#10
	rst_n = 1'b0;
	rs1_sel = 32'd0; // input
	rs2_sel = 32'd9; // input
	cmd_mul_ex = 1'b0; // input
	cmd_mulh_ex = 1'b0; // input
	cmd_mulhsu_ex = 1'b0; // input
	cmd_mulhu_ex = 1'b0; // input
	cmd_div_ex = 1'b0; // input
	cmd_divu_ex = 1'b0; // input
	cmd_rem_ex = 1'b0; // input
	cmd_remu_ex = 1'b0; // input
	cmd_mul_decode_ex = 1'b0; // input
	cmd_div_decode_ex = 1'b0; // input
	cmd_rem_decode_ex = 1'b0; // input
#20
	rst_n = 1'b1;
	rs1_sel = 32'd0; // input
	rs2_sel = 32'd9; // input
#10
	rs1_sel = 32'd40; // input
	rs2_sel = 32'd10; // input
	cmd_mul_ex = 1'b1; // input
	cmd_mul_decode_ex = 1'b1; // input
#10
	cmd_mul_ex = 1'b0; // input
	cmd_mul_decode_ex = 1'b0; // input
#10
	cmd_div_ex = 1'b1; // input
	cmd_div_decode_ex = 1'b1; // input
#10
	cmd_div_ex = 1'b0; // input
	cmd_div_decode_ex = 1'b0; // input
#40
	rs1_sel = 25341; // input
	rs2_sel = 23; // input
	cmd_mul_ex = 1'b1; // input
	cmd_mul_decode_ex = 1'b1; // input
#10
	cmd_mul_ex = 1'b0; // input
	cmd_mulh_ex = 1'b1; // input
#10
	cmd_mulh_ex = 1'b0; // input
	cmd_mulhsu_ex = 1'b1; // input
#10
	cmd_mulhsu_ex = 1'b0; // input
	cmd_mulhu_ex = 1'b1; // input
#10
	cmd_mulhu_ex = 1'b0; // input
	cmd_mul_decode_ex = 1'b0; // input
#10
	cmd_div_ex = 1'b1; // input
	cmd_div_decode_ex = 1'b1; // input
#10
	cmd_div_ex = 1'b0; // input
	cmd_div_decode_ex = 1'b0; // input
#140
	cmd_rem_ex = 1'b1; // input
	cmd_rem_decode_ex = 1'b1; // input
#10
	cmd_rem_ex = 1'b0; // input
	cmd_rem_decode_ex = 1'b0; // input
#140

	rs1_sel = 25341; // input
	rs2_sel = -23; // input
	cmd_mul_ex = 1'b1; // input
	cmd_mul_decode_ex = 1'b1; // input
#10
	cmd_mul_ex = 1'b0; // input
	cmd_mulh_ex = 1'b1; // input
#10
	cmd_mulh_ex = 1'b0; // input
	cmd_mulhsu_ex = 1'b1; // input
#10
	cmd_mulhsu_ex = 1'b0; // input
	cmd_mulhu_ex = 1'b1; // input
#10
	cmd_mulhu_ex = 1'b0; // input
	cmd_mul_decode_ex = 1'b0; // input
#10
	cmd_div_ex = 1'b1; // input
	cmd_div_decode_ex = 1'b1; // input
#10
	cmd_div_ex = 1'b0; // input
	cmd_div_decode_ex = 1'b0; // input
#140
	cmd_rem_ex = 1'b1; // input
	cmd_rem_decode_ex = 1'b1; // input
#10
	cmd_rem_ex = 1'b0; // input
	cmd_rem_decode_ex = 1'b0; // input
#140

	rs1_sel = -25341; // input
	rs2_sel = 23; // input
	cmd_mul_ex = 1'b1; // input
	cmd_mul_decode_ex = 1'b1; // input
#10
	cmd_mul_ex = 1'b0; // input
	cmd_mulh_ex = 1'b1; // input
#10
	cmd_mulh_ex = 1'b0; // input
	cmd_mulhsu_ex = 1'b1; // input
#10
	cmd_mulhsu_ex = 1'b0; // input
	cmd_mulhu_ex = 1'b1; // input
#10
	cmd_mulhu_ex = 1'b0; // input
	cmd_mul_decode_ex = 1'b0; // input
#10
	cmd_div_ex = 1'b1; // input
	cmd_div_decode_ex = 1'b1; // input
#10
	cmd_div_ex = 1'b0; // input
	cmd_div_decode_ex = 1'b0; // input
#140
	cmd_rem_ex = 1'b1; // input
	cmd_rem_decode_ex = 1'b1; // input
#10
	cmd_rem_ex = 1'b0; // input
	cmd_rem_decode_ex = 1'b0; // input
#140

	rs1_sel = -25341; // input
	rs2_sel = -23; // input
	cmd_mul_ex = 1'b1; // input
	cmd_mul_decode_ex = 1'b1; // input
#10
	cmd_mul_ex = 1'b0; // input
	cmd_mulh_ex = 1'b1; // input
#10
	cmd_mulh_ex = 1'b0; // input
	cmd_mulhsu_ex = 1'b1; // input
#10
	cmd_mulhsu_ex = 1'b0; // input
	cmd_mulhu_ex = 1'b1; // input
#10
	cmd_mulhu_ex = 1'b0; // input
	cmd_mul_decode_ex = 1'b0; // input
#10
	cmd_div_ex = 1'b1; // input
	cmd_div_decode_ex = 1'b1; // input
#10
	cmd_div_ex = 1'b0; // input
	cmd_div_decode_ex = 1'b0; // input
#140
	cmd_rem_ex = 1'b1; // input
	cmd_rem_decode_ex = 1'b1; // input
#10
	cmd_rem_ex = 1'b0; // input
	cmd_rem_decode_ex = 1'b0; // input
#140



#1000
	$stop;
end

endmodule

